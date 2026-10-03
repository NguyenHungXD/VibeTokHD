// VibeTokHD v2.0 - All-in-One HD Patch
// Build với Theos: $ make package

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <substrate.h>

// MSHookIvar template - need to use non-template form
#define VHD_HookIvar(obj, name) ((__typeof__(obj))(object_getIvar(obj, object_getInstanceVariable([obj class], #name, NULL))))

// ============================================================================
// CONFIG
// ============================================================================
#define VHD_ENABLED 1
#define VHD_DOWNLOAD_VIDEO 1
#define VHD_DOWNLOAD_PHOTO 1
#define VHD_REMOVE_WATERMARK 1
#define VHD_DOWNLOAD_SLIDESHOW 1
#define VHD_LOG_LEVEL 1

// ============================================================================
// Helper Functions
// ============================================================================

static void vhd_log(NSString *fmt, ...) {
#if VHD_LOG_LEVEL >= 1
    va_list args;
    va_start(args, fmt);
    NSLog([NSString stringWithFormat:@"[VHD] %@", fmt], args);
    va_end(args);
#endif
}

static NSString *vhd_cleanURL(NSString *url) {
    if (!url || ![url isKindOfClass:[NSString class]]) return url;
    NSRange q = [url rangeOfString:@"?"];
    NSString *clean = (q.location != NSNotFound) ? [url substringToIndex:q.location] : url;
    clean = [clean stringByReplacingOccurrencesOfString:@"~tplv-"
                                              withString:@"~tplv-noop."];
    return clean;
}

static NSString *vhd_bestVideoURL(id playURLList) {
    if (![playURLList isKindOfClass:[NSArray class]]) return nil;
    if ([playURLList count] == 0) return nil;
    id first = [playURLList firstObject];
    if ([first isKindOfClass:[NSString class]]) return vhd_cleanURL(first);
    if ([first isKindOfClass:[NSDictionary class]]) {
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

static void vhd_saveData(NSData *data, NSString *filename) {
    if (!data) return;
    UIImage *img = [UIImage imageWithData:data];
    if (img) {
        UIImageWriteToSavedPhotosAlbum(img, nil, NULL, NULL);
        vhd_log(@"Saved %@ (%lu bytes)", filename, (unsigned long)[data length]);
    }
}

static void vhd_downloadURL(NSString *urlStr, NSString *filename, void (^onComplete)(NSData *)) {
    NSString *clean = vhd_cleanURL(urlStr);
    NSURL *url = [NSURL URLWithString:clean];
    [[[NSURLSession sharedSession] dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            vhd_log(@"Download failed for %@: %@", filename, [error localizedDescription]);
            return;
        }
        if (onComplete) onComplete(data);
    }] resume];
}

static UIImage *vhd_cropWatermark(UIImage *original) {
    if (!original) return original;
    CGSize size = [original size];
    CGFloat cropW = size.width * 0.08;
    CGRect keepRect = CGRectMake(0, 0, size.width - cropW, size.height);
    CGImageRef keepImage = CGImageCreateWithImageInRect([original CGImage], keepRect);
    UIImage *cropped = [UIImage imageWithCGImage:keepImage scale:[original scale] orientation:[original imageOrientation]];
    CGImageRelease(keepImage);
    return cropped;
}

static void vhd_saveVideo(NSURL *url, NSString *filename) {
    NSString *clean = [url absoluteString];
    clean = vhd_cleanURL(clean);
    vhd_log(@"Saving video: %@", clean);
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:clean]
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            vhd_log(@"Video download failed: %@", [error localizedDescription]);
            return;
        }
        NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
        [data writeToFile:tempPath atomically:YES];
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:[NSURL fileURLWithPath:tempPath]];
        } completionHandler:^(BOOL success, NSError *err) {
            [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
            if (success) vhd_log(@"Video saved: %@", filename);
            else vhd_log(@"Video save failed: %@", [err localizedDescription]);
        }];
    }] resume];
}

// Helper: get ivar value with type safety
static id vhd_getIvar(id self, const char *name) {
    Ivar ivar = class_getInstanceVariable([self class], name);
    if (!ivar) return nil;
    return object_getIvar(self, ivar);
}

// ============================================================================
// HOOK 1: handleLongPress
// ============================================================================
%hook TTKCommentPhotoSlideDetailViewController

- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    %orig;

#if VHD_DOWNLOAD_PHOTO
    id aweme = vhd_getIvar(self, "_awemeModel");
    if (!aweme) aweme = vhd_getIvar(self, "_model");

    if (!aweme) return;

    id urls = [aweme performSelector:@selector(originPhotoURL)];
    if (![urls isKindOfClass:[NSArray class]]) urls = nil;

    if (![urls count]) {
        urls = [aweme performSelector:@selector(originURLList)];
    }

    if ([urls count] > 0) {
        NSString *bestURL = (NSString *)[urls objectAtIndex:0];
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
// HOOK 2: AWEAwemeModel - Override getters
// ============================================================================
%hook AWEAwemeModel

- (NSArray *)originPhotoURL {
    NSArray *original = %orig;
    if (![original isKindOfClass:[NSArray class]]) return original;

    NSMutableArray *fixed = [NSMutableArray arrayWithCapacity:[original count]];
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

    NSMutableArray *fixed = [NSMutableArray arrayWithCapacity:[original count]];
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
    NSArray *original = %orig;
    if (![original isKindOfClass:[NSArray class]]) return original;

    NSMutableArray *sorted = [original mutableCopy];
    [sorted sortUsingComparator:^NSComparisonResult(id a, id b) {
        NSInteger br_a = 0, br_b = 0;
        if ([a isKindOfClass:[NSDictionary class]]) br_a = [a[@"bit_rate"] integerValue];
        if ([b isKindOfClass:[NSDictionary class]]) br_b = [b[@"bit_rate"] integerValue];
        return br_b - br_a;
    }];
    return sorted;
}

%end

// ============================================================================
// HOOK 3: NSURL - Auto-strip query on TikTokCDN
// ============================================================================
%hook NSURL

+ (id)URLWithString:(NSString *)URLString {
    if (URLString && [URLString containsString:@"tiktokcdn.com"]) {
        URLString = vhd_cleanURL(URLString);
    }
    return %orig(URLString);
}

%end

// ============================================================================
// Init
// ============================================================================
%ctor {
    NSLog(@"[VHD] ============================================");
    NSLog(@"[VHD] VibeTokHD v2.0 loaded");
    NSLog(@"[VHD] Photos HD: %@", VHD_DOWNLOAD_PHOTO ? @"ON" : @"OFF");
    NSLog(@"[VHD] Videos HD: %@", VHD_DOWNLOAD_VIDEO ? @"ON" : @"OFF");
    NSLog(@"[VHD] No Watermark: %@", VHD_REMOVE_WATERMARK ? @"ON" : @"OFF");
    NSLog(@"[VHD] ============================================");
}