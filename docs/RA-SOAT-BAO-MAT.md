# Kèo — Rà soát bảo mật (kèm patch 04)

Rà soát toàn bộ schema + 6 trang web-app + lib. Xếp theo mức độ. Các mục 🔴/🟡
được vá trong `db/patches/04-security-hardening.sql`; 🟢 residual được ghi rõ để
xử lý riêng.

## 🔴 Nghiêm trọng — khai thác được ngay (ĐÃ VÁ ở patch 04)

### #1 — Giả mạo referral qua `profiles_self_update`
Policy gốc chỉ khoá `cccd_verified` + `rating_avg`. Các cột `role`, `referred_by`,
`first_keo_at`, `activated`, `signup_source`, `signup_utm`, `verification`,
`rating_count`, `referral_code` **bỏ ngỏ**. Một user gọi thẳng REST API (chỉ cần
anon/authenticated key công khai, bỏ qua UI):
```js
sb.from('profiles').update({ referred_by:'<id bạn>', first_keo_at:new Date().toISOString() }).eq('id', me)
```
→ trigger `on_user_activated` tự tạo `referral_rewards` → **phá cơ chế chống gian
lận cốt lõi** (README/IMC: "chỉ thưởng khi hoàn thành buổi Kèo thật").
**Vá:** đảo policy sang whitelist — mọi cột danh tính/growth phải == giá trị cũ.

### #2 — Đánh giá giả qua `reviews_author_insert`
Policy gốc chỉ xác thực *reviewer* có tham gia Kèo, không xác thực *reviewee* là
đối tác thật. → Chủ xị của 1 Kèo filled/completed chèn review với `reviewee_id`
là **bất kỳ profile nào** → đánh giá giả (bôi nhọ/thổi phồng) gắn với Kèo có thật.
**Vá:** reviewee phải là "phía bên kia" đúng Kèo (host↔companion-accepted), cấm tự đánh giá.

## 🟡 Đáng lưu ý (ĐÃ VÁ / giảm thiểu ở patch 04)

### #3 — Hash CCCD trần (client SHA-256, không salt/pepper)
Số CCCD có cấu trúc → không gian nhỏ, vét cạn được nếu `cccd_hash` rò rỉ. Mâu thuẫn
cam kết "băm một chiều không khôi phục" trong `privacy.html` (NĐ 13). Patch 04 ghi
chú hướng HMAC server-side; hash client chỉ để so khớp sơ bộ. *(Chưa bắt buộc — cần
thêm secret phía server; xem ghi chú trong patch.)*

### #4 — Race: 2 đơn cùng `accepted` cho 1 Kèo
Trigger chỉ kiểm `old.status` của dòng đang update, không khoá mức Kèo. 2 UPDATE
đồng thời → 2 companion cùng accepted. **Vá:** partial unique index
`uniq_one_accepted_per_keo (keo_id) where status='accepted'`.

### (D) — Trigger xác minh phía server
Sau khi #1 khoá cột `verification`, client không tự set 'submitted' được nữa (đúng
ra RLS phải chặn). Patch 04 thêm trigger `on_verification_submitted` (SECURITY
DEFINER) đặt `verification='submitted'` + ghi `verification_audit`. `xac-minh.html`
đã bỏ 2 lệnh ghi trực tiếp (trước đây lệnh ghi audit còn **âm thầm lỗi** vì RLS
không có policy insert cho user).

## 🟢 Residual — ghi rõ, chưa auto-vá (tránh phá luồng khác)

### #5 — authenticated đọc mọi cột profiles người khác
RLS lọc theo HÀNG, không theo CỘT. `patch 01` tạo view `public_profiles` an toàn cho
anon, nhưng authenticated vẫn `select` được cột growth của người khác. Không revoke
column-privilege được vì sẽ phá `.select('*')` chính-chủ của `tai-khoan.html`.
**Vá đúng (làm cùng lúc):** (1) đổi truy vấn "xem người khác" sang `public_profiles`;
(2) `Keo.getProfile` select cột tường minh; (3) revoke select các cột growth khỏi
authenticated/anon. Chi tiết trong patch 04.

### #6 — Chủ xị "Chấp nhận" đơn đã rejected/withdrawn
Status dòng đổi 'accepted' nhưng trigger không chạy (kiểm old='pending') → không fill
Kèo/không mở chat; chỉ lệch dữ liệu nhẹ, **không phải lỗ hổng**. `patch 03` (nếu áp)
đã chặn cứng qua `check_app_status_transition`. Để riêng vì dễ đụng model patch 03.

## Không có vấn đề (đã kiểm kỹ)
- **XSS**: mọi nơi render dữ liệu user đều qua `Keo.esc()`; `thong-bao.html` bọc thêm
  `encodeURI()` cho `n.link`.
- **Injection**: đăng ký/ref-code dùng bind param.
- **Storage**: policy CCCD/avatar/portfolio đúng mẫu `{userId}/...`; bucket `cccd`
  private, chỉ signed URL.
- **Auth gating**: `requireAuth()` kiểm role → verified đúng thứ tự; `keo-mo` chặn
  chưa-xác-minh khớp RLS `is_verified_companion()`.

## Thứ tự ưu tiên khi lên production
1. `schema.sql` → `04-security-hardening.sql` (bắt buộc, chặn #1/#2/#4).
2. `01` + `02` (bảo vệ tin nhắn + số điện thoại).
3. Cân nhắc #3 (HMAC) trước khi mở xác minh CCCD rộng.
4. #5 khi có thời gian đổi client sang `public_profiles`.
5. `03` (two-sided consent) là feature, làm cùng UI (stage 2).
