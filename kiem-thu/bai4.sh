#!/usr/bin/env bash
# Kiểm thử Bài 4: client_max_body_size, gzip, nginx -t, reload và restart
source "$(dirname "$0")/lib.sh"
trap cleanup EXIT

# Bắt đầu từ cấu hình cũ (bài 2): chưa tăng giới hạn upload, chưa bật gzip
up "$ROOT/bai2/default"

UPLOAD='for f in 3 9 11; do printf "Upload avatar %2sMB -> HTTP %s\n" $f $(curl -s -o /dev/null -w "%{http_code}" -F "avatar=@/tmp/avatar-${f}mb.jpg" http://domain.com/api/users/me/avatar); done'
GZIP='printf "%-22s %10s %12s   %s\n" "Path" "Original" "Downloaded" "Content-Encoding"; for p in / /static/css/main.css /static/js/main.js /api/products; do raw=$(curl -s -o /dev/null -w "%{size_download}" "http://domain.com$p"); gz=$(curl -s -o /dev/null -H "Accept-Encoding: gzip" -w "%{size_download}" "http://domain.com$p"); enc=$(curl -s -o /dev/null -D - -H "Accept-Encoding: gzip" "http://domain.com$p" | grep -i "^content-encoding" | cut -d" " -f2 | tr -d "\r"); printf "%-22s %10s %12s   %s\n" "$p" "$raw" "$gz" "${enc:-(không nén)}"; done'

title "0) Tạo 3 file ảnh giả 3MB, 9MB, 11MB ở máy khách"
client 'for f in 3 9 11; do head -c $((f*1024*1024)) /dev/urandom > /tmp/avatar-${f}mb.jpg; done; ls -lh /tmp/avatar-*'

title "1) TRƯỚC khi sửa: upload avatar"
client "$UPLOAD"
client "curl -s -F avatar=@/tmp/avatar-3mb.jpg http://domain.com/api/users/me/avatar"

title "2) TRƯỚC khi sửa: kích thước tải về khi trình duyệt gửi Accept-Encoding: gzip"
client "$GZIP"

title "3) Áp dụng cấu hình bài 4, LUÔN kiểm tra cú pháp trước"
vps "cp ~/ss11/bai4/default ~/ss11-run/conf.d/default.conf"
nginx_c "nginx -t"

title "4) Reload trong lúc khách hàng đang truy cập (nginx -s reload = systemctl reload nginx)"
traffic 60
sleep 1
nginx_c "nginx -s reload"
traffic_report

title "5) SAU khi sửa: upload avatar"
client "$UPLOAD"
client "curl -s -F avatar=@/tmp/avatar-3mb.jpg http://domain.com/api/users/me/avatar"

title "6) SAU khi sửa: nén gzip"
client "$GZIP"
client "curl -s -o /dev/null -D - -H 'Accept-Encoding: gzip' http://domain.com/static/js/main.js | grep -iE '^(content-type|content-encoding|vary)'"

title "7) So sánh: restart trong lúc khách hàng đang truy cập (dừng hẳn tiến trình rồi khởi động lại, như systemctl restart nginx)"
traffic 60
sleep 1
vps "docker restart ss11-proxy"
traffic_report

title "8) BẪY CHÍ MẠNG: file cấu hình có lỗi (gõ nhầm 10M thành 10MB)"
vps "sed 's/client_max_body_size 10M;/client_max_body_size 10MB;/' ~/ss11/bai4/default > ~/ss11-run/conf.d/default.conf && grep -n client_max_body_size ~/ss11-run/conf.d/default.conf"
nginx_c "nginx -t"

title "8a) Nếu dùng RELOAD: Nginx từ chối cấu hình lỗi, vẫn chạy cấu hình cũ"
nginx_c "nginx -s reload"
client "curl -s -o /dev/null -w 'Trang chủ -> HTTP %{http_code}\n' http://domain.com/"

title "8b) Nếu dùng RESTART: Nginx dừng hẳn rồi không khởi động lại được -> toàn bộ website sập"
vps "docker restart ss11-proxy; sleep 2; docker ps -a --filter name=ss11-proxy --format '{{.Names}}: {{.Status}}'"
vps "docker logs ss11-proxy 2>&1 | grep emerg | tail -n 1"
client "curl -sS -o /dev/null -w 'Trang chủ -> HTTP %{http_code}\n' --max-time 3 http://domain.com/"

title "9) Sửa lại cấu hình đúng, kiểm tra rồi mới khởi động"
vps "cp ~/ss11/bai4/default ~/ss11-run/conf.d/default.conf"
vps "docker run --rm --entrypoint nginx -v ~/ss11-run/conf.d:/etc/nginx/conf.d:ro nginx:alpine -t"
vps "docker start ss11-proxy >/dev/null; sleep 2"
client "curl -s -o /dev/null -w 'Trang chủ -> HTTP %{http_code}\n' http://domain.com/"
