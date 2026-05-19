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
| 2. middleware | `install-middleware.sh` | Cài PostgreSQL, Redis, MySQL, tải Qdrant/MinIO/ES, **build Plugin Daemon từ source** |
| 3. databases | `setup-databases.sh` | Khởi tạo data directory, tạo database `dify` và `dify_plugin` |
| 4. env | `configure-dify-env.sh` | Tạo file `.env` cho Dify API, Dify Web, Plugin Daemon, Frontend |

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
| mysql | 3307 | Database cho RAGFlow |
| elasticsearch | 1200 | Full-text search cho RAGFlow |
| minio | 9000 | Object storage cho RAGFlow |
| ragflow-api | 9380 | RAGFlow API server |
| ragflow-worker | — | RAGFlow task executor |
| ragflow-web | 8080 | RAGFlow Vite frontend |
| chatbot-frontend | 3000 | Custom chatbot Next.js frontend |

### Về Dify Plugin Daemon

Plugin Daemon là thành phần quản lý vòng đời plugin cho Dify v0.14+. Có 2 binary riêng biệt:

- **`plugin-daemon-server`** — Server daemon thực sự, được build từ `cmd/server/main.go`. Đây là process chạy lắng nghe trên port 5002.
- **`plugin-daemon-cli`** — CLI tool dùng để chạy database migration (`migrate`), quản lý plugin. Đây là binary có trên GitHub Releases nhưng **KHÔNG phải server**.

Khi start, hệ thống sẽ tự động chạy `plugin-daemon-cli migrate` trước, sau đó `exec plugin-daemon-server`.

File cấu hình `.env` tại `runtime/ubuntu-stack/plugin-daemon.env` được tự động tạo bởi `configure-dify-env.sh`, bao gồm kết nối PostgreSQL (database `dify_plugin`, port 5433), Redis, và Dify Inner API.

## 5. Xử lý sự cố thường gặp

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

### Cập nhật config sau khi thay đổi script

Nếu bạn sửa file `stack.example.json`, cần ghi đè lại config local:
```bash
./scripts/ubuntu/bootstrap.sh --overwrite-config
```

## 6. Cấu trúc thư mục Runtime

```
runtime/
├── dify/                          # Source code Dify (git clone)
│   ├── api/.env                   # Cấu hình Dify API
│   └── web/.env.local             # Cấu hình Dify Web
├── ragflow/                       # Source code RAGFlow (git clone)
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
    │   ├── mysql/
    │   └── plugin-daemon/         # Storage cho plugin daemon
    ├── logs/                      # Log output của các service
    └── pids/                      # PID files
```
