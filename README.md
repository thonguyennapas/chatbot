# NAPAS Agentic RAG Chatbot

Dự án Hệ thống Chatbot Thông minh dành cho NAPAS ứng dụng kiến trúc **Agentic RAG (Retrieval-Augmented Generation)** tiên tiến, kết hợp khả năng suy luận tự động của AI Agents với hệ thống truy xuất tài liệu chuyên sâu.

## 🛠 Kiến trúc Hệ thống (Tech Stack)

Hệ thống được thiết kế theo kiến trúc Microservices hiện đại, tối ưu cho cả môi trường Windows (phát triển) và Ubuntu Linux (triển khai):

*   **Frontend (Giao diện):** Next.js 15, React, Tailwind CSS, TypeScript.
*   **AI Orchestration (Điều phối Agent):** Dify v0.14+
*   **Document Parsing & RAG Engine:** RAGFlow
*   **Databases & Middleware:** 
    *   **Vector Database:** Qdrant
    *   **Relational Database:** PostgreSQL (Dify), MySQL (RAGFlow)
    *   **Search Engine:** Elasticsearch
    *   **Object Storage:** MinIO
    *   **Cache:** Redis

## 🚀 Hướng dẫn Triển khai (Deployment)

Dự án hỗ trợ chạy Native (không dùng Docker) để tận dụng tối đa tài nguyên phần cứng. Chọn hệ điều hành tương ứng để xem hướng dẫn chi tiết:

### 1. Dành cho Ubuntu Server (Production / VPS)

Môi trường khuyên dùng để triển khai hệ thống thực tế. Toàn bộ quá trình cài đặt được tự động hóa thông qua công cụ quản lý trạng thái thông minh `manage.sh`.

👉 **[Xem Hướng dẫn Cài đặt trên Ubuntu](./scripts/ubuntu/README.md)**

### 2. Dành cho Windows (Local Development)

Môi trường dành cho lập trình viên phát triển trực tiếp trên máy cá nhân, sử dụng PowerShell script để tự động hóa cài đặt.

👉 **Mở PowerShell dưới quyền Admin và chạy:**
```powershell
# Chạy script bootstrap để kiểm tra môi trường và tạo file config
.\scripts\windows\bootstrap.ps1

# Cài đặt tự động các Middleware (Postgres, Qdrant...)
.\scripts\windows\install-middleware.ps1 -All

# Khởi động toàn bộ dự án
.\scripts\windows\start-stack.ps1
```

## 📁 Cấu trúc Mã nguồn

*   `/frontend`: Mã nguồn giao diện Chatbot (Next.js).
*   `/scripts`: Bộ script tự động hóa cài đặt cho Windows và Ubuntu.
*   `/runtime`: Thư mục (bị ẩn khỏi Git) chứa toàn bộ mã nguồn clone của Dify, RAGFlow và dữ liệu các Database sinh ra trong quá trình chạy.
*   `/docs`: Tài liệu thiết kế kiến trúc và kế hoạch triển khai.

## ⚠️ Lưu ý Quan trọng

*   **Bảo mật:** Không bao giờ push thư mục `runtime/` lên Git vì nó chứa toàn bộ mã nguồn hệ thống thứ 3 và các cơ sở dữ liệu nhạy cảm. Thư mục này đã được loại trừ tự động trong `.gitignore`.
*   **Cổng mạng (Ports):** Hệ thống sử dụng rất nhiều cổng (3000, 5001, 5002, 5433, 6333, 6379...). Vui lòng đảm bảo các cổng này không bị ứng dụng khác chiếm dụng trước khi khởi động dự án.
