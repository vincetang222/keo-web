# Kèo — Lộ trình tính năng Marketplace

> So sánh Kèo với các marketplace 2 chiều chuẩn (kiểu Airbnb, Grab, Upwork), chỉ rõ đã có gì, thiếu gì, và thứ tự ưu tiên. Bản này đi kèm việc code sẵn phần schema + hạ tầng cho các tính năng ưu tiên.

## Nguyên tắc ưu tiên

Một marketplace sống hay chết ở 3 thứ, theo đúng thứ tự: **(1) Niềm tin** (không tin thì không ai giao dịch với người lạ) → **(2) Chất lượng khớp nối** (đúng người, đúng nhu cầu) → **(3) Giữ giao dịch trong nền tảng** (chống lách phí). Mọi tính năng xếp hạng theo việc nó phục vụ trụ nào.

---

## Bảng tổng quan: đã có vs cần thêm

| Nhóm | Tính năng | Trạng thái | Ưu tiên |
|---|---|---|---|
| **Danh tính & tin cậy** | Đăng ký, hồ sơ, vai trò | ✅ Có | — |
| | Xác minh CCCD (3 tầng lưu trữ) | ✅ Có (vừa nâng cấp) | — |
| | Đánh giá 2 chiều + rating | ✅ Schema có, cần UI | 🔴 Cao |
| | Huy hiệu tin cậy (đã xác minh, số Kèo) | ⚙️ Một phần | 🟡 Vừa |
| **Khớp nối** | Kèo mở + ứng tuyển + queue | ✅ Có | — |
| | Tìm kiếm & lọc nâng cao | ❌ Thiếu | 🔴 Cao |
| | Hồ sơ Người đồng hành công khai | ⚙️ Một phần | 🟡 Vừa |
| | Gợi ý Kèo/người phù hợp | ❌ Thiếu | 🟢 Thấp |
| **Giao tiếp** | Nhắn tin trong app (sau khi chốt) | ✅ Schema có, cần UI | 🔴 Cao |
| | Thông báo trong app | ✅ Schema+trigger có, cần UI | 🔴 Cao |
| | Thông báo email/đẩy | ❌ Thiếu | 🟡 Vừa |
| **Giao dịch** | Xác nhận hoàn thành 2 chiều | ✅ Schema+trigger có, cần UI | 🔴 Cao |
| | Thanh toán / giữ tiền (escrow) | ❌ Thiếu (cần giấy phép) | 🟡 Vừa* |
| | Lịch sử giao dịch | ⚙️ Một phần ("Kèo của tôi") | 🟡 Vừa |
| **An toàn** | Báo cáo tranh chấp / sự cố | ✅ Schema có, cần UI | 🔴 Cao |
| | Chặn / báo cáo người dùng | ❌ Thiếu | 🟡 Vừa |
| | Nút khẩn cấp / an toàn buổi gặp | ❌ Thiếu | 🟡 Vừa |
| **Tiện ích** | Lưu Kèo / theo dõi người | ✅ Schema+helper có, cần UI | 🟢 Thấp |
| | Lịch rảnh Người đồng hành | ❌ Thiếu | 🟢 Thấp |

_*Escrow ở mức "Vừa" về giá trị nhưng cần giấy phép trung gian thanh toán — xem mục cuối._

---

## Phần đã code sẵn trong đợt này (hạ tầng cho ưu tiên Cao)

Schema `db/schema.sql` giờ có đủ bảng + trigger + RLS cho:

1. **Đánh giá 2 chiều** — bảng `reviews`, trigger tự cập nhật `rating_avg`. Chỉ người thật sự tham gia Kèo mới đánh giá được (RLS kiểm tra).
2. **Nhắn tin trong app** — `conversations` + `messages`. Chat **chỉ mở khi đơn được chấp nhận** (trigger tự tạo conversation) — thiết kế có chủ đích để chống disintermediation.
3. **Thông báo trong app** — `notifications`, trigger tự tạo khi có đơn mới / đơn được chấp nhận. Helper `Keo.unreadNotifications()` sẵn dùng.
4. **Xác nhận hoàn thành 2 chiều** — `keo_completions`. Khi cả 2 bên xác nhận, Kèo tự thành `completed` và kích hoạt đánh giá + thưởng. Helper `Keo.confirmCompletion()`.
5. **Tranh chấp / sự cố** — `disputes`, cho 2 bên báo cáo sau buổi Kèo.
6. **Lưu yêu thích** — `saved_items`, helper `Keo.toggleSaved()`.

→ Các tính năng này chỉ còn cần **giao diện** (trang/thành phần), toàn bộ hạ tầng + bảo mật đã xong.

---

## Chi tiết từng trụ

### Trụ 1 — Niềm tin (ưu tiên cao nhất)

**Đánh giá 2 chiều** là tài sản cạnh tranh cốt lõi. Không có nó, Kèo chỉ là danh bạ. Điểm tinh tế: đánh giá **2 chiều** tạo trách nhiệm cân bằng — Chủ xị cũng phải cư xử đúng mực. Nên **ẩn đánh giá tới khi cả 2 cùng gửi** (hoặc hết hạn) để tránh trả đũa qua lại.

**Huy hiệu tin cậy**: hiển thị "✓ Đã xác minh CCCD", "12 buổi Kèo", "Thành viên từ 2026" — giảm rào cản tâm lý.

### Trụ 2 — Khớp nối

**Tìm kiếm & lọc nâng cao** là thứ thiếu rõ nhất. Hiện chỉ lọc theo thành phố. Cần: lọc theo chuyên môn, khoảng giá, đánh giá tối thiểu, thời gian rảnh, sắp xếp.

**Hồ sơ công khai Người đồng hành** đầy đủ — portfolio, đánh giá, chuyên môn, số Kèo.

### Trụ 3 — Giữ giao dịch trong nền tảng

**Chat trong app** chỉ mở sau khi chốt Kèo; về sau có thể lọc/ẩn số điện thoại, email trong tin nhắn.

**Xác nhận hoàn thành + thanh toán** khép vòng giá trị.

---

## Escrow / thanh toán — vì sao để riêng

Cần **giấy phép trung gian thanh toán** tại VN (quy định NHNN). Ba hướng:
1. **Tích hợp cổng có sẵn** (VNPay, MoMo, ZaloPay) — họ có giấy phép, Kèo là merchant. Nhanh nhất.
2. **Ví trung gian tự giữ** — cần giấy phép riêng, phức tạp.
3. **Kết nối thẳng, Kèo chỉ thu phí nền tảng** — đơn giản pháp lý nhưng khó chống lách phí.

Khuyến nghị: bắt đầu hướng 1 khi có dòng giao dịch thật.

---

## Thứ tự triển khai đề xuất

**Giai đoạn 1 (niềm tin + khớp nối cơ bản) — làm ngay**
Đánh giá 2 chiều (UI) · Thông báo trong app (UI) · Xác nhận hoàn thành (UI) · Tìm kiếm & lọc nâng cao.

**Giai đoạn 2 (giao tiếp + an toàn)**
Chat trong app (UI) · Báo cáo tranh chấp (UI) · Chặn/báo cáo người dùng · Thông báo email.

**Giai đoạn 3 (giao dịch + giữ chân)**
Tích hợp thanh toán · Lịch rảnh · Lưu yêu thích (UI) · Gợi ý thông minh.

Hạ tầng cho Giai đoạn 1 + phần lớn Giai đoạn 2 đã có trong schema. Việc còn lại chủ yếu là giao diện.
