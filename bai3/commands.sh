#!/usr/bin/env bash
# Bài 3: Cài SSL Let's Encrypt cho api.my-ecommerce.com trên Ubuntu (chạy từng lệnh, không chạy cả file một lúc)
#
# ĐIỀU KIỆN TRƯỚC KHI XIN CHỨNG CHỈ:
#   - DNS: bản ghi A  api.my-ecommerce.com -> IP public của VPS  (kiểm tra: dig +short api.my-ecommerce.com)
#   - Cổng 80 và 443 mở từ Internet (UFW + tường lửa của nhà cung cấp VPS).
#     Let's Encrypt xác thực domain bằng cách gọi http://api.my-ecommerce.com/.well-known/acme-challenge/...
#   - Nginx đã có server block với "server_name api.my-ecommerce.com;"

# 1) Cài đặt Nginx, Certbot và plugin Nginx cho Certbot
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx
certbot --version

# 2) Mở tường lửa cho HTTP + HTTPS
sudo ufw allow 'Nginx Full'          # = 80/tcp + 443/tcp
sudo ufw status

# 3) Tạo server block HTTP cho domain (Certbot đọc server_name để biết sửa block nào)
sudo tee /etc/nginx/sites-available/api.my-ecommerce.com > /dev/null <<'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name api.my-ecommerce.com;

    location / {
        proxy_pass http://localhost:8080;
        include proxy_params;
    }
}
EOF
sudo ln -s /etc/nginx/sites-available/api.my-ecommerce.com /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# 4) (Khuyến nghị) Chạy thử với máy chủ staging trước để không dính giới hạn số lần cấp của Let's Encrypt
sudo certbot certonly --nginx --dry-run -d api.my-ecommerce.com

# 5) Xin chứng chỉ thật + để Certbot TỰ CẤU HÌNH Nginx (thêm listen 443 ssl, ssl_certificate, redirect 301)
sudo certbot --nginx -d api.my-ecommerce.com \
     --redirect \
     -m admin@my-ecommerce.com --agree-tos --no-eff-email
#   --nginx     : dùng plugin nginx để xác thực domain và sửa file cấu hình
#   -d          : domain cần cấp (thêm -d khác nếu muốn nhiều domain trong 1 chứng chỉ)
#   --redirect  : tự thêm chuyển hướng HTTP -> HTTPS (301)
#   -m          : email đăng ký tài khoản ACME
#   --agree-tos : đồng ý điều khoản, --no-eff-email: không đăng ký nhận tin của EFF

# 6) Kiểm tra kết quả
sudo certbot certificates                        # tên, đường dẫn, ngày hết hạn của chứng chỉ
sudo ls -l /etc/letsencrypt/live/api.my-ecommerce.com/
curl -I http://api.my-ecommerce.com              # -> 301 Location: https://api.my-ecommerce.com/
curl -I https://api.my-ecommerce.com             # -> 200, không cần -k vì chứng chỉ hợp lệ

# 7) TỰ ĐỘNG GIA HẠN (chứng chỉ chỉ có hạn 90 ngày)
#    Gói certbot của Ubuntu đã tự tạo systemd timer chạy "certbot -q renew" 2 lần/ngày.
systemctl list-timers certbot.timer              # lần chạy kế tiếp / lần chạy trước
systemctl cat certbot.timer certbot.service      # xem lịch và lệnh thực thi
sudo certbot renew --dry-run                     # giả lập gia hạn, phải báo "Congratulations, all simulated renewals succeeded"

#    Reload Nginx sau khi gia hạn thành công để nạp chứng chỉ mới (reload, KHÔNG restart - xem Bài 4)
sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh > /dev/null <<'EOF'
#!/bin/sh
systemctl reload nginx
EOF
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

#    Cách thay thế nếu máy không có certbot.timer (ví dụ cài certbot bằng pip): dùng cronjob của root
#    sudo crontab -e   rồi thêm dòng:
#    0 3,15 * * * certbot renew --quiet --deploy-hook "systemctl reload nginx"
