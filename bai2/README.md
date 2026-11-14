# Bài 2: Định tuyến request đến API Gateway (Path-based routing)

## Mô hình

```
                                     ┌── /api/...            ──▶ http://localhost:8080  (Backend API Gateway)
Trình duyệt ── http://domain.com ──▶ Nginx (:80)
                                     └── /, /about, /products ──▶ http://localhost:3000  (Frontend React)
```

Frontend và backend dùng chung một domain và một cổng 80. Nhờ vậy trình duyệt gọi API cùng origin và **không bị lỗi CORS**.

## File cấu hình: `/etc/nginx/sites-available/default`

File đầy đủ: [`default`](default)

```nginx
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name domain.com www.domain.com;

    # 1) Đường dẫn bắt đầu bằng /api/ -> API Gateway (giữ nguyên URI /api/...)
    location /api/ {
        proxy_pass http://localhost:8080;

        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # 2) Mọi request còn lại -> Frontend React
    location / {
        proxy_pass http://localhost:3000;

        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Nginx chọn `location` như thế nào?
Cả `/api/` và `/` đều là **location tiền tố**. Nginx chọn location có **tiền tố khớp dài nhất**:
- `/api/products` khớp cả `/` và `/api/`. `/api/` dài hơn nên được chọn, request đi tới **8080**.
- `/about` chỉ khớp `/`, nên đi tới **3000**.

`location /` vì vậy là "lưới hứng" cho mọi request còn lại. Thứ tự viết 2 block trong file không ảnh hưởng.

### Kết quả kiểm thử định tuyến

Mỗi service giả lập gắn thêm header `X-Served-By` để biết ai đã trả lời. Output đầy đủ: [`ket-qua-kiem-thu.txt`](ket-qua-kiem-thu.txt).

```
/                    -> HTTP 200  X-Served-By: frontend-react:3000
/about               -> HTTP 200  X-Served-By: frontend-react:3000
/products            -> HTTP 200  X-Served-By: frontend-react:3000
/static/js/main.js   -> HTTP 200  X-Served-By: frontend-react:3000
/api/products        -> HTTP 200  X-Served-By: api-gateway:8080
/api/orders?page=2   -> HTTP 200  X-Served-By: api-gateway:8080
/api                 -> HTTP 301  Location: http://domain.com/api/
```

Dòng cuối là một quy tắc đặc biệt của Nginx. Nếu location có dạng `/api/` (kết thúc bằng `/`) và dùng `proxy_pass`, thì request **`/api`** (không có `/` cuối) được Nginx tự trả về **301 chuyển sang `/api/`**.

### `proxy_pass` có và không có dấu `/` ở cuối

| Cấu hình | Request của client | Backend nhận được |
|---|---|---|
| `proxy_pass http://localhost:8080;` *(bài này dùng)* | `/api/products?page=2` | `/api/products?page=2` (giữ nguyên) |
| `proxy_pass http://localhost:8080/;` | `/api/products?page=2` | `/products?page=2` (bị cắt `/api/`) |

API Gateway thường định tuyến theo tiền tố `/api/...`, ví dụ Spring Cloud Gateway `Path=/api/products/**`. Vì vậy bài này **không** để `/` ở cuối, để giữ nguyên URI. Kết quả kiểm thử xác nhận backend nhận `"uri":"/api/orders?page=2"`.

## Giữ nguyên các header quan trọng

| Header | Giá trị gửi đi | Nếu không khai báo, backend thấy |
|---|---|---|
| `Host` | `$host`: domain người dùng gõ (`domain.com`) | `localhost:8080` |
| `X-Real-IP` | `$remote_addr`: IP của client kết nối tới Nginx | *(không có)* |
| `X-Forwarded-For` | `$proxy_add_x_forwarded_for`: header XFF client gửi lên (nếu có), **nối thêm** IP client | *(không có)* |
| `X-Forwarded-Proto` | `$scheme`: `http` hoặc `https` | *(không có)*. Backend tưởng mọi request là http |

Lưu ý khi viết header ở cấp `server`: `proxy_set_header` chỉ được kế thừa từ cấp ngoài khi location **không tự khai báo** dòng `proxy_set_header` nào. Chỉ cần thêm 1 dòng trong location là toàn bộ header của cấp ngoài bị bỏ.
Vì vậy bài này viết đủ header trong từng location cho chắc chắn. Ubuntu có sẵn file `/etc/nginx/proxy_params`, dùng `include proxy_params;` sẽ cho kết quả tương đương.

## Bẫy: Tại sao phải truyền `X-Forwarded-For`? Nếu không truyền, backend thấy IP của ai?

### Trả lời
Khi đi qua reverse proxy, **người mở kết nối TCP tới backend là Nginx, không phải trình duyệt**.
Nếu không truyền `X-Forwarded-For` / `X-Real-IP`, backend chỉ thấy **IP của Nginx**. Nginx chạy cùng máy với backend, nên đó là địa chỉ loopback **`127.0.0.1`**. Hàm `request.getRemoteAddr()` trong Spring trả về giá trị này.
Hậu quả là **mọi người dùng trên Internet đều có chung một IP** trong mắt backend.

Kiểm chứng thực tế. Máy khách có IP `172.19.0.3`. Backend giả lập trả về đúng những gì nó nhận được:

**Có đủ header** (cấu hình trên):
```json
{"uri":"/api/orders?page=2","host":"domain.com","remote_addr":"::1",
 "x_real_ip":"172.19.0.3","x_forwarded_for":"172.19.0.3","x_forwarded_proto":"http"}
```

**Xóa hết `proxy_set_header`** rồi reload:
```json
{"uri":"/api/orders?page=2","host":"localhost:8080","remote_addr":"::1",
 "x_real_ip":"","x_forwarded_for":"","x_forwarded_proto":""}
```

Khi xóa header, IP thật `172.19.0.3` biến mất hoàn toàn. Backend chỉ còn `remote_addr`, tức IP của Nginx.
Trong lần test, giá trị này là `::1`, dạng IPv6 của `127.0.0.1`, vì `localhost` được phân giải sang IPv6 trước (xem [ghi chú Bài 1](../bai1/README.md#ghi-chú-thêm-từ-log)). Cả hai đều là loopback, tức chính Nginx trên cùng VPS. `Host` cũng bị đổi thành `localhost:8080`.

### Vì sao mất IP thật là nguy hiểm?
- **Log và audit vô dụng**: mọi request đều ghi `127.0.0.1`, không truy được ai đã đặt đơn hay ai đã tấn công.
- **Rate limit hoặc khóa tài khoản theo IP sai**: một kẻ dò mật khẩu sẽ làm khóa *tất cả* người dùng, vì ai cũng là `127.0.0.1`. Ngược lại, chặn theo IP thì chặn được tất cả hoặc không chặn được ai.
- **Lỗ hổng phân quyền theo IP**: nếu backend cho phép trang admin "chỉ từ localhost", ví dụ `hasIpAddress('127.0.0.1')`, thì mọi request đi qua Nginx đều được coi là từ localhost và lọt qua.
- Chống gian lận, thống kê theo vùng (GeoIP), chống spam đều sai.

### Vì sao dùng `X-Forwarded-For` khi đã có `X-Real-IP`?
- `X-Forwarded-For` là header **chuẩn de-facto**. Spring Boot (Tomcat `RemoteIpValve`, bật bằng `server.forward-headers-strategy=native`), Spring Cloud Gateway và các framework khác đều đọc header này để khôi phục IP client.
- Nó là **một chuỗi IP**, ghi lại cả đường đi khi có nhiều proxy (Cloudflare → Nginx → Gateway → service). `$proxy_add_x_forwarded_for` **nối thêm** IP vào chuỗi chứ không ghi đè.

### Cẩn thận: client có thể giả mạo `X-Forwarded-For`
```
[client]$ curl -s -H 'X-Forwarded-For: 6.6.6.6' 'http://domain.com/api/orders?page=2'
{..."x_real_ip":"172.19.0.3","x_forwarded_for":"6.6.6.6, 172.19.0.3"...}
```
Phần đầu chuỗi do client tự gửi nên không đáng tin. Backend chỉ nên tin IP **ngoài cùng bên phải** (do proxy của mình thêm vào), hoặc dùng `X-Real-IP` (Nginx luôn ghi đè bằng IP thật đã kết nối).
