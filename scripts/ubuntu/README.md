# Cài đặt Agentic RAG Stack trên Ubuntu (Native)

Bộ công cụ này giúp bạn triển khai toàn bộ dự án (Dify, RAGFlow, Frontend) trực tiếp trên máy chủ Ubuntu mà **không cần sử dụng Docker**, giúp tối ưu hóa hiệu năng phần cứng.

## 1. Yêu cầu hệ thống

| Phần mềm | Phiên bản tối thiểu | Cách kiểm tra |
|---|---|---|
| Ubuntu | 22.04+ | `lsb_release -a` |
| Node.js | 18+ | `node -v` |
| Python | 3.10+ | `python3 --version` |
| Go | 1.22+ | `go version` |
| jq | bất kỳ | `jq --version` |
| uv | bất kỳ | `uv --version` |
| corepack | bất kỳ | `corepack --version` |

> **Quan trọng:** Go là bắt buộc vì Dify Plugin Daemon phải được **build từ source code** (binary release trên GitHub chỉ là CLI tool, không phải server daemon).

### Dịch vụ hệ thống bắt buộc

Stack sử dụng **MySQL system service** (quản lý bởi systemd) thay vì tự khởi động MySQL riêng. Đảm bảo MySQL đã được cài và đang chạy:

```bash
sudo apt-get install -y mysql-server
sudo systemctl enable mysql
sudo systemctl start mysql
```

## 2. Chuẩn bị

Trước khi chạy bất cứ thứ gì, bạn cần cấp quyền thực thi cho toàn bộ các script trong thư mục này:

```bash
chmod +x scripts/ubuntu/*.sh
```

## 3. Công cụ Quản lý Tập trung (`manage.sh`)

Thay vì phải chạy từng script đơn lẻ, mọi thao tác điều khiển hệ thống đều được gói gọn trong công cụ `manage.sh`.

### Cài đặt toàn bộ hệ thống (Install)

Lệnh này sẽ tự động tải các phần mềm phụ trợ (PostgreSQL, Redis...), khởi tạo Database và setup môi trường:

```bash
./scripts/ubuntu/manage.sh install
```

> **Tính năng Resume (Lưu trạng thái):** 
> Nếu quá trình cài đặt bị gián đoạn (ví dụ: rớt mạng khi đang tải), bạn chỉ cần chạy lại lệnh trên. Hệ thống sẽ đọc file trạng thái ngầm và **chạy tiếp từ đúng bước bị lỗi** thay vì phải cài lại từ đầu.

**Pipeline cài đặt gồm 4 bước:**

| Bước | Script | Mô tả |
|---|---|---|
| 1. bootstrap | `bootstrap.sh` | Tạo thư mục runtime, copy config, clone source Dify & RAGFlow |
| 2. middleware | `install-middleware.sh` | Cài PostgreSQL, Redis, tải Qdrant/MinIO/ES, **build Plugin Daemon từ source** |
| 3. databases | `setup-databases.sh` | Khởi tạo data directory, tạo database `dify`, `dify_plugin`, `rag_flow` |
| 4. env | `configure-dify-env.sh` | Tạo file `.env` cho Dify API, Dify Web, Plugin Daemon, Frontend, và `service_conf.yaml` cho RAGFlow |

### Bước bổ sung: Cài đặt Python dependencies

Sau khi `manage.sh install` hoàn thành, cần cài thêm Python dependencies cho RAGFlow:

```bash
cd ~/chatbot/runtime/ragflow
uv sync --python 3.13 --prerelease=allow --index-strategy unsafe-best-match \
  --default-index https://pypi.org/simple/
```

> **Lưu ý:** Flag `--default-index https://pypi.org/simple/` là bắt buộc vì RAGFlow mặc định dùng mirror Aliyun (Trung Quốc), kết nối từ Việt Nam thường bị timeout.

### Bước bổ sung: Tạo MySQL user cho RAGFlow

RAGFlow cần MySQL user riêng (Ubuntu system MySQL dùng `auth_socket` cho root, không cho phép login qua TCP):

```bash
sudo mysql -e "
CREATE USER IF NOT EXISTS 'ragflow'@'127.0.0.1' IDENTIFIED BY 'ragflow123';
CREATE USER IF NOT EXISTS 'ragflow'@'localhost' IDENTIFIED BY 'ragflow123';
CREATE DATABASE IF NOT EXISTS rag_flow CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON rag_flow.* TO 'ragflow'@'127.0.0.1';
GRANT ALL PRIVILEGES ON rag_flow.* TO 'ragflow'@'localhost';
FLUSH PRIVILEGES;
"
```

### Khởi động & Tắt hệ thống

Sau khi cài đặt xong, bạn dùng các lệnh sau để vận hành hệ thống hàng ngày:

- **Khởi động tất cả dịch vụ:**
  ```bash
  ./scripts/ubuntu/manage.sh start
  ```
- **Kiểm tra trạng thái (đang chạy hay đã tắt):**
  ```bash
  ./scripts/ubuntu/manage.sh status
  ```
- **Tắt toàn bộ dịch vụ an toàn:**
  ```bash
  ./scripts/ubuntu/manage.sh stop
  ```

### Xử lý sự cố & Dọn dẹp (Nuke)

Trong quá trình phát triển, nếu hệ thống bị treo hoặc bạn muốn cài lại từ đầu, hãy sử dụng 2 lệnh "hủy diệt" sau:

- **Giải phóng Cổng & RAM:**
  ```bash
  ./scripts/ubuntu/manage.sh nuke-ports
  ```
  *Tác dụng:* Chủ động truy quét và "ép buộc đóng" (kill -9) bất kỳ tiến trình nào đang chiếm dụng các cổng mạng của dự án (5001, 6379, 5433...). Dùng khi bạn bị lỗi `Address already in use` hoặc hết RAM.

- **Dọn sạch toàn bộ Dữ liệu:**
  ```bash
  ./scripts/ubuntu/manage.sh nuke-data
  ```
  *Tác dụng:* Xóa sạch toàn bộ Database (Postgres, Qdrant), file tạm, log và xóa luôn bộ nhớ trạng thái cài đặt. Dùng khi bạn muốn **Reset dự án về trạng thái như mới tải về**.

## 4. Kiến trúc dịch vụ

Khi chạy `manage.sh start`, các service được khởi động theo thứ tự sau (định nghĩa trong `stack.local.json`):

| Service | Port | Mô tả |
|---|---|---|
| redis | 6379 | Cache & message broker |
| postgres | 5433 | Database chính (Dify + Plugin Daemon) |
| qdrant | 6333 | Vector store cho Dify |
| dify-api | 5001 | Dify Flask API server |
| dify-plugin-daemon | 5002 | Quản lý plugin, build từ source (`cmd/server/main.go`) |
| dify-web | 3001 | Dify Next.js frontend |
| mysql | *(system)* | Database cho RAGFlow — **quản lý bởi systemd** trên port 3306 |
| elasticsearch | 1200 | Full-text search cho RAGFlow (security disabled) |
| minio | 9000 | Object storage cho RAGFlow |
| ragflow-api | 9380 | RAGFlow API server (chạy qua `uv run`) |
| ragflow-worker | — | RAGFlow task executor (chạy qua `uv run`) |
| ragflow-web | 8080 | RAGFlow Vite frontend |
| chatbot-frontend | 3000 | Custom chatbot Next.js frontend |

### Về MySQL

Stack sử dụng **MySQL system service** (cài qua `apt-get`, quản lý bởi `systemd`) trên port mặc định 3306. Không tự khởi động MySQL riêng vì:
- Ubuntu AppArmor chặn mysqld truy cập data directory ngoài `/var/lib/mysql`
- System MySQL ổn định hơn, tự restart khi reboot

RAGFlow kết nối MySQL bằng user `ragflow` / password `ragflow123` (tạo bởi bước setup ở mục 3).

### Về Elasticsearch

Elasticsearch 8.x mặc định **bật security** (yêu cầu authentication). Stack tắt hoàn toàn security vì chạy local:
```
-Expack.security.enabled=false
-Expack.security.http.ssl.enabled=false
-Expack.security.transport.ssl.enabled=false
```

### Về RAGFlow

RAGFlow sử dụng `uv run python` thay vì `python3` trực tiếp để đảm bảo chạy trong virtual environment đã cài đầy đủ dependencies (quart, peewee, valkey, v.v.). Cấu hình kết nối dịch vụ nằm tại `runtime/ragflow/conf/service_conf.yaml`, được tự động tạo bởi `configure-dify-env.sh`.

### Về Dify Plugin Daemon

Plugin Daemon là thành phần quản lý vòng đời plugin cho Dify v0.14+. Có 2 binary riêng biệt:

- **`plugin-daemon-server`** — Server daemon thực sự, được build từ `cmd/server/main.go`. Đây là process chạy lắng nghe trên port 5002.
- **`plugin-daemon-cli`** — CLI tool dùng để chạy database migration (`migrate`), quản lý plugin. Đây là binary có trên GitHub Releases nhưng **KHÔNG phải server**.

Khi start, hệ thống sẽ tự động chạy `plugin-daemon-cli migrate` trước, sau đó `exec plugin-daemon-server`.

File cấu hình `.env` tại `runtime/ubuntu-stack/plugin-daemon.env` được tự động tạo bởi `configure-dify-env.sh`, bao gồm kết nối PostgreSQL (database `dify_plugin`, port 5433), Redis, và Dify Inner API.

## 5. Sau khi Start — Hướng dẫn sử dụng

> 📖 **Hướng dẫn chi tiết:** Xem file [USAGE.md](USAGE.md) để có hướng dẫn đầy đủ từng bước với hình ảnh minh họa cho việc thiết lập Dify, RAGFlow, upload tài liệu, quản trị hàng ngày và backup.

Sau khi `manage.sh start` chạy thành công và `manage.sh status` hiển thị tất cả service `RUNNING`, bạn truy cập các giao diện web qua trình duyệt. Thay `<SERVER_IP>` bằng IP máy chủ (ví dụ: `192.168.1.137`):

### Bước 1: Thiết lập Dify

1. Mở `http://<SERVER_IP>:3001`
2. **Lần đầu tiên:** Tạo tài khoản admin (email + password)
3. Vào **Settings** → **Model Provider** → Thêm API key cho LLM:
   - **DeepSeek** (khuyên dùng): Nhập API key từ [platform.deepseek.com](https://platform.deepseek.com)
   - **OpenAI**: Nhập API key từ [platform.openai.com](https://platform.openai.com)
   - Hoặc bất kỳ provider nào Dify hỗ trợ
4. Tạo **App** → Chọn loại (Chatbot, Agent, Workflow...)
5. Cấu hình Knowledge Base nếu cần (Dify dùng Qdrant làm vector store)

### Bước 2: Thiết lập RAGFlow

1. Mở `http://<SERVER_IP>:8080`
2. **Lần đầu tiên:** Đăng ký tài khoản
3. Vào **Model Providers** → Thêm LLM (DeepSeek, OpenAI...)
4. Tạo **Knowledge Base**:
   - Đặt tên (ví dụ: "Tài liệu nội bộ NAPAS")
   - Chọn **Embedding model** (cần cấu hình model provider trước)
   - Upload tài liệu (.pdf, .docx, .txt, .md...)
5. Tạo **Chat Assistant**:
   - Liên kết với Knowledge Base vừa tạo
   - Chọn LLM cho chat
   - Tùy chỉnh System Prompt

### Bước 3: Sử dụng Chatbot Frontend

1. Mở `http://<SERVER_IP>:3000`
2. Đăng nhập (nếu có cấu hình auth)
3. Bắt đầu đặt câu hỏi — chatbot sẽ tìm kiếm tài liệu nội bộ và trả lời kèm trích dẫn nguồn

### Tóm tắt URL

| Giao diện | URL | Mục đích |
|---|---|---|
| Dify | `http://<SERVER_IP>:3001` | Quản lý LLM, tạo App/Workflow |
| RAGFlow | `http://<SERVER_IP>:8080` | Upload tài liệu, tạo Knowledge Base |
| Chatbot | `http://<SERVER_IP>:3000` | Giao diện chat cho người dùng cuối |
| MinIO Console | `http://<SERVER_IP>:9001` | Quản lý file storage (optional) |
| RAGFlow Admin | `http://<SERVER_IP>:9381` | Admin API của RAGFlow (optional) |

## 6. Xử lý sự cố thường gặp

### dify-api không khởi động được (port 5001 timeout)

**Triệu chứng:**
```
Error: Service 'dify-api' did not open port 5001 within 90 seconds.
```

**Bước 1: Kiểm tra log lỗi**
```bash
tail -50 ~/chatbot/runtime/ubuntu-stack/logs/dify-api.err.log
```

**Bước 2: Nếu log báo lỗi Alembic migration** (ví dụ: `DuplicateTable`, `AmbiguousFunction`, `relation already exists`...)

Nguyên nhân: Quá trình `flask db upgrade` bị gián đoạn giữa chừng, khiến schema đã được tạo trong Postgres nhưng Alembic chưa kịp ghi nhận revision vào bảng `alembic_version`.

**Cách fix:** Stamp database tới revision mới nhất (bỏ qua các migration đã apply một phần):

```bash
cd ~/chatbot/runtime/dify/api
uv run flask db stamp heads
```

Sau đó khởi động lại:
```bash
cd ~/chatbot
./scripts/ubuntu/manage.sh start
```

> **Lưu ý:** Lệnh `stamp heads` chỉ ghi revision vào DB mà **không chạy bất kỳ SQL nào**. Chỉ dùng khi lỗi là do object đã tồn tại (duplicate). Nếu lỗi là thiếu table/column thì không nên stamp mà cần xử lý migration cụ thể.

### dify-plugin-daemon không khởi động được (port 5002 timeout)

**Triệu chứng:**
```
Error: Service 'dify-plugin-daemon' did not open port 5002 within 60 seconds.
```

Khi service bị timeout, hệ thống sẽ tự động in ra 10 dòng log lỗi cuối cùng. Dựa vào đó để xử lý:

**Trường hợp 1: `unknown command "server"`**

Binary đang dùng là CLI tool thay vì server. Cần build lại:
```bash
rm -rf runtime/ubuntu-stack/bin/plugin-daemon
sudo ./scripts/ubuntu/install-middleware.sh
```

**Trường hợp 2: Database connection error**

Đảm bảo database `dify_plugin` đã tồn tại:
```bash
su postgres -c "createdb -p 5433 dify_plugin" 2>/dev/null || echo "DB already exists"
```

**Trường hợp 3: File `.env` chưa được tạo**

```bash
rm -f runtime/ubuntu-stack/plugin-daemon.env
./scripts/ubuntu/configure-dify-env.sh
```

**Trường hợp 4: Kiểm tra log chi tiết**
```bash
tail -30 ~/chatbot/runtime/ubuntu-stack/logs/dify-plugin-daemon.err.log
tail -30 ~/chatbot/runtime/ubuntu-stack/logs/dify-plugin-daemon.out.log
```

### ragflow-api không khởi động được (port 9380 timeout)

**Triệu chứng:**
```
Error: Service 'ragflow-api' did not open port 9380 within 120 seconds.
```

**Trường hợp 1: `ModuleNotFoundError: No module named 'quart'`**

Python dependencies chưa được cài. Chạy:
```bash
cd ~/chatbot/runtime/ragflow
uv sync --python 3.13 --prerelease=allow --index-strategy unsafe-best-match \
  --default-index https://pypi.org/simple/
```

**Trường hợp 2: `Elasticsearch is unhealthy`**

Kiểm tra ES có bật security không:
```bash
curl -s http://localhost:1200
```

Nếu trả về `401 Unauthorized`, ES đang bật authentication. Kiểm tra `stack.local.json` có flag `-Expack.security.enabled=false`:
```bash
grep "xpack.security.enabled" runtime/ubuntu-stack/stack.local.json
```

Nếu thiếu, thêm vào rồi restart ES:
```bash
sed -i 's/-Expack.security.http.ssl.enabled=false/-Expack.security.enabled=false -Expack.security.http.ssl.enabled=false/' runtime/ubuntu-stack/stack.local.json
./scripts/ubuntu/manage.sh stop
./scripts/ubuntu/manage.sh start
```

**Trường hợp 3: `AUTH <password> called without any password configured`**

Redis password trong `service_conf.yaml` không khớp. Redis của stack chạy không có password, nhưng config RAGFlow có password. Fix:
```bash
# Xem password hiện tại
grep -A4 "redis:" runtime/ragflow/conf/service_conf.yaml

# Nếu password không rỗng, reset config
rm -f runtime/ragflow/conf/service_conf.yaml
./scripts/ubuntu/configure-dify-env.sh
```

**Trường hợp 4: `Access denied for user 'root'@'localhost'`**

Ubuntu system MySQL dùng `auth_socket` cho root. Cần tạo user riêng:
```bash
sudo mysql -e "
CREATE USER IF NOT EXISTS 'ragflow'@'127.0.0.1' IDENTIFIED BY 'ragflow123';
CREATE USER IF NOT EXISTS 'ragflow'@'localhost' IDENTIFIED BY 'ragflow123';
CREATE DATABASE IF NOT EXISTS rag_flow CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON rag_flow.* TO 'ragflow'@'127.0.0.1';
GRANT ALL PRIVILEGES ON rag_flow.* TO 'ragflow'@'localhost';
FLUSH PRIVILEGES;
"
```

**Trường hợp 5: `Can't connect to MySQL server` (Connection refused)**

Kiểm tra system MySQL có đang chạy không:
```bash
sudo systemctl status mysql
ss -tlnp | grep mysql
```

Đảm bảo `service_conf.yaml` dùng port 3306 (system MySQL) chứ không phải 3307:
```bash
grep "port:" runtime/ragflow/conf/service_conf.yaml
```

### Cập nhật config sau khi thay đổi script

Nếu bạn sửa file `stack.example.json`, cần ghi đè lại config local:
```bash
./scripts/ubuntu/bootstrap.sh --overwrite-config
```

Nếu bạn muốn tạo lại toàn bộ file `.env` và `service_conf.yaml`:
```bash
rm -f runtime/dify/api/.env runtime/dify/web/.env.local runtime/ubuntu-stack/plugin-daemon.env runtime/ragflow/conf/service_conf.yaml
./scripts/ubuntu/configure-dify-env.sh
```

## 7. Cấu trúc thư mục Runtime

```
runtime/
├── dify/                          # Source code Dify (git clone)
│   ├── api/.env                   # Cấu hình Dify API
│   └── web/.env.local             # Cấu hình Dify Web
├── ragflow/                       # Source code RAGFlow (git clone)
│   ├── conf/service_conf.yaml     # Cấu hình kết nối dịch vụ (auto-generated)
│   └── .venv/                     # Python virtual env (tạo bởi uv sync)
└── ubuntu-stack/
    ├── stack.local.json           # Config dịch vụ (copy từ stack.example.json)
    ├── plugin-daemon.env          # Cấu hình Plugin Daemon
    ├── .install_state             # File trạng thái cài đặt (resume)
    ├── bin/
    │   ├── plugin-daemon/
    │   │   ├── plugin-daemon-server  # Server binary (build từ source)
    │   │   └── plugin-daemon-cli     # CLI binary (build từ source)
    │   ├── qdrant/
    │   ├── minio/
    │   └── elasticsearch/
    ├── src/
    │   └── dify-plugin-daemon/    # Source code plugin daemon (git clone)
    ├── data/
    │   ├── postgres/
    │   └── plugin-daemon/         # Storage cho plugin daemon
    ├── logs/                      # Log output của các service
    └── pids/                      # PID files
```

## 8. Quick Reference — Cài đặt từ đầu

Tóm tắt toàn bộ quy trình cho người mới:

```bash
# 1. Clone repo
git clone <repo-url> ~/chatbot
cd ~/chatbot

# 2. Cấp quyền
chmod +x scripts/ubuntu/*.sh

# 3. Cài đặt pipeline (tự động 4 bước)
./scripts/ubuntu/manage.sh install

# 4. Cài Python dependencies cho RAGFlow
cd runtime/ragflow
uv sync --python 3.13 --prerelease=allow --index-strategy unsafe-best-match \
  --default-index https://pypi.org/simple/
cd ~/chatbot

# 5. Tạo MySQL user cho RAGFlow
sudo mysql -e "
CREATE USER IF NOT EXISTS 'ragflow'@'127.0.0.1' IDENTIFIED BY 'ragflow123';
CREATE USER IF NOT EXISTS 'ragflow'@'localhost' IDENTIFIED BY 'ragflow123';
CREATE DATABASE IF NOT EXISTS rag_flow CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON rag_flow.* TO 'ragflow'@'127.0.0.1';
GRANT ALL PRIVILEGES ON rag_flow.* TO 'ragflow'@'localhost';
FLUSH PRIVILEGES;
"

# 6. Khởi động
./scripts/ubuntu/manage.sh start

# 7. Kiểm tra
./scripts/ubuntu/manage.sh status

# 8. ⚠️ CẤU HÌNH LLM (BẮT BUỘC) — Không có bước này, chatbot không hoạt động!
# Mở Dify:    http://<SERVER_IP>:3001 → Tạo admin → Settings → Model Provider → Thêm DeepSeek API Key
# Mở RAGFlow: http://<SERVER_IP>:8080 → Đăng ký → Model Providers → Thêm DeepSeek API Key
# Lấy API key tại: https://platform.deepseek.com

# 9. Truy cập
# Dify:     http://<SERVER_IP>:3001  (Quản lý AI, tạo App)
# RAGFlow:  http://<SERVER_IP>:8080  (Upload tài liệu, tạo Knowledge Base)
# Chatbot:  http://<SERVER_IP>:3000  (Giao diện chat)
```

> ⚠️ **LLM API Key là bắt buộc!** Hệ thống không chạy model AI local. Bạn cần có API key từ [DeepSeek](https://platform.deepseek.com) (khuyến nghị) hoặc [OpenAI](https://platform.openai.com) và cấu hình trong cả Dify lẫn RAGFlow sau khi start. Xem chi tiết tại [USAGE.md](USAGE.md).
