# Gói ghi đè — sửa 2 lỗi nghiêm trọng sau khi sắp xếp lại repo

## Cách dùng
Giải nén, copy đè (overwrite) toàn bộ file trong gói vào đúng vị trí tương ứng trong repo
`keo-web` (giữ nguyên cấu trúc thư mục — file `blog/xyz.html` trong gói này đè lên đúng
`blog/xyz.html` trong repo). Không file nào trong gói cần đổi tên hay đổi vị trí.

## Gồm những gì (77 file)

1. **`vercel.json`** — thêm 78 rewrite rule (quét trực tiếp từ cây thư mục thật, không phải
   suy đoán) để mọi URL cũ của các trang đã di chuyển (blog/app/legal/internal) tiếp tục
   chạy đúng như trước, dù file vật lý đã đổi chỗ. Giữ nguyên 2 redirect + 7 header rule cũ.

2. **`favicon.ico` + `favicon.svg`** — chuyển ngược về thư mục gốc (trước đó bị đưa nhầm vào
   `assets/icons/`). Hai file này bắt buộc nằm ở gốc vì trình duyệt tự động gọi `/favicon.ico`
   theo quy ước, không đọc qua thẻ `<link>`.

3. **74 file `.html`** — đã tự động sửa mọi tham chiếu ảnh/script còn trỏ đường dẫn cũ sau khi
   dọn `assets/` (ví dụ `og-image.png`, `favicon-16x16.png`, `cookie-consent.js`...) sang đúng
   đường dẫn mới trong `assets/`. Bao gồm cả 1 chỗ nằm trong khối JSON-LD (schema.org) của
   `index.html` mà cách quét thông thường (chỉ tìm `src=`/`href=`) sẽ bỏ sót.

## Đã tự kiểm trước khi giao
- `vercel.json`: cú pháp JSON hợp lệ, đọc lại được.
- Quét lại toàn bộ 89 file `.html` sau khi sửa: 0 tham chiếu asset còn sai (bao gồm cả kiểm
  bằng regex thô, không chỉ giới hạn trong thuộc tính `src=`/`href=`/`content=`, để bắt cả
  trường hợp CSS `url()` hay JSON-LD nếu có).
- Cân bằng thẻ `<div>` trên các file mẫu (blog, app, trang chủ, thi-truong) — không bị lệch
  do script tìm-thay-thế.
- favicon.ico/svg xác nhận là ảnh thật, không rỗng/hỏng sau khi copy.

## CHƯA kiểm được — cần bạn/Claude Code làm
- **Chưa test trên site thật.** Mọi kiểm tra ở trên là tĩnh (đọc file, không chạy mạng) vì
  sandbox không gọi được domain `keo.social` một cách đáng tin (bị chặn bot, trả 403 giả cho
  mọi request kể cả trang chắc chắn còn sống). Sau khi áp dụng gói này, PHẢI:
  - Deploy lên Preview trước (không production trực tiếp).
  - Mở bằng trình duyệt thật, thử ít nhất 10 URL cũ ngẫu nhiên (vd `/tai-khoan`,
    `/bua-an-la-nghi-thuc-ket-noi`, `/privacy`) — xác nhận không cái nào 404.
  - Thử share 1 link bài viết lên Zalo/Facebook — xác nhận ảnh preview (og:image) hiện đúng,
    không vỡ ảnh.
  - Chỉ merge/deploy production khi toàn bộ trên sạch.

## Việc còn lại, không khẩn
- 3 trang thành phố (`nguoi-dong-hanh-da-nang/ha-noi/sai-gon`) đã xác nhận giữ nguyên trong
  `blog/`, không cần tách `dia-diem/` — đã phản ánh đúng trong `vercel.json` (rewrite trỏ
  `/nguoi-dong-hanh-da-nang` → `/blog/nguoi-dong-hanh-da-nang.html`, tương tự 2 trang kia).
