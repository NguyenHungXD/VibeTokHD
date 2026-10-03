#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface VHDManager : NSObject

// Save without watermark (HD quality)
+ (BOOL)saveVideoHD;
+ (BOOL)savePhotoHD;
+ (BOOL)saveMusicHD;
+ (BOOL)removeWatermark;
+ (BOOL)hideAds;
+ (BOOL)autoPlay;
+ (BOOL)progressBar;

// Display
+ (BOOL)showDownloadButton;
+ (BOOL)copyDescription;
+ (BOOL)copyVideoLink;
+ (BOOL)copyMusicLink;

// Helpers
+ (void)cleanCache;
+ (void)showSaveVC:(id)item;
+ (NSString *)getDownloadingPercent:(float)per;
+ (BOOL)isEmpty:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END