# Cấu hình VibeTokHD

Bạn có thể bật/tắt từng tính năng bằng cách sửa `#define` ở đầu `Tweak.x`.

## Mở Tweak.x và tìm:

```objc
// ============================================================================
// CONFIG - Có thể bật/tắt qua Settings nếu muốn
// ============================================================================
#define VHD_ENABLED 1
#define VHD_DOWNLOAD_VIDEO 1
#define VHD_DOWNLOAD_PHOTO 1
#define VHD_REMOVE_WATERMARK 1
#define VHD_DOWNLOAD_SLIDESHOW 1
#define VHD_LOG_LEVEL 1  // 0=silent, 1=info, 2=debug
```

## Tùy chọn

| Define | Mặc định | Mô tả |
|---|---|---|
| `VHD_ENABLED` | 1 | Bật/tắt toàn bộ tweak |
| `VHD_DOWNLOAD_VIDEO` | 1 | Tải video HD khi nhấn Save |
| `VHD_DOWNLOAD_PHOTO` | 1 | Tải ảnh HD khi nhấn giữ |
| `VHD_REMOVE_WATERMARK` | 1 | Crop logo TikTok |
| `VHD_DOWNLOAD_SLIDESHOW` | 1 | Lưu tất cả ảnh slideshow |
| `VHD_LOG_LEVEL` | 1 | 0=silent, 1=info, 2=debug |

## Ví dụ: Chỉ tải ảnh, không tải video

```objc
#define VHD_DOWNLOAD_PHOTO 1
#define VHD_DOWNLOAD_VIDEO 0
#define VHD_REMOVE_WATERMARK 1
#define VHD_DOWNLOAD_SLIDESHOW 0
```

## Build lại

Sau khi sửa, push lên GitHub và trigger build mới:

```bash
git add Tweak.x
git commit -m "Disable video downloads"
git push origin main
```

Vào tab **Actions** → chạy workflow → download artifact mới.

## Nâng cao: Build Settings qua Tweak Preferences

Để toggle in-app (không cần build lại), có thể dùng:
- `libprefs` (libMobileSubstrate Preferences)
- `libSandy` 

Ví dụ: thêm vào control file:
```
Depends: mobilesubstrate, preferenceloader
```

Và đọc giá trị:
```objc
#import <Preferences/PSListController.h>
NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.6gr8.vibetokhd.plist"];
BOOL downloadVideo = [settings[@"downloadVideo"] boolValue];
```

Nhưng cách này phức tạp hơn. Đơn giản nhất là dùng `#define` và build lại.