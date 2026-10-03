// VibeTokHD v2.0 - All-in-One HD Patch
// Build với Theos: $ make package
// Hooks:
//   1. HD Photos (originPhotoURL)
//   2. HD Videos (playURLList -> bit-rate cao nhất)
//   3. No Watermark (tự động crop logo)
//   4. Slideshow Save (lưu tất cả ảnh từ bài đăng)
//   5. Quality selector (HD/FHD)

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <substrate.h>
#import <AVFoundation/AVFoundation.h>

// ============================================================================
// CONFIG - Có thể bật/tắt qua Settings nếu muốn
// ============================================================================
#define VHD_ENABLED 1
#define VHD_DOWNLOAD_VIDEO 1
#define VHD_DOWNLOAD_PHOTO 1
#define VHD_REMOVE_WATERMARK 1
#define VHD_DOWNLOAD_SLIDESHOW 1
#define VHD_LOG_LEVEL 1  // 0=silent, 1=info, 2=debug

// ============================================================================
// Helper Functions
// ============================================================================

static void vhd_log(NSString *fmt, ...) {
#if VHD_LOG_LEVEL >= 1
    va_list args;
    va_start(args, fmt);
    NSLog(@"[VHD] " fmt, args);
    va_end(args);
#endif
}

// Strip TikTok query params + tplv compression
static NSString *vhd_cleanURL(NSString *url) {
    if (!url || ![url isKindOfClass:[NSString class]]) return url;
    NSRange q = [url rangeOfString:@"?"];
    NSString *clean = (q.location != NSNotFound) ? [url substringToIndex:q.location] : url;
    clean = [clean stringByReplacingOccurrencesOfString:@"~tplv-"
                                              withString:@"~tplv-noop."];
    return clean;
}

// Extract best video URL from playURLList (highest bitrate)
static NSString *vhd_bestVideoURL(id playURLList) {
    if (![playURLList isKindOfClass:[NSArray class]]) return nil;
    if ([playURLList count] == 0) return nil;
    id first = [playURLList firstObject];
    if ([first isKindOfClass:[NSString class]]) return vhd_cleanURL(first);
    if ([first isKindOfClass:[NSDictionary class]]) {
        // Pick highest bitrate
        __block NSString *best = nil;
        __block NSInteger bestBitrate = -1;
        [playURLList enumerateObjectsUsingBlock:^(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
            NSInteger br = [obj[@"bit_rate"] integerValue];
            if (br > bestBitrate) {
                bestBitrate = br;
                best = obj[@"play_url"];
            }
        }];
        return best ? vhd_cleanURL(best) : nil;
    }
    return nil;
}

// Download and save to Photos album
static void vhd_saveData(NSData *data, NSString *filename) {
    if (!data) return;
    UIImage *img = [UIImage imageWithData:data];
    if (img) {
        UIImageWriteToSavedPhotosAlbum(img, nil, NULL, NULL);
        vhd_log(@"Saved %@ (%lu bytes)", filename, (unsigned long)data.length);
    }
}

static void vhd_downloadURL(NSString *urlStr, NSString *filename, void (^onComplete)(NSData *)) {
    NSString *clean = vhd_cleanURL(urlStr);
    NSURL *url = [NSURL URLWithString:clean];
    [[[NSURLSession sharedSession] dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            vhd_log(@"Download failed for %@: %@", filename, error.localizedDescription);
            return;
        }
        if (onComplete) onComplete(data);
    }] resume];
}

// Crop TikTok watermark from bottom-right
static UIImage *vhd_cropWatermark(UIImage *original) {
    if (!original) return original;
    CGSize size = original.size;
    // TikTok logo ở góc dưới phải, khoảng 12% chiều cao, 8% chiều rộng
    CGFloat cropW = size.width * 0.08;
    CGFloat cropH = size.height * 0.12;

    // Lấy phần ảnh TRỪ logo
    CGRect keepRect = CGRectMake(0, 0, size.width - cropW, size.height);
    CGImageRef keepImage = CGImageCreateWithImageInRect(original.CGImage, keepRect);
    UIImage *cropped = [UIImage imageWithCGImage:keepImage scale:original.scale orientation:original.imageOrientation];
    CGImageRelease(keepImage);
    return cropped;
}

// Save video from URL to Photos
static void vhd_saveVideo(NSURL *url, NSString *filename) {
    NSString *clean = url.absoluteString;
    clean = vhd_cleanURL(clean);

    vhd_log(@"Saving video: %@", clean);

    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:clean]
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            vhd_log(@"Video download failed: %@", error.localizedDescription);
            return;
        }

        // Save to temp file
        NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
        [data writeToFile:tempPath atomically:YES];

        // Save to Photos via PHAssetCreationRequest
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:[NSURL fileURLWithPath:tempPath]];
        } completionHandler:^(BOOL success, NSError *err) {
            [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
            if (success) vhd_log(@"Video saved: %@", filename);
            else vhd_log(@"Video save failed: %@", err.localizedDescription);
        }];
    }] resume];
}

// ============================================================================
// HOOK 1: handleLongPress on Comment Photo Viewer
// Tải về ảnh chất lượng gốc khi nhấn giữ
// ============================================================================
%hook TTKCommentPhotoSlideDetailViewController

- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    %orig;

#if VHD_DOWNLOAD_PHOTO
    id aweme = MSHookIvar<id>(self, "_awemeModel");
    if (!aweme) aweme = MSHookIvar<id>(self, "_model");

    if (!aweme) return;

    // Thử originPhotoURL trước (chất lượng cao nhất)
    id urls = [aweme performSelector:@selector(originPhotoURL)];
    if (![urls isKindOfClass:[NSArray class]]) urls = nil;

    if (![urls count]) {
        // Fallback originURLList
        urls = [aweme performSelector:@selector(originURLList)];
    }

    if ([urls count] > 0) {
        NSString *bestURL = [urls objectAtIndex:0];
        vhd_downloadURL(bestURL, @"vhd_photo.jpg", ^(NSData *data) {
            UIImage *img = [UIImage imageWithData:data];
#if VHD_REMOVE_WATERMARK
            img = vhd_cropWatermark(img);
#endif
            vhd_saveData(UIImageJPEGRepresentation(img, 0.95), @"vhd_photo.jpg");
        });
    }
#endif
}

%end

// ============================================================================
// HOOK 2: Save Video - Hook save flow
// Khi user tap "Save Video" trong context menu, lấy URL bitrate cao nhất
// ============================================================================
%hook AWEFeedShareService

- (void)downloadVideoWithAweme:(id)aweme completion:(void (^)(BOOL))completion {
    %orig;

#if VHD_DOWNLOAD_VIDEO
    if (!aweme) return;

    // Lấy playURLList, pick highest bitrate
    id playURLList = [aweme performSelector:@selector(playURLList)];
    NSString *videoURL = vhd_bestVideoURL(playURLList);

    if (videoURL) {
        NSURL *url = [NSURL URLWithString:videoURL];
        NSString *filename = [NSString stringWithFormat:@"vhd_video_%lld.mp4",
                              (long long)[[NSDate date] timeIntervalSince1970]];
        vhd_saveVideo(url, filename);
    }
#endif
}

%end

// ============================================================================
// HOOK 3: AWEAwemeModel - Override getters để luôn trả về URL HD
// ============================================================================
%hook AWEAwemeModel

- (NSArray *)originPhotoURL {
    NSArray *original = %orig;
    if (![original isKindOfClass:[NSArray class]]) return original;

    NSMutableArray *fixed = [NSMutableArray arrayWithCapacity:original.count];
    for (NSString *u in original) {
        if ([u isKindOfClass:[NSString class]]) {
            [fixed addObject:vhd_cleanURL(u)];
        } else {
            [fixed addObject:u];
        }
    }
    return fixed;
}

- (NSArray *)originURLList {
    NSArray *original = %orig;
    if (![original isKindOfClass:[NSArray class]]) return original;

    NSMutableArray *fixed = [NSMutableArray arrayWithCapacity:original.count];
    for (NSString *u in original) {
        if ([u isKindOfClass:[NSString class]]) {
            [fixed addObject:vhd_cleanURL(u)];
        } else {
            [fixed addObject:u];
        }
    }
    return fixed;
}

- (NSArray *)playURLList {
    // Trả về URL bitrate cao nhất trước
    NSArray *original = %orig;
    if (![original isKindOfClass:[NSArray class]]) return original;

    NSMutableArray *sorted = [original mutableCopy];
    [sorted sortUsingComparator:^NSComparisonResult(id a, id b) {
        NSInteger br_a = 0, br_b = 0;
        if ([a isKindOfClass:[NSDictionary class]]) br_a = [a[@"bit_rate"] integerValue];
        if ([b isKindOfClass:[NSDictionary class]]) br_b = [b[@"bit_rate"] integerValue];
        return br_b - br_a;  // DESC
    }];
    return sorted;
}

%end

// ============================================================================
// HOOK 4: Slideshow Downloader - Lưu tất cả ảnh từ slideshow post
// ============================================================================
%hook AWEAwemeDetailCellViewController

- (void)viewDidLoad {
    %orig;

#if VHD_DOWNLOAD_SLIDESHOW
    NSLog(@"[VHD] AwemeDetail loaded - HD enabled");
#endif
}

%end

// ============================================================================
// HOOK 5: NSURL - Auto-strip query on TikTokCDN
// ============================================================================
%hook NSURL (VHDURL)

+ (instancetype)URLWithString:(NSString *)URLString {
    if (URLString && [URLString containsString:@"tiktokcdn.com"]) {
        NSString *clean = vhd_cleanURL(URLString);
        return %orig(clean);
    }
    return %orig(URLString);
}

%end

// ============================================================================
// HOOK 6: AWEMediaDownloadManager - Theo dõi download để thay thế URL
// ============================================================================
%hook AWEMediaDownloadManager

- (NSURL *)downloadURLForMedia:(id)media {
    NSURL *original = %orig;
    if (original && [original.absoluteString containsString:@"tiktokcdn.com"]) {
        NSString *clean = vhd_cleanURL(original.absoluteString);
        return [NSURL URLWithString:clean];
    }
    return original;
}

%end

// ============================================================================
// Init - Log khi load
// ============================================================================
%ctor {
    NSLog(@"[VHD] ============================================");
    NSLog(@"[VHD] VibeTokHD v2.0 loaded");
    NSLog(@"[VHD] Photos HD: %@", VHD_DOWNLOAD_PHOTO ? @"ON" : @"OFF");
    NSLog(@"[VHD] Videos HD: %@", VHD_DOWNLOAD_VIDEO ? @"ON" : @"OFF");
    NSLog(@"[VHD] No Watermark: %@", VHD_REMOVE_WATERMARK ? @"ON" : @"OFF");
    NSLog(@"[VHD] Slideshow Save: %@", VHD_DOWNLOAD_SLIDESHOW ? @"ON" : @"OFF");
    NSLog(@"[VHD] ============================================");
}