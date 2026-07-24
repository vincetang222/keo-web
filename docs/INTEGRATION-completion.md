# Tích hợp — Component "Xác nhận hoàn thành buổi Kèo" (STAGE 2)

Nhúng vào "Kèo của tôi" (trong `tai-khoan.html`) cho mỗi Kèo `status='filled'`. Khi
CẢ HAI bên xác nhận đã gặp → Kèo `completed` → kích hoạt đánh giá + referral. Hạ tầng
đã có sẵn trong `db/schema.sql` (bảng `keo_completions`, trigger `on_completion_confirmed`,
helper `Keo.confirmCompletion`), **không cần patch DB thêm** — chỉ cần UI.

## 1. Lấy trạng thái xác nhận của một Kèo
```js
async function loadCompletion(keoId, meId){
  const { data } = await Keo.sb.from('keo_completions').select('confirmed_by').eq('keo_id', keoId);
  const ids = (data||[]).map(r => r.confirmed_by);
  return { iConfirmed: ids.includes(meId), count: ids.length };
}
// RLS chỉ cho host + companion của Kèo đọc → data chỉ gồm 2 bên.
// otherConfirmed = count - (iConfirmed?1:0) > 0
```

## 2. Xác nhận (insert 1 dòng — helper có sẵn)
```js
async function confirmReal(keoId, meId){
  const { error } = await Keo.confirmCompletion(keoId, meId);
  if(error){
    if(String(error.message||'').includes('duplicate')) return; // PK (keo_id, confirmed_by) chặn trùng
    Keo.toast('Lỗi: ' + error.message, 'err'); return;
  }
  Keo.toast('✓ Đã xác nhận hoàn thành');
  // Sau khi CẢ 2 xác nhận, trigger on_completion_confirmed tự:
  //   • open_keos.status → 'completed'
  //   • profiles.first_keo_at = now()  (kích hoạt referral + activation)
  // Client chỉ cần gọi lại loadCompletion() để cập nhật giao diện.
}
```

## 3. Điều kiện hiện khối (khớp RLS insert)
Chỉ hiện nút xác nhận khi TẤT CẢ đúng:
- `keo.status === 'filled'` (đã chốt, chưa completed/cancelled)
- Người xem là `host_id` của Kèo **HOẶC** companion đã `accepted` của Kèo đó
  (nếu không, RLS chặn insert → đừng hiện nút gây lỗi).

## 4. Gợi ý nhúng vào tai-khoan.html
Trong `switchKeoTab()` khi render `keo-item` có `k.status==='filled'`, thêm một khối
mở rộng (hoặc nút) gọi `loadCompletion(k.id, ME.id)` để hiện trạng thái 2 bên + nút
"Xác nhận tôi đã gặp xong" → `confirmReal(k.id, ME.id)` → `loadMyKeos()`.

Bản demo giao diện 3 trạng thái (pending / waiting / done) tham khảo trong lịch sử
bàn giao — logic `computeState()` map thẳng sang `{iConfirmed, otherConfirmed}` ở trên.

## 5. Kiểm thử
- 2 tài khoản thật (1 Chủ xị + 1 NĐH đã accepted cùng 1 Kèo).
- A xác nhận → thấy "chờ bên kia". B xác nhận → cả hai "hoàn thành".
- Kiểm `open_keos.status='completed'` + `first_keo_at` được set (Table Editor).
- Bấm xác nhận 2 lần từ cùng 1 người → không tạo dòng trùng, không lỗi hiện ra.

## Ghi chú
Trong `schema.sql` gốc, `first_keo_at` được set cho cả host và companion khi hoàn
thành — kích hoạt referral 2 phía. Yêu cầu treo từ người dùng: khi dựng UI cho bảng
`reviews`, đổi nhãn hiển thị **"đánh giá" → "cảm nhận"**.
