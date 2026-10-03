// VibeTok HD Photos - Patched
// Build với Theos: $ make package

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <substrate.h>

// ============================================================================
// Hook 1: Comment photo viewer - Lấy URL ảnh gốc thay vì thumbnail
// ============================================================================
%hook TTKCommentPhotoSlideDetailViewController

- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    %orig;

    id aweme = MSHookIvar<id>(self, "_awemeModel");
    if (!aweme) aweme = MSHookIvar<id>(self, "_model");

    if (aweme) {
        // Thử originPhotoURL
        id urls = [aweme performSelector:@selector(originPhotoURL)];
        if ([urls isKindOfClass:[NSArray class]] && [urls count] > 0) {
            NSString *bestURL = [urls objectAtIndex:0];
            if (![bestURL isKindOfClass:[NSString class]]) return;

            // Bỏ query compression
            NSRange q = [bestURL rangeOfString:@"?"];
            if (q.location != NSNotFound) {
                bestURL = [bestURL substringToIndex:q.location];
            }
            bestURL = [bestURL stringByReplacingOccurrencesOfString:@"~tplv-"
                                                           withString:@"~tplv-noop."];
            NSLog(@"[VHDPhotos] Using origin URL: %@", bestURL);

            NSURL *url = [NSURL URLWithString:bestURL];
            [[[NSURLSession sharedSession] dataTaskWithURL:url
                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                    if (data && !error) {
                        UIImage *img = [UIImage imageWithData:data];
                        if (img) {
                            UIImageWriteToSavedPhotosAlbum(img, nil, NULL, NULL);
                            NSLog(@"[VHDPhotos] Saved HD image (%lu bytes)", (unsigned long)data.length);
                        }
                    }
            }] resume];
            return;
        }

        // Fallback: originURLList
        urls = [aweme performSelector:@selector(originURLList)];
        if ([urls isKindOfClass:[NSArray class]] && [urls count] > 0) {
            NSString *bestURL = [urls objectAtIndex:0];
            if ([bestURL isKindOfClass:[NSString class]]) {
                NSRange q = [bestURL rangeOfString:@"?"];
                if (q.location != NSNotFound) bestURL = [bestURL substringToIndex:q.location];
                NSLog(@"[VHDPhotos] Using originURLList: %@", bestURL);
                [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:bestURL]
                    completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
                    if (data) UIImageWriteToSavedPhotosAlbum([UIImage imageWithData:data], nil, NULL, NULL);
                }] resume];
            }
        }
    }
}

%end

// ============================================================================
// Hook 2: AWEAwemeModel - Bỏ quality compression
// ============================================================================
%hook AWEAwemeModel

- (NSArray *)originPhotoURL {
    NSArray *original = %orig;
    if (![original isKindOfClass:[NSArray class]]) return original;
    NSMutableArray *fixed = [NSMutableArray arrayWithCapacity:original.count];
    for (NSString *u in original) {
        if (![u isKindOfClass:[NSString class]]) { [fixed addObject:u]; continue; }
        NSRange q = [u rangeOfString:@"?"];
        NSString *clean = (q.location != NSNotFound) ? [u substringToIndex:q.location] : u;
        clean = [clean stringByReplacingOccurrencesOfString:@"~tplv-"
                                                 withString:@"~tplv-noop."];
        [fixed addObject:clean];
    }
    return fixed;
}

%end

// ============================================================================
// Hook 3: NSURL - Auto-strip TikTok CDN query params
// ============================================================================
%hook NSURL (TikTokURL)

+ (instancetype)URLWithString:(NSString *)URLString {
    if (URLString && [URLString containsString:@"tiktokcdn.com"]) {
        NSRange q = [URLString rangeOfString:@"?"];
        if (q.location != NSNotFound) {
            URLString = [URLString substringToIndex:q.location];
        }
    }
    return %orig(URLString);
}

%end

// ============================================================================
// Init
// ============================================================================
%ctor {
    NSLog(@"[VHDPhotos] VibeTok HD Photos Tweak loaded");
}
