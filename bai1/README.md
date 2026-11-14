# Bài 1: Cấu hình Nginx Reverse Proxy cơ bản

## Reverse Proxy là gì?

Reverse proxy là một máy chủ đứng **trước** ứng dụng. Nó nhận request của người dùng, chuyển tiếp vào ứng dụng thật bên trong, rồi trả kết quả về cho người dùng.
Người dùng chỉ làm việc với reverse proxy. Họ không biết ứng dụng thật chạy ở đâu, cổng nào.

```
                  http://domain.com (cổng 80)                http://localhost:3000
Trình duyệt  ─────────────────────────────────▶  Nginx  ──────────────────────────▶  React app
            ◀─────────────────────────────────  (VPS)  ◀──────────────────────────  (chỉ chạy nội bộ)
```

So sánh với forward proxy: forward proxy đứng phía **người dùng** (ví dụ proxy công ty dùng để ra Internet). Reverse proxy đứng phía **máy chủ** để bảo vệ và phân phối request vào các ứng dụng.

Lợi ích:
- Người dùng chỉ gõ `http://domain.com`, không phải gõ `:3000`.
- Ẩn cổng 3000. Cổng này không cần mở ra Internet.
- Một chỗ duy nhất để làm HTTPS ([Bài 3](../bai3/)), nén gzip và giới hạn upload ([Bài 4](../bai4/)), định tuyến nhiều service ([Bài 2](../bai2/)).

## File cấu hình: `/etc/nginx/sites-available/default`

File đầy đủ: [`default`](default)

```nginx
server {
    listen 80 default_server;          # Nhận mọi request HTTP đến cổng 80 (IPv4)
    listen [::]:80 default_server;     # ... và IPv6

    server_name domain.com www.domain.com;

    location / {
        # Chuyển tiếp mọi request tới ứng dụng React ở cổng 3000 trên chính VPS.
        proxy_pass http://localhost:3000;

        # Giữ lại thông tin gốc của request khi chuyển tiếp
        proxy_http_version 1.1;
        proxy_set_header Host              $host;                       # domain người dùng đã gõ
        proxy_set_header X-Real-IP         $remote_addr;                # IP thật của người dùng
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;  # chuỗi IP: client, proxy...
        proxy_set_header X-Forwarded-Proto $scheme;                     # http hay https
    }
}
```

Áp dụng trên Ubuntu:

```bash
sudo apt install -y nginx
sudo nano /etc/nginx/sites-available/default   # dán nội dung trên
sudo nginx -t                                  # kiểm tra cú pháp
sudo systemctl reload nginx                    # nạp cấu hình mới, không gián đoạn (xem Bài 4)
sudo ufw allow 80/tcp                          # mở cổng 80. KHÔNG mở cổng 3000
```

Trên Ubuntu, `sites-enabled/default` đã là symlink tới `sites-available/default` sẵn, nên không cần tạo thêm.

## Ý nghĩa của chỉ thị `proxy_pass`

`proxy_pass <URL>;` đặt trong một `location`. Nó biến Nginx thành **trung gian** cho mọi request khớp với location đó:

1. Nginx nhận request của người dùng ở cổng 80.
2. Nginx **tự mở một kết nối mới** tới địa chỉ trong `proxy_pass` (ở đây là `http://localhost:3000`) và gửi request vào đó. Lúc này Nginx đóng vai client của ứng dụng React.
3. Nginx nhận response từ React rồi trả nguyên về cho người dùng.

Một số điểm cần biết:
- Địa chỉ đích có dạng `http://host:port`, hoặc tên một nhóm `upstream` (dùng khi cân bằng tải nhiều server).
- Có hay không có phần đường dẫn (dấu `/`) sau `host:port` sẽ quyết định Nginx giữ nguyên hay cắt bớt URI. Chi tiết ở [Bài 2](../bai2/README.md#proxy_pass-có-và-không-có-dấu--ở-cuối).
- Request tới ứng dụng là **request mới do Nginx tạo**. Vì vậy các header `proxy_set_header` ở trên là cần thiết. Nếu thiếu, ứng dụng sẽ thấy `Host: localhost:3000` và IP của chính Nginx thay vì domain và IP thật của người dùng. Phần này được kiểm chứng ở [Bài 2](../bai2/).

## Bẫy: React ở cổng 3000 bị sập thì Nginx trả về mã gì?

### Trả lời: **`502 Bad Gateway`**

- Nginx **vẫn sống** và vẫn nhận request ở cổng 80, nên người dùng vẫn nhận được một response HTTP.
- Khi Nginx kết nối tới `localhost:3000`, không có tiến trình nào lắng nghe ở cổng đó. Hệ điều hành từ chối kết nối (`Connection refused`).
- Nginx đóng vai *gateway* nhưng không lấy được response hợp lệ từ phía sau, nên trả về **502 Bad Gateway**.

Kết quả chạy thật (đầy đủ trong [`ket-qua-kiem-thu.txt`](ket-qua-kiem-thu.txt)):

```
[client]$ curl -si http://domain.com/
HTTP/1.1 200 OK
...
X-Served-By: frontend-react:3000
...
<div id="root">My E-commerce - React frontend (port 3000)</div>

[vps]$ docker stop ss11-frontend          # React bị sập

[client]$ curl -si http://domain.com/
HTTP/1.1 502 Bad Gateway
Server: nginx/1.31.8
...
<center><h1>502 Bad Gateway</h1></center>
```

Nginx ghi lý do vào error log (`/var/log/nginx/error.log` trên Ubuntu):

```
[error] 29#29: *5 connect() failed (111: Connection refused) while connecting to upstream, client: 172.19.0.3, server: domain.com, request: "GET / HTTP/1.1", upstream: "http://[::1]:3000/", host: "domain.com"
[error] 29#29: *5 connect() failed (111: Connection refused) while connecting to upstream, client: 172.19.0.3, server: domain.com, request: "GET / HTTP/1.1", upstream: "http://127.0.0.1:3000/", host: "domain.com"
```

### Phân biệt các trường hợp dễ nhầm

| Tình huống | Người dùng nhận được |
|---|---|
| App ở cổng 3000 **tắt hẳn**, không ai lắng nghe cổng | **502 Bad Gateway** |
| App vẫn chạy nhưng **treo**, không trả lời trong `proxy_read_timeout` (mặc định 60s) | **504 Gateway Timeout** |
| **Chính Nginx** bị tắt | Không có mã HTTP nào. Trình duyệt báo `ERR_CONNECTION_REFUSED` |

Thấy 502 thì kiểm tra **ứng dụng phía sau** trước, ví dụ `ss -ltnp | grep 3000`, `pm2 status`, `docker ps`. Nginx không có lỗi.

### Ghi chú thêm từ log
Log ở trên cho thấy Nginx thử **2 địa chỉ**: `[::1]:3000` (IPv6) rồi `127.0.0.1:3000` (IPv4). Lý do là `localhost` được phân giải ra cả hai địa chỉ.
Nếu ứng dụng chỉ lắng nghe IPv4, lần thử `::1` lúc nào cũng lỗi và làm error log đầy rác. Trên production nên viết thẳng `proxy_pass http://127.0.0.1:3000;` để tránh việc này. Bài này giữ `localhost` theo đúng đề bài.
