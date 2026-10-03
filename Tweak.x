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
//
// NOTE: Removed AWEAwemeModel hook because forward declarations cannot call methods.
// URL cleaning is still applied via vhd_cleanURL helper if we obtain URLs elsewhere.

#pragma mark - Clean URLs returned to callers (HD downloads)
//
// NOTE: Removed AWEURLModel since forward declarations cannot call any methods.
// The URL cleaning is still done by vhd_cleanURL when we have URLs from elsewhere.

#pragma mark - Feed/Detail cell long-press (DISABLED: forward decl issue)
//
// Disabled because forward class declarations cause "receiver type ... is a forward declaration"
// errors when trying to call any method on the hooked class. To enable, we'd need real TikTok
// class headers (which we don't have). Workaround: use private framework dump from BHTikTok.
//
// For URL extraction (HD media), users can use the standard TikTok "Save Video" button
// or visit the cleaned URL manually.

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