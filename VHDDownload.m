#import "VHDDownload.h"

@implementation VHDDownload

- (instancetype)init {
    self = [super init];
    if (self) {
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                 delegate:self
                                            delegateQueue:[NSOperationQueue mainQueue]];
    }
    return self;
}

- (void)downloadFileWithURL:(NSURL *)url {
    if (!url) {
        return;
    }
    self.fileName = url.absoluteString.lastPathComponent;
    NSURLSessionDownloadTask *task = [self.session downloadTaskWithURL:url];
    [task resume];
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    if (totalBytesExpectedToWrite <= 0) return;
    float progress = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;
    if ([self.delegate respondsToSelector:@selector(vhdDownloadProgress:)]) {
        [self.delegate vhdDownloadProgress:progress];
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *filename = self.fileName ?: [NSString stringWithFormat:@"%@.mp4", NSUUID.UUID.UUIDString];
    NSURL *dest = [[NSURL fileURLWithPath:docs] URLByAppendingPathComponent:filename];
    NSError *err = nil;
    [[NSFileManager defaultManager] moveItemAtURL:location toURL:dest error:&err];
    if ([self.delegate respondsToSelector:@selector(vhdDownloadDidFinish:filename:)]) {
        [self.delegate vhdDownloadDidFinish:dest filename:filename];
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (error && [self.delegate respondsToSelector:@selector(vhdDownloadDidFailureWithError:)]) {
        [self.delegate vhdDownloadDidFailureWithError:error];
    }
}

@end