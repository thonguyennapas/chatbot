#!/usr/bin/env python3
"""
preprocess_multimodal.py — Pre-processing pipeline for Napas Technical Docs using pymupdf4llm

Pipeline:
1. Use pymupdf4llm to extract high-fidelity structural Markdown (headings, lists, tables).
2. pymupdf4llm automatically extracts figures/diagrams to temporary PNG files.
3. Parse the Markdown to find image links.
4. Call Gemini Vision API on each image to generate a detailed text description.
5. Inject the description below the image in the Markdown.
6. Copy images to Next.js /public/docs/images/ and rewrite URLs.
7. Generate _full.md (for frontend) and _kb.md (for Dify).

Usage (batch):
  python preprocess_multimodal.py \
    --input-dir "./input" \
    --output-dir "./output" \
    --public-dir "./frontend/public" \
    --project "3ds2" \
    --api-key "sk-or-..." \
    --vision-model "gemini-2.5-flash"
"""

import argparse
import base64
import os
import re
import shutil
import sys
from pathlib import Path
from typing import Any
import json

# Fix Windows console encoding
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass

try:
    import pymupdf4llm
except ImportError:
    print("❌ pymupdf4llm chưa cài. Chạy: pip install pymupdf4llm")
    sys.exit(1)

try:
    import requests
except ImportError:
    print("❌ requests chưa cài. Chạy: pip install requests")
    sys.exit(1)


IMAGE_BASE_URL_DEFAULT = "/docs"

PROMPT_DIAGRAM = """Describe the detailed content of this image/diagram in English.

Rules:
- If this is a FLOWCHART/SEQUENCE DIAGRAM: list EACH STEP in order, describe arrows/connections between components.
- If this is a SYSTEM ARCHITECTURE: list components, connections, protocols, ports.
- If this is a CHART: describe data, axes, trends.
- If there is TEXT in the image: extract verbatim.
- Describe as detailed as possible — this text will be indexed for search.
"""

def describe_image_with_vision(
    image_path: str,
    api_key: str,
    prompt: str,
    api_url: str = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
    model: str = "gemini-2.5-flash",
) -> str:
    with open(image_path, "rb") as f:
        image_b64 = base64.b64encode(f.read()).decode()

    ext = Path(image_path).suffix.lower()
    mime_map = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg"}
    mime_type = mime_map.get(ext, "image/png")

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
                "max_completion_tokens": 2000,
                "temperature": 0.2,
            },
            timeout=180,
        )
        if not response.ok:
            return f"[LỖI: API trả về {response.status_code}]"
        data = response.json()
        return data["choices"][0]["message"]["content"]
    except Exception as e:
        return f"[LỖI: Không thể mô tả ảnh — {e}]"


def process_single_file(
    input_path: str,
    doc_name: str,
    output_dir: str,
    public_dir: str,
    api_key: str,
    api_url: str,
    vision_model: str,
    skip_vision: bool,
    scan_only: bool,
    temp_dir: str | None,
    project: str = "general",
) -> dict[str, Any]:
    
    doc_slug = doc_name.replace(" ", "_").lower()
    file_temp_dir = temp_dir or os.path.join(output_dir, "temp", doc_slug)
    os.makedirs(file_temp_dir, exist_ok=True)
    
    print("=" * 60)
    print(f"Processing with pymupdf4llm: {doc_name}")
    
    if scan_only:
        print("Scan only mode enabled. Note: pymupdf4llm needs full extraction to count images.")
    
    # 1. Extract markdown and images
    print("Step 1: Extracting structural Markdown and saving diagrams...")
    # write_images=True automatically extracts vector graphics and raster images!
    md_text = pymupdf4llm.to_markdown(
        doc=input_path,
        write_images=True,
        image_path=file_temp_dir,
        image_format="png",
        dpi=200
    )
    
    # 2. Parse markdown for images
    # pymupdf4llm outputs images like: ![Image](path/to/image.png)
    image_pattern = re.compile(r'!\[([^\]]*)\]\(([^)]+)\)')
    
    images_found = 0
    vision_calls = 0
    
    # Setup public dir
    public_target_dir = Path(public_dir) / "docs" / project / doc_slug
    public_target_dir.mkdir(parents=True, exist_ok=True)
    
    def image_replacer(match):
        nonlocal images_found, vision_calls
        alt_text = match.group(1)
        local_img_path = match.group(2)
        
        # Resolve the local image path
        img_filename = Path(local_img_path).name
        img_full_path = Path(file_temp_dir) / img_filename
             
        if not img_full_path.exists():
            # Sometimes it might just be an external URL or missing
            return match.group(0)
            
        images_found += 1
        
        # Copy to public
        if not scan_only:
            shutil.copy2(img_full_path, public_target_dir / img_filename)
        
        new_url = f"{IMAGE_BASE_URL_DEFAULT}/{project}/{doc_slug}/{img_filename}"
        new_image_tag = f"![{alt_text}]({new_url})"
        
        if scan_only:
            return new_image_tag
            
        if skip_vision:
            desc = "[Chưa có mô tả — chạy lại không có --skip-vision]"
        else:
            print(f"  🔍 Vision API: Describing {img_filename}...")
            desc = describe_image_with_vision(str(img_full_path), api_key, PROMPT_DIAGRAM, api_url, vision_model)
            vision_calls += 1
            
        return f"{new_image_tag}\n\n{desc}\n"

    print("Step 2: Processing images and injecting Vision descriptions...")
    final_md_text = image_pattern.sub(image_replacer, md_text)
    
    if scan_only:
        print(f"Scan complete. Found {images_found} diagrams/images.")
        return {}
        
    print(f"Step 3: Saving Markdown files (Processed {images_found} images)...")
    md_output = os.path.join(output_dir, f"{doc_slug}_full.md")
    with open(md_output, "w", encoding="utf-8") as f:
        f.write(final_md_text)
        
    # Create KB version (no image refs)
    kb_output = os.path.join(output_dir, f"{doc_slug}_kb.md")
    kb_content = re.sub(r'!\[([^\]]*)\]\(([^)]*)\)', r'[📎 \1](\2)', final_md_text)
    with open(kb_output, "w", encoding="utf-8") as f:
        f.write(kb_content)
        
    print("=" * 60)
    print("DONE!")
    print(f"   Full Markdown:  {md_output}")
    print(f"   KB Markdown:    {kb_output}")
    if images_found > 0:
        print(f"   Images:        {public_target_dir}")
    print("=" * 60)
    
    return {}


SUPPORTED_EXTENSIONS = {".pdf"}

def main() -> None:
    parser = argparse.ArgumentParser(description="Pre-process technical documents using pymupdf4llm.")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--input", "-i", help="Single PDF file path")
    group.add_argument("--input-dir", "-d", help="Directory of PDFs")
    
    parser.add_argument("--doc-name", "-n")
    parser.add_argument("--output-dir", "-o", default="./output")
    parser.add_argument("--public-dir", "-p", default="./frontend/public")
    parser.add_argument("--api-key", "-k", required=True)
    parser.add_argument("--api-url", default="https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
    parser.add_argument("--vision-model", default="gemini-2.5-flash")
    parser.add_argument("--table-model", default="") # Ignored in this version
    parser.add_argument("--skip-vision", action="store_true")
    parser.add_argument("--scan-only", action="store_true")
    parser.add_argument("--project", default="general")
    parser.add_argument("--no-filter", action="store_true") # Ignored
    parser.add_argument("--temp-dir")

    args = parser.parse_args()
    
    if args.input:
        files = [args.input]
    else:
        files = [str(p) for p in Path(args.input_dir).iterdir() if p.suffix.lower() in SUPPORTED_EXTENSIONS]
        
    for f in files:
        doc_name = args.doc_name or Path(f).stem
        process_single_file(
            f, doc_name, args.output_dir, args.public_dir, args.api_key,
            args.api_url, args.vision_model, args.skip_vision, args.scan_only,
            args.temp_dir, args.project
        )

if __name__ == "__main__":
    main()
