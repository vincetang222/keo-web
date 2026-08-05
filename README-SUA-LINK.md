# Gói ghi đè — nối lại link nội bộ trỏ thẳng vị trí thật (bỏ phụ thuộc rewrites)

## Lý do
Sau nhiều vòng debug `vercel.json` rewrites (đã sửa đúng theo tài liệu Vercel nhưng vẫn báo
404 — nghi do cache Edge hoặc lớp DNS/CDN riêng, chưa xác định được gốc rễ), quyết định
chuyển hướng: sửa thẳng mọi link nội bộ trỏ đúng vị trí file thật (`/blog/...`, `/app/...`,
`/legal/...`, `/internal/...`), không còn phụ thuộc rewrites hoạt động hay không.

**Đánh đổi đã biết trước:** link nội bộ trên site giờ hiển thị đúng vị trí thật (có `/blog/`
v.v.) thay vì URL ngắn gọn cũ. Ai từng lưu/backlink URL ngắn cũ từ trước vẫn cần rewrites
hoạt động mới không bị 404 — file `vercel.json` (đã sửa, bỏ đuôi `.html`) vẫn giữ nguyên
làm lưới an toàn cho trường hợp đó, không xoá.

## Cách dùng
Giải nén, ghi đè đúng vị trí tương ứng trong repo. Không đổi tên/vị trí file nào.

## Gồm 80 file `.html`
Quét toàn bộ site, tìm mọi `href="/ten-slug"` trỏ tới 78 trang đã bị di chuyển (blog/app/
legal/internal), thay bằng `href="/blog/ten-slug"` (hoặc `/app/`, `/legal/`, `/internal/`
tương ứng) — tổng cộng 582 link được sửa. Link tới các trang lõi chưa di chuyển (`/`,
`/thi-truong`...) giữ nguyên, không bị đụng.

## Đã tự kiểm trước khi giao
- Quét lại toàn bộ: 0 link short-form nào còn sót trỏ tới trang đã di chuyển.
- Cân bằng thẻ `<div>` trên các file mẫu (khoa-hoc-ket-noi, index, 1 bài blog) — không lệch.
- Xác nhận link tới trang lõi không di chuyển (vd `/thi-truong`) không bị sửa nhầm.

## CHƯA kiểm được — cần bạn/Claude Code test bằng trình duyệt thật
- Bấm thử vài link trong `khoa-hoc-ket-noi.html` sau khi deploy — giờ phải dẫn thẳng
  `keo.social/blog/...` (đã xác nhận đường dẫn này chạy tốt) thay vì URL ngắn.
- Kiểm tra các trang khác (app/, legal/, internal/) cũng dẫn đúng nếu có liên kết chéo.
