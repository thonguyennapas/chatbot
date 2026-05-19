# Cài đặt Agentic RAG Stack trên Ubuntu (Native)

Bộ công cụ này giúp bạn triển khai toàn bộ dự án (Dify, RAGFlow, Frontend) trực tiếp trên máy chủ Ubuntu mà **không cần sử dụng Docker**, giúp tối ưu hóa hiệu năng phần cứng.

## 1. Chuẩn bị

Trước khi chạy bất cứ thứ gì, bạn cần cấp quyền thực thi cho toàn bộ các script trong thư mục này:

```bash
chmod +x scripts/ubuntu/*.sh
```

## 2. Công cụ Quản lý Tập trung (`manage.sh`)

Thay vì phải chạy từng script đơn lẻ, mọi thao tác điều khiển hệ thống đều được gói gọn trong công cụ `manage.sh`.

### Cài đặt toàn bộ hệ thống (Install)

Lệnh này sẽ tự động tải các phần mềm phụ trợ (PostgreSQL, Redis...), khởi tạo Database và setup môi trường:

```bash
./scripts/ubuntu/manage.sh install
```

> **Tính năng Resume (Lưu trạng thái):** 
> Nếu quá trình cài đặt bị gián đoạn (ví dụ: rớt mạng khi đang tải), bạn chỉ cần chạy lại lệnh trên. Hệ thống sẽ đọc file trạng thái ngầm và **chạy tiếp từ đúng bước bị lỗi** thay vì phải cài lại từ đầu.

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

## 3. Xử lý sự cố thường gặp

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
Error: Service 'dify-plugin-daemon' did not open port 5002 within 15 seconds.
```

**Bước 1: Kiểm tra log lỗi**
```bash
tail -30 ~/chatbot/runtime/ubuntu-stack/logs/dify-plugin-daemon.err.log
tail -30 ~/chatbot/runtime/ubuntu-stack/logs/dify-plugin-daemon.out.log
```

**Bước 2: Nếu log không có lỗi rõ ràng** — có thể do timeout quá ngắn (mặc định 15s). Mở file `runtime/ubuntu-stack/stack.local.json`, tìm service `dify-plugin-daemon` và tăng `startupTimeoutSeconds` lên `30` hoặc `60`:

```json
{
  "name": "dify-plugin-daemon",
  "startupTimeoutSeconds": 30
}
```

Sau đó khởi động lại:
```bash
./scripts/ubuntu/manage.sh start
```

**Bước 3: Nếu log báo lỗi `KEY` hoặc `permission denied`** — kiểm tra binary plugin-daemon có quyền thực thi:
```bash
chmod +x ~/chatbot/runtime/ubuntu-stack/bin/plugin-daemon/plugin-daemon
```
