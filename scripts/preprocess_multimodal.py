#!/usr/bin/env python3
"""
preprocess_multimodal.py — Pre-processing pipeline cho tài liệu kỹ thuật Napas

Chạy cho TỪNG tài liệu PDF/DOCX:
1. Extract ảnh (raster + vector fallback screenshot)
2. Vision Model mô tả từng ảnh (Gemini 2.5 Pro via OpenRouter)
3. Tạo .md có link ảnh gốc + mô tả text
4. Copy ảnh gốc vào Next.js /public/docs/images/

Usage:
  python preprocess_multimodal.py \\
    --input "tai_lieu.pdf" \\
    --doc-name "Huong_dan_tich_hop_API_v2.1" \\
    --output-dir "./output" \\
    --public-dir "../frontend/public" \\
    --api-key "sk-..." \\
    [--api-url "https://openrouter.ai/api/v1/chat/completions"] \\
    [--vision-model "google/gemini-2.5-pro"]
"""

import argparse
import base64
import json
import os
import shutil
import sys
from pathlib import Path
from typing import Any

try:
    import fitz  # PyMuPDF
except ImportError:
    print("❌ PyMuPDF chưa cài. Chạy: pip install PyMuPDF")
    sys.exit(1)

try:
    import requests
except ImportError:
    print("❌ requests chưa cài. Chạy: pip install requests")
    sys.exit(1)


# ─── Constants ───────────────────────────────────────────────────────────────

IMAGE_BASE_URL = "/docs/images"  # URL path trên Next.js website
MIN_IMAGE_SIZE = 5000            # bytes — bỏ qua ảnh quá nhỏ (icons, bullets)
VECTOR_DRAWING_THRESHOLD = 10   # Số drawings tối thiểu để trigger screenshot
MAX_EMBEDDED_FOR_SCREENSHOT = 2  # Nếu ít hơn N embedded images → screenshot trang


# ─── Step 1: Extract images from PDF ────────────────────────────────────────

def extract_images_from_pdf(pdf_path: str, output_dir: str) -> list[dict[str, Any]]:
    """Extract tất cả ảnh từ PDF, lưu ra folder.

    Bao gồm fallback: nếu trang có ít/không có embedded images
    nhưng có nhiều drawings → screenshot cả trang cho Vision Model.

    Giới hạn đã xử lý:
    - pymupdf get_images() chỉ extract RASTER images (JPG, PNG embedded)
    - KHÔNG extract được VECTOR GRAPHICS (sơ đồ vẽ bằng lines/shapes)
    - Ảnh nhỏ < MIN_IMAGE_SIZE bytes bị bỏ qua (icons, bullets)
    """
    os.makedirs(output_dir, exist_ok=True)
    doc = fitz.open(pdf_path)
    images: list[dict[str, Any]] = []

    print(f"📄 Đang xử lý {pdf_path} ({len(doc)} trang)...")

    for page_num in range(len(doc)):
        page = doc[page_num]
        page_images = page.get_images(full=True)

        # Extract embedded raster images
        for img_index, img in enumerate(page_images):
            xref = img[0]
            try:
                base_image = doc.extract_image(xref)
            except Exception as e:
                print(f"  ⚠️ Trang {page_num + 1}, ảnh {img_index + 1}: lỗi extract — {e}")
                continue

            image_bytes = base_image["image"]

            # Bỏ qua ảnh quá nhỏ
            if len(image_bytes) < MIN_IMAGE_SIZE:
                continue

            image_ext = base_image["ext"]
            filename = f"page{page_num + 1}_img{img_index + 1}.{image_ext}"
            filepath = os.path.join(output_dir, filename)

            with open(filepath, "wb") as f:
                f.write(image_bytes)

            images.append({
                "file": filepath,
                "page": page_num + 1,
                "index": img_index + 1,
                "type": "embedded",
            })
            print(f"  ✅ Trang {page_num + 1}, ảnh {img_index + 1}: {filename} ({len(image_bytes)} bytes)")

        # Fallback: nếu trang có drawings (vector diagrams) nhưng ít embedded images
        # → screenshot cả trang để Vision Model phân tích
        try:
            drawings = page.get_drawings()
        except Exception:
            drawings = []

        embedded_count = sum(1 for im in page_images if _image_is_significant(doc, im))

        if len(drawings) > VECTOR_DRAWING_THRESHOLD and embedded_count < MAX_EMBEDDED_FOR_SCREENSHOT:
            pix = page.get_pixmap(dpi=200)
            screenshot_path = os.path.join(output_dir, f"page{page_num + 1}_screenshot.png")
            pix.save(screenshot_path)
            images.append({
                "file": screenshot_path,
                "page": page_num + 1,
                "index": 0,
                "type": "page_screenshot",
            })
            print(f"  📸 Trang {page_num + 1}: screenshot (có {len(drawings)} vector drawings)")

    doc.close()
    print(f"\n📊 Tổng cộng: {len(images)} ảnh extracted\n")
    return images


def _image_is_significant(doc: fitz.Document, img_ref: tuple) -> bool:
    """Kiểm tra ảnh có đáng kể (> MIN_IMAGE_SIZE) không."""
    try:
        base = doc.extract_image(img_ref[0])
        return len(base["image"]) >= MIN_IMAGE_SIZE
    except Exception:
        return False


# ─── Step 2: Vision Model describe each image ──────────────────────────────

def describe_image_with_vision(
    image_path: str,
    api_key: str,
    api_url: str = "https://openrouter.ai/api/v1/chat/completions",
    model: str = "google/gemini-2.5-pro",
    context: str = "",
) -> str:
    """Dùng Vision Model để sinh mô tả text cho ảnh/diagram.

    Args:
        image_path: Đường dẫn file ảnh
        api_key: OpenRouter API key
        api_url: API endpoint
        model: Vision model ID
        context: Context bổ sung (tên chương, trang...)

    Returns:
        Mô tả text chi tiết bằng tiếng Việt
    """
    with open(image_path, "rb") as f:
        image_b64 = base64.b64encode(f.read()).decode()

    # Detect MIME type
    ext = Path(image_path).suffix.lower()
    mime_map = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif", ".webp": "image/webp"}
    mime_type = mime_map.get(ext, "image/png")

    prompt = f"""Mô tả chi tiết nội dung của ảnh/diagram này bằng tiếng Việt.

Quy tắc:
- Nếu đây là SƠ ĐỒ LUỒNG (flowchart): liệt kê TỪNG BƯỚC theo thứ tự, mô tả mũi tên/kết nối.
- Nếu đây là BẢNG: chuyển thành dạng text có cấu trúc rõ ràng (dùng markdown table nếu phù hợp).
- Nếu đây là BIỂU ĐỒ: mô tả dữ liệu, trục, xu hướng.
- Nếu đây là KIẾN TRÚC HỆ THỐNG: liệt kê các component, kết nối, protocol.
- Nếu có TEXT trong ảnh: trích xuất nguyên văn.
- Mô tả càng chi tiết càng tốt — text này sẽ được index để search.

{f"Context trong tài liệu: {context}" if context else ""}"""

    try:
        response = requests.post(
            api_url,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": model,
                "messages": [
                    {
                        "role": "user",
                        "content": [
                            {"type": "text", "text": prompt},
                            {
                                "type": "image_url",
                                "image_url": {"url": f"data:{mime_type};base64,{image_b64}"},
                            },
                        ],
                    }
                ],
                "max_tokens": 2000,
                "temperature": 0.2,
            },
            timeout=120,
        )
        response.raise_for_status()
        data = response.json()
        return data["choices"][0]["message"]["content"]
    except requests.exceptions.RequestException as e:
        print(f"  ❌ Vision API error cho {image_path}: {e}")
        return f"[LỖI: Không thể mô tả ảnh — {e}]"
    except (KeyError, IndexError) as e:
        print(f"  ❌ Unexpected API response cho {image_path}: {e}")
        return f"[LỖI: Response không hợp lệ — {e}]"


# ─── Step 3: Create markdown with image URLs ────────────────────────────────

def create_image_descriptions_md(
    images: list[dict[str, Any]],
    doc_name: str,
    output_path: str,
    api_key: str,
    api_url: str = "https://openrouter.ai/api/v1/chat/completions",
    model: str = "google/gemini-2.5-pro",
) -> None:
    """Tạo file .md chứa mô tả + LINK ẢNH GỐC cho 1 tài liệu.

    Mỗi entry chứa:
    - ![alt](url) → frontend render ảnh inline trong chat
    - Mô tả text chi tiết → cho Hybrid Search + LLM context
    """
    doc_slug = doc_name.replace(" ", "_").lower()
    output: list[str] = [f"# Mô Tả Ảnh và Diagram — {doc_name}\n"]
    output.append(f"**Tài liệu nguồn:** {doc_name}\n")

    for i, img in enumerate(images, 1):
        print(f"  🔍 [{i}/{len(images)}] Mô tả {Path(img['file']).name}...")

        description = describe_image_with_vision(
            img["file"],
            api_key=api_key,
            api_url=api_url,
            model=model,
            context=f"Tài liệu: {doc_name}, Trang {img['page']}",
        )

        img_filename = Path(img["file"]).name
        img_url = f"{IMAGE_BASE_URL}/{doc_slug}/{img_filename}"

        output.append(f"## [{doc_name}] Hình ảnh trang {img['page']}, ảnh {img['index']}")
        output.append(f"**Nguồn:** {doc_name}, Trang {img['page']}")
        output.append("")
        output.append(f"![{doc_name} - Trang {img['page']}]({img_url})")
        output.append("")
        output.append(f"**Mô tả chi tiết:**\n{description}\n")
        output.append("---\n")

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(output))

    print(f"  ✅ Saved: {output_path}")


# ─── Step 4: Copy images to Next.js public folder ───────────────────────────

def copy_images_to_public(
    images: list[dict[str, Any]], doc_name: str, public_dir: str
) -> None:
    """Copy ảnh gốc vào /public/docs/images/{doc_slug}/ để frontend hiển thị."""
    doc_slug = doc_name.replace(" ", "_").lower()
    target_dir = Path(public_dir) / "docs" / "images" / doc_slug
    target_dir.mkdir(parents=True, exist_ok=True)

    for img in images:
        src = Path(img["file"])
        dst = target_dir / src.name
        shutil.copy2(src, dst)

    print(f"  ✅ Copied {len(images)} images → {target_dir}")


# ─── CLI ─────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Pre-process tài liệu kỹ thuật Napas: extract ảnh → Vision describe → .md + copy images",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Ví dụ:
  python preprocess_multimodal.py \\
    --input "docs/api_guide.pdf" \\
    --doc-name "Huong_dan_API_v2.1" \\
    --output-dir "./output" \\
    --public-dir "../frontend/public" \\
    --api-key "sk-or-..."

Kết quả:
  ./output/huong_dan_api_v2.1_images.md    → Upload vào Dify KB
  ../frontend/public/docs/images/huong_dan_api_v2.1/  → Ảnh serve trên web
        """,
    )

    parser.add_argument("--input", "-i", required=True, help="Đường dẫn file PDF input")
    parser.add_argument("--doc-name", "-n", required=True, help="Tên tài liệu (dùng cho metadata + folder)")
    parser.add_argument("--output-dir", "-o", default="./output", help="Thư mục output cho .md files")
    parser.add_argument("--public-dir", "-p", default="../frontend/public", help="Thư mục public Next.js")
    parser.add_argument("--api-key", "-k", required=True, help="OpenRouter API key")
    parser.add_argument("--api-url", default="https://openrouter.ai/api/v1/chat/completions", help="Vision API endpoint")
    parser.add_argument("--vision-model", default="google/gemini-2.5-pro", help="Vision model ID")
    parser.add_argument("--skip-vision", action="store_true", help="Bỏ qua Vision API (chỉ extract ảnh, không mô tả)")
    parser.add_argument("--temp-dir", default=None, help="Thư mục tạm cho ảnh extracted (default: output-dir/temp)")

    args = parser.parse_args()

    if not os.path.exists(args.input):
        print(f"❌ File không tồn tại: {args.input}")
        sys.exit(1)

    temp_dir = args.temp_dir or os.path.join(args.output_dir, "temp")
    doc_slug = args.doc_name.replace(" ", "_").lower()

    print("=" * 60)
    print(f"🚀 Pre-processing: {args.doc_name}")
    print(f"   Input:  {args.input}")
    print(f"   Output: {args.output_dir}")
    print(f"   Public: {args.public_dir}")
    print("=" * 60)

    # Step 1: Extract images
    print("\n📦 Step 1: Extracting images...")
    images = extract_images_from_pdf(args.input, temp_dir)

    if not images:
        print("⚠️ Không tìm thấy ảnh nào trong tài liệu.")
        print("   → Chỉ cần upload file gốc vào Dify KB (text + bảng sẽ được parse tự động).")
        return

    # Step 2: Copy images to public
    print("📁 Step 2: Copying images to public folder...")
    copy_images_to_public(images, args.doc_name, args.public_dir)

    # Step 3: Vision describe + create markdown
    md_output = os.path.join(args.output_dir, f"{doc_slug}_images.md")

    if args.skip_vision:
        print("⏭️ Step 3: Skipping Vision API (--skip-vision)")
        # Tạo .md placeholder không có mô tả
        output = [f"# Ảnh từ {args.doc_name}\n"]
        for img in images:
            img_filename = Path(img["file"]).name
            img_url = f"{IMAGE_BASE_URL}/{doc_slug}/{img_filename}"
            output.append(f"## Trang {img['page']}, ảnh {img['index']}")
            output.append(f"![{args.doc_name} - Trang {img['page']}]({img_url})")
            output.append(f"**Nguồn:** {args.doc_name}, Trang {img['page']}")
            output.append("[Chưa có mô tả — chạy lại không có --skip-vision]\n---\n")

        os.makedirs(args.output_dir, exist_ok=True)
        with open(md_output, "w", encoding="utf-8") as f:
            f.write("\n".join(output))
        print(f"  ✅ Saved placeholder: {md_output}")
    else:
        print("🔍 Step 3: Vision Model đang mô tả ảnh...")
        create_image_descriptions_md(
            images,
            doc_name=args.doc_name,
            output_path=md_output,
            api_key=args.api_key,
            api_url=args.api_url,
            model=args.vision_model,
        )

    # Summary
    print("\n" + "=" * 60)
    print("✅ HOÀN TẤT!")
    print(f"   📝 Markdown: {md_output}")
    print(f"   🖼️ Images:   {args.public_dir}/docs/images/{doc_slug}/")
    print()
    print("👉 Bước tiếp theo:")
    print(f"   1. Upload file gốc ({args.input}) vào Dify Knowledge Base")
    print(f"   2. Upload {md_output} vào CÙNG Dify Knowledge Base")
    print(f"   3. Test retrieval trong Dify")
    print("=" * 60)


if __name__ == "__main__":
    main()
