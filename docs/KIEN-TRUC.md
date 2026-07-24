# Kèo — Tài liệu Kiến trúc Nền tảng

> Bản thiết kế tổng thể cho phần web-app có tài khoản của Kèo. Thay thế cách làm chắp vá trước đó (schema đắp V1→V2→V3, mỗi tính năng một file rời) bằng một kiến trúc thống nhất từ hạ tầng tới triển khai.

---

## 1. Quyết định kiến trúc & lý do

### 1.1 Vì sao KHÔNG dùng Next.js/React

Đây là quyết định có chủ đích, không phải để đơn giản hoá:

| Tiêu chí | HTML tĩnh + Supabase (chọn) | Next.js/React |
|---|---|---|
| Phần site hiện có (blog, trang chủ) | Giữ nguyên, không phải viết lại | Phải port toàn bộ |
| SEO organic (chiến lược cốt lõi) | Xuất sắc — HTML thuần, tải nhanh | Cần cấu hình SSR/SSG cẩn thận |
| Chi phí vận hành | 0đ (tĩnh + Supabase free) | Cần Node runtime, build pipeline |
| Độ phức tạp | Thấp — sửa file là xong | Cao — state, routing, hydration |
| Phù hợp giai đoạn | Đã có người dùng, cần scale organic | Khi có team dev + tính năng real-time phức tạp |

**Kết luận:** vấn đề trước đây không phải công nghệ, mà là **thiếu kiến trúc code**. Giải pháp: giữ HTML tĩnh nhưng thêm một **lớp nền dùng chung** (`lib/keo.js`) để mọi trang không lặp lại logic. Khi Kèo đạt quy mô cần real-time (chat, thông báo đẩy) và có đội ngũ kỹ thuật, việc chuyển framework sẽ là quyết định có căn cứ dữ liệu — không phải bây giờ.

### 1.2 Nguyên tắc thiết kế

1. **Một nguồn sự thật cho config** — URL + key Supabase khai báo 1 lần trong `keo.js`, không rải khắp các file.
2. **Bảo mật ở tầng database, không ở tầng giao diện** — mọi quyền truy cập do Row Level Security (RLS) quyết định. Giao diện chỉ là lớp tiện lợi; kể cả người dùng gọi thẳng API cũng không vượt được RLS.
3. **Dữ liệu nhạy cảm cô lập** — ảnh CCCD tách bucket riêng tư, quy trình riêng, không trộn với ảnh thường.
4. **Trigger lo nghiệp vụ tự động** — chấp nhận đơn → đóng Kèo; review → cập nhật rating; xác minh → mở khoá. Logic quan trọng nằm ở DB, không phụ thuộc giao diện gọi đúng thứ tự.

---

## 2. Sơ đồ hạ tầng

```
┌─────────────────────────────────────────────────────────────────┐
│                        NGƯỜI DÙNG (trình duyệt)                   │
└───────────────────────────────┬─────────────────────────────────┘
                                │ HTTPS
                ┌───────────────▼───────────────┐
                │   VERCEL (hosting tĩnh + cron) │
                │  • HTML/CSS/JS tĩnh            │
                │  • /lib/keo.js (lớp nền)       │
                │  • /api/keepalive.js (cron)    │
                └───────────────┬───────────────┘
                                │ Supabase JS SDK
                ┌───────────────▼───────────────────────────────┐
                │                 SUPABASE                        │
                │  ┌──────────┐ ┌──────────┐ ┌────────────────┐  │
                │  │  Auth    │ │ Postgres │ │    Storage     │  │
                │  │ (email/  │ │  + RLS   │ │ avatars(công)  │  │
                │  │  mật khẩu│ │+ triggers│ │ portfolio(công)│  │
                │  │  /phiên) │ │ + views  │ │ cccd (RIÊNG)   │  │
                │  └──────────┘ └──────────┘ └────────────────┘  │
                └────────────────────────────────────────────────┘
```

**Ba dịch vụ, phân vai rõ:**
- **Vercel** — chỉ phục vụ file tĩnh + chạy 1 cronjob/ngày. Không xử lý logic nghiệp vụ.
- **Supabase Auth** — toàn bộ đăng nhập/mật khẩu/phiên. Không tự viết.
- **Supabase Postgres** — dữ liệu + toàn bộ quy tắc bảo mật (RLS) + tự động hoá (triggers).
- **Supabase Storage** — 3 bucket, 2 công khai + 1 riêng tư cho CCCD.

---

## 3. Mô hình dữ liệu

10 bảng, nhóm theo chức năng:

**Nhóm danh tính**
- `profiles` — hồ sơ mỗi người (1-1 với auth.users), gồm vai trò, xác minh, referral, rating.
- `companion_details` — thông tin riêng Người đồng hành (chuyên môn, giá mặc định).

**Nhóm ảnh**
- `portfolio_images` — ảnh hồ sơ công khai (bucket `portfolio`).
- `verification_documents` — ảnh CCCD riêng tư (bucket `cccd`).

**Nhóm marketplace**
- `open_keos` — Kèo mở do Chủ xị đăng.
- `open_keo_invites` — mời riêng cho Kèo private.
- `keo_applications` — đơn ứng tuyển (queue duyệt).

**Nhóm tin cậy & tăng trưởng**
- `reviews` — đánh giá 2 chiều sau buổi Kèo → tự cập nhật `rating_avg`.
- `referral_rewards` — thưởng giới thiệu.
- `system_heartbeat` — kỹ thuật, giữ Supabase khỏi pause.

Chi tiết cột và quan hệ: xem `db/schema.sql` (có chú thích từng dòng).

---

## 4. Bảo mật ảnh — mô hình 2 tầng

Đây là phần quan trọng nhất về pháp lý (Nghị định 13/2023/NĐ-CP về bảo vệ dữ liệu cá nhân).

### 4.1 Ảnh công khai (avatar, portfolio)
- Bucket `public = true`. Ai cũng xem được qua URL cố định.
- Người dùng chỉ upload/xoá được ảnh trong thư mục mang **chính user id của mình** (`{userId}/...`) — chặn ở storage policy.
- Dùng cho: ảnh đại diện, ảnh minh hoạ chuyên môn của Người đồng hành.

### 4.2 Ảnh CCCD (nhạy cảm — tầng bảo mật cao nhất)
- Bucket `cccd` với `public = false`. **Không có URL cố định** — không ai truy cập được bằng cách đoán link.
- Chỉ xem được qua **signed URL hết hạn sau 5 phút** (`signedImageUrl`), và chỉ:
  - **Chủ hồ sơ** — xem lại ảnh mình đã nộp.
  - **Admin xác minh** — qua service role key (phía backend, không lộ ra trình duyệt).
- **Khuyến nghị vận hành:** chỉ giữ ảnh CCCD tới khi xác minh xong, rồi **xoá** — giữ trạng thái `cccd_verified = true` chứ không giữ ảnh. Ít dữ liệu nhạy cảm lưu trữ = ít rủi ro nếu có sự cố.
- **Đồng ý rõ ràng:** trước khi upload, hiện thông báo người dùng đồng ý cho Kèo xử lý CCCD để xác minh danh tính (yêu cầu của Nghị định 13).

### 4.3 Vì sao user không tự đặt `cccd_verified = true`
RLS của `profiles` chặn user tự sửa cột này (policy `profiles_self_update` kiểm tra giá trị không đổi). Chỉ trigger `on_verification_reviewed` — chạy khi admin duyệt qua service role — mới bật được. Nếu không có chốt này, ai cũng tự phong "đã xác minh".

---

## 5. Các luồng chính

### 5.1 Đăng ký → tạo hồ sơ (tự động)
```
Người dùng điền form (dang-nhap.html, tab đăng ký)
  → Keo.sb.auth.signUp({email, password, options:{data:{full_name, role, ref_code, utm}}})
  → Supabase tạo auth.users
  → TRIGGER handle_new_user() tự chạy:
      • sinh referral_code duy nhất
      • gắn referred_by (nếu vào qua link giới thiệu)
      • lưu signup_source + UTM
      • tạo dòng profiles
  → chuyển tới /tai-khoan
```

### 5.2 Xác minh CCCD
```
Người đồng hành vào /xac-minh
  → đồng ý điều khoản xử lý dữ liệu
  → upload ảnh CCCD → bucket 'cccd' (riêng tư), thư mục {userId}/
  → tạo dòng verification_documents (status='submitted')
  → [Admin xem qua signed URL, duyệt bằng service role]
  → TRIGGER on_verification_reviewed: profiles.cccd_verified = true
  → Người đồng hành giờ ứng tuyển được Kèo mở
```

### 5.3 Kèo mở → ứng tuyển → duyệt (queue)
```
CHỦ XỊ: /taokeo → tạo open_keos (fixed_fee optional)
NGƯỜI ĐỒNG HÀNH (đã xác minh): /keo-mo → xem danh sách → ứng tuyển
  → tạo keo_applications (message bắt buộc, proposed_fee nếu Kèo để ngỏ giá)
CHỦ XỊ: /quan-ly-keo → xem queue đơn → Chấp nhận / Từ chối
  → khi chấp nhận: TRIGGER đóng Kèo + tự từ chối đơn còn lại
```

### 5.4 Sau buổi Kèo → đánh giá → rating
```
Buổi Kèo hoàn thành (đội ngũ/hệ thống set first_keo_at + status)
  → cả 2 bên đánh giá nhau (reviews)
  → TRIGGER on_review_added: cập nhật rating_avg + rating_count
  → nếu người được giới thiệu: referral_rewards ghi nhận thưởng
```

---

## 6. Kiến trúc code (hết chắp vá)

```
keo-web/                     ← trong repo này (chung với site marketing)
├── db/
│   └── schema.sql          ← 1 file schema hoàn chỉnh (thay V1/V2/V3)
├── lib/
│   └── keo.js              ← LỚP NỀN dùng chung: client, auth, ảnh, tiện ích
├── (các trang web-app ở root, cùng site tĩnh)
│   ├── dang-nhap.html
│   ├── tai-khoan.html      ← hồ sơ + ảnh + mời bạn + Kèo của tôi
│   ├── xac-minh.html       ← upload CCCD
│   ├── keo-mo.html         ← NĐH khám phá + ứng tuyển
│   └── quan-ly-keo.html    ← Chủ xị duyệt queue
├── api/
│   └── keepalive.js        ← cronjob giữ Supabase
└── docs/
    └── KIEN-TRUC.md        ← tài liệu này
```

**Nguyên tắc:** mọi trang nạp `vendor/supabase.js` rồi `lib/keo.js`, sau đó chỉ gọi `Keo.requireAuth()`, `Keo.uploadImage()`, `Keo.toast()`... — không trang nào tự tạo client hay tự viết lại redirect. Sửa logic chung = sửa 1 chỗ.

---

## 7. Tính năng đề xuất thêm (ngoài yêu cầu ban đầu)

**Nên làm sớm**
1. **Đánh giá 2 chiều** (đã có schema `reviews` + trigger) — xây dựng lòng tin.
2. **"Kèo của tôi"** — trang cho cả 2 vai trò xem lịch sử Kèo. Đã gộp vào `tai-khoan.html`.
3. **Trạng thái hoàn thành buổi Kèo** — nút "Đã gặp xong" để kích hoạt đánh giá + referral.

**Nên làm khi có đà**
4. **Thông báo trong app** — (Supabase Realtime làm được, không cần đổi framework.)
5. **Lưu Kèo yêu thích / theo dõi Người đồng hành**.
6. **Lịch rảnh của Người đồng hành**.

**Cân nhắc dài hạn**
7. **Nhắn tin trong app** (thiết kế thận trọng chống lách phí).
8. **Escrow/thanh toán** — mảng pháp lý riêng (giấy phép trung gian thanh toán).

---

## 8. Lộ trình triển khai

1. **Tạo Supabase project** → chạy `db/schema.sql`.
2. **Điền config** — URL + anon key vào `lib/keo.js`.
3. **Khai báo env Vercel** — `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`.
4. **Deploy**.
5. **Kiểm thử** — đăng ký → hồ sơ tự tạo → upload ảnh → tạo Kèo → ứng tuyển → duyệt.
6. **Bật cron** — kiểm tra tab Cron Jobs trên Vercel.

Chi tiết từng bước: `docs/SETUP.md`.
