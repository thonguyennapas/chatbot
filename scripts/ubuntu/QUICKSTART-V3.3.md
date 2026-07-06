# Triển Khai v3.3 trên Ubuntu Server — Full Dify

> **v3.3:** Kiến trúc lean — chỉ Dify + Qdrant. Không có RAGFlow.
> Tiết kiệm ~4GB RAM so với stack cũ.

## Yêu cầu Server

| Resource | Minimum | Khuyên dùng |
|---|---|---|
| Ubuntu | 22.04+ | 24.04 |
| CPU | 4 cores | 8 cores |
| RAM | 8 GB | 16 GB |
| Storage | 30 GB SSD | 50 GB SSD |
| Node.js | 18+ | 20+ |
| Python | 3.10+ | 3.12+ |
| Go | 1.22+ | (build Plugin Daemon) |

## Quick Start — Từ đầu đến xong

```bash
# ===== BƯỚC 1: Clone repo =====
git clone <repo-url> ~/chatbot
cd ~/chatbot

# ===== BƯỚC 2: Cấp quyền =====
chmod +x scripts/ubuntu/*.sh

# ===== BƯỚC 3: Dùng stack config v3.3 =====
cp scripts/ubuntu/stack.v3.3.json scripts/ubuntu/stack.example.json

# ===== BƯỚC 4: Cài đặt (tự động 4 bước) =====
./scripts/ubuntu/manage.sh install
#   → bootstrap.sh: clone Dify source, tạo thư mục
#   → install-middleware.sh: cài Postgres, Redis, download Qdrant, build Plugin Daemon
#   → setup-databases.sh: tạo DB dify, dify_plugin
#   → configure-dify-env.sh: tạo .env cho Dify API, Web, Frontend, Plugin Daemon

# ===== BƯỚC 5: Build Dify Web (Admin UI) =====
cd ~/chatbot/runtime/dify/web
corepack enable && corepack pnpm install
corepack pnpm build
cd ~/chatbot

# ===== BƯỚC 6: Build Chatbot Frontend =====
cd ~/chatbot/frontend
npm install
npm run build
cd ~/chatbot

# ===== BƯỚC 7: Khởi động =====
./scripts/ubuntu/manage.sh start

# ===== BƯỚC 8: Kiểm tra =====
./scripts/ubuntu/manage.sh status
# Cần 7 services RUNNING:
#   ✅ redis (6379)
#   ✅ postgres (5433)
#   ✅ qdrant (6333)
#   ✅ dify-api (5001)
#   ✅ dify-plugin-daemon (5002)
#   ✅ dify-web (3001)
#   ✅ chatbot-frontend (3000)
```

## Sau khi Start — Cấu hình Dify (trên trình duyệt)

### Bước 1: Tạo Admin Account
Mở trình duyệt → `http://<SERVER_IP>:3001/install`
→ Tạo email + password admin.

### Bước 2: Cấu hình Model Providers
```
Dify Admin → Settings → Model Provider:

1. Thêm OpenRouter (hoặc OpenAI/DeepSeek):
   - API Base: https://openrouter.ai/api/v1
   - API Key: sk-or-...
   - Dùng cho: LLM (Claude 4.6 Sonnet, Haiku)

2. Thêm Embedding Model:
   - OpenAI provider → text-embedding-3-large
   - Hoặc qua OpenRouter

3. Thêm Reranking Model (xem mục bên dưới)
```

### Bước 3: Tạo Knowledge Base (Ví dụ: Tài liệu 3DS2)

1. Đăng nhập Dify Admin → chọn tab **Knowledge** (Kiến thức) → **Create Knowledge Base**.
2. Kéo thả tài liệu kỹ thuật vào (PDF, DOCX, TXT, CSV, Markdown). *Lưu ý: Nếu có bảng mã lỗi Excel, nên convert sang CSV hoặc Markdown để parse chuẩn nhất.*
3. Cấu hình phân tích văn bản:
```text
   Name: napas_3ds2_knowledge_base
   Index Mode: High Quality (Dùng Embedding Model để vector hóa lưu vào Qdrant)
   Chunking Setting: Custom (Tùy chỉnh)
      - Chunk size: 800 - 1000 tokens (Giúp bối cảnh kỹ thuật không bị đứt đoạn)
      - Chunk overlap: 150 - 200 tokens
   Embedding Model: text-embedding-3-large
   Search Setting: Hybrid Search (BẮT BUỘC để tìm kiếm chính xác)
   Reranking: Enable
```

### Bước 4: Upload tài liệu
```
1. Copy tất cả file PDF/DOCX vào thư mục input/:
   cp ~/tai_lieu/*.pdf ~/chatbot/input/

2. Pre-processing ảnh/diagram (1 lệnh cho TẤT CẢ files):

   # Cài Python deps (chỉ lần đầu)
   pip3 install -r scripts/requirements.txt

   # Scan trước để xem thống kê + ước tính chi phí
   python3 scripts/preprocess_multimodal.py \
     --input-dir "./input" \
     --api-key "dummy" \
     --scan-only

   # Chạy pipeline (model rẻ cho diagram, pro cho bảng)
   python3 scripts/preprocess_multimodal.py \
     --input-dir "./input" \
     --output-dir "./output" \
     --public-dir "./frontend/public" \
     --api-key "sk-or-..." \
     --vision-model "google/gemini-2.5-flash" \
     --table-model "google/gemini-2.5-pro"

   # Kết quả (mỗi file 1 cặp output):
   #   output/<tên_file>_images.md → Upload vào Dify KB
   #   frontend/public/docs/images/<tên_file>/ → Ảnh serve trên web

3. Trên Dify: upload file PDF gốc + file .md (output) vào CÙNG Knowledge Base
```

### Bước 5: Tạo Chatflow & Link Knowledge Base

1. **Dify Admin → Studio → Create App → Chatflow**
2. Cấu hình luồng cơ bản:

```text
   [Start]
     │
     ▼
   [Question Classifier] ← Claude 4.6 Sonnet (Phân loại câu hỏi)
     │
     ├── Class 1: "Câu hỏi về 3DS2, tài liệu kỹ thuật"
     │     │
     │     ▼
     │   [Knowledge Retrieval] ← Chọn Context: napas_3ds2_knowledge_base
     │     │                     (top_k=8, score_threshold=0.4)
     │     ▼
     │   [LLM Summarizer] ← Claude 4.6 Sonnet, temp=0.2
     │     │                (Prompt: "Bạn là Trợ lý AI nội bộ của NAPAS chuyên về 3D Secure 2.0. 
     │     │                 Hãy dựa vào bối cảnh (Context) để trả lời. Trình bày bằng Markdown, 
     │     │                 sử dụng bảng biểu nếu cần thiết.")
     │     ▼
     │   [Answer]
     │
     └── Class 2: "Chào hỏi, chitchat, ngoài phạm vi"
           │
           ▼
         [LLM Chitchat] ← Claude Haiku (nhẹ), temp=0.7
           │
           ▼
         [Answer]
```

### Bước 6: Kết nối Frontend → Dify
```bash
# Sau khi Chatflow đã Publish:
# Dify → Studio → App → API Access → Copy API Key

# Edit frontend env:
nano ~/chatbot/frontend/.env.local

# Set:
DIFY_API_KEY=app-xxxxxxxxxxxxxxxxxxxx

# Restart frontend:
./scripts/ubuntu/manage.sh stop
./scripts/ubuntu/manage.sh start
```

## Reranking Model Setup

### Option A: Cohere API (không cần GPU — khuyến nghị)
```
Dify → Settings → Model Provider → Cohere:
  API Key: <cohere-api-key>
  → Model: rerank-multilingual-v3.0
```

### Option B: Self-host bge-reranker-v2-m3 (cần GPU)
```bash
docker run -d --gpus all -p 8002:80 \
  ghcr.io/huggingface/text-embeddings-inference:latest \
  --model-id BAAI/bge-reranker-v2-m3

# Trong Dify → Settings → Model Provider → OpenAI-compatible:
#   Server URL: http://<gpu-server>:8002
#   Model Type: Rerank
```

## Frontend .env.local

File `frontend/.env.local` được **tự động tạo** bởi `configure-dify-env.sh`:

```env
# Auto-generated:
SESSION_SECRET=<random 32 bytes>        # JWT session
DIFY_BASE_URL=http://127.0.0.1:5001     # Dify API cùng server
DIFY_API_KEY=                            # ← SET THỦ CÔNG sau bước 6
DIFY_USE_MOCK=false                      # Production mode
```

Nếu muốn tạo thủ công:
```bash
cp frontend/.env.local.example frontend/.env.local
# Edit SESSION_SECRET, DIFY_BASE_URL, DIFY_API_KEY
```

## Tóm tắt URL

| Giao diện | URL | Mục đích |
|---|---|---|
| **Dify Admin** | `http://<SERVER_IP>:3001` | Chatflow, KB, Model config |
| **Chatbot** | `http://<SERVER_IP>:3000` | Chat UI cho người dùng cuối |

## Quản lý hàng ngày

```bash
# Khởi động
./scripts/ubuntu/manage.sh start

# Tắt
./scripts/ubuntu/manage.sh stop

# Kiểm tra
./scripts/ubuntu/manage.sh status

# Xem log
tail -f ~/chatbot/runtime/ubuntu-stack/logs/dify-api.out.log
tail -f ~/chatbot/runtime/ubuntu-stack/logs/chatbot-frontend.out.log

# Giải phóng ports (khi bị Address already in use)
./scripts/ubuntu/manage.sh nuke-ports

# Reset toàn bộ data
./scripts/ubuntu/manage.sh nuke-data
```

## Xử lý sự cố

### dify-api không start (port 5001 timeout)
```bash
tail -50 ~/chatbot/runtime/ubuntu-stack/logs/dify-api.err.log

# Nếu lỗi Alembic migration:
cd ~/chatbot/runtime/dify/api
uv run flask db stamp heads
cd ~/chatbot && ./scripts/ubuntu/manage.sh start
```

### Frontend không hiển thị ảnh
```bash
# Kiểm tra ảnh có trong public/:
ls ~/chatbot/frontend/public/docs/images/

# Kiểm tra build đã chạy chưa:
cd ~/chatbot/frontend && npm run build

# Restart:
cd ~/chatbot && ./scripts/ubuntu/manage.sh stop && ./scripts/ubuntu/manage.sh start
```
