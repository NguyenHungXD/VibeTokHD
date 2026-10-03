#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol VHDDownloadDelegate <NSObject>
@optional
- (void)vhdDownloadProgress:(float)progress;
- (void)vhdDownloadDidFinish:(NSURL *)filePath filename:(NSString *)fileName;
- (void)vhdDownloadDidFailureWithError:(NSError *)error;
@end

@interface VHDDownload : NSObject <NSURLSessionDownloadDelegate>
@property (nonatomic, weak) id delegate;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy) NSString *fileName;
- (void)downloadFileWithURL:(NSURL *)url;
@end

NS_ASSUME_NONNULL_END