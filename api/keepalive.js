// ╔═══════════════════════════════════════════════════════════════════════════╗
// ║  /api/keepalive.js — Vercel Cron chạy mỗi ngày, làm 2 việc:                 ║
// ║   1. Giữ Supabase free tier khỏi bị pause (ghi 1 dòng heartbeat).           ║
// ║   2. Dọn ảnh CCCD đã quá hạn lưu (tầng 2) — tự xoá ảnh gốc, giữ dữ liệu     ║
// ║      trích xuất (tầng 1) và nhật ký (tầng 3).                               ║
// ║  Gộp vào 1 cron vì Vercel Hobby chỉ cho 1 cronjob/ngày.                     ║
// ╚═══════════════════════════════════════════════════════════════════════════╝

export default async function handler(req, res) {
  const auth = req.headers.authorization;
  if (process.env.CRON_SECRET && auth !== `Bearer ${process.env.CRON_SECRET}`) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const SUPABASE_URL = process.env.SUPABASE_URL;
  const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!SUPABASE_URL || !SERVICE_KEY) {
    return res.status(500).json({ error: 'Thiếu env SUPABASE_URL hoặc SUPABASE_SERVICE_ROLE_KEY' });
  }

  const headers = {
    'apikey': SERVICE_KEY,
    'Authorization': `Bearer ${SERVICE_KEY}`,
    'Content-Type': 'application/json'
  };
  const result = { heartbeat: false, images_cleaned: 0 };

  try {
    // ── Việc 1: heartbeat ──
    const hb = await fetch(`${SUPABASE_URL}/rest/v1/system_heartbeat`, {
      method: 'POST', headers: { ...headers, 'Prefer': 'return=minimal' },
      body: JSON.stringify({ pinged_at: new Date().toISOString() })
    });
    result.heartbeat = hb.ok;

    // ── Việc 2: dọn ảnh CCCD hết hạn ──
    const now = new Date().toISOString();
    const q = `${SUPABASE_URL}/rest/v1/verification_documents` +
      `?select=id,profile_id,storage_path&storage_path=not.is.null&image_expires_at=lt.${now}`;
    const expired = await fetch(q, { headers });
    if (expired.ok) {
      const docs = await expired.json();
      for (const doc of docs) {
        await fetch(`${SUPABASE_URL}/storage/v1/object/cccd/${doc.storage_path}`, {
          method: 'DELETE', headers
        });
        await fetch(`${SUPABASE_URL}/rest/v1/verification_documents?id=eq.${doc.id}`, {
          method: 'PATCH', headers: { ...headers, 'Prefer': 'return=minimal' },
          body: JSON.stringify({ storage_path: null, image_deleted_at: now })
        });
        await fetch(`${SUPABASE_URL}/rest/v1/verification_audit`, {
          method: 'POST', headers: { ...headers, 'Prefer': 'return=minimal' },
          body: JSON.stringify({ profile_id: doc.profile_id, document_id: doc.id, action: 'image_deleted', note: 'Tự động xoá theo hạn lưu 90 ngày' })
        });
        result.images_cleaned++;
      }
    }

    return res.status(200).json({ ok: true, at: now, ...result });
  } catch (e) {
    return res.status(500).json({ error: e.message, partial: result });
  }
}
