-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  KÈO — MIGRATION: tách `phone` khỏi profiles (bảo vệ dữ liệu cá nhân)      ║
-- ║                                                                            ║
-- ║  LÝ DO: `profiles` bị đọc rộng (marketplace cần xem hồ sơ người khác),     ║
-- ║  nên để `phone` trong đó là rủi ro lộ số điện thoại — dữ liệu cá nhân      ║
-- ║  theo Nghị định 13/2023/NĐ-CP. Tách sang bảng riêng chỉ-chủ-đọc.           ║
-- ║                                                                            ║
-- ║  ⚠️  CHƯA TEST TRÊN POSTGRES THẬT. Người viết (Claude) không chạy được DB   ║
-- ║      ở môi trường này. BẮT BUỘC chạy trên project TEST trước, kiểm bằng    ║
-- ║      2 tài khoản thật (checklist ở cuối), rồi mới chạy lên production.     ║
-- ║                                                                            ║
-- ║  Chạy SAU rls-patch-01.sql. Thứ tự: (1) tạo bảng+RLS (2) di dữ liệu cũ     ║
-- ║  (3) bỏ cột cũ (4) sửa client tai-khoan.html (hướng dẫn ở cuối).           ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝


-- ═══════════════════════════════════════════════════════════════════════════
--  PHƯƠNG ÁN CHÍNH — tách bảng riêng (khuyến nghị)
-- ═══════════════════════════════════════════════════════════════════════════

-- 1) Bảng riêng: 1-1 với profiles, chỉ chứa liên hệ nhạy cảm.
create table if not exists public.profile_private (
  id          uuid primary key references public.profiles(id) on delete cascade,
  phone       text,
  updated_at  timestamptz not null default now()
);

-- 2) Bật RLS + policy: CHỈ chủ hồ sơ đọc/ghi hàng của mình. Không ai khác.
alter table public.profile_private enable row level security;

create policy "pp_self_read"   on public.profile_private for select
  using (auth.uid() = id);
create policy "pp_self_insert" on public.profile_private for insert
  with check (auth.uid() = id);
create policy "pp_self_update" on public.profile_private for update
  using (auth.uid() = id) with check (auth.uid() = id);
-- Không có policy cho người khác → RLS mặc định từ chối. Kể cả gọi thẳng API
-- cũng không đọc được phone của người khác (khác hẳn để trong profiles).

-- 3) Di chuyển dữ liệu phone cũ (nếu đã có người dùng nhập số) sang bảng mới.
--    Chạy 1 lần. Bỏ qua hàng phone rỗng.
insert into public.profile_private (id, phone)
  select id, phone from public.profiles
  where phone is not null and phone <> ''
on conflict (id) do update set phone = excluded.phone;

-- 4) SAU KHI đã xác nhận dữ liệu di chuyển đúng (chạy câu kiểm ở checklist),
--    mới bỏ cột phone khỏi profiles. GIỮ 2 bước tách rời — đừng drop vội.
--    ↓↓↓ chạy riêng, sau khi verify ↓↓↓
-- alter table public.profiles drop column phone;


-- ═══════════════════════════════════════════════════════════════════════════
--  SỬA CLIENT — tai-khoan.html (3 chỗ). Làm SAU khi migration DB xong.
-- ═══════════════════════════════════════════════════════════════════════════
-- Hiện `phone` đọc/ghi chung trong profiles. Sau khi tách, phải đọc/ghi ở
-- bảng profile_private. Cụ thể:
--
-- (a) Khi NẠP hồ sơ — thêm 1 query lấy phone riêng (chạy song song getProfile):
--     const { data: priv } = await Keo.sb.from('profile_private')
--       .select('phone').eq('id', ME.id).maybeSingle();
--     PROFILE.phone = priv?.phone || '';     // giữ nguyên fillProfile() bên dưới
--     → dòng `document.getElementById('phone').value = PROFILE.phone||''` giữ nguyên.
--
-- (b) Trong saveProfile(): BỎ `phone:` ra khỏi .update({...}) của 'profiles',
--     và thêm 1 upsert riêng vào profile_private:
--     await Keo.sb.from('profiles').update({
--        full_name:..., city:..., bio:..., updated_at:...   // KHÔNG còn phone
--     }).eq('id', ME.id);
--     await Keo.sb.from('profile_private').upsert({
--        id: ME.id,
--        phone: document.getElementById('phone').value.trim(),
--        updated_at: new Date().toISOString()
--     });
--
-- (c) (Tuỳ chọn, gọn hơn) thêm 2 helper vào lib/keo.js để các trang khác dùng lại:
--     getMyPhone()  → select phone from profile_private where id = auth.uid()
--     setMyPhone(p) → upsert profile_private
--     rồi tai-khoan.html gọi Keo.getMyPhone()/Keo.setMyPhone() thay vì query thẳng.


-- ═══════════════════════════════════════════════════════════════════════════
--  CHECKLIST TEST (bắt buộc, trước khi lên production)
-- ═══════════════════════════════════════════════════════════════════════════
-- Trên project TEST:
-- [ ] 1. Chạy phần "PHƯƠNG ÁN CHÍNH" bước 1-3 (chưa drop cột).
-- [ ] 2. Verify dữ liệu di chuyển đúng:
--        select count(*) from public.profiles where phone is not null and phone<>'';
--        select count(*) from public.profile_private;   -- 2 số phải khớp
-- [ ] 3. Sửa client tai-khoan.html (3 chỗ trên).
-- [ ] 4. Test bằng TÀI KHOẢN THẬT trên app (KHÔNG test bằng SQL Editor — nó chạy
--        service role, bỏ qua RLS, không phản ánh thật):
--        [ ] User A: vào /tai-khoan, nhập số ĐT, lưu → tải lại trang, số vẫn còn.
--        [ ] User B đăng nhập, thử đọc phone của A qua API:
--            supabase.from('profile_private').select('phone').eq('id', A_id)
--            → PHẢI trả rỗng (RLS chặn). Đây là mấu chốt của cả migration.
--        [ ] Khách chưa đăng nhập: cùng query trên → cũng PHẢI rỗng.
-- [ ] 5. Chỉ khi 4 mục trên PASS: chạy `alter table profiles drop column phone;`
-- [ ] 6. Chạy lại toàn bộ trên project PRODUCTION, cẩn thận, giờ thấp điểm.


-- ═══════════════════════════════════════════════════════════════════════════
--  ROLLBACK (nếu cần hoàn tác — chỉ dùng khi CHƯA drop cột phone ở profiles)
-- ═══════════════════════════════════════════════════════════════════════════
-- -- đưa phone về lại profiles (nếu đã lỡ drop, thêm lại cột rồi copy về):
-- -- alter table public.profiles add column if not exists phone text;
-- -- update public.profiles p set phone = pp.phone
-- --   from public.profile_private pp where pp.id = p.id;
-- drop table if exists public.profile_private cascade;
-- -- rồi revert 3 chỗ sửa trong tai-khoan.html.


-- ═══════════════════════════════════════════════════════════════════════════
--  PHƯƠNG ÁN B (tham khảo) — không tách bảng, dùng RPC + thu hồi quyền cột
-- ═══════════════════════════════════════════════════════════════════════════
-- Nếu không muốn tách bảng, có thể giữ phone trong profiles nhưng:
--   revoke select (phone) on public.profiles from anon, authenticated;
--   -- rồi tạo function chạy quyền definer, chỉ trả phone của chính mình:
--   create or replace function public.my_phone() returns text
--     language sql security definer stable as $$
--       select phone from public.profiles where id = auth.uid()
--     $$;
--   grant execute on function public.my_phone() to authenticated;
-- NHƯỢC ĐIỂM so với tách bảng:
--   - `security definer` phải viết CỰC cẩn thận (dễ tạo lỗ nếu sai điều kiện).
--   - Thu hồi quyền cột ảnh hưởng mọi truy vấn `select *` — dễ vỡ chỗ khác.
--   - Tách bảng rõ ràng hơn về ý định "dữ liệu này là riêng tư".
-- → Khuyến nghị dùng PHƯƠNG ÁN CHÍNH (tách bảng) trừ khi có lý do đặc biệt.
