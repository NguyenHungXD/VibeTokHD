#import "VHDManager.h"

static inline UIViewController *topMostController(void) {
    UIViewController *topVC = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        for (UIWindow *w in ws.windows) {
            if (!w.isKeyWindow) continue;
            topVC = w.rootViewController;
            break;
        }
        if (topVC) break;
    }
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    return topVC;
}

static inline BOOL is_iPad(void) {
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
}

@implementation VHDManager

+ (BOOL)saveVideoHD    { return [[NSUserDefaults standardUserDefaults] boolForKey:@"vh_save_video_hd"]; }
+ (BOOL)savePhotoHD    { return [[NSUserDefaults standardUserDefaults] boolForKey:@"vh_save_photo_hd"]; }
+ (BOOL)saveMusicHD    { return [[NSUserDefaults standardUserDefaults] boolForKey:@"vh_save_music_hd"]; }
+ (BOOL)removeWatermark{ return [[NSUserDefaults standardUserDefaults] boolForKey:@"vh_remove_watermark"]; }
+ (BOOL)hideAds        { return [[NSUserDefaults standardUserDefaults] boolForKey:@"vh_hide_ads"]; }
+ (BOOL)autoPlay       { return [[NSUserDefaults standardUserDefaults] boolForKey:@"vh_auto_play"]; }
+ (BOOL)progressBar    { return [[NSUserDefaults standardUserDefaults] boolForKey:@"vh_progress_bar"]; }
+ (BOOL)showDownloadButton { return [[NSUserDefaults standardUserDefaults] boolForKey:@"vh_download_button"]; }
+ (BOOL)copyDescription{ return [[NSUserDefaults standardUserDefaults] boolForKey:@"vh_copy_description"]; }
+ (BOOL)copyVideoLink  { return [[NSUserDefaults standardUserDefaults] boolForKey:@"vh_copy_video_link"]; }
+ (BOOL)copyMusicLink  { return [[NSUserDefaults standardUserDefaults] boolForKey:@"vh_copy_music_link"]; }

+ (void)cleanCache {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *dirs = @[
        NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject,
        NSTemporaryDirectory()
    ];
    NSArray *exts = @[@"mp4", @"mov", @"mp3", @"m4a", @"png", @"jpeg", @"tmp"];
    for (NSString *dir in dirs) {
        NSError *err = nil;
        NSArray *items = [fm contentsOfDirectoryAtPath:dir error:&err];
        for (NSString *name in items) {
            NSString *ext = [[name pathExtension] lowercaseString];
            if ([exts containsObject:ext]) {
                [fm removeItemAtPath:[dir stringByAppendingPathComponent:name] error:nil];
            }
        }
    }
}

+ (BOOL)isEmpty:(NSURL *)url {
    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:url
                                                    includingPropertiesForKeys:@[]
                                                       options:NSDirectoryEnumerationSkipsHiddenFiles
                                                         error:nil];
    return items.count == 0;
}

+ (void)showSaveVC:(id)item {
    if (!item) return;
    UIViewController *top = topMostController();
    if (!top) return;
    UIActivityViewController *ac = [[UIActivityViewController alloc] initWithActivityItems:@[item] applicationActivities:nil];
    if (is_iPad()) {
        ac.popoverPresentationController.sourceView = top.view;
        ac.popoverPresentationController.sourceRect = CGRectMake(top.view.bounds.size.width/2, top.view.bounds.size.height/2, 1, 1);
    }
    [top presentViewController:ac animated:YES completion:nil];
}

+ (NSString *)getDownloadingPercent:(float)per {
    return [NSString stringWithFormat:@"%.0f%%", per * 100];
}

@end