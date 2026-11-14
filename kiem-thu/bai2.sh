#!/usr/bin/env bash
# Kiểm thử Bài 2: định tuyến theo đường dẫn và các header gửi tới backend
source "$(dirname "$0")/lib.sh"
trap cleanup EXIT
up "$ROOT/bai2/default"

title "1) Kiểm tra cú pháp file cấu hình"
nginx_c "nginx -t"

title "2) IP của máy khách"
client "hostname -i"

title "3) Định tuyến theo đường dẫn (header X-Served-By cho biết service nào trả lời)"
client 'for p in / /about /products /static/js/main.js /api/products "/api/orders?page=2" /api; do printf "%-20s -> HTTP %s  %s\n" "$p" "$(curl -s -o /dev/null -w "%{http_code}" "http://domain.com$p")" "$(curl -s -o /dev/null -D - "http://domain.com$p" | grep -iE "^(x-served-by|location)" | tr -d "\r")"; done'

title "4) Backend nhận được gì? (cấu hình đầy đủ header)"
client "curl -s 'http://domain.com/api/orders?page=2'"

title "5) BẪY: xóa hết các dòng proxy_set_header rồi reload"
vps "grep -v proxy_set_header ~/ss11/bai2/default > ~/ss11-run/conf.d/default.conf"
nginx_c "nginx -t && nginx -s reload"
sleep 1
client "curl -s 'http://domain.com/api/orders?page=2'"

title "6) Khôi phục cấu hình. Client tự gửi kèm X-Forwarded-For giả mạo"
vps "cp ~/ss11/bai2/default ~/ss11-run/conf.d/default.conf"
nginx_c "nginx -s reload"
sleep 1
client "curl -s -H 'X-Forwarded-For: 6.6.6.6' 'http://domain.com/api/orders?page=2'"
