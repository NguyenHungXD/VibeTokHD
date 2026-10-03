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
static NSArray *vh_cleanURLArray(NSArray *arr) {
    if (![arr isKindOfClass:[NSArray class]]) return arr;
    NSMutableArray *fixed = [NSMutableArray arrayWithCapacity:arr.count];
    for (id u in arr) {
        [fixed addObject:([u isKindOfClass:[NSString class]] ? vhd_cleanURL(u) : u)];
    }
    return fixed;
}

%hook AWEAwemeModel

- (NSArray *)originPhotoURL { return vh_cleanURLArray(%orig); }

- (NSArray *)originURLList { return vh_cleanURLArray(%orig); }

- (BOOL)progressBarDraggable { return [VHDManager progressBar] || %orig; }
- (BOOL)progressBarVisible   { return [VHDManager progressBar] || %orig; }
%end

#pragma mark - Clean URLs returned to callers (HD downloads)
%hook AWEURLModel
%new - (NSURL *)bestURLtoDownload {
    NSArray *urls = self.originURLList;
    for (NSString *u in urls) {
        if ([u isKindOfClass:[NSString class]] &&
            ([u containsString:@"video_mp4"] || [u containsString:@".jpeg"] || [u containsString:@".mp3"])) {
            return [NSURL URLWithString:vhd_cleanURL(u)];
        }
    }
    id first = urls.firstObject;
    if ([first isKindOfClass:[NSString class]]) return [NSURL URLWithString:vhd_cleanURL(first)];
    return nil;
}

%new - (NSString *)bestURLtoDownloadFormat {
    for (NSString *u in self.originURLList) {
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

#pragma mark - Feed Cell: long-press menu (download / copy)
%hook AWEFeedViewTemplateCell

%property (nonatomic, strong) VHDDownload *hudDownloader;
%property (nonatomic, copy)   NSString *hudFileext;

- (void)configWithModel:(id)model {
    %orig;
    if ([VHDManager showDownloadButton]) {
        [self vhd_addLongPress];
    }
}

- (void)configureWithModel:(id)model {
    %orig;
    if ([VHDManager showDownloadButton]) {
        [self vhd_addLongPress];
    }
}

%new - (void)vhd_addLongPress {
    UILongPressGestureRecognizer *existing = (UILongPressGestureRecognizer *)objc_getAssociatedObject(self, @selector(vhd_onLongPress:));
    if (existing) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(vhd_onLongPress:)];
    lp.minimumPressDuration = 0.4;
    objc_setAssociatedObject(self, @selector(vhd_onLongPress:), lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self addGestureRecognizer:lp];
}

%new - (void)vhd_onLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    if (![self.viewController isKindOfClass:%c(AWEFeedCellViewController)]) return;
    AWEFeedCellViewController *vc = (AWEFeedCellViewController *)self.viewController;

    NSString *desc = vc.model.music_songName ?: @"TikTok";
    TUXActionSheetController *sheet = [[%c(TUXActionSheetController) alloc] initWithTitle:desc];

    if ([VHDManager saveVideoHD]) {
        [sheet addAction:[[%c(TUXActionSheetAction) alloc] initWithStyle:0 title:@"Download video (HD)"
                                                                 subtitle:nil
                                                                    image:[UIImage systemImageNamed:@"arrow.down"]
                                                              imageLabel:nil
                                                                  handler:^(TUXActionSheetAction *act) {
            NSURL *url = [vc.model.video.playURL bestURLtoDownload];
            self.hudFileext = [vc.model.video.playURL bestURLtoDownloadFormat];
            if (!url) return;
            VHDDownload *dw = [VHDDownload new];
            dw.delegate = self;
            self.hudDownloader = dw;
            [dw downloadFileWithURL:url];
        }]];
    }

    if ([VHDManager savePhotoHD]) {
        [sheet addAction:[[%c(TUXActionSheetAction) alloc] initWithStyle:0 title:@"Download photo (HD)"
                                                                 subtitle:nil
                                                                    image:[UIImage systemImageNamed:@"photo"]
                                                              imageLabel:nil
                                                                  handler:^(TUXActionSheetAction *act) {
            NSArray *urls = vc.model.originPhotoURL;
            NSString *first = [urls isKindOfClass:[NSArray class]] ? urls.firstObject : nil;
            if (![first isKindOfClass:[NSString class]]) return;
            NSURL *url = [NSURL URLWithString:vhd_cleanURL(first)];
            if (!url) return;
            self.hudFileext = @"jpeg";
            VHDDownload *dw = [VHDDownload new];
            dw.delegate = self;
            self.hudDownloader = dw;
            [dw downloadFileWithURL:url];
        }]];
    }

    if ([VHDManager saveMusicHD] && vc.model.music) {
        [sheet addAction:[[%c(TUXActionSheetAction) alloc] initWithStyle:0 title:@"Download music"
                                                                 subtitle:nil
                                                                    image:[UIImage systemImageNamed:@"music.note"]
                                                              imageLabel:nil
                                                                  handler:^(TUXActionSheetAction *act) {
            AWEMusicModel *m = (AWEMusicModel *)vc.model.music;
            NSURL *url = [m.playURL bestURLtoDownload];
            self.hudFileext = [m.playURL bestURLtoDownloadFormat];
            if (!url) return;
            VHDDownload *dw = [VHDDownload new];
            dw.delegate = self;
            self.hudDownloader = dw;
            [dw downloadFileWithURL:url];
        }]];
    }

    if ([VHDManager copyVideoLink]) {
        [sheet addAction:[[%c(TUXActionSheetAction) alloc] initWithStyle:0 title:@"Copy video link"
                                                                 subtitle:nil
                                                                    image:[UIImage systemImageNamed:@"doc.on.clipboard"]
                                                              imageLabel:nil
                                                                  handler:^(TUXActionSheetAction *act) {
            NSURL *url = [vc.model.video.playURL bestURLtoDownload];
            [UIPasteboard generalPasteboard].string = url ? url.absoluteString : @"";
        }]];
    }

    if ([VHDManager copyDescription]) {
        [sheet addAction:[[%c(TUXActionSheetAction) alloc] initWithStyle:0 title:@"Copy description"
                                                                 subtitle:nil
                                                                    image:[UIImage systemImageNamed:@"text.alignleft"]
                                                              imageLabel:nil
                                                                  handler:^(TUXActionSheetAction *act) {
            [UIPasteboard generalPasteboard].string = desc ?: @"";
        }]];
    }

    [sheet setDismissOnDraggingDown:YES];
    UIViewController *top = self.viewController;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:sheet animated:YES completion:nil];
}

%new - (void)vhdDownloadProgress:(float)progress {}
%new - (void)vhdDownloadDidFinish:(NSURL *)filePath filename:(NSString *)fileName {
    if ([self.hudFileext isEqualToString:@"mp4"]) {
        NSURL *videoURL = filePath;
        [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
            [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:videoURL];
        } completionHandler:^(BOOL ok, NSError *err) {
            [[NSFileManager defaultManager] removeItemAtURL:filePath error:nil];
            if (ok) [%c(AWEToast) showSuccess:@"Saved"];
        }];
    } else if ([self.hudFileext isEqualToString:@"jpeg"] || [self.hudFileext isEqualToString:@"png"]) {
        UIImage *img = [UIImage imageWithContentsOfFile:filePath.path];
        if (img) {
            if ([VHDManager removeWatermark]) img = vhd_cropWatermark(img);
            UIImage *final = img;
            [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
                [PHAssetCreationRequest creationRequestForAssetFromImage:final];
            } completionHandler:^(BOOL ok, NSError *err) {
                [[NSFileManager defaultManager] removeItemAtURL:filePath error:nil];
                if (ok) [%c(AWEToast) showSuccess:@"Saved"];
            }];
        }
    } else {
        vhd_showSaveMenu(filePath, fileName);
    }
    self.hudDownloader = nil;
}
%new - (void)vhdDownloadDidFailureWithError:(NSError *)error {
    self.hudDownloader = nil;
}
%end

#pragma mark - Detail cell (same pattern)
%hook AWEAwemeDetailTableViewCell
%property (nonatomic, strong) VHDDownload *hudDownloader;
%property (nonatomic, copy)   NSString *hudFileext;

- (void)configWithModel:(id)model {
    %orig;
    if ([VHDManager showDownloadButton]) [self vhd_addLongPress];
}
- (void)configureWithModel:(id)model {
    %orig;
    if ([VHDManager showDownloadButton]) [self vhd_addLongPress];
}

%new - (void)vhd_addLongPress {
    UILongPressGestureRecognizer *existing = (UILongPressGestureRecognizer *)objc_getAssociatedObject(self, @selector(vhd_onLongPress:));
    if (existing) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(vhd_onLongPress:)];
    lp.minimumPressDuration = 0.4;
    objc_setAssociatedObject(self, @selector(vhd_onLongPress:), lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self addGestureRecognizer:lp];
}

%new - (void)vhd_onLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    if (![self.viewController isKindOfClass:%c(AWEAwemeDetailCellViewController)]) return;
    AWEAwemeDetailCellViewController *vc = (AWEAwemeDetailCellViewController *)self.viewController;

    NSString *desc = vc.model.music_songName ?: @"TikTok";
    TUXActionSheetController *sheet = [[%c(TUXActionSheetController) alloc] initWithTitle:desc];

    if ([VHDManager saveVideoHD]) {
        [sheet addAction:[[%c(TUXActionSheetAction) alloc] initWithStyle:0 title:@"Download video"
                                                                 subtitle:nil image:nil imageLabel:nil
                                                                  handler:^(TUXActionSheetAction *act) {
            NSURL *url = [vc.model.video.playURL bestURLtoDownload];
            self.hudFileext = [vc.model.video.playURL bestURLtoDownloadFormat];
            if (!url) return;
            VHDDownload *dw = [VHDDownload new]; dw.delegate = self;
            self.hudDownloader = dw;
            [dw downloadFileWithURL:url];
        }]];
    }

    [sheet setDismissOnDraggingDown:YES];
    [self.viewController presentViewController:sheet animated:YES completion:nil];
}

%new - (void)vhdDownloadProgress:(float)p {}
%new - (void)vhdDownloadDidFinish:(NSURL *)filePath filename:(NSString *)fileName {
    [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
        [PHAssetCreationRequest.creationRequestForAssetFromVideoAtFileURL fileURL];
    } completionHandler:^(BOOL ok, NSError *err) {
        [[NSFileManager defaultManager] removeItemAtURL:filePath error:nil];
        if (ok) [%c(AWEToast) showSuccess:@"Saved"];
    }];
    self.hudDownloader = nil;
}
%new - (void)vhdDownloadDidFailureWithError:(NSError *)error { self.hudDownloader = nil; }
%end

#pragma mark - Photo album cells
%hook TTKPhotoAlbumFeedCellController
- (void)viewDidLoad {
    %orig;
    if ([VHDManager showDownloadButton]) {
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(vhd_albumLongPress:)];
        lp.minimumPressDuration = 0.4;
        [self.view addGestureRecognizer:lp];
    }
}

%new - (void)vhd_albumLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    NSArray *photos = self.model.photoAlbum.photos;
    if (![photos isKindOfClass:[NSArray class]] || photos.count == 0) return;
    AWEPhotoAlbumPhoto *first = photos.firstObject;
    if (![first isKindOfClass:[AWEPhotoAlbumPhoto class]]) return;
    NSArray *urls = first.originPhotoURL;
    NSString *urlStr = [urls isKindOfClass:[NSArray class]] ? urls.firstObject : nil;
    if (![urlStr isKindOfClass:[NSString class]]) return;
    NSURL *url = [NSURL URLWithString:vhd_cleanURL(urlStr)];
    if (!url) return;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!data) return;
        UIImage *img = [UIImage imageWithData:data];
        if ([VHDManager removeWatermark]) img = vhd_cropWatermark(img);
        if (!img) return;
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.jpg", NSUUID.UUID.UUIDString]];
        NSData *jpeg = UIImageJPEGRepresentation(img, 0.95);
        [jpeg writeToFile:tmp atomically:YES];
        NSURL *tmpURL = [NSURL fileURLWithPath:tmp];
        [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
            [PHAssetCreationRequest creationRequestForAssetFromImageAtFileURL:tmpURL];
        } completionHandler:^(BOOL ok, NSError *err) {
            [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
            if (ok) [%c(AWEToast) showSuccess:@"Saved"];
        }];
    }];
    [task resume];
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