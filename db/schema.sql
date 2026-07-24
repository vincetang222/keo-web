-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  KÈO — DATABASE SCHEMA (bản hoàn chỉnh, chạy 1 lần trên Supabase mới)       ║
-- ║  Thứ tự: types → tables → indexes → storage → functions → triggers → RLS   ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- Chạy toàn bộ file này trong Supabase SQL Editor (New query → dán → Run).
-- Idempotent ở mức hợp lý: dùng "if not exists" nơi có thể. Nếu chạy lại từ đầu
-- trên project đã có dữ liệu, xem phần "RESET" ở cuối file (đã comment).

-- ═══ 1. EXTENSIONS ═══════════════════════════════════════════════════════════
create extension if not exists "pgcrypto";   -- gen_random_uuid()

-- ═══ 2. ENUM TYPES ═══════════════════════════════════════════════════════════
do $$ begin
  create type user_role as enum ('chu_xi', 'nguoi_dong_hanh');
exception when duplicate_object then null; end $$;

do $$ begin
  create type keo_status as enum ('open', 'filled', 'completed', 'cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type application_status as enum ('pending', 'accepted', 'rejected', 'withdrawn');
exception when duplicate_object then null; end $$;

do $$ begin
  create type verification_status as enum ('none', 'submitted', 'verified', 'rejected');
exception when duplicate_object then null; end $$;

-- ═══ 3. TABLES ═══════════════════════════════════════════════════════════════

-- 3.1 profiles — 1-1 với auth.users (Supabase Auth lo email/mật khẩu/phiên)
create table if not exists public.profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  role              user_role not null default 'chu_xi',
  full_name         text,
  phone             text,
  city              text,                      -- 'hcm' | 'hn' | 'dn'
  bio               text,
  avatar_url        text,                      -- ảnh hồ sơ (bucket công khai)
  -- Xác minh danh tính
  verification      verification_status not null default 'none',
  cccd_verified     boolean not null default false,  -- = (verification = 'verified')
  -- Growth / attribution
  referral_code     text unique,
  referred_by       uuid references public.profiles(id),
  signup_source     text default 'organic',
  signup_utm        jsonb,
  -- Activation & rating
  first_keo_at      timestamptz,
  activated         boolean not null default false,
  rating_avg        numeric(2,1),
  rating_count      int not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- 3.2 companion_details — thông tin riêng của Người đồng hành (1-1, optional)
create table if not exists public.companion_details (
  profile_id        uuid primary key references public.profiles(id) on delete cascade,
  headline          text,                      -- "Hướng dẫn viên cà phê specialty"
  expertise         text[],                    -- ['ca-phe','nhiep-anh']
  base_rate         int,                       -- mức giá mặc định / buổi (VND)
  available         boolean not null default true,
  updated_at        timestamptz not null default now()
);

-- 3.3 portfolio_images — ảnh hồ sơ công khai của Người đồng hành
create table if not exists public.portfolio_images (
  id                uuid primary key default gen_random_uuid(),
  profile_id        uuid not null references public.profiles(id) on delete cascade,
  storage_path      text not null,             -- đường dẫn trong bucket 'portfolio'
  caption           text,
  sort_order        int not null default 0,
  created_at        timestamptz not null default now()
);

-- 3.4 verification_documents — XÁC MINH CCCD (mô hình 3 TẦNG dữ liệu)
-- Giải bài toán: cần đối chiếu lại thông tin sau này mà KHÔNG bắt user show CCCD
-- lại, đồng thời không giữ ảnh nhạy cảm vô thời hạn. 3 tầng vòng đời khác nhau:
--   TẦNG 1 (giữ lâu, mã hoá) — dữ liệu trích xuất: hash số CCCD + 4 số cuối hiển thị.
--   TẦNG 2 (có hạn) — ảnh gốc trong bucket private, tự xoá sau image_expires_at.
--   TẦNG 3 (giữ lâu, không ảnh) — nhật ký xác minh: xem bảng verification_audit.
create table if not exists public.verification_documents (
  id                uuid primary key default gen_random_uuid(),
  profile_id        uuid not null references public.profiles(id) on delete cascade,
  doc_type          text not null default 'cccd',
  status            verification_status not null default 'submitted',
  -- TẦNG 1: dữ liệu trích xuất (giữ lâu dài để đối chiếu)
  cccd_hash         text,                      -- băm SHA-256 của số CCCD (đối chiếu trùng/khớp)
  cccd_last4        text,                      -- 4 số cuối hiển thị: ••••1234
  full_name_snapshot text,                     -- tên trên CCCD lúc xác minh
  -- TẦNG 2: ảnh gốc (có thời hạn)
  storage_path      text,                      -- đường dẫn bucket PRIVATE 'cccd'; NULL sau khi xoá
  image_expires_at  timestamptz,               -- mốc tự xoá ảnh (VD +90 ngày sau verified)
  image_deleted_at  timestamptz,               -- đã xoá ảnh lúc nào (giữ lại để biết)
  -- Meta duyệt
  reviewed_by       uuid references public.profiles(id),
  reviewed_at       timestamptz,
  reject_reason     text,
  created_at        timestamptz not null default now()
);

-- 3.4b verification_audit — TẦNG 3: nhật ký xác minh (giữ lâu dài, KHÔNG chứa ảnh)
-- Bằng chứng "đã từng xác minh hợp lệ" tồn tại cả sau khi ảnh bị xoá.
create table if not exists public.verification_audit (
  id                bigint generated always as identity primary key,
  profile_id        uuid not null references public.profiles(id) on delete cascade,
  document_id       uuid references public.verification_documents(id) on delete set null,
  action            text not null,             -- 'submitted'|'verified'|'rejected'|'image_deleted'|'reverify_requested'
  actor_id          uuid references public.profiles(id), -- ai thực hiện (null = hệ thống)
  note              text,
  created_at        timestamptz not null default now()
);

-- 3.5 open_keos — Kèo mở do Chủ xị đăng
create table if not exists public.open_keos (
  id                uuid primary key default gen_random_uuid(),
  host_id           uuid not null references public.profiles(id) on delete cascade,
  title             text not null,
  description       text,
  city              text not null,
  category          text,                      -- 'ca-phe' | 'an-toi' | 'trien-lam' ...
  scheduled_at      timestamptz,               -- null = linh hoạt, thoả thuận sau
  fixed_fee         int,                       -- null = để Người đồng hành đề xuất giá
  visibility        text not null default 'public',  -- 'public' | 'private'
  status            keo_status not null default 'open',
  accepted_application_id uuid,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- 3.6 open_keo_invites — mời riêng (cho Kèo visibility='private')
create table if not exists public.open_keo_invites (
  keo_id            uuid not null references public.open_keos(id) on delete cascade,
  companion_id      uuid not null references public.profiles(id) on delete cascade,
  primary key (keo_id, companion_id)
);

-- 3.7 keo_applications — đơn ứng tuyển (queue)
create table if not exists public.keo_applications (
  id                uuid primary key default gen_random_uuid(),
  keo_id            uuid not null references public.open_keos(id) on delete cascade,
  companion_id      uuid not null references public.profiles(id) on delete cascade,
  message           text not null,
  proposed_fee      int,                       -- optional, chỉ khi Kèo để ngỏ giá
  status            application_status not null default 'pending',
  created_at        timestamptz not null default now(),
  unique (keo_id, companion_id)
);

-- 3.8 reviews — đánh giá sau buổi Kèo (2 chiều)
create table if not exists public.reviews (
  id                uuid primary key default gen_random_uuid(),
  keo_id            uuid not null references public.open_keos(id) on delete cascade,
  reviewer_id       uuid not null references public.profiles(id) on delete cascade,
  reviewee_id       uuid not null references public.profiles(id) on delete cascade,
  rating            int not null check (rating between 1 and 5),
  comment           text,
  created_at        timestamptz not null default now(),
  unique (keo_id, reviewer_id)                 -- mỗi người đánh giá 1 lần / buổi
);

-- 3.9 referral_rewards — thưởng giới thiệu (ghi nhận, duyệt thủ công giai đoạn đầu)
create table if not exists public.referral_rewards (
  id                bigint generated always as identity primary key,
  referrer_id       uuid not null references public.profiles(id),
  referred_id       uuid not null references public.profiles(id),
  status            text not null default 'pending',  -- 'pending'|'approved'|'paid'
  created_at        timestamptz not null default now(),
  unique (referred_id)
);

-- 3.10 conversations + messages — nhắn tin trong app (sau khi Kèo được chốt)
-- LƯU Ý disintermediation: chỉ mở chat KHI đơn đã được chấp nhận (2 bên đã cam
-- kết qua nền tảng) — không cho nhắn tự do từ khi chưa chốt, tránh trao đổi info
-- rồi gặp ngoài nền tảng né phí.
create table if not exists public.conversations (
  id                uuid primary key default gen_random_uuid(),
  keo_id            uuid not null references public.open_keos(id) on delete cascade,
  host_id           uuid not null references public.profiles(id) on delete cascade,
  companion_id      uuid not null references public.profiles(id) on delete cascade,
  created_at        timestamptz not null default now(),
  unique (keo_id)
);
create table if not exists public.messages (
  id                uuid primary key default gen_random_uuid(),
  conversation_id   uuid not null references public.conversations(id) on delete cascade,
  sender_id         uuid not null references public.profiles(id) on delete cascade,
  body              text not null,
  read_at           timestamptz,
  created_at        timestamptz not null default now()
);

-- 3.11 notifications — thông báo trong app
create table if not exists public.notifications (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.profiles(id) on delete cascade,
  type              text not null,             -- 'application'|'accepted'|'message'|'review'|'dispute'
  title             text not null,
  body              text,
  link              text,                      -- đường dẫn liên quan (VD /quan-ly-keo)
  read_at           timestamptz,
  created_at        timestamptz not null default now()
);

-- 3.12 keo_completions — xác nhận hoàn thành buổi Kèo (2 chiều)
-- Kèo chỉ chuyển 'completed' khi CẢ HAI xác nhận đã gặp → mở luồng đánh giá + thưởng.
create table if not exists public.keo_completions (
  keo_id            uuid not null references public.open_keos(id) on delete cascade,
  confirmed_by      uuid not null references public.profiles(id) on delete cascade,
  confirmed_at      timestamptz not null default now(),
  primary key (keo_id, confirmed_by)
);

-- 3.13 disputes — báo cáo tranh chấp / sự cố sau buổi Kèo
create table if not exists public.disputes (
  id                uuid primary key default gen_random_uuid(),
  keo_id            uuid not null references public.open_keos(id) on delete cascade,
  reporter_id       uuid not null references public.profiles(id) on delete cascade,
  reason            text not null,             -- 'no_show'|'behaviour'|'payment'|'safety'|'other'
  detail            text,
  status            text not null default 'open',  -- 'open'|'reviewing'|'resolved'|'dismissed'
  resolved_by       uuid references public.profiles(id),
  resolution_note   text,
  created_at        timestamptz not null default now(),
  resolved_at       timestamptz
);

-- 3.14 saved_items — lưu Kèo / theo dõi Người đồng hành yêu thích
create table if not exists public.saved_items (
  user_id           uuid not null references public.profiles(id) on delete cascade,
  item_type         text not null,             -- 'keo' | 'companion'
  item_id           uuid not null,
  created_at        timestamptz not null default now(),
  primary key (user_id, item_type, item_id)
);

-- 3.15 system_heartbeat — cho cronjob giữ Supabase free tier khỏi bị pause
create table if not exists public.system_heartbeat (
  id                bigint generated always as identity primary key,
  pinged_at         timestamptz not null default now()
);

-- ═══ 4. INDEXES ══════════════════════════════════════════════════════════════
create index if not exists idx_keos_discovery on public.open_keos (status, city, visibility);
create index if not exists idx_keos_host on public.open_keos (host_id);
create index if not exists idx_apps_queue on public.keo_applications (keo_id, status);
create index if not exists idx_apps_companion on public.keo_applications (companion_id);
create index if not exists idx_portfolio_profile on public.portfolio_images (profile_id);
create index if not exists idx_reviews_reviewee on public.reviews (reviewee_id);
create index if not exists idx_messages_convo on public.messages (conversation_id, created_at);
create index if not exists idx_notif_user on public.notifications (user_id, read_at);
create index if not exists idx_disputes_keo on public.disputes (keo_id);
create index if not exists idx_verif_profile on public.verification_documents (profile_id);
create index if not exists idx_verif_expiry on public.verification_documents (image_expires_at) where storage_path is not null;

-- ═══ 5. STORAGE BUCKETS ══════════════════════════════════════════════════════
-- 'portfolio' và 'avatars': công khai (ai cũng xem ảnh hồ sơ được).
-- 'cccd': PRIVATE tuyệt đối — chỉ chủ + admin truy cập qua signed URL.
insert into storage.buckets (id, name, public)
  values ('avatars', 'avatars', true) on conflict (id) do nothing;
insert into storage.buckets (id, name, public)
  values ('portfolio', 'portfolio', true) on conflict (id) do nothing;
insert into storage.buckets (id, name, public)
  values ('cccd', 'cccd', false) on conflict (id) do nothing;

-- ═══ 6. HELPER FUNCTIONS ═════════════════════════════════════════════════════

-- 6.1 Kiểm tra người đang đăng nhập đã xác minh CCCD (Người đồng hành)
create or replace function public.is_verified_companion()
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'nguoi_dong_hanh' and cccd_verified = true
  );
$$;

-- 6.2 Sinh mã giới thiệu (bỏ ký tự dễ nhầm 0/O/1/I)
create or replace function public.gen_referral_code()
returns text language plpgsql as $$
declare
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  result text := 'KEO';
  i int;
begin
  for i in 1..6 loop
    result := result || substr(chars, floor(random()*length(chars)+1)::int, 1);
  end loop;
  return result;
end $$;

-- ═══ 7. TRIGGERS ═════════════════════════════════════════════════════════════

-- 7.1 Tạo hồ sơ + mã giới thiệu tự động khi có tài khoản mới
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  new_code text;
  ref_by uuid;
begin
  loop
    new_code := public.gen_referral_code();
    exit when not exists (select 1 from public.profiles where referral_code = new_code);
  end loop;

  if new.raw_user_meta_data->>'ref_code' is not null then
    select id into ref_by from public.profiles
      where referral_code = upper(new.raw_user_meta_data->>'ref_code');
  end if;

  insert into public.profiles (id, full_name, role, referral_code, referred_by, signup_source, signup_utm)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    coalesce((new.raw_user_meta_data->>'role')::user_role, 'chu_xi'),
    new_code, ref_by,
    coalesce(new.raw_user_meta_data->>'signup_source', 'organic'),
    (new.raw_user_meta_data->>'signup_utm')::jsonb
  );
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 7.2 Khi chấp nhận 1 đơn → đóng Kèo + tự từ chối đơn còn lại
create or replace function public.on_application_accepted()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'accepted' and old.status = 'pending' then
    update public.open_keos
      set status = 'filled', accepted_application_id = new.id, updated_at = now()
      where id = new.keo_id;
    update public.keo_applications
      set status = 'rejected'
      where keo_id = new.keo_id and id <> new.id and status = 'pending';
  end if;
  return new;
end $$;

drop trigger if exists on_app_accepted on public.keo_applications;
create trigger on_app_accepted
  after update on public.keo_applications
  for each row execute function public.on_application_accepted();

-- 7.3 Khi buổi Kèo hoàn thành (first_keo_at set) → ghi nhận referral
create or replace function public.on_user_activated()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.first_keo_at is not null and old.first_keo_at is null then
    new.activated := true;
    if new.referred_by is not null then
      insert into public.referral_rewards (referrer_id, referred_id)
      values (new.referred_by, new.id) on conflict (referred_id) do nothing;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists on_profile_activated on public.profiles;
create trigger on_profile_activated
  before update on public.profiles
  for each row execute function public.on_user_activated();

-- 7.4 Khi có review mới → cập nhật rating trung bình của người được đánh giá
create or replace function public.on_review_added()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.profiles p set
    rating_count = (select count(*) from public.reviews where reviewee_id = new.reviewee_id),
    rating_avg = (select round(avg(rating)::numeric, 1) from public.reviews where reviewee_id = new.reviewee_id)
  where p.id = new.reviewee_id;
  return new;
end $$;

drop trigger if exists on_review_insert on public.reviews;
create trigger on_review_insert
  after insert on public.reviews
  for each row execute function public.on_review_added();

-- 7.5 Khi document xác minh được duyệt → cập nhật profile
create or replace function public.on_verification_reviewed()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'verified' and old.status <> 'verified' then
    update public.profiles set verification = 'verified', cccd_verified = true, updated_at = now()
      where id = new.profile_id;
    -- Đặt hạn tự xoá ẢNH gốc (tầng 2) sau 90 ngày; dữ liệu trích xuất (tầng 1) giữ lại
    new.image_expires_at := now() + interval '90 days';
    -- Ghi nhật ký (tầng 3)
    insert into public.verification_audit (profile_id, document_id, action, actor_id)
      values (new.profile_id, new.id, 'verified', new.reviewed_by);
  elsif new.status = 'rejected' and old.status <> 'rejected' then
    update public.profiles set verification = 'rejected' where id = new.profile_id;
    insert into public.verification_audit (profile_id, document_id, action, actor_id, note)
      values (new.profile_id, new.id, 'rejected', new.reviewed_by, new.reject_reason);
  end if;
  return new;
end $$;

drop trigger if exists on_verif_reviewed on public.verification_documents;
create trigger on_verif_reviewed
  before update on public.verification_documents
  for each row execute function public.on_verification_reviewed();

-- 7.6 Tự tạo thông báo khi có đơn ứng tuyển mới (báo Chủ xị)
create or replace function public.notify_new_application()
returns trigger language plpgsql security definer set search_path = public as $$
declare host uuid; ktitle text;
begin
  select host_id, title into host, ktitle from public.open_keos where id = new.keo_id;
  insert into public.notifications (user_id, type, title, body, link)
    values (host, 'application', 'Có đơn ứng tuyển mới', 'Một Người đồng hành vừa ứng tuyển "' || ktitle || '"', '/quan-ly-keo');
  return new;
end $$;
drop trigger if exists on_new_application on public.keo_applications;
create trigger on_new_application
  after insert on public.keo_applications
  for each row execute function public.notify_new_application();

-- 7.7 Khi đơn được chấp nhận: báo Người đồng hành + mở conversation (chat)
create or replace function public.on_application_accepted_extra()
returns trigger language plpgsql security definer set search_path = public as $$
declare host uuid; ktitle text;
begin
  if new.status = 'accepted' and old.status = 'pending' then
    select host_id, title into host, ktitle from public.open_keos where id = new.keo_id;
    insert into public.notifications (user_id, type, title, body, link)
      values (new.companion_id, 'accepted', 'Đơn của bạn được chấp nhận 🎉', 'Chủ xị đã chọn bạn cho "' || ktitle || '"', '/tai-khoan');
    -- Mở kênh chat giữa 2 bên (chỉ khi đã chốt — chống disintermediation)
    insert into public.conversations (keo_id, host_id, companion_id)
      values (new.keo_id, host, new.companion_id) on conflict (keo_id) do nothing;
  end if;
  return new;
end $$;
drop trigger if exists on_app_accepted_extra on public.keo_applications;
create trigger on_app_accepted_extra
  after update on public.keo_applications
  for each row execute function public.on_application_accepted_extra();

-- 7.8 Khi cả 2 bên xác nhận hoàn thành → Kèo thành 'completed' + set first_keo_at
create or replace function public.on_completion_confirmed()
returns trigger language plpgsql security definer set search_path = public as $$
declare cnt int; hid uuid; cid uuid;
begin
  select count(*) into cnt from public.keo_completions where keo_id = new.keo_id;
  if cnt >= 2 then
    update public.open_keos set status = 'completed', updated_at = now() where id = new.keo_id;
    select host_id into hid from public.open_keos where id = new.keo_id;
    select companion_id into cid from public.keo_applications
      where keo_id = new.keo_id and status = 'accepted' limit 1;
    -- set first_keo_at cho cả 2 nếu chưa có (kích hoạt referral + activation)
    update public.profiles set first_keo_at = now() where id in (hid, cid) and first_keo_at is null;
  end if;
  return new;
end $$;
drop trigger if exists on_completion on public.keo_completions;
create trigger on_completion
  after insert on public.keo_completions
  for each row execute function public.on_completion_confirmed();

-- ═══ 8. VIEWS ════════════════════════════════════════════════════════════════
create or replace view public.keo_application_counts as
  select keo_id,
    count(*) filter (where status = 'pending') as pending_count,
    count(*) as total_count
  from public.keo_applications group by keo_id;

create or replace view public.my_referral_stats as
  select referrer_id,
    count(*) filter (where status in ('approved','paid')) as successful_referrals,
    count(*) as total_referrals
  from public.referral_rewards group by referrer_id;

-- ═══ 9. ROW LEVEL SECURITY ═══════════════════════════════════════════════════
-- Bật RLS cho MỌI bảng có dữ liệu người dùng (nếu quên = lỗ hổng nghiêm trọng).
alter table public.profiles              enable row level security;
alter table public.companion_details     enable row level security;
alter table public.portfolio_images      enable row level security;
alter table public.verification_documents enable row level security;
alter table public.open_keos             enable row level security;
alter table public.open_keo_invites      enable row level security;
alter table public.keo_applications      enable row level security;
alter table public.reviews               enable row level security;
alter table public.referral_rewards      enable row level security;
alter table public.verification_audit    enable row level security;
alter table public.conversations         enable row level security;
alter table public.messages              enable row level security;
alter table public.notifications         enable row level security;
alter table public.keo_completions       enable row level security;
alter table public.disputes              enable row level security;
alter table public.saved_items           enable row level security;
alter table public.system_heartbeat      enable row level security;

-- ── profiles ──
create policy "profiles_public_read"   on public.profiles for select using (true);
create policy "profiles_self_insert"   on public.profiles for insert with check (auth.uid() = id);
create policy "profiles_self_update"   on public.profiles for update using (auth.uid() = id)
  with check (
    auth.uid() = id
    -- Chặn user tự set cccd_verified / verification / rating
    and cccd_verified = (select cccd_verified from public.profiles where id = auth.uid())
    and rating_avg is not distinct from (select rating_avg from public.profiles where id = auth.uid())
  );

-- ── companion_details ──
create policy "compdet_public_read" on public.companion_details for select using (true);
create policy "compdet_self_all"    on public.companion_details for all
  using (auth.uid() = profile_id) with check (auth.uid() = profile_id);

-- ── portfolio_images (ảnh công khai) ──
create policy "portfolio_public_read" on public.portfolio_images for select using (true);
create policy "portfolio_self_all"    on public.portfolio_images for all
  using (auth.uid() = profile_id) with check (auth.uid() = profile_id);

-- ── verification_documents (NHẠY CẢM) — chỉ chủ xem/tạo, KHÔNG ai khác ──
create policy "verifdoc_self_read"   on public.verification_documents for select
  using (auth.uid() = profile_id);
create policy "verifdoc_self_insert" on public.verification_documents for insert
  with check (auth.uid() = profile_id);
-- Không có policy update/delete cho user thường → chỉ service role (admin) duyệt được.

-- ── open_keos ──
create policy "keos_host_read"   on public.open_keos for select using (auth.uid() = host_id);
create policy "keos_host_insert" on public.open_keos for insert with check (auth.uid() = host_id);
create policy "keos_host_update" on public.open_keos for update using (auth.uid() = host_id);
create policy "keos_public_discover" on public.open_keos for select
  using (status = 'open' and visibility = 'public' and public.is_verified_companion());
create policy "keos_private_invited" on public.open_keos for select
  using (visibility = 'private'
    and exists (select 1 from public.open_keo_invites i where i.keo_id = id and i.companion_id = auth.uid()));

-- ── open_keo_invites ──
create policy "invites_host_all" on public.open_keo_invites for all
  using (exists (select 1 from public.open_keos k where k.id = keo_id and k.host_id = auth.uid()));
create policy "invites_companion_read" on public.open_keo_invites for select
  using (companion_id = auth.uid());

-- ── keo_applications (queue) ──
create policy "apps_companion_insert" on public.keo_applications for insert
  with check (
    companion_id = auth.uid() and public.is_verified_companion()
    and exists (
      select 1 from public.open_keos k
      where k.id = keo_id and k.status = 'open'
        and ( k.visibility = 'public'
              or exists (select 1 from public.open_keo_invites i where i.keo_id = k.id and i.companion_id = auth.uid()))
    )
  );
create policy "apps_companion_read"   on public.keo_applications for select using (companion_id = auth.uid());
create policy "apps_companion_withdraw" on public.keo_applications for update
  using (companion_id = auth.uid()) with check (companion_id = auth.uid() and status = 'withdrawn');
create policy "apps_host_read"   on public.keo_applications for select
  using (exists (select 1 from public.open_keos k where k.id = keo_id and k.host_id = auth.uid()));
create policy "apps_host_decide" on public.keo_applications for update
  using (exists (select 1 from public.open_keos k where k.id = keo_id and k.host_id = auth.uid()))
  with check (status in ('accepted', 'rejected'));

-- ── reviews ──
create policy "reviews_public_read" on public.reviews for select using (true);
create policy "reviews_author_insert" on public.reviews for insert
  with check (auth.uid() = reviewer_id and exists (
    select 1 from public.open_keos k
    where k.id = keo_id and k.status in ('filled','completed')
      and (k.host_id = auth.uid() or exists (
        select 1 from public.keo_applications a
        where a.keo_id = k.id and a.companion_id = auth.uid() and a.status = 'accepted'))
  ));

-- ── referral_rewards ──
create policy "rewards_self_read" on public.referral_rewards for select using (auth.uid() = referrer_id);

-- ── verification_audit ── (chủ xem nhật ký của mình; ghi qua trigger/service role)
create policy "audit_self_read" on public.verification_audit for select using (auth.uid() = profile_id);

-- ── conversations ── (chỉ 2 bên trong cuộc trò chuyện)
create policy "convo_participants_read" on public.conversations for select
  using (auth.uid() = host_id or auth.uid() = companion_id);

-- ── messages ── (chỉ người trong conversation đọc/gửi; không sửa/xoá tin đã gửi)
create policy "msg_participants_read" on public.messages for select
  using (exists (select 1 from public.conversations c where c.id = conversation_id
    and (c.host_id = auth.uid() or c.companion_id = auth.uid())));
create policy "msg_participants_send" on public.messages for insert
  with check (sender_id = auth.uid() and exists (
    select 1 from public.conversations c where c.id = conversation_id
      and (c.host_id = auth.uid() or c.companion_id = auth.uid())));
create policy "msg_mark_read" on public.messages for update
  using (exists (select 1 from public.conversations c where c.id = conversation_id
    and (c.host_id = auth.uid() or c.companion_id = auth.uid())))
  with check (true);  -- chỉ dùng để set read_at

-- ── notifications ── (chỉ chủ đọc + đánh dấu đã đọc)
create policy "notif_self_read" on public.notifications for select using (auth.uid() = user_id);
create policy "notif_self_update" on public.notifications for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── keo_completions ── (chỉ 2 bên của Kèo xác nhận)
create policy "completion_read" on public.keo_completions for select
  using (auth.uid() = confirmed_by or exists (
    select 1 from public.open_keos k where k.id = keo_id and k.host_id = auth.uid()));
create policy "completion_confirm" on public.keo_completions for insert
  with check (confirmed_by = auth.uid() and exists (
    select 1 from public.open_keos k where k.id = keo_id
      and (k.host_id = auth.uid() or exists (
        select 1 from public.keo_applications a where a.keo_id = k.id
          and a.companion_id = auth.uid() and a.status = 'accepted'))));

-- ── disputes ── (người báo cáo + người liên quan xem; chỉ 2 bên của Kèo tạo)
create policy "dispute_reporter_read" on public.disputes for select
  using (auth.uid() = reporter_id or exists (
    select 1 from public.open_keos k where k.id = keo_id and k.host_id = auth.uid()));
create policy "dispute_create" on public.disputes for insert
  with check (reporter_id = auth.uid() and exists (
    select 1 from public.open_keos k where k.id = keo_id
      and (k.host_id = auth.uid() or exists (
        select 1 from public.keo_applications a where a.keo_id = k.id
          and a.companion_id = auth.uid() and a.status = 'accepted'))));

-- ── saved_items ── (chỉ chủ quản lý mục đã lưu)
create policy "saved_self_all" on public.saved_items for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── system_heartbeat ── (không policy nào → chỉ service role ghi được)

-- ═══ 10. STORAGE POLICIES ════════════════════════════════════════════════════
-- avatars + portfolio (công khai đọc, chủ tự upload vào thư mục theo user id)
create policy "avatars_public_read" on storage.objects for select
  using (bucket_id = 'avatars');
create policy "avatars_owner_write" on storage.objects for insert
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars_owner_update" on storage.objects for update
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "portfolio_public_read" on storage.objects for select
  using (bucket_id = 'portfolio');
create policy "portfolio_owner_write" on storage.objects for insert
  with check (bucket_id = 'portfolio' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "portfolio_owner_delete" on storage.objects for delete
  using (bucket_id = 'portfolio' and (storage.foldername(name))[1] = auth.uid()::text);

-- cccd (PRIVATE): chỉ chủ upload + đọc file của chính mình; admin dùng service role.
create policy "cccd_owner_read" on storage.objects for select
  using (bucket_id = 'cccd' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "cccd_owner_write" on storage.objects for insert
  with check (bucket_id = 'cccd' and (storage.foldername(name))[1] = auth.uid()::text);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  RESET (chỉ dùng khi cần chạy lại từ đầu trên project TEST — bỏ comment):   ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- drop view if exists public.keo_application_counts, public.my_referral_stats;
-- drop table if exists public.saved_items, public.disputes, public.keo_completions,
--   public.notifications, public.messages, public.conversations, public.verification_audit,
--   public.reviews, public.keo_applications, public.open_keo_invites,
--   public.open_keos, public.verification_documents, public.portfolio_images,
--   public.companion_details, public.referral_rewards, public.system_heartbeat,
--   public.profiles cascade;
-- drop type if exists user_role, keo_status, application_status, verification_status;
