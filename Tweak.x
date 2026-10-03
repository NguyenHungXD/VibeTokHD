// VibeTokHD - Tweak.x
// Pattern: long-press menu on TikTok cells, downloads via NSURLSession, save via UIActivityViewController.
// Reference: BandarHL/BHTikTok
//
// Build:
//   $ make package

#import "TikTokHeaders.h"
#import "VHDManager.h"
#import "VHDDownload.h"
#import <Photos/Photos.h>

#pragma mark - Jailbreak quarantine
static NSArray *vhd_jailbreakPaths;

#pragma mark - Helper: crop right edge (remove TikTok watermark area)
static UIImage *vhd_cropWatermark(UIImage *original) {
    if (!original) return original;
    CGSize sz = original.size;
    CGFloat cropW = sz.width * 0.08;
    CGRect keep = CGRectMake(0, 0, sz.width - cropW, sz.height);
    CGImageRef ref = CGImageCreateWithImageInRect(original.CGImage, keep);
    UIImage *out = [UIImage imageWithCGImage:ref scale:original.scale orientation:original.imageOrientation];
    CGImageRelease(ref);
    return out;
}

#pragma mark - URL helpers (clean watermark template markers)
static NSString *vhd_cleanURL(NSString *url) {
    if (![url isKindOfClass:[NSString class]]) return url;
    NSRange q = [url rangeOfString:@"?"];
    NSString *clean = (q.location != NSNotFound) ? [url substringToIndex:q.location] : url;
    clean = [clean stringByReplacingOccurrencesOfString:@"~tplv-" withString:@"~tplv-noop."];
    return clean;
}

#pragma mark - Save controller (viral Save Files menu)
static void vhd_showSaveMenu(id media, NSString *defaultFilename) {
    if (!media) return;
    UIViewController *top = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) { top = w.rootViewController; break; }
        }
        if (top) break;
    }
    while (top.presentedViewController) top = top.presentedViewController;
    if (!top) return;
    UIActivityViewController *ac = [[UIActivityViewController alloc] initWithActivityItems:@[media] applicationActivities:nil];
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        ac.popoverPresentationController.sourceView = top.view;
        ac.popoverPresentationController.sourceRect = CGRectMake(top.view.bounds.size.width/2, top.view.bounds.size.height/2, 1, 1);
    }
    [top presentViewController:ac animated:YES completion:nil];
}

#pragma mark - AppDelegate init
%hook AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig;
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"VHDFirstRun"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"VHDFirstRun"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"vh_save_video_hd"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"vh_save_photo_hd"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"vh_save_music_hd"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"vh_remove_watermark"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"vh_hide_ads"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"vh_download_button"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"vh_copy_video_link"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"vh_progress_bar"];
        [VHDManager cleanCache];
    }
    return YES;
}
%end

#pragma mark - Hide ads: handled by checking isAds in feed cells (no init hook needed)

#pragma mark - Origin photo list override (HD / no watermark)
%hook AWEAwemeModel

- (NSArray *)originPhotoURL {
    NSArray *original = %orig;
    if (![original isKindOfClass:[NSArray class]]) return original;
    NSMutableArray *fixed = [NSMutableArray arrayWithCapacity:original.count];
    for (id u in original) {
        if ([u isKindOfClass:[NSString class]]) [fixed addObject:vhd_cleanURL(u)];
        else [fixed addObject:u];
    }
    return fixed;
}

- (NSArray *)originURLList {
    NSArray *original = %orig;
    if (![original isKindOfClass:[NSArray class]]) return original;
    NSMutableArray *fixed = [NSMutableArray arrayWithCapacity:original.count];
    for (id u in original) {
        if ([u isKindOfClass:[NSString class]]) [fixed addObject:vhd_cleanURL(u)];
        else [fixed addObject:u];
    }
    return fixed;
}

- (BOOL)progressBarDraggable {
    if ([VHDManager progressBar]) return YES;
    return %orig;
}
- (BOOL)progressBarVisible {
    if ([VHDManager progressBar]) return YES;
    return %orig;
}
%end

#pragma mark - Clean URLs returned to callers (HD downloads)
%hook AWEURLModel
%new - (NSURL *)bestURLtoDownload {
    id urls = self.originURLList;
    if (![urls isKindOfClass:[NSArray class]]) return nil;
    for (id u in urls) {
        if ([u isKindOfClass:[NSString class]] &&
            ([u containsString:@"video_mp4"] || [u containsString:@".jpeg"] || [u containsString:@".mp3"])) {
            return [NSURL URLWithString:vhd_cleanURL(u)];
        }
    }
    id first = [urls firstObject];
    if ([first isKindOfClass:[NSString class]]) return [NSURL URLWithString:vhd_cleanURL(first)];
    return nil;
}

%new - (NSString *)bestURLtoDownloadFormat {
    id urls = self.originURLList;
    if (![urls isKindOfClass:[NSArray class]]) return @"mp4";
    for (id u in urls) {
        if (![u isKindOfClass:[NSString class]]) continue;
        if ([u containsString:@"video_mp4"]) return @"mp4";
        if ([u containsString:@".jpeg"]) return @"jpeg";
        if ([u containsString:@".png"]) return @"png";
        if ([u containsString:@".mp3"]) return @"mp3";
        if ([u containsString:@".m4a"]) return @"m4a";
    }
    return @"mp4";
}
%end

#pragma mark - Simple long-press: copy video URL to clipboard (no action sheet, safe)
%hook AWEFeedViewTemplateCell

- (void)configWithModel:(id)model {
    %orig;
    if ([VHDManager showDownloadButton]) {
        [self vhd_attachLongPress];
    }
}

- (void)configureWithModel:(id)model {
    %orig;
    if ([VHDManager showDownloadButton]) {
        [self vhd_attachLongPress];
    }
}

%new - (void)vhd_attachLongPress {
    id existing = objc_getAssociatedObject(self, @selector(vhd_onLongPress:));
    if (existing) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(vhd_onLongPress:)];
    lp.minimumPressDuration = 0.4;
    objc_setAssociatedObject(self, @selector(vhd_onLongPress:), lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self addGestureRecognizer:lp];
}

%new - (void)vhd_onLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    UIViewController *vc = nil;
    SEL vcSel = NSSelectorFromString(@"viewController");
    if ([self respondsToSelector:vcSel]) vc = [self performSelector:vcSel];
    if (![vc isKindOfClass:[UIViewController class]]) return;

    id model = [vc performSelector:NSSelectorFromString(@"model")];
    if (!model) return;
    id video = [model performSelector:NSSelectorFromString(@"video")];
    if (!video) return;
    id playURL = [video performSelector:NSSelectorFromString(@"playURL")];
    if (!playURL) return;
    id list = [playURL performSelector:NSSelectorFromString(@"originURLList")];
    NSString *first = nil;
    if ([list isKindOfClass:[NSArray class]]) {
        for (id u in list) {
            if ([u isKindOfClass:[NSString class]]) { first = u; break; }
        }
    }
    if (!first) return;

    NSString *clean = [first stringByReplacingOccurrencesOfString:@"~tplv-" withString:@"~tplv-noop."];
    NSRange q = [clean rangeOfString:@"?"];
    if (q.location != NSNotFound) clean = [clean substringToIndex:q.location];

    [UIPasteboard generalPasteboard].string = clean;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"VibeTokHD"
                                                                    message:[NSString stringWithFormat:@"Video link copied!\n\n%@", clean]
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *top = vc;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:alert animated:YES completion:nil];
}
%end

#pragma mark - Detail cell long-press (copy link)
%hook AWEAwemeDetailTableViewCell

- (void)configWithModel:(id)model {
    %orig;
    if ([VHDManager showDownloadButton]) [self vhd_attachLongPress];
}
- (void)configureWithModel:(id)model {
    %orig;
    if ([VHDManager showDownloadButton]) [self vhd_attachLongPress];
}

%new - (void)vhd_attachLongPress {
    id existing = objc_getAssociatedObject(self, @selector(vhd_onLongPress:));
    if (existing) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(vhd_onLongPress:)];
    lp.minimumPressDuration = 0.4;
    objc_setAssociatedObject(self, @selector(vhd_onLongPress:), lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self addGestureRecognizer:lp];
}

%new - (void)vhd_onLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    UIViewController *vc = nil;
    SEL vcSel = NSSelectorFromString(@"viewController");
    if ([self respondsToSelector:vcSel]) vc = [self performSelector:vcSel];
    if (![vc isKindOfClass:[UIViewController class]]) return;

    id model = [vc performSelector:NSSelectorFromString(@"model")];
    if (!model) return;
    id video = [model performSelector:NSSelectorFromString(@"video")];
    if (!video) return;
    id playURL = [video performSelector:NSSelectorFromString(@"playURL")];
    if (!playURL) return;
    id list = [playURL performSelector:NSSelectorFromString(@"originURLList")];
    NSString *first = nil;
    if ([list isKindOfClass:[NSArray class]]) {
        for (id u in list) {
            if ([u isKindOfClass:[NSString class]]) { first = u; break; }
        }
    }
    if (!first) return;
    NSString *clean = [first stringByReplacingOccurrencesOfString:@"~tplv-" withString:@"~tplv-noop."];
    NSRange q = [clean rangeOfString:@"?"];
    if (q.location != NSNotFound) clean = [clean substringToIndex:q.location];
    [UIPasteboard generalPasteboard].string = clean;
}
%end

#pragma mark - Jailbreak quarantine
%hook NSFileManager
- (BOOL)fileExistsAtPath:(NSString *)path {
    for (NSString *p in vhd_jailbreakPaths) {
        if ([path isEqualToString:p]) return NO;
    }
    return %orig;
}
- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDir {
    for (NSString *p in vhd_jailbreakPaths) {
        if ([path isEqualToString:p]) { if (isDir) *isDir = NO; return NO; }
    }
    return %orig;
}
%end

%hook BDADeviceHelper
+ (BOOL)isJailBroken { return NO; }
%end

%hook TTInstallUtil
+ (BOOL)isJailBroken { return NO; }
%end

%hook AppsFlyerUtils
+ (BOOL)isJailbrokenWithSkipAdvancedJailbreakValidation:(BOOL)arg2 { return NO; }
%end

%hook IESLiveDeviceInfo
+ (BOOL)isJailBroken { return NO; }
%end

%hook BDInstallNetworkUtility
+ (BOOL)isJailBroken { return NO; }
%end

%hook TTAdSplashDeviceHelper
+ (BOOL)isJailBroken { return NO; }
%end

%hook UIDevice
+ (BOOL)btd_isJailBroken { return NO; }
%end

%hook GULAppEnvironmentUtil
+ (BOOL)isFromAppStore { return YES; }
+ (BOOL)isAppStoreReceiptSandbox { return NO; }
+ (BOOL)isAppExtension { return YES; }
%end

%hook NSBundle
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext {
    if ([ext isEqualToString:@"mobileprovision"]) return nil;
    return %orig;
}
%end

#pragma mark - Init
%ctor {
    vhd_jailbreakPaths = @[
        @"/Applications/Cydia.app", @"/Applications/Sileo.app", @"/Applications/Zebra.app",
        @"/Library/MobileSubstrate/MobileSubstrate.dylib",
        @"/usr/libexec/cydia/firmware.sh", @"/usr/bin/ssh", @"/usr/sbin/sshd",
        @"/var/lib/cydia", @"/var/log/apt", @"/var/cache/apt",
        @"/etc/apt", @"/jb/jailbreakd.plist", @"/usr/lib/libjailbreak.dylib",
        @"/private/var/lib/apt", @"/private/var/stash",
        @"/bin/bash", @"/bin/sh"
    ];
    %init;
}