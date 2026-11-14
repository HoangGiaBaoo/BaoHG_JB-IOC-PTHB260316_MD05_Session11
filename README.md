# MD05 - Session 11: Nginx Reverse Proxy

Bài tập về nhà Session 11. Mỗi bài có file cấu hình Nginx, `README.md` giải thích và trả lời câu bẫy, cùng file `ket-qua-kiem-thu.txt` chứa output khi chạy thật.

| Bài | Nội dung | Câu bẫy | Thư mục |
|---|---|---|---|
| 1 | Reverse proxy cơ bản: cổng 80 → React `localhost:3000` | React sập thì trả về **502 Bad Gateway** | [`bai1/`](bai1/) |
| 2 | Định tuyến theo path: `/api/` → API Gateway `:8080`, còn lại → React `:3000` | Thiếu `X-Forwarded-For` thì backend chỉ thấy IP của Nginx (**127.0.0.1**) | [`bai2/`](bai2/) |
| 3 | HTTPS với Let's Encrypt (Certbot), redirect HTTP → HTTPS | Tự động gia hạn bằng **`certbot.timer`** hoặc **cronjob** `certbot renew` | [`bai3/`](bai3/) |
| 4 | `client_max_body_size 10M`, nén Gzip | **`nginx -t` trước**, sau đó **`reload`** (zero-downtime), không `restart` | [`bai4/`](bai4/) |

## Kiểm thử
Các file cấu hình được chạy thật bằng Nginx 1.31.8 trên VPS Ubuntu 24.04 (Session 10), trong một mạng Docker riêng có React và API Gateway giả lập. Chi tiết và cách chạy lại: [`kiem-thu/`](kiem-thu/).

Kết quả chính:
- **Bài 1**: `http://domain.com` trả về trang React (200). Tắt React thì nhận **502 Bad Gateway**.
- **Bài 2**: `/`, `/about`, `/products` đi tới frontend. `/api/...` đi tới API Gateway, giữ nguyên URI. Bỏ header thì backend mất IP thật của client.
- **Bài 3**: `nginx -t` thành công. HTTP trả về **301** sang HTTPS. HTTPS chạy TLS 1.3, có HSTS. Bài này dùng chứng chỉ tự ký đặt đúng đường dẫn Let's Encrypt, vì domain trong đề không thuộc quyền quản lý của mình.
- **Bài 4**: upload 3MB chuyển từ **413 → 200**. CSS giảm **86%**, JS **67%**, JSON **86%** nhờ gzip. Reload: **60/60 request thành công**. Restart: có request lỗi. Cấu hình lỗi + restart: **website sập**.
