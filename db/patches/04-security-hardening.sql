-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  KÈO — BẢN VÁ BẢO MẬT #04 (rà soát bổ sung sau schema.sql)                 ║
-- ║                                                                            ║
-- ║  Vá 3 lỗ hổng khai thác được + 1 trigger cần cho luồng xác minh mới:       ║
-- ║   (A) profiles_self_update chỉ khoá 2/nhiều cột nhạy cảm → GIẢ MẠO         ║
-- ║       referral: user tự set referred_by/first_keo_at qua API để "chín"     ║
-- ║       thưởng giới thiệu mà không cần buổi Kèo thật.                        ║
-- ║   (B) reviews_author_insert không kiểm reviewee_id là đối tác thật của     ║
-- ║       Kèo → tạo đánh giá giả (bôi nhọ/thổi phồng) cho bất kỳ profile nào.  ║
-- ║   (C) Race: 2 đơn cùng 'accepted' cho 1 Kèo nếu update gần đồng thời.      ║
-- ║   (D) Trigger on_verification_submitted: đặt profiles.verification =        ║
-- ║       'submitted' + ghi audit phía SERVER (xac-minh.html không còn ghi     ║
-- ║       trực tiếp — RLS chặn user tự sửa verification / bảng audit).         ║
-- ║                                                                            ║
-- ║  CHẠY SAU schema.sql. Độc lập với patch 01/02/03 (không đụng nhau).        ║
-- ║  Có phần TEST + ROLLBACK ở cuối. Xem thêm docs/RA-SOAT-BAO-MAT.md.         ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝


-- ═══════════════════════════════════════════════════════════════════════════
--  (A) PROFILES — khoá CỨNG mọi cột danh tính/growth (whitelist, không blacklist)
-- ═══════════════════════════════════════════════════════════════════════════
-- VẤN ĐỀ: policy cũ chỉ khoá cccd_verified + rating_avg. Các cột sau BỎ NGỎ,
-- user gọi thẳng REST API sửa được (bỏ qua UI):
--   role, referred_by, first_keo_at, activated, signup_source, signup_utm,
--   verification, rating_count, referral_code.
-- Nguy hiểm nhất: set referred_by = <bạn mình> + first_keo_at = now() → trigger
-- on_user_activated tự tạo referral_rewards → GIẢ MẠO chống-gian-lận cốt lõi.
--
-- CÁCH SỬA: đảo sang whitelist — mọi cột nhạy cảm PHẢI GIỮ NGUYÊN giá trị cũ.
-- Chỉ còn các cột hồ sơ do user tự sửa (full_name, city, bio, avatar_url,
-- phone, updated_at) là được đổi. (phone: nếu đã chạy patch 02 tách bảng thì
-- cột này không còn trong profiles — policy dưới không tham chiếu phone nên vẫn
-- chạy đúng ở cả 2 trường hợp.)

drop policy if exists "profiles_self_update" on public.profiles;
create policy "profiles_self_update" on public.profiles for update
  using (auth.uid() = id)
  with check (
    auth.uid() = id
    -- các cột nhạy cảm phải == giá trị cũ (đọc từ hàng hiện tại của chính mình)
    and role            =            (select p.role            from public.profiles p where p.id = auth.uid())
    and verification    =            (select p.verification    from public.profiles p where p.id = auth.uid())
    and cccd_verified   =            (select p.cccd_verified   from public.profiles p where p.id = auth.uid())
    and referral_code   is not distinct from (select p.referral_code   from public.profiles p where p.id = auth.uid())
    and referred_by     is not distinct from (select p.referred_by     from public.profiles p where p.id = auth.uid())
    and signup_source   is not distinct from (select p.signup_source   from public.profiles p where p.id = auth.uid())
    and signup_utm      is not distinct from (select p.signup_utm      from public.profiles p where p.id = auth.uid())
    and first_keo_at    is not distinct from (select p.first_keo_at    from public.profiles p where p.id = auth.uid())
    and activated       =            (select p.activated       from public.profiles p where p.id = auth.uid())
    and rating_avg      is not distinct from (select p.rating_avg      from public.profiles p where p.id = auth.uid())
    and rating_count    =            (select p.rating_count    from public.profiles p where p.id = auth.uid())
  );


-- ═══════════════════════════════════════════════════════════════════════════
--  (B) REVIEWS — bắt buộc reviewee_id là ĐỐI TÁC THẬT của Kèo được đánh giá
-- ═══════════════════════════════════════════════════════════════════════════
-- VẤN ĐỀ: policy cũ chỉ xác nhận REVIEWER có tham gia Kèo, không xác nhận
-- REVIEWEE là bên còn lại. → Chủ xị (hoặc NĐH) của 1 Kèo filled/completed có
-- thể chèn review với reviewee_id là BẤT KỲ ai → đánh giá giả gắn Kèo thật.
--
-- CÁCH SỬA: reviewee phải là "phía bên kia" của đúng Kèo đó:
--   • nếu reviewer là host → reviewee phải là companion đã 'accepted' của Kèo
--   • nếu reviewer là companion đã 'accepted' → reviewee phải là host của Kèo
-- Và không cho tự đánh giá chính mình.

drop policy if exists "reviews_author_insert" on public.reviews;
create policy "reviews_author_insert" on public.reviews for insert
  with check (
    auth.uid() = reviewer_id
    and reviewer_id <> reviewee_id
    and exists (
      select 1 from public.open_keos k
      where k.id = keo_id
        and k.status in ('filled','completed')
        and (
          -- reviewer = host, reviewee = companion đã accepted
          ( k.host_id = auth.uid()
            and exists (select 1 from public.keo_applications a
                        where a.keo_id = k.id and a.companion_id = reviews.reviewee_id
                          and a.status = 'accepted') )
          or
          -- reviewer = companion đã accepted, reviewee = host
          ( k.host_id = reviews.reviewee_id
            and exists (select 1 from public.keo_applications a
                        where a.keo_id = k.id and a.companion_id = auth.uid()
                          and a.status = 'accepted') )
        )
    )
  );


-- ═══════════════════════════════════════════════════════════════════════════
--  (C) RACE — chỉ 1 đơn 'accepted' cho mỗi Kèo (chốt cứng bằng unique index)
-- ═══════════════════════════════════════════════════════════════════════════
-- VẤN ĐỀ: trigger accept chỉ kiểm old.status của đúng dòng đang update, không
-- khoá ở mức Kèo. 2 UPDATE gần đồng thời (bấm nhanh/2 tab) có thể cho 2 đơn
-- cùng 'accepted'. Partial unique index chặn cứng ở tầng DB (giao dịch thứ 2 lỗi).
create unique index if not exists uniq_one_accepted_per_keo
  on public.keo_applications (keo_id)
  where status = 'accepted';


-- ═══════════════════════════════════════════════════════════════════════════
--  (D) VERIFICATION — trigger đặt profiles.verification='submitted' phía server
-- ═══════════════════════════════════════════════════════════════════════════
-- Sau khi (A) khoá cột verification, client KHÔNG tự set 'submitted' được nữa
-- (và không nên — RLS đúng ra phải chặn). xac-minh.html giờ chỉ insert vào
-- verification_documents; trigger dưới lo cập nhật profiles + ghi audit (tầng 3),
-- chạy SECURITY DEFINER nên vượt RLS một cách có kiểm soát.
create or replace function public.on_verification_submitted()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'submitted' then
    -- không hạ cấp hồ sơ đã 'verified'
    update public.profiles
      set verification = 'submitted', updated_at = now()
      where id = new.profile_id and verification <> 'verified';
    insert into public.verification_audit (profile_id, document_id, action, actor_id)
      values (new.profile_id, new.id, 'submitted', new.profile_id);
  end if;
  return new;
end $$;

drop trigger if exists on_verif_submitted on public.verification_documents;
create trigger on_verif_submitted
  after insert on public.verification_documents
  for each row execute function public.on_verification_submitted();


-- ═══════════════════════════════════════════════════════════════════════════
--  GHI CHÚ 2 ĐIỂM RESIDUAL (chưa vá trong file này — cần cân nhắc riêng)
-- ═══════════════════════════════════════════════════════════════════════════
-- #5 (medium) — authenticated vẫn đọc được MỌI cột profiles của người khác
--   (signup_utm, referred_by, first_keo_at, activated) vì RLS lọc theo HÀNG,
--   không theo CỘT. Không thể revoke column-privilege mà không phá luồng
--   `.select('*')` chính-chủ của tai-khoan.html.
--   → CÁCH VÁ ĐÚNG (làm cùng lúc, không auto ở đây vì đụng client):
--     1. Đổi mọi truy vấn "xem người khác" sang view public_profiles (patch 01).
--     2. Đổi Keo.getProfile()/tai-khoan sang select cột tường minh (bỏ '*').
--     3. Rồi: revoke select (signup_utm,signup_source,referred_by,first_keo_at,
--        activated) on public.profiles from authenticated, anon;
--
-- #6 (thấp) — Chủ xị có thể "Chấp nhận" một đơn đã rejected/withdrawn: status
--   dòng đó đổi 'accepted' nhưng trigger KHÔNG chạy (nó kiểm old.status='pending')
--   → không fill Kèo, không mở chat; chỉ lệch dữ liệu nhẹ, không phải lỗ hổng.
--   Nếu áp patch 03 (two-sided consent), trigger check_app_status_transition ở
--   đó đã chặn cứng mọi chuyển state trái phép — #6 được vá luôn. Nếu KHÔNG
--   dùng patch 03, có thể siết apps_host_decide bằng cách kiểm old.status qua
--   subquery (giống cách làm ở (A)); để riêng vì dễ đụng model của patch 03.


-- ═══════════════════════════════════════════════════════════════════════════
--  TEST (bằng tài khoản thật trên app — SQL Editor chạy service role, bỏ RLS)
-- ═══════════════════════════════════════════════════════════════════════════
-- (A) User C (đã đăng nhập) gọi API:
--     supabase.from('profiles').update({ referred_by:'<id khác>', first_keo_at:new Date().toISOString() }).eq('id', C_id)
--     → PHẢI lỗi (RLS with check chặn). Trước patch: thành công + tạo referral giả.
--     Đồng thời: sửa full_name/city/bio/avatar vẫn PHẢI thành công.
-- (B) Chủ xị H của 1 Kèo completed chèn review reviewee_id = người lạ X (không
--     phải companion của Kèo) → PHẢI lỗi. Chèn review cho companion thật → OK.
-- (C) Mở 2 tab quan-ly-keo, bấm "Chấp nhận" 2 đơn khác nhau của cùng Kèo gần
--     như đồng thời → chỉ 1 thành công, cái còn lại lỗi unique index.
-- (D) NĐH vào /xac-minh gửi CCCD → kiểm profiles.verification='submitted' và có
--     1 dòng verification_audit action='submitted' (Table Editor).


-- ═══════════════════════════════════════════════════════════════════════════
--  ROLLBACK
-- ═══════════════════════════════════════════════════════════════════════════
-- drop trigger if exists on_verif_submitted on public.verification_documents;
-- drop function if exists public.on_verification_submitted();
-- drop index if exists public.uniq_one_accepted_per_keo;
-- -- rồi tạo lại reviews_author_insert + profiles_self_update theo bản schema.sql gốc.
