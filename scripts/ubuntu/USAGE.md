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
5. Bật **Knowledge** nếu muốn kết nối tài liệu

---

## Phần 2: Thiết lập RAGFlow (Upload tài liệu)

### 2.1 Tạo tài khoản

1. Mở `http://<SERVER_IP>:8080`
2. Click **"Sign up"**
3. Điền email + password → Đăng ký → Đăng nhập

### 2.2 Cấu hình Model Provider

1. Click avatar → **Model Providers**
2. Thêm provider (giống Dify):
   - Chọn **DeepSeek** hoặc **OpenAI**
   - Nhập API Key
   - **Quan trọng:** Thêm cả **Embedding model** (ví dụ: `BAAI/bge-m3` từ Hugging Face hoặc `text-embedding-3-small` từ OpenAI)

### 2.3 Tạo Knowledge Base

1. Vào menu **"Knowledge Base"**
2. Click **"Create Knowledge Base"**
3. Điền:
   - **Name**: Tên knowledge base (ví dụ: *"Tài liệu quy trình NAPAS"*)
   - **Embedding Model**: Chọn model đã cấu hình
   - **Chunk Method**: Chọn cách chia tài liệu:
     - **Naive**: Chia theo kích thước cố định (đơn giản, nhanh)
     - **Q&A**: Tự động tạo cặp hỏi-đáp (tốt cho FAQ)
     - **Manual**: Chia theo heading/section
     - **Paper**: Tối ưu cho bài báo khoa học
     - **Book**: Tối ưu cho sách
     - **Table**: Tối ưu cho bảng biểu
4. Nhấn **"Create"**

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

---

## Phần 3: Sử dụng Chatbot Frontend

### 3.1 Truy cập

1. Mở `http://<SERVER_IP>:3000`
2. Đăng nhập (nếu có cấu hình authentication)

### 3.2 Chat

1. Nhập câu hỏi vào ô chat (ví dụ: *"Quy trình thanh toán liên ngân hàng là gì?"*)
2. Chatbot sẽ:
   - Tìm kiếm trong knowledge base
   - Lấy các đoạn tài liệu liên quan
   - Sinh câu trả lời bằng LLM
   - Hiển thị **trích dẫn nguồn** kèm theo

### 3.3 Tips sử dụng hiệu quả

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
