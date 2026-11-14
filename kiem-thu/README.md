# Bộ kiểm thử cấu hình Nginx

Các file cấu hình của bài 1-4 được **chạy thật** bằng Nginx 1.31.8 (image `nginx:alpine`) trên VPS Ubuntu 24.04 dùng ở Session 10.
Output được lưu vào `bai*/ket-qua-kiem-thu.txt`.

## Vì sao mô phỏng bằng Docker?
- Cổng 80 của VPS đang được dùng cho một project khác. Tường lửa của nhà cung cấp VPS cũng chỉ mở cổng 22 ra Internet.
- Vì vậy mọi thứ chạy trong một mạng Docker riêng (`ss11-net`), không chiếm cổng nào của VPS và bị xóa sạch sau khi chạy.

```
                     mạng ss11-net
 ┌──────────────┐                         ┌──────────────── ss11-pod (đóng vai "VPS") ────────────────┐
 │ ss11-client  │  http://domain.com      │  ss11-proxy    Nginx với file cấu hình của bài  :80 / :443 │
 │ 172.19.0.3   │ ──────────────────────▶ │  ss11-frontend giả lập React app               localhost:3000 │
 │ (trình duyệt)│                         │  ss11-api      giả lập API Gateway             localhost:8080 │
 └──────────────┘                         └───────────────────────────────────────────────────────────┘
```

`proxy`, `frontend` và `api` dùng chung network namespace. Vì vậy `localhost:3000` và `localhost:8080` trong file cấu hình có nghĩa đúng như khi cài trên VPS thật.
`ss11-api` trả về JSON mô tả những gì backend nhận được (URI, Host, IP kết nối, các header `X-*`). Mỗi service còn gắn header `X-Served-By` để biết ai đã trả lời.

Trên Ubuntu, file cấu hình đặt ở `/etc/nginx/sites-available/default`. Trong image `nginx:alpine`, file được mount vào `/etc/nginx/conf.d/default.conf`. Cả hai đều được `include` bên trong khối `http { }` nên ý nghĩa hoàn toàn giống nhau.

Ký hiệu trong output:
- `[client]$`: lệnh chạy ở máy khách
- `[nginx]$`: lệnh chạy trong container Nginx
- `[vps]$`: lệnh chạy trên VPS

## Chạy lại
Trên một máy Linux có Docker:
```bash
git clone https://github.com/HoangGiaBaoo/BaoHG_JB-IOC-PTHB260316_MD05_Session11.git ss11 && cd ss11
bash kiem-thu/bai1.sh
bash kiem-thu/bai2.sh
bash kiem-thu/bai3.sh
bash kiem-thu/bai4.sh
```
