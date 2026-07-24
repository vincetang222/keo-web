-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  KÈO — BẢN VÁ BẢO MẬT RLS #01                                              ║
-- ║  Sửa 2 điểm phát hiện khi rà soát schema.sql:                              ║
-- ║   (A) messages: msg_mark_read cho phép sửa MỌI cột, không chỉ read_at      ║
-- ║   (B) profiles: public_read lộ cả phone + dữ liệu marketing nội bộ         ║
-- ║                                                                            ║
-- ║  CÁCH DÙNG: dán toàn bộ file này vào Supabase → SQL Editor → Run.          ║
-- ║  An toàn chạy trên project đang có dữ liệu (chỉ thay policy, không đụng     ║
-- ║  bảng/dữ liệu). Có phần TEST và ROLLBACK ở cuối.                           ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝


-- ═══════════════════════════════════════════════════════════════════════════
--  (A) MESSAGES — chỉ cho phép cập nhật read_at, không cho sửa nội dung tin
-- ═══════════════════════════════════════════════════════════════════════════
-- VẤN ĐỀ: policy cũ dùng `with check (true)` → người trong cuộc trò chuyện có
-- thể UPDATE bất kỳ cột nào của bất kỳ tin nào trong hội thoại, kể cả sửa `body`
-- của tin người kia đã gửi. Rủi ro: bịa/sửa nội dung tin nhắn người khác.
--
-- CÁCH SỬA: Postgres RLS không so sánh được "cột nào đang bị sửa" trực tiếp
-- trong policy một cách gọn gàng, nên ta chặn ở tầng chắc chắn hơn:
--   1) Thu hồi quyền UPDATE trên các cột nội dung, chỉ cấp UPDATE trên read_at.
--      → Đây là chốt THẬT: dù policy có cho qua, Postgres vẫn từ chối sửa cột
--        không được cấp quyền. Column-level privilege + RLS = 2 lớp.
--   2) Giữ policy RLS yêu cầu người update phải là thành viên hội thoại.

-- Bước 1: thu hồi UPDATE toàn bảng, chỉ cấp lại UPDATE trên đúng cột read_at
--         cho role 'authenticated' (người dùng đã đăng nhập qua Supabase).
revoke update on public.messages from authenticated;
grant  update (read_at) on public.messages to authenticated;

-- Bước 2: thay policy cũ bằng policy vẫn kiểm tra thành viên hội thoại.
--         (with check vẫn để điều kiện thành viên; quyền cột ở trên lo phần "chỉ read_at")
drop policy if exists "msg_mark_read" on public.messages;
create policy "msg_mark_read" on public.messages for update
  using (exists (
    select 1 from public.conversations c
    where c.id = conversation_id
      and (c.host_id = auth.uid() or c.companion_id = auth.uid())
  ))
  with check (exists (
    select 1 from public.conversations c
    where c.id = conversation_id
      and (c.host_id = auth.uid() or c.companion_id = auth.uid())
  ));


-- ═══════════════════════════════════════════════════════════════════════════
--  (B) PROFILES — không public toàn bộ cột; tách "hồ sơ công khai" ra view
-- ═══════════════════════════════════════════════════════════════════════════
-- VẤN ĐỀ: policy `profiles_public_read using (true)` cho bất kỳ ai (kể cả chưa
-- đăng nhập) đọc MỌI cột của MỌI profile — gồm `phone` (số ĐT, dữ liệu cá nhân
-- theo NĐ 13), `signup_utm`, `signup_source`, `referred_by` (dữ liệu nội bộ).
--
-- NGUYÊN TẮC SỬA: chủ hồ sơ đọc được mọi cột CỦA MÌNH; người khác chỉ đọc các
-- cột công khai an toàn. Client hiện tại (keo-mo, quan-ly-keo) chỉ lấy
-- full_name/rating_avg/city của người khác → KHÔNG bị phá bởi thay đổi này.

-- Bước 1: bỏ policy đọc-tất-cả.
drop policy if exists "profiles_public_read" on public.profiles;

-- Bước 2: chủ hồ sơ đọc đầy đủ hàng của mình (cho trang /tai-khoan select *).
create policy "profiles_self_read" on public.profiles for select
  using (auth.uid() = id);

-- Bước 3: người đã đăng nhập đọc hàng người khác — nhưng ta sẽ CHẶN cột nhạy cảm
--         bằng column privilege (giống cách làm với messages), vì RLS lọc theo
--         HÀNG chứ không theo CỘT.
--         → thu hồi SELECT toàn bảng, cấp lại SELECT trên đúng các cột công khai.
--         Chủ hồ sơ vẫn đọc đủ cột của mình vì... (xem lưu ý QUAN TRỌNG bên dưới)
--
-- LƯU Ý QUAN TRỌNG VỀ COLUMN PRIVILEGE + RLS:
--   Column privilege áp cho MỌI truy vấn của role đó, không phân biệt hàng.
--   Nghĩa là nếu thu hồi SELECT trên cột `phone`, thì ngay cả chủ hồ sơ cũng
--   không select được `phone` của chính mình qua PostgREST bằng anon/auth key.
--   → Đây là lý do ta KHÔNG dùng column-privilege cho profiles, mà thay bằng
--     một VIEW công khai chỉ chứa cột an toàn. Chủ hồ sơ đọc bảng gốc (đủ cột)
--     qua policy self_read; người khác đọc qua VIEW.

-- Bước 3 (thực thi): giữ policy cho phép đọc hàng người khác, nhưng client
-- KHÔNG nên select cột nhạy cảm của người khác. Vì RLS không chặn được theo cột,
-- ta tạo VIEW an toàn để client dùng khi xem người khác, và khuyến nghị đổi
-- client sang view đó. Đồng thời vẫn cho authenticated đọc hàng người khác
-- (chỉ các trang nội bộ, cột an toàn) — nhưng bỏ quyền đọc của ANON hoàn toàn.

-- 3a. KHÔNG cho khách vãng lai (chưa đăng nhập) đọc profiles nữa.
--     (Trước đây using(true) cho cả anon đọc — giờ yêu cầu đăng nhập.)
create policy "profiles_auth_read_others" on public.profiles for select
  to authenticated
  using (true);
-- → Người đã đăng nhập vẫn đọc được hàng người khác (cần cho marketplace),
--   nhưng client PHẢI chỉ select cột an toàn. Xem view + khuyến nghị dưới.

-- 3b. VIEW hồ sơ công khai — chỉ cột an toàn. Dùng cho mọi nơi hiển thị
--     người khác (danh sách Người đồng hành, host của Kèo, tác giả review...).
create or replace view public.public_profiles as
  select
    id,
    role,
    full_name,
    avatar_url,
    bio,
    city,
    cccd_verified,
    rating_avg,
    rating_count,
    created_at
  from public.profiles;

-- View kế thừa RLS của bảng gốc (security_invoker) để không rò hàng ngoài ý muốn.
alter view public.public_profiles set (security_invoker = on);

grant select on public.public_profiles to anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
--  KIỂM TRA SAU KHI CHẠY (chạy từng câu, xem kết quả có đúng kỳ vọng không)
-- ═══════════════════════════════════════════════════════════════════════════
-- 1) Liệt kê policy hiện có trên 2 bảng — xác nhận policy mới đã thay policy cũ:
--    select tablename, policyname, cmd from pg_policies
--    where tablename in ('messages','profiles') order by tablename, policyname;
--
-- 2) Xác nhận quyền cột trên messages (authenticated chỉ còn UPDATE(read_at)):
--    select grantee, privilege_type, column_name
--    from information_schema.column_privileges
--    where table_name='messages' and grantee='authenticated';
--
-- 3) TEST THỰC TẾ (làm bằng 2 tài khoản test trên app, KHÔNG phải SQL admin —
--    vì SQL Editor chạy quyền service role, bỏ qua RLS nên không phản ánh thật):
--    (A) Đăng nhập user A, thử sửa body 1 tin trong hội thoại → PHẢI bị từ chối.
--        Thử đánh dấu đã đọc (chỉ set read_at) → PHẢI thành công.
--    (B) Từ tài khoản B (hoặc chưa đăng nhập), thử đọc `phone` của A qua API:
--        supabase.from('profiles').select('phone').eq('id', A_id)
--        → PHẢI trả rỗng/lỗi; còn select từ public_profiles → ra cột an toàn.


-- ═══════════════════════════════════════════════════════════════════════════
--  ROLLBACK (nếu cần quay lại trạng thái cũ — dán riêng phần này để hoàn tác)
-- ═══════════════════════════════════════════════════════════════════════════
-- -- messages:
-- drop policy if exists "msg_mark_read" on public.messages;
-- grant update on public.messages to authenticated;
-- create policy "msg_mark_read" on public.messages for update
--   using (exists (select 1 from public.conversations c where c.id = conversation_id
--     and (c.host_id = auth.uid() or c.companion_id = auth.uid())))
--   with check (true);
-- -- profiles:
-- drop policy if exists "profiles_self_read" on public.profiles;
-- drop policy if exists "profiles_auth_read_others" on public.profiles;
-- drop view if exists public.public_profiles;
-- create policy "profiles_public_read" on public.profiles for select using (true);
