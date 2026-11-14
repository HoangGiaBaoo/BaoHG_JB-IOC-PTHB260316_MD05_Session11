# /etc/nginx/sites-available/api.my-ecommerce.com
# Bài 3: HTTPS cho api.my-ecommerce.com, viết tay (tương đương kết quả của "certbot --nginx --redirect")
# Kích hoạt:  sudo ln -s /etc/nginx/sites-available/api.my-ecommerce.com /etc/nginx/sites-enabled/
#             sudo nginx -t && sudo systemctl reload nginx

# 1) Cổng 80 (HTTP): chỉ dùng để chuyển hướng sang HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name api.my-ecommerce.com;

    # Cho Let's Encrypt xác thực domain qua HTTP-01 (dùng khi cấp/gia hạn bằng --webroot -w /var/www/certbot)
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Mọi request khác: chuyển hướng vĩnh viễn (301) sang https, giữ nguyên đường dẫn và query string
    location / {
        return 301 https://$host$request_uri;
    }
}

# 2) Cổng 443 (HTTPS)
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    # Bật HTTP/2: nginx >= 1.25.1 dùng "http2 on;"
    #             nginx cũ hơn (Ubuntu 22.04 = 1.18, Ubuntu 24.04 = 1.24) dùng "listen 443 ssl http2;"
    server_name api.my-ecommerce.com;

    # Chứng chỉ do Certbot cấp. Luôn trỏ vào thư mục live/: đây là symlink tới bản mới nhất,
    # nên sau mỗi lần renew không phải sửa lại đường dẫn.
    ssl_certificate     /etc/letsencrypt/live/api.my-ecommerce.com/fullchain.pem;  # chứng chỉ domain + chứng chỉ trung gian
    ssl_certificate_key /etc/letsencrypt/live/api.my-ecommerce.com/privkey.pem;    # khóa bí mật, chỉ root đọc được

    # Tham số TLS. Certbot thay khối này bằng 2 dòng:
    #   include /etc/letsencrypt/options-ssl-nginx.conf;
    #   ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    ssl_protocols TLSv1.2 TLSv1.3;          # bỏ TLS 1.0/1.1 đã lỗi thời
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # HSTS: trình duyệt ghi nhớ "domain này chỉ dùng HTTPS" trong 1 năm
    add_header Strict-Transport-Security "max-age=31536000" always;

    location / {
        proxy_pass http://localhost:8080;   # API Gateway chạy nội bộ, vẫn là HTTP thường

        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;   # = "https": backend biết request gốc là HTTPS
    }
}
