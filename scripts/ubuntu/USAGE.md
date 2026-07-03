# Hướng dẫn Sử dụng Hệ thống Chatbot NAPAS

Tài liệu này hướng dẫn cách sử dụng hệ thống sau khi đã cài đặt và khởi động thành công (`manage.sh start` + `manage.sh status` hiển thị tất cả `RUNNING`).

> **Ghi chú:** Thay `<SERVER_IP>` bằng IP thực tế của máy chủ (ví dụ: `192.168.1.137`).

---

## Tổng quan hệ thống

Hệ thống gồm 3 thành phần chính, mỗi thành phần có giao diện web riêng:

| Thành phần | URL | Vai trò |
|---|---|---|
| **Dify** | `http://<SERVER_IP>:3001` | Nền tảng LLM — quản lý AI model, tạo chatbot/workflow |
| **RAGFlow** | `http://<SERVER_IP>:8080` | Nền tảng RAG — upload tài liệu, tạo knowledge base |
| **Chatbot Frontend** | `http://<SERVER_IP>:3000` | Giao diện chat cho người dùng cuối |

**Luồng hoạt động:**

```
Người dùng → Chatbot Frontend → Dify API → RAGFlow API → Tài liệu nội bộ
                                    ↓
                              LLM (DeepSeek/OpenAI)
                                    ↓
                            Câu trả lời + Trích dẫn nguồn
```

---

## Phần 1: Thiết lập Dify (Bắt buộc — Làm đầu tiên)

### 1.1 Tạo tài khoản Admin

1. Mở trình duyệt → `http://<SERVER_IP>:3001`
2. Lần đầu tiên sẽ hiện form **"Set up your account"**
3. Điền:
   - **Email**: email admin (ví dụ: `admin@napas.com.vn`)
   - **Username**: tên hiển thị
   - **Password**: mật khẩu mạnh
4. Nhấn **"Set up"** → Đăng nhập

### 1.2 Cấu hình Model Provider (LLM)

Đây là bước **quan trọng nhất** — hệ thống cần LLM để sinh câu trả lời.

1. Click avatar góc trái dưới → **Settings**
2. Chọn tab **"Model Provider"**
3. Tìm và thêm provider:

#### Option A: DeepSeek (Khuyến nghị — Giá rẻ, chất lượng cao)

1. Tìm **"DeepSeek"** trong danh sách
2. Click **"Set up"**
3. Nhập **API Key** từ [platform.deepseek.com](https://platform.deepseek.com)
4. Nhấn **Save**

#### Option B: OpenAI

1. Tìm **"OpenAI"** trong danh sách
2. Click **"Set up"**
3. Nhập **API Key** từ [platform.openai.com](https://platform.openai.com)
4. Nhấn **Save**

> **Mẹo:** Bạn có thể thêm nhiều provider cùng lúc. Dify cho phép chọn model khác nhau cho từng app.

### 1.3 Cấu hình System Model (Mặc định)

1. Vẫn trong **Settings** → Tab **"Model Provider"**
2. Phần **"System Model Settings"** ở trên cùng
3. Chọn model mặc định cho:
   - **System Reasoning Model**: `deepseek-chat` hoặc `gpt-4o`
   - **Embedding Model**: `text-embedding-3-small` (OpenAI) hoặc tương đương
4. Nhấn **Save**

### 1.4 Tạo App đầu tiên

1. Quay về trang chủ → Click **"Create from Blank"**
2. Chọn loại app:
   - **Chatbot**: Chat đơn giản
   - **Agent**: Chatbot có khả năng gọi tool
   - **Chatflow**: Workflow phức tạp kéo-thả
3. Đặt tên (ví dụ: "Trợ lý NAPAS")
4. Cấu hình:
   - Chọn **Model** (ví dụ: `deepseek-chat`)
   - Viết **System Prompt** (ví dụ: *"Bạn là trợ lý nội bộ NAPAS. Trả lời dựa trên tài liệu được cung cấp. Luôn trích dẫn nguồn."*)
5. Liên kết tri thức ngoài (External Knowledge Base) từ RAGFlow (Xem chi tiết hướng dẫn liên kết tại **Phần 2.7**).

> ⚠️ **Lưu ý quan trọng:** Không nên tải file trực tiếp lên Dify vì trình phân tách văn bản (chunking) của Dify rất đơn giản, dễ gây lỗi định dạng bảng biểu hoặc mất ngữ cảnh khi sinh câu trả lời. Hãy xử lý tài liệu trên RAGFlow và liên kết nó sang Dify.

---

## Phần 2: Thiết lập RAGFlow (Upload tài liệu)

### 2.1 Tạo tài khoản

1. Mở `http://<SERVER_IP>:8080`
2. Click **"Sign up"**
3. Điền email + password → Đăng ký → Đăng nhập

### 2.2 Cấu hình Model Provider

RAGFlow cần cả mô hình **Chat (LLM)** để trả lời câu hỏi và mô hình **Embedding (Nhúng)** để phân mảnh lập chỉ mục tài liệu.

1. Click vào avatar ở góc trên bên phải → Chọn **Model Providers**
2. **Cấu hình Chat Model (LLM):**
   - **Trường hợp dùng trực tiếp DeepSeek / OpenAI:** Chọn nhà cung cấp tương ứng → Nhập **API Key** → Nhấn **Save**.
   - **Trường hợp dùng OpenRouter (hoặc cổng API trung gian):**
     - Chọn nhà cung cấp **OpenRouter** (hoặc **OpenAI-compatible**).
     - Nhập **API Key** của OpenRouter (dạng `sk-or-v1-...`).
     - Nhập **Base URL**: `https://openrouter.ai/api/v1`
     - Nhấp nút **Add Model** để khai báo thủ công mô hình:
       - **Model Type**: Chọn `chat`
       - **Model Name**: Nhập chính xác ID model từ OpenRouter:
         - DeepSeek V3: `deepseek/deepseek-chat`
         - DeepSeek R1: `deepseek/deepseek-r1` (hoặc bản miễn phí: `deepseek/deepseek-r1:free`)
         - Claude 3.5 Sonnet: `anthropic/claude-3.5-sonnet`
         - GPT-4o: `openai/gpt-4o`
       - **Base URL**: Điền `https://openrouter.ai/api/v1` *(Lưu ý: RAGFlow yêu cầu điền lại Base URL cho từng model trong bảng popup này)*
       - **Max Tokens**: Điền `4096`
       - Nhấn **OK** để lưu.

3. **Cấu hình Embedding Model (Quan trọng & Bắt buộc):**
   - RAGFlow bắt buộc phải có mô hình nhúng để phân tích file. Bạn có các lựa chọn:
     - **Dùng mô hình chạy Offline (Khuyên dùng - Tiết kiệm chi phí):** Tìm nhà cung cấp **LocalAI** hoặc danh sách mô hình mặc định trong RAGFlow. Chọn mô hình **`BAAI/bge-m3`** hoặc **`BAAI/bge-large-zh-v1.5`** và bật lên (mô hình này chạy hoàn toàn bằng CPU/GPU của máy chủ, không tốn tiền API).
     - **Dùng Embedding qua OpenRouter (Nếu muốn dùng API ngoài):** Nhấn **Add Model** dưới thẻ cấu hình OpenRouter của bạn:
       - **Model Type**: Chọn `embedding`
       - **Model Name**: Điền chính xác ID mô hình nhúng của OpenRouter:
         - OpenAI Embedding Small: `openai/text-embedding-3-small`
         - OpenAI Embedding Large: `openai/text-embedding-3-large`
         - Cohere Multilingual V3: `cohere/embed-multilingual-v3`
         - BAAI BGE-M3 API: `baai/bge-m3`
       - **Base URL**: Điền `https://openrouter.ai/api/v1` *(Lưu ý: Điền Base URL tương tự như phần Chat)*
       - Nhấn **OK** để lưu.
     - **Dùng OpenAI Embedding trực tiếp:** Chọn OpenAI, nhập API Key và bật mô hình `text-embedding-3-small`.

### 2.3 Tạo Knowledge Base

1. Vào menu **"Knowledge"** (hoặc **"Kiến thức"**) ở thanh điều hướng trên cùng.
2. Click nút **"Create Dataset"** (hoặc **"Tạo cơ sở tri thức"**).
3. Điền:
   - **Name**: Tên knowledge base (ví dụ: *"Tài liệu quy trình NAPAS"*)
   - **Embedding Model**: Chọn model đã cấu hình
   - **Chunk Method (Phương thức phân mảnh - Cực kỳ quan trọng cho RAG)**: Chọn phương thức phù hợp nhất với loại tài liệu của NAPAS mà bạn định tải lên:
     - **General / Naive**: Phù hợp cho các văn bản quy chế, quy định hành chính, chính sách nhân sự hoặc quy trình vận hành chung (văn bản chủ yếu là các đoạn văn xuôi liền mạch).
     - **Table**: Đặc biệt khuyên dùng cho các tài liệu đặc tả kỹ thuật, bảng mã lỗi giao dịch, bảng phí dịch vụ, hoặc danh sách BIN thẻ ngân hàng (chứa nhiều bảng biểu, cột và dòng). RAGFlow sẽ phân tích cấu trúc bảng để LLM đọc đúng hàng ngang/cột dọc, tránh việc đọc lộn xộn thông tin.
     - **Q&A**: Tối ưu cho tài liệu hỗ trợ khách hàng, tài liệu đào tạo nội bộ dạng FAQ hoặc sổ tay hướng dẫn xử lý sự cố. RAGFlow sẽ tự động chuyển đổi văn bản thành các cặp câu hỏi-đáp để khớp cực nhanh với câu hỏi thực tế của người dùng.
     - **Manual**: Cho phép tự phân mảnh và căn chỉnh thủ công (tốn thời gian, chỉ dùng khi cần độ chính xác tuyệt đối cho một số văn bản đặc thù).
     - **Paper / Book**: Chỉ nên dùng khi bạn tải lên sách hoặc bài báo nghiên cứu dài.
4. Nhấn **"Create"** để tạo cơ sở tri thức.

> 💡 **Kinh nghiệm thực tế:** Bạn nên tạo **nhiều cơ sở tri thức (Knowledge Base) riêng biệt** tùy theo loại tài liệu (ví dụ: 1 KB dạng `Table` cho đặc tả kỹ thuật, 1 KB dạng `General` cho quy chế). Khi tạo App bên Dify, bạn hoàn toàn có thể liên kết đồng thời nhiều KB này vào để trợ lý AI có đầy đủ thông tin nhất!

### 2.4 Upload tài liệu

1. Trong Knowledge Base vừa tạo → Click **"Upload file"**
2. Chọn file:
   - Hỗ trợ: `.pdf`, `.docx`, `.xlsx`, `.pptx`, `.txt`, `.md`, `.csv`, `.html`
   - Tải lên nhiều file cùng lúc
3. Chờ hệ thống xử lý (parsing + chunking + embedding)
4. Trạng thái file sẽ chuyển từ `Unstarted` → `Processing` → `Done`

> **Lưu ý:** Thời gian xử lý phụ thuộc vào kích thước file và tốc độ embedding model. File PDF lớn (>50 trang) có thể mất vài phút.

### 2.5 Kiểm tra tài liệu đã xử lý

1. Click vào tên file đã upload
2. Xem danh sách **chunks** (đoạn văn bản đã chia)
3. Mỗi chunk hiển thị:
   - Nội dung text
   - Số token
   - Trạng thái embedding
4. Có thể **chỉnh sửa** hoặc **xóa** từng chunk nếu cần

### 2.6 Tạo Chat Assistant

1. Vào menu **"Chat"**
2. Click **"Create an Assistant"**
3. Cấu hình:
   - **Assistant Name**: Tên (ví dụ: *"Trợ lý tài liệu NAPAS"*)
   - **Knowledge Bases**: Chọn knowledge base đã tạo
   - **Model**: Chọn LLM (ví dụ: `deepseek-chat`)
   - **System Prompt**: Viết prompt hệ thống
   - **Top N**: Số đoạn văn bản tham khảo (mặc định 6)
   - **Similarity Threshold**: Ngưỡng tương đồng (mặc định 0.2)
4. Nhấn **"OK"** → Bắt đầu chat thử

### 2.7 Kết nối RAGFlow làm bộ nhớ Tri thức ngoài cho Dify (External Knowledge Base)

Để Dify (Bộ não suy luận) truy cập được tài liệu đã xử lý tối ưu từ RAGFlow (Bộ nhớ tri thức):

1. **Lấy API Key và Dataset ID từ RAGFlow:**
   - **API Key**: Trên RAGFlow UI, nhấn avatar ở góc phải → chọn **API Key** → **Create new key** và lưu lại key (dạng `ragflow-xxxxxxxx`).
   - **Dataset ID**: Vào menu **Knowledge** → click vào Knowledge Base bạn đã tạo → Chọn tab **Settings** → Copy chuỗi **Dataset ID** (định dạng UUID).

2. **Khai báo API Kết nối trong Dify:**
   - Mở Dify UI → Vào menu **Knowledge** ở bên trái → Chọn tab **External Knowledge API** ở trên cùng → Click **Add**.
   - Điền thông tin:
     - **Name**: `RAGFlow Local`
     - **API Endpoint**: `http://127.0.0.1:9380/api/v1/dify`
     - **API Key**: Điền RAGFlow API Key của bạn.
   - Nhấn **Save**.

3. **Liên kết Cơ sở tri thức ngoài:**
   - Quay lại tab **Knowledge** chính của Dify → Click nút **Connect to an External Knowledge Base**.
   - Điền thông tin:
     - **Name**: Tên hiển thị (ví dụ: `napas-rag-quality-mvp`)
     - **External KB API**: Chọn `RAGFlow Local`
     - **External KB ID**: Dán **Dataset ID** của RAGFlow.
   - Nhấn **Save**.

4. **Gán vào App Dify:**
   - Vào mục **Studio** → Mở App Dify của bạn (ví dụ: "Trợ lý NAPAS").
   - Tìm mục **Context (Ngữ cảnh)** → Click **Add** → Chọn Cơ sở tri thức ngoài `napas-rag-quality-mvp` vừa liên kết.

---

## Phần 3: Kết nối Chatbot Frontend với Dify

### 3.1 Lấy API Key từ Dify

Chatbot Frontend giao tiếp với Dify qua API. Cần lấy API Key:

1. Mở Dify: `http://<SERVER_IP>:3001`
2. Tạo một **App** (nếu chưa có) — xem Phần 1.4
3. Trong App, click **"API Access"** (góc trái)
4. Click **"API Key"** → **"Create"**
5. Copy API Key (dạng `app-xxxxxxxxxxxx`)

### 3.2 Cấu hình Frontend

Sửa file `frontend/.env.local` trên server:

```bash
nano ~/chatbot/frontend/.env.local
```

Cập nhật 3 dòng quan trọng:

```env
# Đã tự động set bởi configure-dify-env.sh:
DIFY_BASE_URL=http://127.0.0.1:5001

# ⚠️ BẮT BUỘC — Paste API Key từ bước 3.1:
DIFY_API_KEY=app-xxxxxxxxxxxx

# Tắt mock mode để dùng Dify thật:
DIFY_USE_MOCK=false
```

> ⚠️ **Không có `DIFY_API_KEY`**, chatbot sẽ chạy ở **mock mode** — trả lời giả lập, không dùng AI thật!

### 3.3 Restart Frontend (sau khi sửa .env)

```bash
cd ~/chatbot

# Build lại (vì production mode cần rebuild khi đổi env)
cd frontend && npm run build && cd ~/chatbot

# Restart chỉ frontend
./scripts/ubuntu/manage.sh restart chatbot-frontend
```

### 3.4 Kiểm tra kết nối

1. Mở `http://<SERVER_IP>:3000`
2. Đăng nhập
3. Nhập câu hỏi thử → Nếu câu trả lời có nội dung thật (không phải "phản hồi giả lập") → **Thành công!**

### 3.5 Tips sử dụng hiệu quả

- **Câu hỏi cụ thể** cho kết quả tốt hơn câu hỏi chung chung
  - ❌ *"Nói về NAPAS"*
  - ✅ *"Quy trình xử lý khiếu nại giao dịch thanh toán thẻ tại NAPAS gồm những bước nào?"*
- **Đặt câu hỏi follow-up** để đào sâu thêm
- **Yêu cầu trích dẫn** nếu chatbot không tự đưa ra: *"Trích dẫn nguồn tài liệu cho câu trả lời trên"*

---

## Phần 4: Quản trị hàng ngày

### 4.1 Khởi động/Tắt hệ thống

```bash
cd ~/chatbot

# Khởi động tất cả service
./scripts/ubuntu/manage.sh start

# Kiểm tra trạng thái
./scripts/ubuntu/manage.sh status

# Tắt tất cả service
./scripts/ubuntu/manage.sh stop

# Restart 1 service (ví dụ: sau khi update frontend code)
./scripts/ubuntu/manage.sh restart chatbot-frontend
```

### 4.2 Workflow update code

```bash
cd ~/chatbot
git pull

# Nếu sửa frontend:
cd frontend && npm run build && cd ~/chatbot
./scripts/ubuntu/manage.sh restart chatbot-frontend

# Nếu sửa config (stack.example.json):
./scripts/ubuntu/bootstrap.sh --overwrite-config
./scripts/ubuntu/manage.sh stop
./scripts/ubuntu/manage.sh start
```

### 4.2 Xem log

```bash
# Xem log theo service
tail -f ~/chatbot/runtime/ubuntu-stack/logs/dify-api.out.log
tail -f ~/chatbot/runtime/ubuntu-stack/logs/ragflow-api.err.log
tail -f ~/chatbot/runtime/ubuntu-stack/logs/chatbot-frontend.out.log

# Xem tất cả log cùng lúc
tail -f ~/chatbot/runtime/ubuntu-stack/logs/*.log
```

### 4.3 Thêm tài liệu mới

1. Mở RAGFlow → Knowledge Base
2. Upload file mới → Chờ xử lý
3. Không cần restart — chatbot sẽ tự động tìm kiếm trong tài liệu mới

### 4.4 Cập nhật LLM API Key

- **Dify:** Settings → Model Provider → Click provider → Update key
- **RAGFlow:** Avatar → Model Providers → Chọn provider → Update key

### 4.5 Backup dữ liệu

```bash
# Backup Postgres (Dify data)
su postgres -c "pg_dump -p 5433 dify" > ~/backup/dify_$(date +%Y%m%d).sql

# Backup MySQL (RAGFlow data)
mysqldump -h 127.0.0.1 -P 3306 -u ragflow -pragflow123 rag_flow > ~/backup/ragflow_$(date +%Y%m%d).sql

# Backup uploaded files (MinIO)
cp -r ~/chatbot/runtime/ubuntu-stack/data/minio ~/backup/minio_$(date +%Y%m%d)
```

### 4.6 Khởi động lại sau khi reboot server

```bash
cd ~/chatbot

# Đảm bảo MySQL system đang chạy
sudo systemctl start mysql

# Start stack
./scripts/ubuntu/manage.sh start
```

> **Gợi ý:** Thêm lệnh trên vào crontab để tự động start khi reboot:
> ```bash
> crontab -e
> # Thêm dòng:
> @reboot sleep 30 && cd /root/chatbot && ./scripts/ubuntu/manage.sh start >> /root/chatbot/runtime/ubuntu-stack/logs/autostart.log 2>&1
> ```

---

## Phần 5: URL tham khảo nhanh

| Giao diện | URL | Ghi chú |
|---|---|---|
| **Dify** (Quản lý AI) | `http://<SERVER_IP>:3001` | Tạo app, cấu hình LLM |
| **RAGFlow** (Quản lý tài liệu) | `http://<SERVER_IP>:8080` | Upload tài liệu, tạo knowledge base |
| **Chatbot** (Người dùng cuối) | `http://<SERVER_IP>:3000` | Giao diện chat |
| MinIO Console | `http://<SERVER_IP>:9001` | Quản lý file storage (login: `minioadmin`/`minioadmin`) |
| RAGFlow Admin API | `http://<SERVER_IP>:9381` | Admin endpoint |
| Dify API | `http://<SERVER_IP>:5001` | Backend API |
| RAGFlow API | `http://<SERVER_IP>:9380` | Backend API |
| Qdrant Dashboard | `http://<SERVER_IP>:6333/dashboard` | Vector store UI |

---

## Phần 6: Xử lý sự cố thường gặp (Troubleshooting)

### 6.1 Lỗi 403 Forbidden khi Setup / Init Dify
**Triệu chứng:** Khi truy cập trang cài đặt Dify hoặc nhập password khởi tạo, hệ thống trả về lỗi `403 Forbidden (authorization_error)`.
**Nguyên nhân:** Database PostgreSQL của Dify rơi vào trạng thái "nửa vời" (đã có Workspace/Tài khoản nhưng chưa hoàn thành ghi nhận setup vào bảng `dify_setups`), hoặc bị lỗi trong quá trình migration.
**Cách xử lý (Reset và Cài đặt lại từ đầu):**
1. Dừng các dịch vụ và giải phóng cổng:
   ```bash
   cd ~/chatbot
   ./scripts/ubuntu/manage.sh stop
   ```
2. Khởi động riêng Postgres:
   ```bash
   ./scripts/ubuntu/manage.sh restart postgres
   ```
3. Cưỡng chế xóa và tạo lại cơ sở dữ liệu `dify`:
   ```bash
   su postgres -c "psql -p 5433 -c 'DROP DATABASE IF EXISTS dify WITH (FORCE);'"
   su postgres -c "psql -p 5433 -c 'CREATE DATABASE dify;'"
   ```
4. Chạy lại DB Migration:
   ```bash
   cd ~/chatbot/runtime/dify/api
   uv run flask db upgrade
   ```
5. Khởi động lại toàn bộ hệ thống:
   ```bash
   cd ~/chatbot
   ./scripts/ubuntu/manage.sh start
   ```

### 6.2 Lỗi DB Migration trùng lặp Index / Hàm `uuidv7`
**Triệu chứng:** Khi chạy `flask db upgrade` trên database mới, gặp lỗi:
- `ProgrammingError: (psycopg2.errors.DuplicateTable) relation "workflow_node_executions_tenant_id_idx" already exists`
- `ProgrammingError: (psycopg2.errors.AmbiguousFunction) function name "uuidv7" is not unique`

**Nguyên nhân & Cách xử lý:**
Dify có sự mâu thuẫn trong file migration khi cài đặt trên hệ thống PostgreSQL mới (Postgres 17+ đã tích hợp sẵn hàm `uuidv7` ở hệ thống hoặc extension):
1. **Lỗi trùng Index:** Bọc lệnh tạo index trong `migrations/versions/*_workflow_draft_varaibles_add_node_execution_id.py` bằng khối lệnh `try...except` để bỏ qua nếu index đã được tạo tự động bởi Model.
2. **Lỗi trùng hàm `uuidv7`:** Bỏ qua hoàn toàn việc tạo hàm `uuidv7()` trong `migrations/versions/*_add_uuidv7_function_in_sql.py` và chỉ giữ lại việc tạo hàm `uuidv7_boundary` bằng câu lệnh `CREATE OR REPLACE FUNCTION` an toàn.
*(⚠️ Hệ thống hiện tại của bạn đã được cập nhật bản vá này trong mã nguồn nên các lượt deploy/migrate sau này sẽ không còn gặp lỗi này nữa).*

