# Kèo — Hướng dẫn triển khai (repo keo-web)

Từ số 0 tới web-app chạy được. Phần code đã nằm sẵn trong repo này; việc còn lại
là **của bạn** vì cần tài khoản Supabase + Vercel thật (Claude Code không tạo/không
truy cập được các tài khoản đó).

## Cấu trúc đã có trong repo

```
keo-web/                     ← site marketing tĩnh CŨ + web-app MỚI, chung 1 deploy
├── (các trang marketing .html, .json ... giữ nguyên)
├── vendor/supabase.js       ← thư viện Supabase JS v2 (UMD, self-host) — ĐÃ tải sẵn
├── lib/keo.js               ← lớp nền dùng chung (ĐIỀN CONFIG Ở ĐÂY)
├── api/keepalive.js         ← cronjob giữ Supabase + dọn ảnh CCCD hết hạn
├── dang-nhap.html  tai-khoan.html  xac-minh.html  keo-mo.html
├── quan-ly-keo.html  thong-bao.html            ← 6 trang web-app
├── vercel.json              ← ĐÃ thêm cron + header /api (giữ nguyên CSP cũ)
└── db/
    ├── schema.sql           ← chạy 1 lần trên Supabase (10 bảng + RLS + trigger)
    └── patches/
        ├── 01-rls-patch.sql            ← vá RLS messages + profiles
        ├── 02-phone-migration.sql      ← tách phone sang bảng riêng
        ├── 03-two-sided-consent.sql    ← [STAGE 2] đồng ý hai chiều (cần UI kèm)
        └── 04-security-hardening.sql   ← vá 3 lỗ hổng rà soát bổ sung
```

## Bước 1 — Tạo Supabase project
1. [supabase.com](https://supabase.com) → New project. Region gần VN nhất (Singapore).
2. Đợi ~2 phút khởi tạo.
3. **SQL Editor** → New query → dán **toàn bộ** `db/schema.sql` → **Run**.
   Tạo hết: 17 bảng, 4 enum, 3 storage bucket, function, trigger, RLS đầy đủ.

## Bước 2 — Chạy các bản vá bảo mật (khuyến nghị, đúng thứ tự)
Trên project TEST trước:
1. `db/patches/01-rls-patch.sql`   → Run.
2. `db/patches/02-phone-migration.sql` → Run bước 1-3 (CHƯA drop cột), verify theo checklist trong file, rồi mới drop.
3. `db/patches/04-security-hardening.sql` → Run. (Độc lập, chạy được ngay sau schema.)
4. `db/patches/03-two-sided-consent.sql` → **STAGE 2**, chỉ chạy khi ghép UI kèm
   (xem `docs/INTEGRATION-two-sided-consent.md`). Nếu chạy SQL mà chưa đổi UI,
   luồng chốt Kèo sẽ đứng ở `host_selected`.

## Bước 3 — Lấy khoá API
**Settings → API**, copy 3 giá trị:
- **Project URL** (`https://xxxx.supabase.co`)
- **anon public key** (công khai được — bảo mật thật ở RLS)
- **service_role key** (BÍ MẬT — chỉ dùng cho cronjob + duyệt xác minh, KHÔNG để lộ)

## Bước 4 — Điền config (1 chỗ duy nhất)
Mở `lib/keo.js`, sửa 2 dòng đầu trong IIFE:
```js
const SUPABASE_URL = 'https://xxxx.supabase.co';   // Project URL
const SUPABASE_ANON_KEY = 'eyJhbG...';              // anon public key
```
Mọi trang dùng chung — không phải sửa từng file.

> ⚠️ Các trang HTML trong repo hiện để placeholder `YOUR_PROJECT_REF`/`YOUR_ANON_KEY`
> qua `lib/keo.js`. Chỉ cần điền ở `lib/keo.js` là đủ cho 6 trang web-app.

## Bước 5 — Cấu hình Auth
**Authentication → Providers → Email**: bật Email. Giai đoạn đầu có thể tắt
"Confirm email". **URL Configuration** → thêm domain thật vào Redirect URLs.

## Bước 6 — Env Vercel (cho cronjob)
**Settings → Environment Variables**:
- `SUPABASE_URL` = Project URL
- `SUPABASE_SERVICE_ROLE_KEY` = service_role key  (KHÔNG dán nhầm anon key)
- `CRON_SECRET` = Vercel tự sinh khi có `crons` trong vercel.json (hoặc tự đặt chuỗi ngẫu nhiên)

## Bước 7 — Deploy & kiểm thử
Deploy. Vào tab **Cron Jobs** xác nhận `/api/keepalive` chạy hàng ngày 3:00 UTC.
Luồng thử: đăng ký Chủ xị → `/tai-khoan` (hồ sơ tự tạo, có mã giới thiệu) → đăng ký
Người đồng hành (cửa sổ ẩn danh) → `/xac-minh` upload → **duyệt thủ công**: Table
Editor → `verification_documents` → đổi `status` thành `verified` (trigger tự bật
`cccd_verified`) → NĐH vào `/keo-mo` ứng tuyển → Chủ xị `/quan-ly-keo` chấp nhận.

## ⚠️ Lưu ý gói Vercel
Vercel Hobby (miễn phí) chỉ cho mục đích **cá nhân/phi thương mại** theo ToS. Kèo là
marketplace có thu phí — nếu chạy production nên cân nhắc Vercel Pro.

## Còn thiếu để hoàn chỉnh 100% (bước sau)
1. **Nâng `taokeo.html` thành form tạo Kèo thật** — hiện `/taokeo` là trang giới thiệu.
   Cần form ghi vào `open_keos` (`Keo.sb.from('open_keos').insert(...)`). Các trang
   `keo-mo`/`quan-ly-keo` link tới `/taokeo` giả định điều này.
2. **Giao diện admin duyệt xác minh** — hiện duyệt thủ công qua Table Editor.
3. **Stage 2**: đồng ý hai chiều (patch 03 + `loi-moi-cho-xac-nhan.html`) và component
   "xác nhận hoàn thành" nhúng vào "Kèo của tôi" — xem `docs/INTEGRATION-*.md`.
4. **Yêu cầu treo**: đổi nhãn "đánh giá" → "cảm nhận" khi dựng UI cho bảng `reviews`.
