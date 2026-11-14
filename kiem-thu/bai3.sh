#!/usr/bin/env bash
# Kiểm thử Bài 3: cấu hình HTTPS viết tay + redirect HTTP -> HTTPS.
# Không xin được chứng chỉ Let's Encrypt thật vì domain my-ecommerce.com không thuộc quyền quản lý của mình,
# nên dùng chứng chỉ TỰ KÝ đặt đúng đường dẫn /etc/letsencrypt/live/... để chạy thử cấu hình.
source "$(dirname "$0")/lib.sh"
trap cleanup EXIT

title "0) Tạo chứng chỉ tự ký đặt đúng vị trí Certbot sẽ tạo (chỉ để kiểm thử)"
vps "mkdir -p ~/ss11-run/letsencrypt/live/api.my-ecommerce.com && cd ~/ss11-run/letsencrypt/live/api.my-ecommerce.com && openssl req -x509 -newkey rsa:2048 -nodes -days 7 -subj '/CN=api.my-ecommerce.com' -addext 'subjectAltName=DNS:api.my-ecommerce.com' -keyout privkey.pem -out fullchain.pem 2>/dev/null && ls -l"

up "$ROOT/bai3/api.my-ecommerce.com" -v "$RUN/letsencrypt:/etc/letsencrypt:ro"

title "1) Kiểm tra cú pháp file cấu hình"
nginx_c "nginx -t"

title "2) Truy cập bằng HTTP -> bị chuyển hướng 301 sang HTTPS (giữ nguyên path + query)"
client "curl -sI 'http://api.my-ecommerce.com/api/products?page=1'"

title "3) Truy cập HTTPS"
client "curl -sS https://api.my-ecommerce.com/api/orders"
client "curl -sk https://api.my-ecommerce.com/api/orders"

title "4) Thông tin kết nối TLS và header HSTS"
client "curl -skv -o /dev/null https://api.my-ecommerce.com/api/orders 2>&1 | grep -iE 'SSL connection|subject:|issuer:|expire date|strict-transport'"

title "5) Trình duyệt gõ http:// sẽ tự theo redirect sang https://"
client "curl -skL -o /dev/null -w 'HTTP %{http_code}, số lần redirect: %{num_redirects}, URL cuối: %{url_effective}\n' http://api.my-ecommerce.com/api/orders"
