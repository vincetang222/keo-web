/**
 * cookie-consent.js — Banner xin đồng ý cookie cho keo.social
 * ─────────────────────────────────────────────────────────────────────────
 * Dùng chung cho MỌI trang — chỉ cần thêm 1 dòng trước </body>:
 *   <script src="/cookie-consent.js"></script>
 *
 * Tuân thủ:
 * - Nghị định 13/2023/NĐ-CP: không tự bật cookie không thiết yếu khi chưa
 *   có đồng ý, "im lặng không phải là đồng ý" (phải bấm nút, không có lựa
 *   chọn nào được tick sẵn).
 * - Luật Bảo vệ dữ liệu cá nhân 91/2025/QH15, Điều 28: phải có nút "Từ chối"
 *   dễ thấy ngang hàng với nút "Chấp nhận" — không được chỉ có accept-only.
 *
 * Cách dùng cho script khác (VD sau này thêm Google Analytics):
 *   if (window.KeoConsent.has('analytics')) { // load GA ở đây }
 *   window.addEventListener('keo-consent-updated', e => {
 *     if (e.detail.analytics) { // load GA ngay khi user vừa đồng ý }
 *   });
 */
(function(){
  'use strict';

  const COOKIE_NAME = 'keo_consent';
  const COOKIE_DAYS = 365;
  const POLICY_VERSION = 1; // tăng số này khi đổi chính sách cookie → banner sẽ tự hiện lại cho user cũ
  const CONSENT_LOG_URL = 'https://keo-sport-worker.keo-social.workers.dev/consent'; // đổi nếu domain worker khác

  // ─── Đọc/ghi cookie phía client (để enforce lựa chọn ngay, không cần chờ server) ───
  function getCookie(name){
    const m = document.cookie.match(new RegExp('(?:^|; )'+name+'=([^;]*)'));
    return m ? decodeURIComponent(m[1]) : null;
  }
  function setCookie(name, value, days){
    const d = new Date();
    d.setTime(d.getTime() + days*24*60*60*1000);
    document.cookie = `${name}=${encodeURIComponent(value)}; expires=${d.toUTCString()}; path=/; SameSite=Lax; Secure`;
  }

  function readConsent(){
    const raw = getCookie(COOKIE_NAME);
    if(!raw) return null;
    try{
      const data = JSON.parse(raw);
      if(data.v !== POLICY_VERSION) return null; // chính sách đã đổi version → coi như chưa đồng ý, hỏi lại
      return data;
    }catch(e){ return null; }
  }

  function writeConsent(choice){
    // choice: {analytics: bool, marketing: bool}
    const data = {
      necessary: true, // luôn bật, không thể tắt
      analytics: !!choice.analytics,
      marketing: !!choice.marketing,
      v: POLICY_VERSION,
      t: new Date().toISOString(),
    };
    setCookie(COOKIE_NAME, JSON.stringify(data), COOKIE_DAYS);

    // Log lên server để có bằng chứng tuân thủ — KHÔNG chặn UI nếu lỗi/chậm mạng.
    // Không gửi kèm định danh cá nhân nào (không IP, không user id) — chỉ ghi lựa chọn + thời điểm.
    fetch(CONSENT_LOG_URL, {
      method: 'POST',
      headers: {'Content-Type':'application/json'},
      body: JSON.stringify({ analytics: data.analytics, marketing: data.marketing, timestamp: data.t, policyVersion: POLICY_VERSION }),
    }).then(r=>r.json()).then(res=>{
      if(res && res.consentId) data.id = res.consentId; // lưu lại id để user có thể tự tra cứu bằng chứng đồng ý của mình nếu cần
      setCookie(COOKIE_NAME, JSON.stringify(data), COOKIE_DAYS);
    }).catch(()=>{ /* im lặng bỏ qua — không được để lỗi mạng chặn trải nghiệm người dùng */ });

    window.dispatchEvent(new CustomEvent('keo-consent-updated', {detail: data}));
    return data;
  }

  // ─── API công khai cho các script khác dùng (VD Google Analytics sau này) ───
  window.KeoConsent = {
    get(){ return readConsent(); },
    has(category){ const c = readConsent(); return !!(c && c[category]); },
    reopen(){ showBanner(true); },
  };

  // ─── Giao diện ───
  let styleInjected = false;
  function injectStyle(){
    if(styleInjected) return; styleInjected = true;
    const css = `
    .kc-wrap{position:fixed;left:0;right:0;bottom:0;z-index:9999;display:flex;justify-content:center;padding:16px;pointer-events:none;font-family:'Be Vietnam Pro',-apple-system,sans-serif}
    .kc-card{pointer-events:auto;max-width:640px;width:100%;background:linear-gradient(165deg,#26191F 0%,#17111A 100%);border-radius:20px;padding:20px 22px;box-shadow:0 20px 50px rgba(0,0,0,.4),inset 0 1px 0 rgba(255,255,255,.06);transform:translateY(140%);transition:transform .45s cubic-bezier(.2,.9,.25,1);border:1px solid rgba(255,255,255,.08)}
    .kc-wrap.kc-show .kc-card{transform:translateY(0)}
    .kc-head{display:flex;align-items:center;gap:9px;margin-bottom:8px}
    .kc-icon{font-size:18px}
    .kc-title{font-family:'Playfair Display',serif;font-size:16px;font-weight:700;color:#F5EFE6}
    .kc-body{font-size:12.5px;line-height:1.6;color:rgba(245,239,230,.72);margin-bottom:14px}
    .kc-body a{color:#E8A22B;text-decoration:underline}
    .kc-btns{display:flex;gap:8px;flex-wrap:wrap}
    .kc-btn{font-family:inherit;font-size:12.5px;font-weight:700;padding:10px 16px;border-radius:100px;cursor:pointer;border:1px solid rgba(255,255,255,.14);background:rgba(255,255,255,.06);color:#F5EFE6;transition:background .15s,transform .15s}
    .kc-btn:hover{background:rgba(255,255,255,.12);transform:translateY(-1px)}
    .kc-btn.kc-primary{background:linear-gradient(135deg,#E8A22B,#D65F35,#D14060);border:none;color:#1A1006;flex:1;min-width:150px;text-align:center}
    .kc-btn.kc-primary:hover{filter:brightness(1.08)}
    .kc-prefs{margin-top:14px;padding-top:14px;border-top:1px solid rgba(255,255,255,.08);display:none;flex-direction:column;gap:10px}
    .kc-prefs.kc-open{display:flex}
    .kc-row{display:flex;align-items:center;justify-content:space-between;gap:12px}
    .kc-row-text{flex:1}
    .kc-row-title{font-size:12.5px;font-weight:700;color:#F5EFE6;margin-bottom:2px}
    .kc-row-desc{font-size:11px;color:rgba(245,239,230,.55);line-height:1.5}
    .kc-toggle{position:relative;width:38px;height:22px;flex-shrink:0}
    .kc-toggle input{opacity:0;width:0;height:0}
    .kc-slider{position:absolute;inset:0;background:rgba(255,255,255,.15);border-radius:100px;cursor:pointer;transition:background .2s}
    .kc-slider::before{content:'';position:absolute;width:16px;height:16px;left:3px;top:3px;background:#fff;border-radius:50%;transition:transform .2s}
    .kc-toggle input:checked + .kc-slider{background:linear-gradient(135deg,#E8A22B,#D65F35)}
    .kc-toggle input:checked + .kc-slider::before{transform:translateX(16px)}
    .kc-toggle input:disabled + .kc-slider{opacity:.5;cursor:not-allowed}
    .kc-save{margin-top:4px}
    .kc-reopen{position:fixed;left:16px;bottom:16px;z-index:9998;width:42px;height:42px;border-radius:50%;background:#17111A;border:1px solid rgba(255,255,255,.14);color:#F5EFE6;font-size:18px;cursor:pointer;display:none;align-items:center;justify-content:center;box-shadow:0 6px 18px rgba(0,0,0,.35)}
    .kc-reopen.kc-visible{display:flex}
    @media(max-width:480px){.kc-btns{flex-direction:column}.kc-btn.kc-primary{width:100%}}
    `;
    const style = document.createElement('style');
    style.textContent = css;
    document.head.appendChild(style);
  }

  let wrapEl, reopenEl;

  function buildBanner(){
    wrapEl = document.createElement('div');
    wrapEl.className = 'kc-wrap';
    wrapEl.innerHTML = `
      <div class="kc-card">
        <div class="kc-head"><span class="kc-icon">🍪</span><span class="kc-title">Kèo dùng cookie</span></div>
        <div class="kc-body">Mình dùng cookie thiết yếu để trang hoạt động (đăng nhập, ghi nhớ lựa chọn), và có thể dùng thêm cookie phân tích/tiếp thị nếu bạn đồng ý — giúp mình hiểu trang nào hữu ích, cải thiện trải nghiệm. Xem <a href="/chinh-sach-cookie" target="_blank" rel="noopener">Chính sách Cookie</a>.</div>
        <div class="kc-btns">
          <button class="kc-btn" data-act="reject">Từ chối tất cả</button>
          <button class="kc-btn" data-act="prefs">Tuỳ chỉnh</button>
          <button class="kc-btn kc-primary" data-act="accept">Chấp nhận tất cả</button>
        </div>
        <div class="kc-prefs">
          <div class="kc-row">
            <div class="kc-row-text">
              <div class="kc-row-title">Cần thiết</div>
              <div class="kc-row-desc">Bắt buộc để trang hoạt động — đăng nhập, bảo mật phiên. Không thể tắt.</div>
            </div>
            <label class="kc-toggle"><input type="checkbox" checked disabled><span class="kc-slider"></span></label>
          </div>
          <div class="kc-row">
            <div class="kc-row-text">
              <div class="kc-row-title">Phân tích</div>
              <div class="kc-row-desc">Giúp mình hiểu bạn dùng trang thế nào, để cải thiện sản phẩm.</div>
            </div>
            <label class="kc-toggle"><input type="checkbox" id="kc-analytics"><span class="kc-slider"></span></label>
          </div>
          <div class="kc-row">
            <div class="kc-row-text">
              <div class="kc-row-title">Tiếp thị</div>
              <div class="kc-row-desc">Cá nhân hoá nội dung quảng bá phù hợp với bạn hơn.</div>
            </div>
            <label class="kc-toggle"><input type="checkbox" id="kc-marketing"><span class="kc-slider"></span></label>
          </div>
          <button class="kc-btn kc-primary kc-save" data-act="save">Lưu lựa chọn</button>
        </div>
      </div>
    `;
    document.body.appendChild(wrapEl);

    reopenEl = document.createElement('button');
    reopenEl.className = 'kc-reopen';
    reopenEl.title = 'Cài đặt cookie';
    reopenEl.innerHTML = '🍪';
    reopenEl.onclick = () => showBanner(true);
    document.body.appendChild(reopenEl);

    wrapEl.querySelector('[data-act="accept"]').onclick = () => { writeConsent({analytics:true, marketing:true}); hideBanner(); };
    wrapEl.querySelector('[data-act="reject"]').onclick = () => { writeConsent({analytics:false, marketing:false}); hideBanner(); };
    wrapEl.querySelector('[data-act="prefs"]').onclick = () => { wrapEl.querySelector('.kc-prefs').classList.toggle('kc-open'); };
    wrapEl.querySelector('[data-act="save"]').onclick = () => {
      const analytics = wrapEl.querySelector('#kc-analytics').checked;
      const marketing = wrapEl.querySelector('#kc-marketing').checked;
      writeConsent({analytics, marketing});
      hideBanner();
    };
  }

  function showBanner(forceReopen){
    if(!wrapEl) { injectStyle(); buildBanner(); }
    // Nếu mở lại để chỉnh sửa (không phải lần đầu), điền sẵn lựa chọn hiện tại lên toggle
    if(forceReopen){
      const c = readConsent();
      if(c){
        wrapEl.querySelector('#kc-analytics').checked = !!c.analytics;
        wrapEl.querySelector('#kc-marketing').checked = !!c.marketing;
        wrapEl.querySelector('.kc-prefs').classList.add('kc-open');
      }
    }
    requestAnimationFrame(()=> wrapEl.classList.add('kc-show'));
  }
  function hideBanner(){
    wrapEl.classList.remove('kc-show');
    reopenEl.classList.add('kc-visible');
  }

  // ─── Khởi động ───
  document.addEventListener('DOMContentLoaded', function(){
    const existing = readConsent();
    if(!existing){
      showBanner(false);
    } else {
      injectStyle();
      buildBanner();
      reopenEl.classList.add('kc-visible');
    }
  });
})();
