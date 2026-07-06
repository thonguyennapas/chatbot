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
# ⚠️ Nếu đã cài lần trước (có runtime/ubuntu-stack/stack.local.json cũ),
#    thêm --overwrite-config để ghi đè config cũ (có thể còn ragflow/elasticsearch):
#    ./scripts/ubuntu/manage.sh install --overwrite-config
./scripts/ubuntu/manage.sh install
#   → bootstrap.sh: clone Dify source, tạo thư mục, copy stack.example.json → stack.local.json
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
# Cần 8 services RUNNING:
#   ✅ redis (6379)
#   ✅ postgres (5433)
#   ✅ qdrant (6333)
#   ✅ dify-api (5001)
#   ✅ dify-worker (no port — background task processor)
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

1. Thêm Google Gemini:
   - Provider: Google
   - API Key: AIza...
   - Dùng cho: LLM (gemini-2.5-flash, gemini-2.5-pro)

2. Embedding Model:
   - Dùng Google: text-embedding-004
   - Hoặc OpenAI: text-embedding-3-large

3. Thêm Reranking Model (xem mục bên dưới)
```

### Bước 3: Tạo Knowledge Base

Dify Admin → **Knowledge** tab → **Create Knowledge** (hoặc URL: `/datasets/create`)

#### 3.1 Upload tài liệu

Kéo thả file PDF/DOCX/TXT/CSV/Markdown vào.

> **Lưu ý:** Bảng mã lỗi Excel nên convert sang CSV hoặc Markdown trước khi upload — Dify parse Excel không tốt.

#### 3.2 Chunk Settings (Phân đoạn văn bản)

⚠️ **Chunk Mode không đổi được sau khi tạo Knowledge Base.** Chọn kỹ.

**So sánh 2 chế độ:**

| | **General** | **Parent-child** |
|---|---|---|
| **Cấu trúc** | Phẳng — tất cả chunk ngang hàng | Phân cấp — parent chứa child |
| **Cách tìm** | Tìm chunk → trả chunk đó | Tìm child chunk (chính xác) → trả parent chunk (đầy đủ ngữ cảnh) |
| **Khi nào dùng** | Tài liệu ngắn, FAQ, mỗi đoạn độc lập | Tài liệu dài, kỹ thuật, chi tiết nằm rải rác trong đoạn lớn |
| **Khuyên dùng cho Napas** | ✅ Tài liệu mã lỗi, bảng tra cứu | ✅ Tài liệu spec EMVCo, API guide dài |

**Cấu hình chi tiết (cho General mode):**

| Setting | Giá trị | Giải thích |
|---|---|---|
| **Delimiter** | `\n\n` (mặc định) | Tách theo đoạn văn. Dùng `\n` nếu muốn mịn hơn. |
| **Max Chunk Length** | **800 – 1000** | Đủ dài để giữ nguyên bảng + đoạn kỹ thuật. |
| **Chunk Overlap** | **150 – 200** | Giữ liên tục ngữ nghĩa giữa các chunk liền kề. |

**Cấu hình chi tiết (cho Parent-child mode):**

| Setting | Giá trị | Giải thích |
|---|---|---|
| **Parent Chunk Length** | **1500 – 2000** | Chunk lớn chứa ngữ cảnh đầy đủ, trả về cho LLM. |
| **Child Chunk Length** | **200 – 500** | Chunk nhỏ dùng để tìm kiếm chính xác. |
| **Delimiter** | `\n\n` | Tách ở ranh giới đoạn văn. |

#### 3.3 Index Method (Phương pháp lập chỉ mục)

| Option | Chọn | Giải thích |
|---|---|---|
| **High Quality** | ✅ BẮT BUỘC | Dùng Embedding Model vector hóa → lưu vào Qdrant. Hỗ trợ Hybrid Search + Rerank. |
| Economical | ❌ Không dùng | Chỉ keyword search, không hỗ trợ semantic, chất lượng kém. |

#### 3.4 Embedding Model

| Setting | Giá trị |
|---|---|
| **Model** | `text-embedding-3-large` (OpenAI) |
| **Provider** | OpenAI provider đã thêm ở Bước 2 (hoặc qua OpenRouter) |

> Nếu đổi model sau → Dify tự re-embed toàn bộ tài liệu (chạy background, mất thời gian).

#### 3.5 Retrieval Settings (Cấu hình truy xuất)

**So sánh 3 chế độ:**

| Retrieval Mode | Cách hoạt động | Khi nào dùng |
|---|---|---|
| **Vector Search** | Tìm theo ngữ nghĩa (embedding similarity) | Câu hỏi tự nhiên, diễn đạt khác tài liệu |
| **Full-Text Search** | Tìm theo keyword chính xác | Mã lỗi, tên field, ID cụ thể |
| **Hybrid Search** ✅ | Kết hợp cả hai + trọng số điều chỉnh | **Khuyên dùng** — tốt nhất cho tài liệu kỹ thuật |

**Cấu hình Hybrid Search:**

| Setting | Giá trị khuyến nghị | Giải thích |
|---|---|---|
| **Semantic Weight** | **0.7** | Ưu tiên tìm theo ý nghĩa câu hỏi. |
| **Keyword Weight** | **0.3** | "Lưới an toàn" cho mã lỗi, tên API, ID chính xác. |
| **Top K** | **5 – 8** | Số chunk trả về cho LLM. Tăng nếu câu trả lời thiếu context. |
| **Score Threshold** | **0.3 – 0.5** | Loại chunk điểm thấp. Tăng nếu câu trả lời chứa noise. |

> **Semantic 0.7 / Keyword 0.3** là mặc định tốt. Với tài liệu Napas (nhiều mã lỗi + error code), có thể thử **0.5 / 0.5** nếu thấy tìm mã lỗi kém.

**Rerank Model (tùy chọn nhưng khuyên dùng):**

| Option | Giải thích |
|---|---|
| **Weighted Score** (không cần Rerank) | Dùng trọng số semantic/keyword ở trên để xếp hạng. Miễn phí. |
| **Rerank Model** ✅ (khuyên dùng) | Dùng model AI (Cohere `rerank-multilingual-v3.0`) để sắp xếp lại top kết quả. Chính xác hơn nhưng tốn thêm API call. Xem mục *Reranking* bên dưới để setup. |

4. Nhấn **Save & Process** → Dify bắt đầu chunk + embed. Theo dõi tiến trình trên giao diện.

### Bước 4: Pre-process + Upload tài liệu
```
1. Copy tất cả file PDF/DOCX vào thư mục input/:
   cp ~/tai_lieu/*.pdf ~/chatbot/input/

2. Pre-processing (extract text + bảng + diagram → 1 file .md):

   # Cài Python deps (chỉ lần đầu)
   pip3 install -r scripts/requirements.txt

   # Scan trước để xem thống kê + ước tính chi phí
   python3 scripts/preprocess_multimodal.py \
     --input-dir "./input" \
     --project "3ds2" \
     --api-key "dummy" \
     --scan-only

   # Chạy pipeline (dùng Google Gemini Flash — rẻ, nhanh)
   python3 scripts/preprocess_multimodal.py \
     --input-dir "./input" \
     --output-dir "./output" \
     --public-dir "./frontend/public" \
     --project "3ds2" \
     --api-key "AIza..."  \
     --vision-model "gemini-2.5-flash"

   # Kết quả:
   #   output/<tên_file>_full.md                    → Upload vào Dify KB
   #   frontend/public/docs/3ds2/<tên_file>/        → Ảnh serve trên web
   #
   # Ví dụ project khác: --project "qr_pay", --project "tokenization"

3. Trên Dify: upload CHỈ file .md (output) vào Knowledge Base
   → KHÔNG cần upload PDF gốc (file .md đã chứa đầy đủ text + mô tả bảng/diagram)
```

### Bước 5: Tạo Chatflow & Link Knowledge Base

1. **Dify Admin → Studio → Create App → Chatflow**
2. Cấu hình luồng cơ bản:

```text
   [Start]
     │
     ▼
   [Question Classifier] ← Gemini 2.5 Flash (Phân loại câu hỏi)
     │
     ├── Class 1: "Câu hỏi về 3DS2, tài liệu kỹ thuật"
     │     │
     │     ▼
     │   [Knowledge Retrieval] ← Chọn Context: napas_3ds2_knowledge_base
     │     │                     (top_k=8, score_threshold=0.4)
     │     ▼
     │   [LLM Summarizer] ← Gemini 2.5 Flash, temp=0.2
     │     │                (Prompt: "Bạn là Trợ lý AI nội bộ của NAPAS chuyên về 3D Secure 2.0. 
     │     │                 Hãy dựa vào bối cảnh (Context) để trả lời. Trình bày bằng Markdown, 
     │     │                 sử dụng bảng biểu nếu cần thiết.")
     │     ▼
     │   [Answer]
     │
     └── Class 2: "Chào hỏi, chitchat, ngoài phạm vi"
           │
           ▼
         [LLM Chitchat] ← Gemini 2.5 Flash (nhẹ), temp=0.7
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
