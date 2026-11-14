#!/usr/bin/env bash
# Kiểm thử Bài 1: reverse proxy cổng 80 -> React :3000, và mã lỗi khi React bị sập
source "$(dirname "$0")/lib.sh"
trap cleanup EXIT
up "$ROOT/bai1/default"

title "1) Kiểm tra cú pháp file cấu hình"
nginx_c "nginx -t"

title "2) Người dùng gõ http://domain.com (cổng 80 mặc định, không có :3000)"
client "curl -si http://domain.com/"
client "curl -s -o /dev/null -w 'GET /products -> HTTP %{http_code}\n' http://domain.com/products"

title "3) BẪY: ứng dụng React ở cổng 3000 bị sập"
vps "docker stop ss11-frontend"
client "curl -si http://domain.com/"

title "4) Nginx ghi lý do vào error log"
vps "docker logs ss11-proxy 2>&1 | grep -m 2 'connect() failed'"
