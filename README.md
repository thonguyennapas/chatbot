# NAPAS Agentic RAG Chatbot

Dự án Hệ thống Chatbot Thông minh dành cho NAPAS ứng dụng kiến trúc **Agentic RAG (Retrieval-Augmented Generation)** tiên tiến, kết hợp khả năng suy luận tự động của AI Agents với hệ thống truy xuất tài liệu chuyên sâu.

## 🛠 Kiến trúc Hệ thống (v3.3 — Full Dify)

Hệ thống sử dụng kiến trúc **Full Dify** (monolithic), tối ưu cho vài tài liệu kỹ thuật:

*   **Frontend (Giao diện):** Next.js 16, React, Tailwind CSS, TypeScript.
*   **AI Orchestration + RAG Engine:** Dify v0.14+ (Chatflow 2 nhánh + Knowledge Base)
*   **Databases & Middleware:**
    *   **Vector Database:** Qdrant (Hybrid Search: vector + BM25)
    *   **Relational Database:** PostgreSQL (Dify)
    *   **Cache:** Redis

## 🚀 Hướng dẫn Triển khai (Deployment)

Dự án hỗ trợ chạy Native (không dùng Docker) để tận dụng tối đa tài nguyên phần cứng.

### Ubuntu Server (Production / VPS) — Khuyên dùng

👉 **[Xem Quick Start v3.3](./scripts/ubuntu/QUICKSTART-V3.3.md)**

```bash
# Quick setup
git clone <repo-url> ~/chatbot && cd ~/chatbot
chmod +x scripts/ubuntu/*.sh
cp scripts/ubuntu/stack.v3.3.json scripts/ubuntu/stack.example.json
./scripts/ubuntu/manage.sh install
./scripts/ubuntu/manage.sh start
```

### Windows (Local Development)

```powershell
.\scripts\windows\bootstrap.ps1
.\scripts\windows\install-middleware.ps1 -All
.\scripts\windows\start-stack.ps1
```

## 📁 Cấu trúc Mã nguồn

*   `/frontend`: Mã nguồn giao diện Chatbot (Next.js).
*   `/scripts`: Bộ script tự động hóa cài đặt cho Windows và Ubuntu.
*   `/scripts/preprocess_multimodal.py`: Pipeline extract ảnh → Vision describe → Markdown.
*   `/runtime`: Thư mục (bị ẩn khỏi Git) chứa mã nguồn Dify và dữ liệu Database.
*   `/docs`: Tài liệu thiết kế kiến trúc và kế hoạch triển khai.

## ⚠️ Lưu ý Quan trọng

*   **Bảo mật:** Không bao giờ push thư mục `runtime/` lên Git vì nó chứa mã nguồn hệ thống thứ 3 và dữ liệu nhạy cảm. Đã được loại trừ trong `.gitignore`.
*   **Cổng mạng (Ports):** Hệ thống sử dụng các cổng: 3000 (Chatbot), 3001 (Dify Web), 5001 (Dify API), 5002 (Plugin Daemon), 5433 (Postgres), 6333 (Qdrant), 6379 (Redis).
