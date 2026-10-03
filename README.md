# VibeTok HD Photos - Patched

Phiên bản đã patch của VibeTok tweak, nâng cấp chất lượng ảnh tải về trong TikTok.

## Thay đổi chính
- Lấy `originPhotoURL` thay vì UIImage thumbnail
- Bỏ query compression `~tplv-` → `~tplv-noop.`
- Auto-strip URL có chứa `tiktokcdn.com?` query

## Build IPA

### Tự động (GitHub Actions)
Workflow `.github/workflows/build.yml` sẽ tự build trên macOS-14 runner.

Để trigger build:
1. Push code lên GitHub
2. Vào tab **Actions** → chọn workflow "Build IPA" → **Run workflow**
3. Sau khi build xong, download artifact `VibeTokHD-iPA`

### Thủ công (cần macOS/Linux + Theos)
```bash
git clone https://github.com/YOUR_USERNAME/VibeTokHD
cd VibeTokHD
make package
```

## Tải về

Vào tab **Actions** của repo → chọn lần build → download artifact `.ipa`.

Cài qua:
- AltStore iPad/iPhone
- Sideloadly (Windows)
- Hoặc nạp thẳng vào jailbroken qua Sileo/Zebra

## Credits
- DENS0R - Tác giả VibeTok gốc
- Theos VibeTV Team
