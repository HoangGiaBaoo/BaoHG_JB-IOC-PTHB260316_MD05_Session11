# Bài 4: Tối ưu hóa và reload cấu hình không gián đoạn

File cấu hình đầy đủ (cấu hình [Bài 2](../bai2/) + phần bổ sung): [`default`](default). Output kiểm thử: [`ket-qua-kiem-thu.txt`](ket-qua-kiem-thu.txt).

## 1. Lỗi `413 Request Entity Too Large`: cho phép upload tới 10MB

### Nguyên nhân
`client_max_body_size` mặc định là **`1m`**. Ảnh 3MB vượt giới hạn này nên **Nginx tự chặn** và trả về 413. Request không bao giờ tới được backend.

### Cấu hình bổ sung
```nginx
server {
    ...
    client_max_body_size 10M;
    ...
}
```

Có thể đặt ở 3 cấp:

| Đặt trong | Phạm vi |
|---|---|
| `http { }` trong `/etc/nginx/nginx.conf` | Mọi website trên server |
| `server { }` *(bài này)* | Cả domain |
| `location /api/users/avatar { }` | Chỉ API upload. An toàn nhất vì các API khác vẫn giữ giới hạn nhỏ |

Đơn vị hợp lệ: `k`/`K`, `m`/`M`, `g`/`G`. Viết **`10MB` là sai cú pháp** (phần 3 bên dưới dùng đúng lỗi này để thử).

### Kết quả
```
TRƯỚC (mặc định 1m)                     SAU (client_max_body_size 10M)
Upload avatar  3MB -> HTTP 413          Upload avatar  3MB -> HTTP 200
Upload avatar  9MB -> HTTP 413          Upload avatar  9MB -> HTTP 200
Upload avatar 11MB -> HTTP 413          Upload avatar 11MB -> HTTP 413   (vẫn chặn, đúng mong muốn)
```

### Lưu ý
- Giới hạn tính trên **toàn bộ body request**, không chỉ riêng file. Upload dạng `multipart/form-data` có thêm phần boundary và header của từng field. Ví dụ file 3MB (3 145 728 byte) tạo ra body **3 145 934 byte**. Một file *đúng* 10MB sẽ vượt `10M` vài trăm byte. Nếu phải nhận file đúng 10MB thì đặt `11M`.
- Backend Spring Boot cũng có giới hạn riêng: `max-file-size` mặc định chỉ **1MB**. Sửa Nginx xong thì phải sửa cả backend, nếu không sẽ gặp `MaxUploadSizeExceededException`:
  ```properties
  spring.servlet.multipart.max-file-size=10MB
  spring.servlet.multipart.max-request-size=10MB
  ```

## 2. Bật nén Gzip cho HTML, CSS, JS, JSON

```nginx
gzip on;
gzip_comp_level 5;        # 1 = nhanh, nén ít ... 9 = chậm, nén nhiều. 5 là mức cân bằng
gzip_min_length 256;      # file nhỏ hơn 256 byte thì nén không có lợi
gzip_vary on;             # thêm "Vary: Accept-Encoding" cho CDN/proxy cache
gzip_proxied any;         # vẫn nén khi request đi qua một proxy/CDN khác (có header Via)
gzip_types                # text/html luôn được nén khi "gzip on", không liệt kê lại
    text/plain
    text/css
    text/javascript
    application/javascript
    application/json
    application/xml
    image/svg+xml;
```

Cách hoạt động: trình duyệt gửi `Accept-Encoding: gzip`. Nginx nén response (kể cả response lấy từ React/API phía sau) và gửi về kèm `Content-Encoding: gzip`. Trình duyệt tự giải nén.
Không nén ảnh JPG/PNG, video, `.zip` vì chúng đã được nén sẵn, nén lại chỉ tốn CPU.

### Kết quả (bundle thật: Bootstrap 5.3.3 CSS, React DOM 18.3.1 JS)

| Đường dẫn | Gốc (byte) | Sau gzip (byte) | Giảm |
|---|---:|---:|---:|
| `/` (HTML) | 526 | 356 | 32% |
| `/static/css/main.css` | 232 803 | 31 840 | **86%** |
| `/static/js/main.js` | 131 835 | 43 387 | **67%** |
| `/api/products` (JSON) | 4 781 | 677 | **86%** |

```
Content-Type: application/javascript
Vary: Accept-Encoding
Content-Encoding: gzip
```

### Bẫy khi sửa trên Ubuntu
File `/etc/nginx/nginx.conf` mặc định **đã có sẵn `gzip on;`** trong khối `http`, các dòng `gzip_*` còn lại bị comment. Nếu thêm một dòng `gzip on;` nữa vào khối `http` (kể cả qua file trong `conf.d/`), Nginx báo lỗi `"gzip" directive is duplicate`. Có 2 cách đúng:
- bỏ comment các dòng `gzip_*` có sẵn trong `nginx.conf`, **hoặc**
- đặt khối gzip trong `server { }` như file [`default`](default) của bài này. Cấp `server` ghi đè cấp `http` nên không bị trùng.

## 3. Bẫy cực kỳ nguy hiểm: `restart` hay `reload`?

### Trả lời ngắn
1. **Lệnh gõ trước tiên: `sudo nginx -t`** để kiểm tra cú pháp và kiểm tra các file được tham chiếu (ví dụ file chứng chỉ SSL) có tồn tại không.
2. Sau đó dùng **`sudo systemctl reload nginx`**. **Không** dùng `restart` trên production.

```bash
sudo nginx -t && sudo systemctl reload nginx
```
`&&` đảm bảo chỉ reload khi kiểm tra thành công.

### Khác biệt chí mạng

| | `systemctl reload nginx` | `systemctl restart nginx` |
|---|---|---|
| Bản chất | Gửi tín hiệu **HUP** cho master process (chính là `nginx -s reload`) | **Dừng hẳn** toàn bộ Nginx (stop), rồi chạy tiến trình mới (start) |
| Cổng 80/443 | **Luôn mở**. Master process giữ socket suốt quá trình | **Bị đóng** trong khoảng giữa stop và start. Khách nhận "connection refused" |
| Request đang xử lý (upload dở, tải file, WebSocket) | Worker cũ **xử lý xong rồi mới thoát** (graceful) | Bị **cắt ngang** |
| Nếu file cấu hình **có lỗi** | Master **từ chối** cấu hình mới, ghi lỗi vào log, **vẫn chạy cấu hình cũ**. Web không ảnh hưởng | Nginx đã bị stop, bước start thất bại. **Toàn bộ website sập** tới khi có người vào sửa |

Cơ chế zero-downtime của `reload`:
1. Master process đọc và kiểm tra cấu hình mới. Nếu lỗi thì giữ nguyên mọi thứ.
2. Master tạo **worker mới** chạy cấu hình mới. Các worker này nhận ngay các kết nối mới trên socket đang mở sẵn.
3. Master báo cho **worker cũ** ngừng nhận kết nối mới. Worker cũ phục vụ nốt các request đang dở rồi tự thoát.

Khách hàng đang online không bị rớt request nào.

### Kiểm chứng
Một máy khách gửi liên tục 60 request (mỗi 50ms một request) trong lúc thực hiện thao tác:

```
4) RELOAD khi đang có traffic (nginx -s reload)
   60 request ->  60 x HTTP 200                      => không lỗi request nào

7) RESTART khi đang có traffic (dừng hẳn rồi khởi động lại)
   60 request ->  58 x HTTP 200, 2 x 000 (không kết nối được)
```

Với file cấu hình có lỗi (gõ nhầm `10M` thành `10MB`):

```
[nginx]$ nginx -t
nginx: [emerg] "client_max_body_size" directive invalid value in /etc/nginx/conf.d/default.conf:13
nginx: configuration file /etc/nginx/nginx.conf test failed

8a) RELOAD
[nginx]$ nginx -s reload
nginx: [emerg] "client_max_body_size" directive invalid value in /etc/nginx/conf.d/default.conf:13
[client]$ curl ... http://domain.com/
Trang chủ -> HTTP 200                  <- website VẪN CHẠY bằng cấu hình cũ

8b) RESTART
ss11-proxy: Exited (1) 2 seconds ago   <- Nginx không khởi động lại được
[client]$ curl ... http://domain.com/
curl: (7) Failed to connect to domain.com:80 after 73 ms: Could not connect to server
Trang chủ -> HTTP 000                  <- TOÀN BỘ WEBSITE SẬP
```

Trong bài kiểm thử, Nginx chạy trong container nên "restart" được mô phỏng bằng `docker restart`, tức dừng hẳn tiến trình Nginx rồi chạy tiến trình mới, giống `systemctl restart`. Còn `nginx -s reload` chính là lệnh mà `systemctl reload nginx` gọi trên Ubuntu.
Trên VPS thật, `systemctl restart` với cấu hình lỗi sẽ báo `Job for nginx.service failed because the control process exited with error code` và Nginx nằm im ở trạng thái `failed`.

Downtime 2 request ở bước 7 nghe có vẻ nhỏ. Nhưng đây là một server rỗng chỉ có 1 khách truy cập. Trên production, mỗi lần restart là hàng trăm kết nối bị ngắt, upload bị hỏng, đơn hàng đang thanh toán bị lỗi. Nếu cấu hình có lỗi, website sẽ **sập hẳn**.

### Quy trình an toàn khi sửa cấu hình trên production
```bash
sudo cp /etc/nginx/sites-available/default ~/default.bak.$(date +%F-%H%M)   # sao lưu
sudo nano /etc/nginx/sites-available/default                                # sửa
sudo nginx -t && sudo systemctl reload nginx                                # kiểm tra rồi mới reload
sudo systemctl status nginx --no-pager                                      # xác nhận đang active (running)
sudo tail -n 20 /var/log/nginx/error.log                                    # xem có cảnh báo gì không
```
Chỉ dùng `restart` khi Nginx đang bị treo hoặc đã dừng, hoặc trong khung giờ bảo trì đã thông báo trước.
