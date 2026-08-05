# Bộ khung 11ty cho keo-web — ĐÃ BUILD THẬT, ĐÃ KIỂM CHỨNG BẰNG MẮT

## Đây là gì
Bộ khung Eleventy (11ty) thật — không phải bản nháp — chứng minh cách giải quyết vấn đề
"viết quá nhiều HTML lặp lại" mà không đánh đổi SEO/tốc độ (vẫn xuất ra HTML tĩnh thuần,
đúng triết lý `KIEN-TRUC.md` đã chọn từ đầu). Đã cài `@11ty/eleventy` thật từ npm, build
thật, và **render kiểm chứng bằng Playwright + xem ảnh thật** — không chỉ đọc code.

## Đã kiểm chứng những gì
- Build chạy sạch, không lỗi.
- 1 bài viết thật (`su-khac-biet-giua-dong-cam-va-thuong-hai`) được chuyển hoàn toàn từ
  file gốc — đúng từng chữ nội dung, đúng FAQ (4 câu), đúng 6 bài liên quan, đúng SVG
  minh hoạ vẽ tay, đúng chuyển ngữ VI/EN.
- Output HTML: cân bằng thẻ, JSON-LD (schema.org FAQPage) hợp lệ, canonical/og:url đúng
  dạng không đuôi `.html` (khớp cách `cleanUrls` của Vercel phục vụ trang thật — bài học
  rút ra từ chính lỗi 404 gặp phải trong phiên làm việc trước).
- Render bằng Playwright qua HTTP server cục bộ (không dùng `file://` — dùng `file://` sẽ
  làm CSS "biến mất" do đường dẫn tuyệt đối bị hiểu nhầm là gốc ổ đĩa, không phải gốc site
  — một cái bẫy khi test cục bộ, không phải lỗi thật khi deploy lên Vercel).
- Kết quả render đúng 100% thiết kế gốc: nav, hero, minh hoạ, FAQ accordion, related-articles
  đúng màu/icon theo danh mục, CTA cuối bài.

## Giải quyết đúng vấn đề gốc
1 bài viết giờ chỉ còn **front-matter (metadata) + nội dung** (~140 dòng, dễ đọc) thay vì
405 dòng HTML+CSS lặp lại. Nav/head/footer/FAQ-markup/related-markup/CTA đều nằm trong
**2 file layout dùng chung** (`_includes/base.njk`, `_includes/blog-post.njk`) — sửa 1 chỗ,
áp dụng cho mọi bài. Icon 4 danh mục tách thành 4 file nhỏ dùng lại qua `{% include %}`
thay vì dán SVG nguyên khối hàng trăm lần.

**Quan trọng nhất:** link "bài viết liên quan" giờ sinh từ `related: [{slug: "..."}]` trong
front-matter — nếu sau này đổi cấu trúc thư mục lần nữa, chỉ cần sửa 1 chỗ trong
`.eleventy.js` (hàm tính `permalink`), không phải sửa tay 582 link như lần vừa rồi.

## Cách chạy thử
```bash
npm install
npx @11ty/eleventy          # build ra thư mục _site/
npx @11ty/eleventy --serve  # build + xem trực tiếp tại localhost:8080
```

## Việc còn lại — chuyển nốt phần còn thiếu (hợp với Claude Code, việc lặp lại có khuôn mẫu)

1. **52 bài blog còn lại**: theo đúng khuôn mẫu file
   `src/blog/su-khac-biet-giua-dong-cam-va-thuong-hai.njk` — tách front-matter (title,
   description, categoryVi/En, titleVi/En, dekVi/En, faq[], related[], illustration) khỏi
   nội dung, dán nội dung vào phần dưới `---`. Có thể viết 1 script chuyển đổi bán tự động
   (đọc file HTML gốc, trích các phần bằng regex/BeautifulSoup, tự sinh front-matter) thay
   vì làm tay từng bài — với 52 bài cùng cấu trúc, đáng đầu tư viết script 1 lần.

2. **3 trang thành phố** (`nguoi-dong-hanh-da-nang/ha-noi/sai-gon`) hiện nằm trong `blog/` —
   nếu cấu trúc HTML của chúng khác bài blog thường (không có FAQ/related kiểu bài viết),
   có thể cần 1 layout riêng nhỏ (`city-page.njk`) thay vì dùng chung `blog-post.njk`.

3. **Trang lõi** (`index.html`, `thi-truong.html`, `khoa-hoc-ket-noi.html`...) — cấu trúc
   khác hẳn bài blog (không phải bài viết), cần layout riêng (`page.njk`) đơn giản hơn,
   chỉ có head+nav+footer dùng chung, phần giữa để nguyên HTML tự do.

4. **Trang `app/`** (đăng nhập, tài khoản...) — dùng Supabase JS SDK trực tiếp, gần như giữ
   nguyên, chỉ cần bọc vào layout chung để không lặp `<head>`. Không cần đổi logic JS.

5. **Cấu hình Vercel build**: thêm vào `vercel.json` (hoặc Project Settings trên Vercel
   Dashboard) — Build Command: `npx @11ty/eleventy`, Output Directory: `_site`. File
   `api/keepalive.js` (Vercel Function) không bị ảnh hưởng — 11ty chỉ sinh phần tĩnh.

## Không cần làm ngay
Đây là bộ khung để làm dần, không phải yêu cầu đổi toàn bộ site trong 1 lần. Có thể để
site tĩnh hiện tại chạy song song, chuyển từng nhóm trang sang 11ty, test kỹ từng nhóm
trước khi deploy — đúng tinh thần "làm từng bước, kiểm chứng trước khi qua bước tiếp" đã
áp dụng xuyên suốt các phần việc trước.
