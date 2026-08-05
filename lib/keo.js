// ╔═══════════════════════════════════════════════════════════════════════════╗
// ║  keo.js — LỚP NỀN DÙNG CHUNG cho mọi trang web-app của Kèo                  ║
// ║  Mọi trang chỉ cần: <script src="/vendor/supabase.js"></script>            ║
// ║                     <script src="/lib/keo.js"></script>                    ║
// ║  Thay vì lặp lại createClient/auth/redirect ở từng file (nguyên nhân        ║
// ║  "chắp vá" trước đây), tất cả logic chung gom về đây.                       ║
// ╚═══════════════════════════════════════════════════════════════════════════╝

(function (global) {
  'use strict';

  // ─── Cấu hình: điền 2 giá trị này 1 LẦN DUY NHẤT cho cả web-app ───
  // (Supabase Dashboard → Settings → API). anon key công khai được — bảo mật
  // thật nằm ở Row Level Security trong schema.sql.
  const SUPABASE_URL = 'https://cxfzvprnzydowakkeyci.supabase.co';
  const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN4Znp2cHJuenlkb3dha2tleWNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ4NzU3NDgsImV4cCI6MjEwMDQ1MTc0OH0.EWjNO-q1F2M9mFFZZaqAV5Nzzk99iTvF6lqViD0yOR0';
  

  if (!global.supabase) {
    console.error('[Kèo] Chưa tải vendor/supabase.js trước lib/keo.js');
    return;
  }
  const sb = global.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

  // ─── Hằng số dùng chung ───
  const CITY_LABEL = { hcm: 'TP.HCM', hn: 'Hà Nội', dn: 'Đà Nẵng' };
  const CATEGORY_LABEL = {
    'ca-phe': 'Cà phê', 'an-toi': 'Ăn tối', 'trien-lam': 'Triển lãm',
    'da-ngoai': 'Dã ngoại', 'the-thao': 'Thể thao', 'khac': 'Khác'
  };
  const ROLE_LABEL = { chu_xi: 'Chủ xị', nguoi_dong_hanh: 'Người đồng hành' };

  // ─── Tiện ích ───
  function esc(s) {
    return (s || '').replace(/[&<>"']/g, c =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }
  function formatVND(n) {
    return n == null ? null : n.toLocaleString('vi-VN') + '₫';
  }
  function formatDate(iso) {
    if (!iso) return 'Linh hoạt';
    return new Date(iso).toLocaleString('vi-VN',
      { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
  }
  function toast(msg, type = 'ok') {
    let el = document.getElementById('keoToast');
    if (!el) {
      el = document.createElement('div');
      el.id = 'keoToast';
      el.style.cssText = 'position:fixed;bottom:26px;left:50%;transform:translateX(-50%) translateY(80px);' +
        'padding:12px 24px;border-radius:100px;font-size:13.5px;font-weight:600;opacity:0;' +
        'transition:all .3s;z-index:9999;font-family:"Be Vietnam Pro",sans-serif';
      document.body.appendChild(el);
    }
    el.textContent = msg;
    el.style.background = type === 'err' ? '#E0637A' : '#5CC49A';
    el.style.color = type === 'err' ? '#fff' : '#0A0806';
    requestAnimationFrame(() => {
      el.style.transform = 'translateX(-50%) translateY(0)';
      el.style.opacity = '1';
    });
    clearTimeout(el._t);
    el._t = setTimeout(() => {
      el.style.transform = 'translateX(-50%) translateY(80px)';
      el.style.opacity = '0';
    }, 2600);
  }

  // ─── Xác thực ───
  async function getSession() {
    const { data: { session } } = await sb.auth.getSession();
    return session;
  }
  async function getProfile(userId) {
    const { data, error } = await sb.from('profiles').select('*').eq('id', userId).single();
    if (error) return null;
    return data;
  }

  // Bảo vệ trang: yêu cầu đăng nhập, tuỳ chọn yêu cầu vai trò / xác minh.
  // Trả về { session, profile } nếu hợp lệ; nếu không, tự redirect và trả null.
  async function requireAuth(opts = {}) {
    const session = await getSession();
    if (!session) {
      const next = encodeURIComponent(location.pathname + location.search);
      location.href = '/dang-nhap?tab=login&next=' + next;
      return null;
    }
    const profile = await getProfile(session.user.id);
    if (!profile) {
      location.href = '/dang-nhap?tab=login';
      return null;
    }
    if (opts.role && profile.role !== opts.role) {
      return { session, profile, roleMismatch: true };
    }
    if (opts.requireVerified && !profile.cccd_verified) {
      return { session, profile, needsVerification: true };
    }
    return { session, profile };
  }

  async function signOut() {
    await sb.auth.signOut();
    location.href = '/dang-nhap';
  }

  // ─── Ảnh / Storage ───
  // Upload ảnh vào bucket, đường dẫn LUÔN bắt đầu bằng {userId}/ để khớp policy.
  async function uploadImage(bucket, userId, file, opts = {}) {
    const ext = (file.name.split('.').pop() || 'jpg').toLowerCase();
    const path = `${userId}/${opts.prefix || 'img'}-${Date.now()}.${ext}`;
    const { error } = await sb.storage.from(bucket).upload(path, file, {
      cacheControl: '3600', upsert: !!opts.upsert
    });
    if (error) throw error;
    return path;
  }
  // URL công khai (avatars, portfolio)
  function publicImageUrl(bucket, path) {
    return sb.storage.from(bucket).getPublicUrl(path).data.publicUrl;
  }
  // URL ký tạm cho ảnh PRIVATE (cccd) — hết hạn sau expiresIn giây
  async function signedImageUrl(bucket, path, expiresIn = 300) {
    const { data, error } = await sb.storage.from(bucket).createSignedUrl(path, expiresIn);
    if (error) throw error;
    return data.signedUrl;
  }

  // ─── Attribution: bắt ref + UTM (first-touch), gọi ở trang đăng ký ───
  function captureAttribution() {
    const p = new URLSearchParams(location.search);
    const ref = p.get('ref');
    if (ref && !localStorage.getItem('keo_ref')) localStorage.setItem('keo_ref', ref.toUpperCase());
    const utm = {};
    ['utm_source', 'utm_medium', 'utm_campaign'].forEach(k => {
      if (p.get(k)) utm[k.replace('utm_', '')] = p.get(k);
    });
    if (Object.keys(utm).length && !localStorage.getItem('keo_utm')) {
      localStorage.setItem('keo_utm', JSON.stringify(utm));
    }
  }
  function getAttribution() {
    return {
      ref_code: localStorage.getItem('keo_ref') || null,
      utm: localStorage.getItem('keo_utm') || null
    };
  }
  function clearAttribution() {
    localStorage.removeItem('keo_ref');
    localStorage.removeItem('keo_utm');
  }

  // ─── Thông báo trong app ───
  async function unreadNotifications(userId) {
    const { data } = await sb.from('notifications')
      .select('*').eq('user_id', userId).is('read_at', null)
      .order('created_at', { ascending: false });
    return data || [];
  }
  async function markNotificationRead(id) {
    return sb.from('notifications').update({ read_at: new Date().toISOString() }).eq('id', id);
  }

  // ─── Lưu / bỏ lưu (Kèo yêu thích, theo dõi Người đồng hành) ───
  async function toggleSaved(userId, itemType, itemId) {
    const { data: existing } = await sb.from('saved_items').select('item_id')
      .eq('user_id', userId).eq('item_type', itemType).eq('item_id', itemId).maybeSingle();
    if (existing) {
      await sb.from('saved_items').delete()
        .eq('user_id', userId).eq('item_type', itemType).eq('item_id', itemId);
      return false;
    }
    await sb.from('saved_items').insert({ user_id: userId, item_type: itemType, item_id: itemId });
    return true;
  }

  // ─── Xác nhận hoàn thành buổi Kèo (2 chiều) ───
  async function confirmCompletion(keoId, userId) {
    return sb.from('keo_completions').insert({ keo_id: keoId, confirmed_by: userId });
  }

  // Dịch lỗi Supabase Auth sang tiếng Việt
  function friendlyAuthError(msg) {
    const m = (msg || '').toLowerCase();
    if (m.includes('invalid login credentials')) return 'Email hoặc mật khẩu không đúng.';
    if (m.includes('user already registered')) return 'Email này đã có tài khoản — thử đăng nhập.';
    if (m.includes('password should be at least')) return 'Mật khẩu cần tối thiểu 8 ký tự.';
    if (m.includes('unable to validate email')) return 'Email không hợp lệ.';
    if (m.includes('email not confirmed')) return 'Vui lòng xác nhận email trước khi đăng nhập.';
    if (m.includes('rate limit')) return 'Bạn thao tác quá nhanh — thử lại sau ít phút.';
    return 'Có lỗi: ' + msg;
  }

  // ─── Xuất API công khai ───
  global.Keo = {
    sb,
    // hằng số
    CITY_LABEL, CATEGORY_LABEL, ROLE_LABEL,
    // tiện ích
    esc, formatVND, formatDate, toast,
    // auth
    getSession, getProfile, requireAuth, signOut, friendlyAuthError,
    // ảnh
    uploadImage, publicImageUrl, signedImageUrl,
    // attribution
    captureAttribution, getAttribution, clearAttribution,
    // tính năng marketplace
    unreadNotifications, markNotificationRead, toggleSaved, confirmCompletion,
  };
})(window);
