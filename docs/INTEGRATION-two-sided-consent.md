# Tích hợp — Luồng "Đồng ý hai chiều" (STAGE 2)

Thêm bước "Người đồng hành đồng ý cuối" trước khi Kèo được chốt. **Phải triển khai
DB + UI cùng lúc** — nếu chỉ chạy SQL mà chưa đổi UI phía Chủ xị, luồng chốt Kèo sẽ
đứng ở `host_selected`.

## Thứ tự bắt buộc
1. Chạy `db/patches/03-two-sided-consent.sql` trên project TEST → test 3 tài khoản (checklist trong file SQL).
2. Đổi UI (2 chỗ dưới) → test lại toàn luồng.
3. Chỉ khi cả 2 OK → chạy lên production giờ thấp điểm.

## Đã có sẵn trong repo
- **`loi-moi-cho-xac-nhan.html`** — trang Người đồng hành xem lời mời `host_selected`
  và bấm đồng ý/từ chối. ĐÃ dùng `Keo.*`, hoạt động ngay sau patch 03.

## Cần sửa: `quan-ly-keo.html` (phía Chủ xị)
Đổi ý nghĩa nút "Chấp nhận" → "Chọn người này" (đặt `host_selected` thay vì `accepted`).

Trong `loadApps()` — nhánh render theo status:
```js
if(a.status==='pending'){
  actions=`<div class="app-actions">
    <button class="btn-accept" onclick="decide('${a.id}','${keoId}','host_selected')">✓ Chọn người này</button>
    <button class="btn-reject" onclick="decide('${a.id}','${keoId}','rejected')">Từ chối</button></div>`;
} else if(a.status==='host_selected'){
  actions='<div class="app-result waiting">⏳ Đang chờ Người đồng hành đồng ý cuối</div>';
} else if(a.status==='accepted'){
  actions='<div class="app-result accepted">✓ Đã chốt — Kèo bắt đầu</div>';
} else if(a.status==='rejected'){
  actions='<div class="app-result rejected">Đã từ chối / bị đóng</div>';
} else if(a.status==='withdrawn'){
  actions='<div class="app-result rejected">Người này đã rút đơn</div>';
}
```
Trong `decide()` — toast phù hợp khi `decision==='host_selected'`:
`Keo.toast('✓ Đã đề nghị chọn — đang chờ Người đồng hành đồng ý cuối')`.

Thêm CSS:
```css
.app-result.waiting{background:rgba(232,162,43,.1);color:#E8A22B;border:1px solid rgba(232,162,43,.3)}
```

## Kèo "mời riêng" (visibility='private')
`open_keo_invites` chỉ cấp quyền xem, KHÔNG tự tạo application. Khi Chủ xị mời đích
danh, tạo LUÔN 1 `keo_applications` status `host_selected` để NĐH thấy ở trang mới:
```js
await Keo.sb.from('open_keo_invites').insert({ keo_id, companion_id });
await Keo.sb.from('keo_applications').insert({
  keo_id, companion_id, message:'(Lời mời riêng từ Chủ xị)', status:'host_selected'
});
```
Trigger `check_app_status_transition` chỉ chạy on-update, không chặn insert thẳng
`host_selected` — hợp lệ.

## Link vào trang lời mời
- Header khi role='nguoi_dong_hanh': badge "📬 Lời mời (N)" đếm
  `keo_applications where companion_id=me and status='host_selected'`.
- Từ notification `type='invited'` (trigger patch 03 tạo, link `/loi-moi-cho-xac-nhan`).
- Card ở `/tai-khoan`.

## Checklist test toàn luồng (H, C1, C2)
- [ ] H tạo Kèo công khai → C1, C2 ứng tuyển.
- [ ] H "Chọn người này" cho C1 → Kèo vẫn open, đơn C2 vẫn pending, C1 nhận thông báo.
- [ ] C1 vào `/loi-moi-cho-xac-nhan` → thấy card → "Tôi đồng ý" → Kèo `filled`, C2 `rejected`, H nhận thông báo, có conversation.
- [ ] Làm lại, C1 "Không thể tham gia" → Kèo vẫn open, H chọn tiếp C2.
- [ ] Kèo private: H mời riêng C1 → C1 thấy card tag "Mời riêng".
