#!/usr/bin/env bash
# Hạ tầng giả lập dùng chung cho các script kiểm thử bài 1-4.
# Chạy trên VPS bằng user có quyền docker (deploy). Không chiếm cổng nào của VPS:
# mọi container nằm trong mạng riêng "ss11-net" và bị xóa khi script kết thúc.
#
#   ss11-pod       giữ network namespace chung, đóng vai "VPS" trong đề bài
#   ss11-proxy     Nginx reverse proxy với file cấu hình của từng bài    (cổng 80/443 của "VPS")
#   ss11-frontend  giả lập React app đã build                           (localhost:3000)
#   ss11-api       giả lập API Gateway, trả về JSON mô tả request nhận được (localhost:8080)
#   ss11-client    máy khách (trình duyệt) ở một IP khác trong mạng ss11-net
#
# Vì proxy, frontend, api dùng chung network namespace của ss11-pod nên
# "localhost:3000" / "localhost:8080" trong file cấu hình Nginx có nghĩa đúng như trên VPS thật.

set -u
KT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$KT_DIR/.." && pwd)"
IMG=nginx:alpine
NET=ss11-net
RUN="$HOME/ss11-run"
ALL="ss11-client ss11-proxy ss11-frontend ss11-api ss11-pod"

title()   { printf '\n==== %s ====\n' "$*"; }
client()  { printf '[client]$ %s\n' "$1"; docker exec ss11-client sh -c "$1" 2>&1; echo; }
nginx_c() { printf '[nginx]$ %s\n'  "$1"; docker exec ss11-proxy  sh -c "$1" 2>&1; echo; }
vps()     { printf '[vps]$ %s\n'    "$1"; bash -c "$1" 2>&1; echo; }

cleanup() {
  docker rm -f $ALL >/dev/null 2>&1
  docker network rm "$NET" >/dev/null 2>&1
  true
}

prepare_files() {
  mkdir -p "$RUN/conf.d" "$RUN/html/static/js" "$RUN/html/static/css" "$RUN/api-data" "$RUN/cache"
  rm -f "$RUN/conf.d/"*
  cp "$KT_DIR/mock/frontend.conf" "$RUN/frontend.conf"
  cp "$KT_DIR/mock/api.conf"      "$RUN/api.conf"
  cp "$KT_DIR/mock/index.html"    "$RUN/html/index.html"
  # Bundle JS/CSS thật (React DOM, Bootstrap) để thử nén gzip với file có kích thước thực tế
  [ -s "$RUN/cache/main.js" ]  || curl -fsSL -o "$RUN/cache/main.js"  https://cdnjs.cloudflare.com/ajax/libs/react-dom/18.3.1/umd/react-dom.production.min.js
  [ -s "$RUN/cache/main.css" ] || curl -fsSL -o "$RUN/cache/main.css" https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.3/css/bootstrap.min.css
  cp "$RUN/cache/main.js"  "$RUN/html/static/js/main.js"
  cp "$RUN/cache/main.css" "$RUN/html/static/css/main.css"
  # Danh sách sản phẩm JSON cho GET /api/products
  {
    printf '['
    for i in $(seq 1 60); do
      [ "$i" -gt 1 ] && printf ','
      printf '{"id":%d,"name":"San pham %d","price":%d000,"stock":%d,"category":"Thoi trang"}' "$i" "$i" $((i * 7)) $((i % 13))
    done
    printf ']\n'
  } > "$RUN/api-data/products.json"
}

# up <file cấu hình Nginx của bài> [tham số docker run bổ sung cho container proxy...]
up() {
  local conf="$1"; shift
  cleanup
  prepare_files
  cp "$conf" "$RUN/conf.d/default.conf"
  docker network create "$NET" >/dev/null
  docker run -d --name ss11-pod --hostname vps --network "$NET" "$IMG" tail -f /dev/null >/dev/null
  POD_IP=$(docker inspect -f "{{(index .NetworkSettings.Networks \"$NET\").IPAddress}}" ss11-pod)
  docker run -d --name ss11-frontend --network container:ss11-pod \
    -v "$RUN/frontend.conf:/etc/nginx/conf.d/default.conf:ro" \
    -v "$RUN/html:/usr/share/nginx/html:ro" "$IMG" >/dev/null
  docker run -d --name ss11-api --network container:ss11-pod \
    -v "$RUN/api.conf:/etc/nginx/conf.d/default.conf:ro" \
    -v "$RUN/api-data:/data:ro" "$IMG" >/dev/null
  docker run -d --name ss11-proxy --network container:ss11-pod \
    -v "$RUN/conf.d:/etc/nginx/conf.d" "$@" "$IMG" >/dev/null
  docker run -d --name ss11-client --hostname client --network "$NET" \
    --add-host "domain.com:$POD_IP" --add-host "www.domain.com:$POD_IP" \
    --add-host "api.my-ecommerce.com:$POD_IP" \
    "$IMG" tail -f /dev/null >/dev/null
  sleep 2
}

# traffic <số request>: giả lập khách hàng truy cập liên tục (chạy nền), mỗi 50ms một request
traffic() {
  docker exec ss11-client sh -c "for i in \$(seq 1 $1); do curl -s -o /dev/null --max-time 2 -w '%{http_code}\n' http://domain.com/; sleep 0.05; done" \
    > "$RUN/traffic.txt" 2>&1 &
  TRAFFIC_PID=$!
}

traffic_report() {
  wait "$TRAFFIC_PID"
  echo "Kết quả $(wc -l < "$RUN/traffic.txt") request của khách hàng trong lúc thao tác (số lần | mã HTTP):"
  sort "$RUN/traffic.txt" | uniq -c | sed 's/^/   /'
  echo "   (000 = không kết nối được tới Nginx, khách hàng thấy trang lỗi)"
}
