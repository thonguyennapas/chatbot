#!/usr/bin/env python3
"""
preprocess_multimodal.py — Pre-processing pipeline cho tài liệu kỹ thuật Napas

Pipeline:
1. Extract ảnh (raster + vector fallback screenshot)
2. Smart classify mỗi trang: table / diagram / boilerplate / text_only
3. Vision Model mô tả (prompt chuyên biệt cho bảng vs sơ đồ)
4. Tạo .md có link ảnh gốc + mô tả text
5. Copy ảnh gốc vào Next.js /public/docs/images/

Usage (batch — recommended):
  python preprocess_multimodal.py \\
    --input-dir "./input" \\
    --output-dir "./output" \\
    --public-dir "./frontend/public" \\
    --api-key "sk-or-..." \\
    --vision-model "google/gemini-2.5-flash" \\
    --table-model "google/gemini-2.5-pro"

Usage (single file):
  python preprocess_multimodal.py \\
    --input "tai_lieu.pdf" \\
    --doc-name "Huong_dan_API_v2.1" \\
    --api-key "sk-or-..."
"""

import argparse
import base64
import json
import os
import re
import shutil
import sys
from pathlib import Path
from typing import Any

# Fix Windows console encoding for emoji output
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass  # Python < 3.7

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

IMAGE_BASE_URL_DEFAULT = "/docs"  # URL path trên Next.js website
MIN_IMAGE_SIZE = 5000            # bytes — bỏ qua ảnh quá nhỏ (icons, bullets)
VECTOR_DRAWING_THRESHOLD = 10   # Số drawings tối thiểu để trigger screenshot
MAX_EMBEDDED_FOR_SCREENSHOT = 2  # Nếu ít hơn N embedded images → screenshot trang

# Page classification thresholds
TABLE_MIN_HORIZONTAL_LINES = 3   # Tối thiểu 3 đường ngang để coi là bảng
TABLE_MIN_VERTICAL_LINES = 2     # Tối thiểu 2 đường dọc
TABLE_MIN_GRAY_RECTS = 5         # Tối thiểu 5 gray-filled rectangles (cell backgrounds)
BOILERPLATE_MAX_TEXT_LEN = 100   # Trang có ít hơn N ký tự text thực → boilerplate
BOILERPLATE_MAX_DRAWINGS = 50    # Boilerplate thường chỉ có border/header drawings

# Copyright patterns phổ biến trong tài liệu EMVCo, Napas
BOILERPLATE_PATTERNS = [
    r"©\s*\d{4}",
    r"all rights reserved",
    r"reproduction.*distribution.*permitted",
    r"emvco.*llc",
    r"page\s+\d+\s*/\s*\d+",
]

# Cost estimation (USD per Vision API call via OpenRouter, approximate)
COST_PER_CALL_PRO = 0.15    # gemini-2.5-pro
COST_PER_CALL_FLASH = 0.02  # gemini-2.5-flash


# ─── Page Classification ────────────────────────────────────────────────────

def _count_table_indicators(drawings: list[dict]) -> tuple[int, int, int]:
    """Count drawing features that indicate table presence.

    PDFs render tables in two ways:
    1. Lines ('l'): horizontal + vertical lines forming a grid
    2. Rectangles ('re'): filled rectangles for cell backgrounds (EMVCo style)

    Returns:
        Tuple of (horizontal_lines, vertical_lines, gray_rects)
    """
    h_lines = 0
    v_lines = 0
    gray_rects = 0
    rect_y_coords: list[float] = []  # Track Y positions for row alignment

    for d in drawings:
        for sub in d.get("items", []):
            try:
                kind = sub[0]
                if kind == "l":  # Line
                    p1, p2 = sub[1], sub[2]
                    if abs(p1.y - p2.y) < 2 and abs(p1.x - p2.x) > 30:
                        h_lines += 1
                    elif abs(p1.x - p2.x) < 2 and abs(p1.y - p2.y) > 15:
                        v_lines += 1
                elif kind == "re":  # Rectangle
                    fill = d.get("fill")
                    if fill and isinstance(fill, tuple) and len(fill) >= 3:
                        r, g, b = fill[0], fill[1], fill[2]
                        # Gray fill (table cell background) or very light color
                        # Gray: r ≈ g ≈ b, and not black (>0.3) and not white (< 0.95)
                        is_gray = (abs(r - g) < 0.05 and abs(g - b) < 0.05
                                   and 0.3 < r < 0.95)
                        # Light colored fill (also common for table headers)
                        is_light = r > 0.7 and g > 0.7 and b > 0.7 and r < 0.98
                        if is_gray or is_light:
                            gray_rects += 1
                            rect = sub[1]  # fitz.Rect
                            rect_y_coords.append(round(rect.y0, 1))
            except (IndexError, AttributeError, TypeError):
                continue

    return h_lines, v_lines, gray_rects


def _strip_boilerplate_text(text: str) -> str:
    """Remove common header/footer/copyright text from page content."""
    lines = text.strip().split("\n")
    content_lines = []
    for line in lines:
        line_stripped = line.strip()
        if not line_stripped:
            continue
        # Skip page numbers like "Page 16 / 286"
        if re.match(r"^Page\s+\d+\s*/\s*\d+\s*$", line_stripped, re.IGNORECASE):
            continue
        # Skip copyright notices
        is_boilerplate = False
        for pattern in BOILERPLATE_PATTERNS:
            if re.search(pattern, line_stripped, re.IGNORECASE):
                is_boilerplate = True
                break
        if not is_boilerplate:
            content_lines.append(line_stripped)
    return " ".join(content_lines)


def classify_page(page: fitz.Page, doc: fitz.Document) -> str:
    """Classify a PDF page into: table, diagram, boilerplate, or text_only.

    Classification logic:
    - table: Has grid lines OR many gray-filled rectangles (cell backgrounds)
    - diagram: Has many drawings but not table indicators
    - boilerplate: Minimal content (copyright, page numbers, borders only)
    - text_only: No significant vector content
    """
    try:
        drawings = page.get_drawings()
    except Exception:
        drawings = []

    page_images = page.get_images(full=True)
    embedded_count = sum(1 for im in page_images if _image_is_significant(doc, im))
    text = page.get_text()
    content_text = _strip_boilerplate_text(text)
    drawing_count = len(drawings)

    # No drawings → text_only
    if drawing_count <= VECTOR_DRAWING_THRESHOLD and embedded_count < MAX_EMBEDDED_FOR_SCREENSHOT:
        return "text_only"

    # Boilerplate check: minimal content + few drawings
    if len(content_text) < BOILERPLATE_MAX_TEXT_LEN and drawing_count < BOILERPLATE_MAX_DRAWINGS:
        return "boilerplate"

    # Count table indicators
    h_lines, v_lines, gray_rects = _count_table_indicators(drawings)

    # Table detection:
    # Method 1: Grid lines (h + v lines)
    # Method 2: Many gray-filled rectangles (EMVCo-style cell backgrounds)
    is_table_by_lines = (h_lines >= TABLE_MIN_HORIZONTAL_LINES
                         and v_lines >= TABLE_MIN_VERTICAL_LINES)
    is_table_by_rects = gray_rects >= TABLE_MIN_GRAY_RECTS

    if is_table_by_lines or is_table_by_rects:
        return "table"

    # Diagram: many drawings but not a table
    if drawing_count > VECTOR_DRAWING_THRESHOLD and embedded_count < MAX_EMBEDDED_FOR_SCREENSHOT:
        return "diagram"

    return "text_only"


# ─── Vision Prompts ─────────────────────────────────────────────────────────

PROMPT_TABLE = """Bạn đang xem ảnh chụp một trang tài liệu kỹ thuật. Trang này chứa MỘT HOẶC NHIỀU BẢNG.

Nhiệm vụ: Trích xuất CHÍNH XÁC nội dung bảng thành Markdown table.

Quy tắc:
1. Giữ nguyên CẤU TRÚC bảng gốc: headers, số cột, alignment.
2. Mỗi cell phải giữ nguyên nội dung — KHÔNG tóm tắt, KHÔNG bỏ sót.
3. Nếu có NHIỀU bảng trên trang: tách riêng mỗi bảng, đặt heading mô tả bên trên.
4. Nếu bảng quá rộng: vẫn giữ đủ cột, dùng viết tắt nếu cần nhưng KHÔNG xóa cột.
5. Nếu có text NGOÀI bảng (heading, ghi chú): include kèm, đặt trước/sau bảng.
6. Nếu có merged cells hoặc cấu trúc phức tạp: dùng ghi chú dạng "[merged: ...]".
7. Trích xuất bằng NGÔN NGỮ GỐC của tài liệu (English nếu là spec EMVCo).

Format output:
### [Tên bảng / Table caption nếu có]

| Column 1 | Column 2 | ... |
|---|---|---|
| data | data | ... |

{context}"""

PROMPT_DIAGRAM = """Mô tả chi tiết nội dung của ảnh/diagram này bằng tiếng Việt.

Quy tắc:
- Nếu đây là SƠ ĐỒ LUỒNG (flowchart/sequence diagram): liệt kê TỪNG BƯỚC theo thứ tự, mô tả mũi tên/kết nối giữa các component.
- Nếu đây là KIẾN TRÚC HỆ THỐNG: liệt kê các component, kết nối, protocol, port.
- Nếu đây là BIỂU ĐỒ: mô tả dữ liệu, trục, xu hướng.
- Nếu có TEXT trong ảnh: trích xuất nguyên văn.
- Mô tả càng chi tiết càng tốt — text này sẽ được index để search.

{context}"""

PROMPT_GENERIC = """Mô tả chi tiết nội dung của ảnh/diagram này bằng tiếng Việt.

Quy tắc:
- Nếu đây là SƠ ĐỒ LUỒNG (flowchart): liệt kê TỪNG BƯỚC theo thứ tự, mô tả mũi tên/kết nối.
- Nếu đây là BẢNG: chuyển thành dạng text có cấu trúc rõ ràng (dùng markdown table nếu phù hợp).
- Nếu đây là BIỂU ĐỒ: mô tả dữ liệu, trục, xu hướng.
- Nếu đây là KIẾN TRÚC HỆ THỐNG: liệt kê các component, kết nối, protocol.
- Nếu có TEXT trong ảnh: trích xuất nguyên văn.
- Mô tả càng chi tiết càng tốt — text này sẽ được index để search.

{context}"""


def _get_prompt_for_type(page_type: str, context: str = "") -> str:
    """Return the appropriate Vision prompt based on page classification."""
    ctx = f"Context trong tài liệu: {context}" if context else ""
    if page_type == "table":
        return PROMPT_TABLE.format(context=ctx)
    elif page_type == "diagram":
        return PROMPT_DIAGRAM.format(context=ctx)
    else:
        return PROMPT_GENERIC.format(context=ctx)


# ─── Step 1: Extract images from PDF ────────────────────────────────────────

def extract_images_from_pdf(
    pdf_path: str,
    output_dir: str,
    enable_filter: bool = True,
    scan_only: bool = False,
) -> tuple[list[dict[str, Any]], dict[str, int], list[dict[str, Any]]]:
    """Extract tất cả ảnh + text từ PDF, lưu ra folder.

    Bao gồm:
    - Smart page classification (table/diagram/boilerplate/text_only)
    - Fallback screenshot cho trang vector
    - Boilerplate filtering
    - Text extraction cho text_only pages

    Returns:
        Tuple of (images list, classification stats dict, text_pages list)
    """
    os.makedirs(output_dir, exist_ok=True)
    doc = fitz.open(pdf_path)
    images: list[dict[str, Any]] = []
    text_pages: list[dict[str, Any]] = []
    stats: dict[str, int] = {"table": 0, "diagram": 0, "boilerplate": 0, "text_only": 0, "embedded": 0}

    print(f"📄 Đang xử lý {pdf_path} ({len(doc)} trang)...")
    if scan_only:
        print("   (scan-only mode — không tạo screenshot)\n")

    for page_num in range(len(doc)):
        page = doc[page_num]
        page_images = page.get_images(full=True)

        # Extract embedded raster images (always, regardless of classification)
        if not scan_only:
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
                    "page_class": "embedded",
                })
                stats["embedded"] += 1
                print(f"  ✅ Trang {page_num + 1}, ảnh {img_index + 1}: {filename} ({len(image_bytes)} bytes)")

        # Classify page for vector content handling
        page_class = classify_page(page, doc)
        stats[page_class] += 1

        # Skip boilerplate pages
        if page_class == "boilerplate":
            if enable_filter:
                print(f"  🚫 Trang {page_num + 1}: boilerplate (skip)")
                continue
            else:
                # --no-filter: treat as diagram
                page_class = "diagram"

        # Text-only pages: extract text directly (no screenshot needed)
        if page_class == "text_only":
            if not scan_only:
                raw_text = page.get_text().strip()
                clean_text = _strip_boilerplate_text(raw_text)
                if clean_text:
                    text_pages.append({
                        "page": page_num + 1,
                        "text": raw_text,
                    })
            continue

        # Screenshot for table/diagram pages
        icon = "📋" if page_class == "table" else "📐"

        if scan_only:
            print(f"  {icon} Trang {page_num + 1}: {page_class}")
            continue

        pix = page.get_pixmap(dpi=200)
        screenshot_path = os.path.join(output_dir, f"page{page_num + 1}_screenshot.png")
        pix.save(screenshot_path)

        try:
            drawings = page.get_drawings()
        except Exception:
            drawings = []

        images.append({
            "file": screenshot_path,
            "page": page_num + 1,
            "index": 0,
            "type": "page_screenshot",
            "page_class": page_class,
        })
        print(f"  {icon} Trang {page_num + 1}: {page_class} screenshot ({len(drawings)} drawings)")

    doc.close()

    if not scan_only:
        print(f"\n📊 Tổng cộng: {len(images)} ảnh + {len(text_pages)} trang text extracted\n")

    return images, stats, text_pages


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
    prompt: str,
    api_url: str = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
    model: str = "gemini-2.5-flash",
) -> str:
    """Dùng Vision Model để sinh mô tả text cho ảnh/diagram.

    Args:
        image_path: Đường dẫn file ảnh
        api_key: OpenRouter API key
        prompt: Vision prompt (chuyên biệt theo loại trang)
        api_url: API endpoint
        model: Vision model ID

    Returns:
        Mô tả text chi tiết
    """
    with open(image_path, "rb") as f:
        image_b64 = base64.b64encode(f.read()).decode()

    # Detect MIME type
    ext = Path(image_path).suffix.lower()
    mime_map = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif", ".webp": "image/webp"}
    mime_type = mime_map.get(ext, "image/png")

    # Table prompts need more tokens for full Markdown tables
    max_tokens = 4000 if "bảng" in prompt.lower() or "table" in prompt.lower() else 2000

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
                "max_tokens": max_tokens,
                "temperature": 0.2,
            },
            timeout=180,
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

def create_full_markdown(
    images: list[dict[str, Any]],
    text_pages: list[dict[str, Any]],
    doc_name: str,
    output_path: str,
    api_key: str,
    api_url: str = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
    model: str = "gemini-2.5-flash",
    table_model: str | None = None,
    project: str = "general",
) -> None:
    """Tạo file .md ĐẦY ĐỦ NỘI DUNG tài liệu: text + ảnh + bảng + diagram.

    Merge tất cả content theo thứ tự trang:
    - Text-only pages: plain text từ PyMuPDF
    - Table/diagram pages: screenshot + Vision AI mô tả
    - Embedded images: ảnh gốc + Vision AI mô tả

    Output: 1 file .md duy nhất → upload thẳng vào Dify KB (không cần PDF gốc).
    """
    effective_table_model = table_model or model
    doc_slug = doc_name.replace(" ", "_").lower()
    image_base_url = f"{IMAGE_BASE_URL_DEFAULT}/{project}"

    # Build lookup: page_num → text content
    text_by_page: dict[int, str] = {tp["page"]: tp["text"] for tp in text_pages}
    # Build lookup: page_num → list of images on that page
    images_by_page: dict[int, list[dict[str, Any]]] = {}
    for img in images:
        images_by_page.setdefault(img["page"], []).append(img)

    # Collect all page numbers that have content
    all_pages = sorted(set(text_by_page.keys()) | set(images_by_page.keys()))

    output: list[str] = [f"# {doc_name}\n"]
    output.append(f"**Tài liệu nguồn:** {doc_name}\n")

    vision_call_idx = 0
    total_vision_calls = len(images)

    for page_num in all_pages:
        # Text content for this page
        if page_num in text_by_page:
            text = text_by_page[page_num]
            output.append(f"<!-- Trang {page_num} -->")
            output.append(text)
            output.append("")

        # Image/table/diagram content for this page
        if page_num in images_by_page:
            for img in images_by_page[page_num]:
                vision_call_idx += 1
                page_class = img.get("page_class", "embedded")
                icon = {"table": "📋", "diagram": "📐", "embedded": "🖼️"}.get(page_class, "📄")
                use_model = effective_table_model if page_class == "table" else model

                print(f"  🔍 [{vision_call_idx}/{total_vision_calls}] {icon} {page_class}: {Path(img['file']).name} (model: {use_model.split('/')[-1]})...")

                context = f"Tài liệu: {doc_name}, Trang {img['page']}"
                prompt = _get_prompt_for_type(page_class, context)

                description = describe_image_with_vision(
                    img["file"],
                    api_key=api_key,
                    prompt=prompt,
                    api_url=api_url,
                    model=use_model,
                )

                img_filename = Path(img["file"]).name
                img_url = f"{image_base_url}/{doc_slug}/{img_filename}"

                class_label = {"table": "Bảng", "diagram": "Sơ đồ", "embedded": "Hình ảnh"}.get(page_class, "Hình ảnh")
                output.append(f"### {class_label} — Trang {img['page']}")
                output.append(f"![{doc_name} - Trang {img['page']}]({img_url})")
                output.append("")
                output.append(f"{description}\n")

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(output))

    print(f"  ✅ Saved: {output_path}")


# ─── Step 4: Copy images to Next.js public folder ───────────────────────────

def copy_images_to_public(
    images: list[dict[str, Any]], doc_name: str, public_dir: str, project: str = "general"
) -> None:
    """Copy ảnh gốc vào /public/docs/{project}/{doc_slug}/ để frontend hiển thị."""
    doc_slug = doc_name.replace(" ", "_").lower()
    target_dir = Path(public_dir) / "docs" / project / doc_slug
    target_dir.mkdir(parents=True, exist_ok=True)

    for img in images:
        src = Path(img["file"])
        dst = target_dir / src.name
        shutil.copy2(src, dst)

    print(f"  ✅ Copied {len(images)} images → {target_dir}")


# ─── Scan Summary ───────────────────────────────────────────────────────────

def print_scan_summary(stats: dict[str, int], model: str, table_model: str | None) -> None:
    """Print classification summary with cost estimate."""
    effective_table_model = table_model or model
    table_count = stats.get("table", 0)
    diagram_count = stats.get("diagram", 0)
    embedded_count = stats.get("embedded", 0)
    boilerplate_count = stats.get("boilerplate", 0)
    text_only_count = stats.get("text_only", 0)
    total_vision_calls = table_count + diagram_count + embedded_count

    # Cost estimation
    is_pro_table = "pro" in effective_table_model.lower()
    is_pro_diagram = "pro" in model.lower()
    table_cost = table_count * (COST_PER_CALL_PRO if is_pro_table else COST_PER_CALL_FLASH)
    diagram_cost = (diagram_count + embedded_count) * (COST_PER_CALL_PRO if is_pro_diagram else COST_PER_CALL_FLASH)
    total_cost = table_cost + diagram_cost

    print("\n" + "=" * 60)
    print("📊 Page Classification Summary:")
    print(f"   📋 Tables:      {table_count:3d} pages (table prompt → {effective_table_model.split('/')[-1]})")
    print(f"   📐 Diagrams:    {diagram_count:3d} pages (diagram prompt → {model.split('/')[-1]})")
    print(f"   🖼️  Embedded:    {embedded_count:3d} images (generic prompt → {model.split('/')[-1]})")
    print(f"   📄 Text-only:   {text_only_count:3d} pages (no screenshot)")
    print(f"   🚫 Boilerplate: {boilerplate_count:3d} pages (skip)")
    print(f"   ─────────────────────")
    print(f"   💰 Vision API calls: {total_vision_calls}")
    print(f"   💰 Estimated cost:   ${total_cost:.2f} - ${total_cost * 1.5:.2f}")
    print("=" * 60)


# ─── Single File Processing ──────────────────────────────────────────────────

def process_single_file(
    input_path: str,
    doc_name: str,
    output_dir: str,
    public_dir: str,
    api_key: str,
    api_url: str,
    vision_model: str,
    table_model: str | None,
    skip_vision: bool,
    scan_only: bool,
    no_filter: bool,
    temp_dir: str | None,
    project: str = "general",
) -> dict[str, Any]:
    """Process a single PDF/DOCX file. Returns stats dict."""

    doc_slug = doc_name.replace(" ", "_").lower()
    file_temp_dir = temp_dir or os.path.join(output_dir, "temp", doc_slug)

    print("=" * 60)
    print(f"Pre-processing: {doc_name}")
    print(f"   Input:  {input_path}")
    print(f"   Output: {output_dir}")
    print(f"   Project: {project}")
    print(f"   Model (diagram): {vision_model}")
    print(f"   Model (table):   {table_model or vision_model}")
    print(f"   Filter: {'OFF (--no-filter)' if no_filter else 'ON'}")
    print("=" * 60)

    # Step 1: Extract images + text + classify pages
    print("\nStep 1: Extracting images + text + classifying pages...")
    images, stats, text_pages = extract_images_from_pdf(
        input_path,
        file_temp_dir,
        enable_filter=not no_filter,
        scan_only=scan_only,
    )

    # Print classification summary
    print_scan_summary(stats, vision_model, table_model)

    # Scan-only mode: stop here
    if scan_only:
        return stats

    if not images and not text_pages:
        print("No content found in document.")
        return stats

    # Step 2: Copy images to public
    if images:
        print("\nStep 2: Copying images to public folder...")
        copy_images_to_public(images, doc_name, public_dir, project=project)
    else:
        print("\nStep 2: No images to copy (text-only document).")

    # Step 3: Create full markdown (text + vision descriptions)
    md_output = os.path.join(output_dir, f"{doc_slug}_full.md")

    if skip_vision:
        print("Step 3: Skipping Vision API (--skip-vision) — text-only output")
        image_base_url = f"{IMAGE_BASE_URL_DEFAULT}/{project}"
        output = [f"# {doc_name}\n"]
        # Write text pages
        for tp in text_pages:
            output.append(f"<!-- Trang {tp['page']} -->")
            output.append(tp["text"])
            output.append("")
        # Write image placeholders
        for img in images:
            page_class = img.get("page_class", "embedded")
            class_label = {"table": "Bảng", "diagram": "Sơ đồ", "embedded": "Hình ảnh"}.get(page_class, "Hình ảnh")
            img_filename = Path(img["file"]).name
            img_url = f"{image_base_url}/{doc_slug}/{img_filename}"
            output.append(f"### {class_label} — Trang {img['page']}")
            output.append(f"![{doc_name} - Trang {img['page']}]({img_url})")
            output.append("[Chưa có mô tả — chạy lại không có --skip-vision]\n")

        os.makedirs(output_dir, exist_ok=True)
        with open(md_output, "w", encoding="utf-8") as f:
            f.write("\n".join(output))
        print(f"  Saved placeholder: {md_output}")
    else:
        print(f"\nStep 3: Creating full markdown ({len(text_pages)} text pages + {len(images)} vision calls)...")
        create_full_markdown(
            images,
            text_pages=text_pages,
            doc_name=doc_name,
            output_path=md_output,
            api_key=api_key,
            project=project,
            api_url=api_url,
            model=vision_model,
            table_model=table_model,
        )

    # Summary
    print("\n" + "=" * 60)
    print("DONE!")
    print(f"   Full Markdown: {md_output}")
    if images:
        print(f"   Images:        {public_dir}/docs/{project}/{doc_slug}/")
    print()
    print("Next steps:")
    print(f"   1. Upload {md_output} vào Dify Knowledge Base")
    print(f"   2. KHÔNG cần upload PDF gốc (đã bao gồm text + ảnh)")
    print(f"   3. Test retrieval trong Dify")
    print("=" * 60)

    return stats


# ─── Helpers ─────────────────────────────────────────────────────────────────

SUPPORTED_EXTENSIONS = {".pdf"}  # DOCX support can be added later


def _auto_doc_name(filepath: str) -> str:
    """Generate a doc-name from a filename.

    'EMVCo_3DS_Spec_v220_122018.pdf' -> 'EMVCo_3DS_Spec_v220_122018'
    """
    return Path(filepath).stem


def _discover_files(input_dir: str) -> list[str]:
    """Find all supported files in a directory (non-recursive)."""
    files = []
    for entry in sorted(Path(input_dir).iterdir()):
        if entry.is_file() and entry.suffix.lower() in SUPPORTED_EXTENSIONS:
            files.append(str(entry))
    return files


# ─── CLI ─────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Pre-process technical documents: extract images, classify pages, Vision describe, output .md + copy images",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Batch: process ALL PDFs in a folder (single command)
  python preprocess_multimodal.py \\
    --input-dir "./input" \\
    --output-dir "./output" \\
    --public-dir "./frontend/public" \\
    --api-key "sk-or-..." \\
    --vision-model "google/gemini-2.5-flash" \\
    --table-model "google/gemini-2.5-pro"

  # Batch scan: preview stats for all files
  python preprocess_multimodal.py \\
    --input-dir "./input" \\
    --api-key "dummy" \\
    --scan-only

  # Single file (backward compatible)
  python preprocess_multimodal.py \\
    --input "docs/api_guide.pdf" \\
    --doc-name "Huong_dan_API_v2.1" \\
    --output-dir "./output" \\
    --public-dir "./frontend/public" \\
    --api-key "sk-or-..."

Output:
  ./output/<doc_name>_full.md                    -> Upload to Dify KB
  ./frontend/public/docs/<project>/<doc_name>/   -> Images served on web
        """,
    )

    # Input: single file OR directory (mutually exclusive)
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument("--input", "-i", help="Single PDF file path")
    input_group.add_argument("--input-dir", "-d", help="Directory of PDFs (batch mode - processes all)")

    parser.add_argument("--doc-name", "-n", default=None, help="Document name (auto-generated from filename if omitted)")
    parser.add_argument("--output-dir", "-o", default="./output", help="Output directory for .md files")
    parser.add_argument("--public-dir", "-p", default="./frontend/public", help="Next.js public directory")
    parser.add_argument("--api-key", "-k", required=True, help="Google Gemini API key (AIza...)")
    parser.add_argument("--api-url", default="https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", help="Vision API endpoint (default: Google Gemini)")
    parser.add_argument("--vision-model", default="gemini-2.5-flash", help="Vision model for diagrams + embedded images")
    parser.add_argument("--table-model", default=None, help="Vision model for tables (default: uses --vision-model)")
    parser.add_argument("--skip-vision", action="store_true", help="Skip Vision API (extract images only, no description)")
    parser.add_argument("--scan-only", action="store_true", help="Classify + stats only, no screenshots/Vision")
    parser.add_argument("--project", default="general", help="Project name for organizing images (e.g., 3ds2, qr_pay). Images saved to /docs/<project>/<doc_name>/")
    parser.add_argument("--no-filter", action="store_true", help="Disable boilerplate filter (screenshot all pages)")
    parser.add_argument("--temp-dir", default=None, help="Temp directory for extracted images (default: output-dir/temp)")

    args = parser.parse_args()

    # Collect files to process
    if args.input_dir:
        # Batch mode
        if not os.path.isdir(args.input_dir):
            print(f"Directory not found: {args.input_dir}")
            sys.exit(1)

        files = _discover_files(args.input_dir)
        if not files:
            print(f"No PDF files found in: {args.input_dir}")
            sys.exit(1)

        print("=" * 60)
        print(f"Batch mode: found {len(files)} file(s) in {args.input_dir}")
        for f in files:
            print(f"   - {Path(f).name}")
        print("=" * 60)
    else:
        # Single file mode
        if not os.path.exists(args.input):
            print(f"File not found: {args.input}")
            sys.exit(1)
        files = [args.input]

    # Process each file
    all_stats: list[tuple[str, dict[str, int]]] = []

    for idx, filepath in enumerate(files, 1):
        doc_name = args.doc_name if (args.doc_name and len(files) == 1) else _auto_doc_name(filepath)

        if len(files) > 1:
            print(f"\n{'#' * 60}")
            print(f"# [{idx}/{len(files)}] {Path(filepath).name}")
            print(f"{'#' * 60}")

        stats = process_single_file(
            input_path=filepath,
            doc_name=doc_name,
            output_dir=args.output_dir,
            public_dir=args.public_dir,
            api_key=args.api_key,
            api_url=args.api_url,
            vision_model=args.vision_model,
            table_model=args.table_model,
            skip_vision=args.skip_vision,
            scan_only=args.scan_only,
            no_filter=args.no_filter,
            temp_dir=args.temp_dir,
            project=args.project,
        )
        all_stats.append((Path(filepath).name, stats))

    # Batch summary
    if len(files) > 1:
        print("\n" + "=" * 60)
        print(f"BATCH SUMMARY ({len(files)} files)")
        print("=" * 60)
        total_tables = 0
        total_diagrams = 0

        for filename, stats in all_stats:
            t = stats.get("table", 0)
            d = stats.get("diagram", 0)
            total_tables += t
            total_diagrams += d
            print(f"   {filename}: {t} tables, {d} diagrams")

        total_calls = total_tables + total_diagrams
        print(f"\n   Total Vision API calls: {total_calls}")

        if args.scan_only:
            print("\nBatch scan done. Rerun without --scan-only to generate output.")
        else:
            print(f"\nBatch done! Output at: {args.output_dir}/")
            print("Next: upload all .md files to Dify Knowledge Base.")



if __name__ == "__main__":
    main()

