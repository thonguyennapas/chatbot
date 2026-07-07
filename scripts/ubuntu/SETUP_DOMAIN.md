# Hướng dẫn cấu hình Domain Public (3ds.hevitech.io.vn) chạy song song với Localhost

Để hỗ trợ truy cập từ bên ngoài qua domain `3ds.hevitech.io.vn` trong khi vẫn giữ nguyên hoạt động bình thường của `127.0.0.1:3000` ở nội bộ (local), cách chuẩn nhất là cài đặt một **Reverse Proxy** (thường dùng Nginx hoặc Caddy). 

Giải pháp này hoàn toàn an toàn: Nginx sẽ đứng ra nhận request từ domain public và chuyển tiếp (proxy pass) vào cổng `3000` đang chạy local của bạn. Frontend Next.js không cần sửa đổi gì.

Dưới đây là các bước cấu hình sử dụng **Nginx**.

## Bước 1: Trỏ Domain (DNS)
Trước tiên, bạn cần vào trang quản lý tên miền (nơi bạn mua `hevitech.io.vn`) và tạo một bản ghi (Record) DNS:
- **Type:** `A`
- **Name/Host:** `3ds`
- **Value/Points to:** `[IP_PUBLIC_CỦA_SERVER_UBUNTU]`

Đợi vài phút để DNS cập nhật.

## Bước 2: Cài đặt Nginx trên server Ubuntu
Mở terminal trên server Ubuntu và chạy lệnh sau để cài đặt Nginx:
```bash
sudo apt update
sudo apt install nginx -y
```

Đảm bảo Nginx đang chạy:
```bash
sudo systemctl enable nginx
sudo systemctl start nginx
```

## Bước 3: Tạo cấu hình Nginx cho Domain

Tạo một file cấu hình mới cho domain của bạn:
```bash
sudo nano /etc/nginx/sites-available/3ds.hevitech.io.vn
```

Dán nội dung sau vào file (Cấu hình này đã bao gồm hỗ trợ WebSocket cần thiết cho ứng dụng Chat streaming):

```nginx
server {
    listen 80;
    server_name 3ds.hevitech.io.vn;

    location / {
        proxy_pass http://127.0.0.1:3000;
        
        # Các header cần thiết để chuyển tiếp đúng IP và Host
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Cấu hình cực kỳ quan trọng cho WebSocket (Streaming text từ AI)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Bỏ qua timeout nếu câu trả lời AI quá dài
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
    }
}
```
*Nhấn `Ctrl+O`, `Enter` để lưu và `Ctrl+X` để thoát.*

## Bước 4: Kích hoạt cấu hình và Khởi động lại Nginx

Tạo symlink (liên kết) để kích hoạt cấu hình vừa tạo:
```bash
sudo ln -s /etc/nginx/sites-available/3ds.hevitech.io.vn /etc/nginx/sites-enabled/
```

Kiểm tra xem cú pháp Nginx có lỗi gì không:
```bash
sudo nginx -t
```
*(Nếu hiển thị `syntax is ok` và `test is successful` là thành công)*

Reload lại Nginx để áp dụng:
```bash
sudo systemctl reload nginx
```

## Bước 5: Cài đặt SSL/HTTPS (Bắt buộc để web an toàn)

Để trang web hiển thị là Bảo mật (có ổ khóa HTTPS) và tránh bị trình duyệt chặn, bạn cài chứng chỉ SSL miễn phí từ Let's Encrypt qua Certbot:

```bash
# Cài đặt Certbot cho Nginx
sudo apt install certbot python3-certbot-nginx -y

# Xin cấp chứng chỉ SSL tự động
sudo certbot --nginx -d 3ds.hevitech.io.vn
```
Certbot sẽ tự động cấu hình lại file Nginx ở Bước 3 để hỗ trợ HTTPS cổng 443 và tự động chuyển hướng HTTP sang HTTPS.

---

### Xác minh kết quả
Sau khi hoàn thành 5 bước trên:
1. Bạn có thể truy cập `https://3ds.hevitech.io.vn` từ bất kỳ mạng nào bên ngoài (điện thoại, mạng công ty). Request sẽ được Nginx chuyển hướng an toàn vào cổng 3000 trên server.
2. Bạn vẫn có thể truy cập `http://127.0.0.1:3000` (hoặc IP LAN của server) nếu dùng mạng nội bộ, vì tiến trình Next.js vẫn đang lắng nghe ở cổng đó bình thường. Không có xung đột nào xảy ra.
