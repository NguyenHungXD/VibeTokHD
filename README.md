# VibeTok HD Photos - Patched

Phiên bản đã patch của VibeTok tweak, nâng cấp chất lượng ảnh tải về trong TikTok.

## Vấn đề

Khi tải ảnh từ TikTok qua VibeTok, ảnh thường bị mờ vì:
- VibeTok lấy UIImage thumbnail (đã scale) thay vì URL ảnh gốc
- URL TikTok CDN có query params nén: `~tplv-aaawodaw-720p.jpg`
- Hook `handleLongPress` dùng selector sai

## Giải pháp

Tweak này patch các điểm sau:

### 1. Hook `handleLongPress` (TTKCommentPhotoSlideDetailViewController)
- Lấy `originPhotoURL` thay vì UIImage `image`
- Bỏ query compression
- Tải về Photos album ở độ phân giải gốc

### 2. Hook `AWEAwemeModel.originPhotoURL`
- Auto-strip query `?`
- Replace `~tplv-` với `~tplv-noop.` để tắt nén

### 3. Hook `NSURL.URLWithString:`
- Auto-strip query trên URL `tiktokcdn.com`

## Tính năng (v2.0 - All-in-One)

### 📸 Photos (HD Photos)
- Lấy `originPhotoURL` thay vì UIImage thumbnail
- Bỏ query compression `~tplv-` → `~tplv-noop.`
- Auto-strip URL có chứa `tiktokcdn.com?` query

### 🎬 Videos (HD Videos)
- Lấy `playURLList` với bit-rate cao nhất
- Tự động tải khi nhấn "Save Video"

### 🚫 No Watermark
- Tự động crop logo TikTok ở góc dưới phải
- Áp dụng cho tất cả ảnh tải về

### 📑 Slideshow
- Lưu tất cả ảnh từ bài slideshow
- Hỗ trợ bài đăng nhiều ảnh

## Build

### Tự động - GitHub Actions (Khuyến nghị)

Workflow tại `.github/workflows/build.yml` sẽ tự động build trên macOS-14 runner.

**Trigger build:**

1. Push code lên GitHub:
   ```bash
   git push origin main
   ```

2. Hoặc manual trigger:
   - Vào tab **Actions** trên GitHub
   - Click "Build Full IPA" → **Run workflow**

**Download artifact:**

1. Vào tab **Actions** → chọn lần build thành công
2. Scroll xuống **Artifacts** → click `VibeTokHD-IPA`
3. Giải nén ZIP, lấy file `.ipa`

### Thủ công - macOS/Linux với Theos

```bash
git clone https://github.com/YOUR_USERNAME/VibeTokHD
cd VibeTokHD
make package
```

## Cài đặt

### Cách 1: Sideloadly (Windows, không jailbreak)
1. Tải Sideloadly: https://sideload.com/
2. Kết nối iPhone bằng cáp
3. Kéo file `.ipa` vào Sideloadly
4. Đăng nhập Apple ID
5. Click **Start** → chờ sign xong → Install

### Cách 2: AltStore (iPhone, không jailbreak)
1. Tải AltServer trên PC/Mac
2. Cài AltStore trên iPhone
3. Mở AltStore → My Apps → Install `.ipa`

### Cách 3: Jailbroken (tốt nhất)
1. Copy `.deb` vào iPhone (qua SSH hoặc Filza)
2. Cài qua Filza hoặc `dpkg -i`

## Build Output

- `.deb` file trong thư mục `packages/` (cài qua jailbreak)
- `.ipa` file trong artifact (cài qua Sideloadly)

## Credits

- DENS0R - Tác giả VibeTok gốc
- iOS Tweak community
- Theos build system

## License

MIT - tự do sử dụng và phân phối

## Disclaimer

- Tweak chỉ dành cho mục đích nghiên cứu
- Không sử dụng cho mục đích thương mại
- Tác giả không chịu trách nhiệm về vi phạm bản quyền