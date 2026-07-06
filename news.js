// /api/news.js
// Vercel Serverless Function — gộp tin tức từ nhiều nguồn, giấu API key phía server.
//
// CÁCH DÙNG:
// 1. Đặt file này vào thư mục /api/news.js ở gốc project Vercel của bạn.
// 2. Đăng ký key miễn phí tại https://currentsapi.services/en/register (1.000 request/ngày).
// 3. Vào Vercel Dashboard → Project → Settings → Environment Variables,
//    thêm biến CURRENTS_API_KEY = <key của bạn>.
// 4. Deploy lại. Trang web gọi vào /api/news thay vì gọi thẳng các nguồn,
//    nên key Currents không bao giờ lộ ra phía trình duyệt.
//
// ============================================================================
// LƯU Ý VỀ ĐIỀU KHOẢN SỬ DỤNG — ĐỌC KỸ TRƯỚC KHI BẬT TỪNG NGUỒN
// ============================================================================
// VnExpress & Tuổi Trẻ: điều khoản RSS (vnexpress.net/rss, tuoitre.vn/rss.htm)
//   ghi giống hệt nhau: "cung cấp miễn phí cho các cá nhân và các tổ chức
//   PHI LỢI NHUẬN". Kèo là mô hình kinh doanh có thu phí — dùng RSS này cho
//   mục đích thương mại nằm trong vùng xám về điều khoản (không phải rào cản
//   kỹ thuật, RSS vẫn công khai đọc được, nhưng là rủi ro pháp lý nhẹ).
//
// Investing.com Việt Nam: điều khoản chung của trang có câu khá rộng
//   ("không được dùng/phân phối dữ liệu khi chưa có phép bằng văn bản"),
//   NHƯNG các feed dưới đây nằm trong mục "Webmaster Tools > Dịch vụ RSS"
//   mà chính Investing.com chủ động công bố để các site khác nhúng vào —
//   nên rủi ro thấp hơn 2 nguồn trên, dù không tuyệt đối chắc chắn 100%.
//
// Mỗi nguồn bên dưới đều có thể BẬT/TẮT độc lập bằng cách comment dòng
// tương ứng trong mảng RSS_SOURCES — không cần sửa logic.
// ============================================================================

const RSS_SOURCES = [
  { name: 'VnExpress',      url: 'https://vnexpress.net/rss/kinh-doanh.rss' },
  { name: 'Tuổi Trẻ',       url: 'https://tuoitre.vn/rss/kinh-doanh.rss' },
  { name: 'Investing.com',  url: 'https://vn.investing.com/rss/news_25.rss' },   // Thị trường Chứng khoán
  { name: 'Investing.com',  url: 'https://vn.investing.com/rss/news_477.rss' },  // Bản tin tài chính mới nhất
  // { name: 'Investing.com', url: 'https://vn.investing.com/rss/news_14.rss' },   // Kinh tế — bật thêm nếu muốn
  // { name: 'Investing.com', url: 'https://vn.investing.com/rss/news_1.rss' },    // Forex — bật thêm nếu muốn
];

export default async function handler(req, res) {
  const CURRENTS_KEY = process.env.CURRENTS_API_KEY;

  const jobs = [
    fetchCurrentsAPI(CURRENTS_KEY),
    ...RSS_SOURCES.map(s => fetchRSS(s.url, s.name)),
  ];

  const results = await Promise.allSettled(jobs);

  const international = results[0].status === 'fulfilled' ? results[0].value : [];
  const vietnam = results.slice(1).flatMap(r => r.status === 'fulfilled' ? r.value : []);
  const errors = results.map((r, i) => r.status === 'rejected'
    ? { source: i === 0 ? 'Currents API' : RSS_SOURCES[i - 1].name, error: String(r.reason) }
    : null
  ).filter(Boolean);

  res.setHeader('Cache-Control', 's-maxage=3600, stale-while-revalidate=7200'); // cache 1 tiếng, tối đa 24 lần gọi Currents/ngày — dư sức nằm dưới 1.000/ngày
  res.status(200).json({ international, vietnam, errors });
}

async function fetchCurrentsAPI(apiKey) {
  if (!apiKey) throw new Error('Thiếu CURRENTS_API_KEY trong Environment Variables');

  const url = `https://api.currentsapi.services/v1/latest-news?language=en&category=business&apiKey=${apiKey}`;
  const r = await fetch(url);
  if (!r.ok) throw new Error(`Currents API trả về lỗi ${r.status}`);
  const data = await r.json();

  return (data.news || []).slice(0, 8).map(a => ({
    title: a.title || '',
    description: (a.description || '').slice(0, 200),
    url: a.url,
    source: (a.author || 'Currents API').trim(),
    published: a.published || '',
  }));
}

// Hàm đọc RSS dùng chung cho mọi nguồn tiếng Việt — chỉ cần đổi url + tên nguồn.
async function fetchRSS(feedUrl, sourceName) {
  const r = await fetch(feedUrl, {
    headers: { 'User-Agent': 'Mozilla/5.0 (compatible; KeoBot/1.0; +https://keo.social)' },
  });
  if (!r.ok) throw new Error(`${sourceName} RSS trả về lỗi ${r.status}`);
  const xml = await r.text();

  const items = [...xml.matchAll(/<item>([\s\S]*?)<\/item>/g)].slice(0, 5); // 5 bài/nguồn để không lấn át nguồn khác

  return items.map(m => {
    const block = m[1];
    const pick = (tag) => {
      const m2 = block.match(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`));
      if (!m2) return '';
      return m2[1].replace('<![CDATA[', '').replace(']]>', '').trim();
    };
    return {
      title: pick('title'),
      description: pick('description').replace(/<[^>]+>/g, '').slice(0, 200), // bỏ thẻ HTML lẫn trong mô tả
      url: pick('link'),
      source: sourceName,
      published: pick('pubDate'),
    };
  });
}
