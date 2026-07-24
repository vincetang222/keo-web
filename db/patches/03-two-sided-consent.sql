-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  KÈO — SCHEMA PATCH: thêm bước "Người đồng hành đồng ý cuối"               ║
-- ║                                                                            ║
-- ║  LÝ DO: hiện tại Chủ xị chấp nhận đơn → Kèo tự động 'filled', Người đồng   ║
-- ║  hành không có tiếng nói ở bước cuối. Cần đối xứng với bước "cả hai xác    ║
-- ║  nhận hoàn thành" ở cuối vòng đời — cả hai cùng gật rồi mới ràng buộc.    ║
-- ║                                                                            ║
-- ║  Áp dụng cho CẢ HAI kịch bản:                                              ║
-- ║   • Kèo công khai: Chủ xị chọn từ đơn ứng tuyển                            ║
-- ║   • Kèo mời riêng: Chủ xị mời đích danh                                    ║
-- ║                                                                            ║
-- ║  ⚠️  CHƯA TEST TRÊN POSTGRES THẬT. Thay đổi trigger lõi — bắt buộc chạy    ║
-- ║      trên project TEST trước, test bằng 2 tài khoản thật theo checklist    ║
-- ║      cuối file, mới lên production.                                        ║
-- ║                                                                            ║
-- ║  ⚠️  PHỤ THUỘC UI: patch này ĐỔI Ý NGHĨA nút "Chấp nhận" phía Chủ xị và    ║
-- ║      cần trang mới /loi-moi-cho-xac-nhan cho Người đồng hành. PHẢI ghép    ║
-- ║      UI CÙNG LÚC (xem docs/INTEGRATION-two-sided-consent.md) — nếu chỉ     ║
-- ║      chạy SQL mà không đổi UI, luồng chốt Kèo sẽ đứng ở host_selected.     ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝


-- ═══════════════════════════════════════════════════════════════════════════
--  1. THÊM TRẠNG THÁI TRUNG GIAN vào enum application_status
-- ═══════════════════════════════════════════════════════════════════════════
-- Trạng thái mới 'host_selected' = Chủ xị đã chọn, đang chờ Người đồng hành gật.
-- Ý NGHĨA sau khi patch:
--   pending       — chờ Chủ xị xem
--   host_selected — Chủ xị đã chọn, chờ Người đồng hành đồng ý cuối     [MỚI]
--   accepted      — CẢ HAI đã đồng ý, Kèo chính thức chốt
--   rejected      — bị từ chối (bởi Chủ xị hoặc Người đồng hành)
--   withdrawn     — người ứng tuyển tự rút

alter type application_status add value if not exists 'host_selected' before 'accepted';
-- Postgres yêu cầu ADD VALUE nằm ngoài transaction; nếu chạy qua migration tool,
-- có thể phải tách câu này ra file riêng chạy trước.


-- ═══════════════════════════════════════════════════════════════════════════
--  2. TÁCH TRIGGER on_application_accepted THÀNH HAI NẤC
-- ═══════════════════════════════════════════════════════════════════════════
-- Trigger CŨ: fill Kèo ngay khi status thành 'accepted'.
-- Trigger MỚI:
--   NẤC 1: pending → host_selected  (Chủ xị chọn)
--          • KHÔNG fill Kèo (Kèo vẫn 'open' để Người đồng hành xem lại)
--          • KHÔNG đóng các đơn khác (nhỡ Người đồng hành này từ chối, còn đơn khác)
--          • Gửi thông báo cho Người đồng hành: "Bạn được đề nghị chọn — xem lại và trả lời"
--
--   NẤC 2: host_selected → accepted  (Người đồng hành đồng ý cuối)
--          • Fill Kèo: open_keos.status = 'filled', accepted_application_id = new.id
--          • Đóng các đơn khác của cùng Kèo: pending & host_selected → rejected
--          • Mở kênh chat (conversations)
--          • Gửi thông báo cho Chủ xị: "Người đồng hành đã đồng ý"
--
--   host_selected → rejected  (Người đồng hành từ chối)
--          • KHÔNG fill Kèo, giữ Kèo 'open' để Chủ xị chọn người khác
--          • Gửi thông báo cho Chủ xị: "Người đồng hành đã từ chối — bạn có thể chọn lại"

-- 2a. Trigger chính (thay hoàn toàn on_application_accepted cũ)
create or replace function public.on_application_status_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare host uuid; ktitle text; comp_name text;
begin
  -- NẤC 1: Chủ xị chọn (pending → host_selected)
  if new.status = 'host_selected' and old.status = 'pending' then
    select host_id, title into host, ktitle from public.open_keos where id = new.keo_id;
    insert into public.notifications (user_id, type, title, body, link)
      values (new.companion_id, 'invited',
              'Chủ xị đã chọn bạn — cần bạn đồng ý',
              'Xem lại buổi Kèo "' || ktitle || '" và cho biết bạn có tham gia không.',
              '/loi-moi-cho-xac-nhan');
    return new;
  end if;

  -- NẤC 2a: Người đồng hành đồng ý (host_selected → accepted)
  if new.status = 'accepted' and old.status = 'host_selected' then
    -- fill Kèo
    update public.open_keos
      set status = 'filled', accepted_application_id = new.id, updated_at = now()
      where id = new.keo_id;
    -- đóng mọi đơn khác của cùng Kèo (kể cả pending lẫn host_selected khác)
    update public.keo_applications
      set status = 'rejected'
      where keo_id = new.keo_id and id <> new.id
        and status in ('pending', 'host_selected');
    -- thông báo Chủ xị + mở chat
    select host_id, title into host, ktitle from public.open_keos where id = new.keo_id;
    select full_name into comp_name from public.profiles where id = new.companion_id;
    insert into public.notifications (user_id, type, title, body, link)
      values (host, 'accepted',
              'Người đồng hành đã đồng ý 🎉',
              coalesce(comp_name, 'Người đồng hành') || ' đã đồng ý tham gia "' || ktitle || '"',
              '/quan-ly-keo');
    insert into public.conversations (keo_id, host_id, companion_id)
      values (new.keo_id, host, new.companion_id) on conflict (keo_id) do nothing;
    return new;
  end if;

  -- NẤC 2b: Người đồng hành từ chối lời đề nghị (host_selected → rejected)
  if new.status = 'rejected' and old.status = 'host_selected' then
    select host_id, title into host, ktitle from public.open_keos where id = new.keo_id;
    select full_name into comp_name from public.profiles where id = new.companion_id;
    insert into public.notifications (user_id, type, title, body, link)
      values (host, 'declined',
              'Người đồng hành đã từ chối',
              coalesce(comp_name, 'Người đồng hành') || ' không thể tham gia "' || ktitle || '". Bạn có thể chọn người khác.',
              '/quan-ly-keo');
    return new;
  end if;

  return new;
end $$;

-- Thay trigger cũ
drop trigger if exists on_app_accepted on public.keo_applications;
drop trigger if exists on_app_accepted_extra on public.keo_applications;

create trigger on_app_status_change
  after update of status on public.keo_applications
  for each row execute function public.on_application_status_change();


-- ═══════════════════════════════════════════════════════════════════════════
--  3. RLS: cho Người đồng hành đổi status của đơn mình (chấp nhận/từ chối lời đề nghị)
-- ═══════════════════════════════════════════════════════════════════════════
-- Policy hiện tại 'app_companion_withdraw' cho Người đồng hành đổi status
-- đơn của mình về 'withdrawn'. Cần bổ sung: khi status hiện là 'host_selected',
-- họ được đổi sang 'accepted' hoặc 'rejected' (đồng ý/từ chối lời đề nghị).

-- Tạo policy mới, KHÔNG đụng policy cũ để tránh vỡ luồng withdraw.
create policy "app_companion_respond_to_offer" on public.keo_applications
  for update to authenticated
  using (companion_id = auth.uid())
  with check (
    companion_id = auth.uid()
    and status in ('accepted', 'rejected')
    -- postgres RLS không nhìn được old.status, nên tin cậy trigger để chặn
    -- chuyển state trái phép. Trigger chỉ xử lý host_selected → accepted/rejected.
  );

-- LƯU Ý: RLS with check không so được old.status. Nếu muốn chặt tay, thêm
-- CHECK constraint hoặc trigger BEFORE UPDATE kiểm tra chuyển đổi hợp lệ.
-- Đề xuất trigger BEFORE UPDATE để chặn cứng ở tầng DB:

create or replace function public.check_app_status_transition()
returns trigger language plpgsql as $$
begin
  -- Chỉ áp cho update từ auth user (không cản service role/trigger nội bộ)
  if auth.uid() is null then return new; end if;

  -- Chủ xị: chỉ được đổi pending → host_selected hoặc pending → rejected
  if exists (select 1 from public.open_keos k where k.id = new.keo_id and k.host_id = auth.uid()) then
    if not (
      (old.status = 'pending' and new.status in ('host_selected', 'rejected'))
    ) then
      raise exception 'Chủ xị chỉ được chuyển đơn từ pending sang host_selected hoặc rejected';
    end if;
    return new;
  end if;

  -- Người đồng hành: pending → withdrawn, hoặc host_selected → accepted/rejected
  if new.companion_id = auth.uid() then
    if not (
      (old.status = 'pending' and new.status = 'withdrawn') or
      (old.status = 'host_selected' and new.status in ('accepted', 'rejected'))
    ) then
      raise exception 'Người đồng hành chỉ được rút đơn pending hoặc đồng ý/từ chối lời đề nghị';
    end if;
    return new;
  end if;

  raise exception 'Không có quyền đổi đơn này';
end $$;

drop trigger if exists check_app_transition on public.keo_applications;
create trigger check_app_transition
  before update of status on public.keo_applications
  for each row execute function public.check_app_status_transition();


-- ═══════════════════════════════════════════════════════════════════════════
--  CHECKLIST TEST (bắt buộc trên project TEST trước khi lên production)
-- ═══════════════════════════════════════════════════════════════════════════
-- Test bằng 3 tài khoản: 1 Chủ xị H, 2 Người đồng hành C1 và C2.
--
-- [ ] 1. H tạo 1 Kèo công khai.
-- [ ] 2. C1 ứng tuyển → keo_applications có 1 dòng (H, C1, pending).
-- [ ] 3. C2 ứng tuyển → có 1 dòng nữa (H, C2, pending).
-- [ ] 4. H chọn C1 (đổi status C1 sang 'host_selected'):
--        [ ] Kèo VẪN 'open' (chưa filled)
--        [ ] Đơn C2 vẫn 'pending' (chưa bị đóng)
--        [ ] C1 nhận thông báo 'Chủ xị đã chọn bạn — cần bạn đồng ý'
-- [ ] 5. C1 đồng ý (đổi status của MÌNH sang 'accepted'):
--        [ ] Kèo status = 'filled', accepted_application_id đúng
--        [ ] Đơn C2 bị đóng: status = 'rejected'
--        [ ] H nhận thông báo 'Người đồng hành đã đồng ý'
--        [ ] Có 1 dòng conversations mới
-- [ ] 6. Ở Kèo khác, làm lại tới bước C1 host_selected, rồi C1 TỪ CHỐI (rejected):
--        [ ] Kèo vẫn 'open' — chưa filled
--        [ ] Đơn C2 vẫn 'pending'
--        [ ] H nhận thông báo 'Người đồng hành đã từ chối — có thể chọn người khác'
--        [ ] H chọn tiếp C2 → luồng tiếp tục bình thường
-- [ ] 7. Test tấn công: C1 cố đổi status của MÌNH từ pending sang accepted trực tiếp
--        (bỏ qua bước host_selected) qua API → trigger BEFORE UPDATE phải raise exception.
-- [ ] 8. Test tấn công: H cố đổi status đơn của C1 sang accepted trực tiếp → chặn.


-- ═══════════════════════════════════════════════════════════════════════════
--  ROLLBACK (nếu cần hoàn tác — chú ý: KHÔNG thể xoá value khỏi enum Postgres)
-- ═══════════════════════════════════════════════════════════════════════════
-- drop trigger if exists check_app_transition on public.keo_applications;
-- drop function if exists public.check_app_status_transition();
-- drop policy if exists "app_companion_respond_to_offer" on public.keo_applications;
-- drop trigger if exists on_app_status_change on public.keo_applications;
-- drop function if exists public.on_application_status_change();
-- -- Rồi tạo lại 2 trigger cũ (on_application_accepted + on_application_accepted_extra)
-- -- theo nội dung nguyên bản của schema.sql.
-- -- Value 'host_selected' vẫn còn trong enum — không xoá được, nhưng không sao,
-- -- chỉ cần code không dùng tới nó nữa là được.
