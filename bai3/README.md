# Bài 3: Bảo mật bằng HTTPS với Let's Encrypt

| File | Nội dung |
|---|---|
| [`commands.sh`](commands.sh) | Toàn bộ chuỗi lệnh: cài đặt, xin chứng chỉ, kiểm tra, tự động gia hạn |
| [`api.my-ecommerce.com`](api.my-ecommerce.com) | File cấu hình HTTPS viết tay: `/etc/nginx/sites-available/api.my-ecommerce.com` |
| [`ket-qua-kiem-thu.txt`](ket-qua-kiem-thu.txt) | Output chạy thử cấu hình HTTPS |

## Điều kiện trước khi xin chứng chỉ

Let's Encrypt chỉ cấp chứng chỉ khi **chứng minh được mình quản lý domain** (thử thách HTTP-01). Máy chủ Let's Encrypt sẽ gọi vào `http://api.my-ecommerce.com/.well-known/acme-challenge/<token>` và Certbot phải trả lời đúng. Vì vậy cần:

1. **DNS**: bản ghi `A` của `api.my-ecommerce.com` trỏ về IP public của VPS. Kiểm tra bằng `dig +short api.my-ecommerce.com`.
2. **Cổng 80 và 443 mở** từ Internet, ở cả UFW và tường lửa của nhà cung cấp VPS.
3. Nginx có server block với `server_name api.my-ecommerce.com;`. Certbot dựa vào dòng này để biết cần sửa block nào.

## 1. Cài đặt `certbot` và `python3-certbot-nginx` trên Ubuntu

```bash
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx
certbot --version

sudo ufw allow 'Nginx Full'      # mở 80/tcp + 443/tcp
```

- `certbot`: công cụ ACME client, nói chuyện với Let's Encrypt để xin và gia hạn chứng chỉ.
- `python3-certbot-nginx`: plugin cho phép Certbot **tự đọc và sửa cấu hình Nginx** (`--nginx`).

## 2. Lệnh để Certbot tự cấp SSL và tự cấu hình Nginx

```bash
# Chạy thử trên máy chủ staging trước, tránh vượt giới hạn số lần cấp
sudo certbot certonly --nginx --dry-run -d api.my-ecommerce.com

# Xin chứng chỉ thật + tự cấu hình Nginx + tự redirect HTTP -> HTTPS
sudo certbot --nginx -d api.my-ecommerce.com --redirect \
     -m admin@my-ecommerce.com --agree-tos --no-eff-email
```

Lệnh này thực hiện các bước sau:
1. Tìm server block có `server_name api.my-ecommerce.com`, tạm thêm cấu hình để trả lời thử thách HTTP-01, sau đó reload Nginx.
2. Let's Encrypt xác thực thành công và cấp chứng chỉ. Chứng chỉ được lưu vào `/etc/letsencrypt/live/api.my-ecommerce.com/`.
3. Sửa server block: thêm `listen 443 ssl`, `ssl_certificate`, `ssl_certificate_key` và `include options-ssl-nginx.conf` (đánh dấu `# managed by Certbot`). Với `--redirect`, Certbot thêm cả block **301 từ HTTP sang HTTPS**.
4. Lưu thông tin gia hạn vào `/etc/letsencrypt/renewal/api.my-ecommerce.com.conf`, rồi reload Nginx.

Kiểm tra: `sudo certbot certificates`, `curl -I http://api.my-ecommerce.com` (trả về 301), `curl -I https://api.my-ecommerce.com` (trả về 200).

## 3. Cấu hình HTTPS viết tay (cổng 443)

File đầy đủ: [`api.my-ecommerce.com`](api.my-ecommerce.com)

```nginx
# Cổng 80: chỉ dùng để chuyển hướng sang HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name api.my-ecommerce.com;

    location /.well-known/acme-challenge/ {   # để gia hạn bằng --webroot vẫn chạy được
        root /var/www/certbot;
    }
    location / {
        return 301 https://$host$request_uri;  # giữ nguyên đường dẫn và query string
    }
}

# Cổng 443: HTTPS
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name api.my-ecommerce.com;

    ssl_certificate     /etc/letsencrypt/live/api.my-ecommerce.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.my-ecommerce.com/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    add_header Strict-Transport-Security "max-age=31536000" always;   # HSTS

    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;   # "https"
    }
}
```

### Trỏ tới `ssl_certificate` và `ssl_certificate_key`

Certbot tạo 4 file trong `/etc/letsencrypt/live/api.my-ecommerce.com/`:

| File | Nội dung | Dùng cho |
|---|---|---|
| `fullchain.pem` | Chứng chỉ domain **+** chứng chỉ trung gian của Let's Encrypt | **`ssl_certificate`** |
| `privkey.pem` | Khóa bí mật (chỉ root đọc được) | **`ssl_certificate_key`** |
| `cert.pem` | Chỉ chứng chỉ domain | *(không dùng cho Nginx)* |
| `chain.pem` | Chỉ chứng chỉ trung gian | `ssl_trusted_certificate` (nếu cần) |

- Phải dùng **`fullchain.pem`**, không dùng `cert.pem`. Nếu thiếu chứng chỉ trung gian, Chrome trên máy tính có thể vẫn chạy được, nhưng Android, `curl`, Java `HttpClient` và các app mobile sẽ báo lỗi chứng chỉ.
- Luôn trỏ vào thư mục **`live/`**. Các file ở đây là symlink tới bản mới nhất trong `archive/`, nên sau mỗi lần gia hạn không phải sửa cấu hình.
- `X-Forwarded-Proto $scheme` báo cho backend biết request gốc là HTTPS. Backend chỉ nói HTTP với Nginx ở nội bộ (gọi là *SSL termination*). Spring Boot cần header này để tạo đúng link `https://...` khi redirect.
- HTTP/2: Nginx ≥ 1.25.1 dùng `http2 on;`. Ubuntu 22.04 (1.18) và 24.04 (1.24) dùng `listen 443 ssl http2;`.

### Kiểm thử cấu hình
Mình **không xin được chứng chỉ thật cho `api.my-ecommerce.com`**, vì domain này không thuộc quyền quản lý của mình và Let's Encrypt sẽ từ chối ở bước xác thực.
Để chứng minh file cấu hình chạy đúng, mình tạo một **chứng chỉ tự ký** đặt đúng đường dẫn `/etc/letsencrypt/live/api.my-ecommerce.com/` rồi chạy Nginx với file cấu hình ở trên. Output đầy đủ: [`ket-qua-kiem-thu.txt`](ket-qua-kiem-thu.txt).

```
[nginx]$ nginx -t
nginx: configuration file /etc/nginx/nginx.conf test is successful

[client]$ curl -sI 'http://api.my-ecommerce.com/api/products?page=1'
HTTP/1.1 301 Moved Permanently
Location: https://api.my-ecommerce.com/api/products?page=1

[client]$ curl -sk https://api.my-ecommerce.com/api/orders
{"service":"api-gateway:8080","uri":"/api/orders","host":"api.my-ecommerce.com",
 "x_real_ip":"172.19.0.3","x_forwarded_for":"172.19.0.3","x_forwarded_proto":"https",...}

[client]$ curl -skv -o /dev/null https://api.my-ecommerce.com/api/orders 2>&1 | grep -iE '...'
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384 / X25519MLKEM768 / RSASSA-PSS
< Strict-Transport-Security: max-age=31536000

[client]$ curl -skL ... http://api.my-ecommerce.com/api/orders
HTTP 200, số lần redirect: 1, URL cuối: https://api.my-ecommerce.com/api/orders
```

Khi bỏ `-k`, curl báo `SSL certificate ... self-signed certificate`. Đây chính là cảnh báo "Not Secure" mà trình duyệt sẽ hiện, và cũng là lý do phải dùng chứng chỉ do CA được tin cậy như Let's Encrypt cấp.

## 4. Bẫy: chứng chỉ chỉ có hạn 90 ngày, tự động gia hạn thế nào?

### Cách 1 (mặc định trên Ubuntu): systemd timer có sẵn
Gói `certbot` cài bằng `apt` **đã tự tạo** `certbot.timer`. Timer này chạy `certbot -q renew` **2 lần mỗi ngày** (vào một thời điểm ngẫu nhiên để không dồn tải lên Let's Encrypt). Việc của mình là **kiểm tra lại** cho chắc:

```bash
systemctl list-timers certbot.timer           # timer có đang chạy không, lần chạy kế tiếp lúc nào
systemctl cat certbot.timer certbot.service   # lịch chạy + lệnh thực thi
sudo certbot renew --dry-run                  # giả lập gia hạn toàn bộ chứng chỉ
#   -> "Congratulations, all simulated renewals succeeded"
```

Lệnh `certbot renew` chỉ gia hạn những chứng chỉ **còn dưới 30 ngày**. Chạy 2 lần/ngày nên phần lớn các lần chạy không làm gì cả. Chứng chỉ được gia hạn khoảng 30 ngày trước khi hết hạn, nên còn nhiều lần thử lại nếu có lần gặp lỗi mạng.

Sau khi gia hạn, Nginx phải **reload** để nạp chứng chỉ mới. Chứng chỉ cấp bằng `--nginx` được Certbot tự reload. Để chắc chắn (và để dùng được với `--webroot`), thêm một *deploy hook*. Hook này chỉ chạy khi gia hạn thành công:

```bash
sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh > /dev/null <<'EOF'
#!/bin/sh
systemctl reload nginx
EOF
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

### Cách 2: cronjob (khi không có systemd timer, ví dụ cài certbot bằng pip)
```bash
sudo crontab -e
```
```cron
# Chạy lúc 03:00 và 15:00 mỗi ngày, chỉ reload Nginx khi thật sự có chứng chỉ mới
0 3,15 * * * certbot renew --quiet --deploy-hook "systemctl reload nginx"
```

### Lưu ý
- Dùng **`reload`, không dùng `restart`** trong hook để không làm gián đoạn người dùng. Lý do xem [Bài 4](../bai4/).
- Không nên chỉ dựa vào email nhắc hạn: Let's Encrypt **đã ngừng gửi email nhắc hết hạn từ năm 2025**. Họ cũng đã công bố lộ trình rút ngắn thời hạn chứng chỉ xuống **45 ngày**. Gia hạn tự động là cách duy nhất đáng tin.
- Theo dõi bằng `sudo certbot certificates` (xem ngày hết hạn) và `journalctl -u certbot.service` (xem log các lần chạy).
