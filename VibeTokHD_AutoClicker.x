// VibeTokHD_AutoClicker.x
// Popup Autoclick + Auto Swipe như Autoclicker Pro / Click Assistant
//
// Features:
//  - Floating control panel (nút nổi, kéo thả)
//  - Auto swipe (lên/xuống/trai/phải) với interval & loop
//  - Auto click tại điểm bất kỳ (touch synthesized)
//  - Random delay để chống detection
//  - Lưu/tải profile macro qua NSUserDefaults
//  - Activation gesture: 3-finger tap để hiện panel

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>

// ============================================================================
// CONFIG
// ============================================================================
#define VHD_AC_ENABLED 1
#define VHD_AC_FLOATING_PANEL 1
#define VHD_AC_AUTO_SWIPE 1
#define VHD_AC_AUTO_CLICK 1
#define VHD_AC_RANDOM_DELAY 1
#define VHD_AC_SAVE_PROFILE 1
#define VHD_AC_ACTIVATION_GESTURE 1

// Logs
static void vhd_ac_log(NSString *fmt, ...) {
#if 1
    va_list args;
    va_start(args, fmt);
    NSLog(@"[VHD-AC] %@", [NSString stringWithFormat:fmt, args]);
    va_end(args);
#endif
}

// UserDefaults keys
static NSString *const kVHD_AC_Enabled        = @"VHD_AC_Enabled";
static NSString *const kVHD_AC_SwipeEnabled   = @"VHD_AC_SwipeEnabled";
static NSString *const kVHD_AC_ClickEnabled   = @"VHD_AC_ClickEnabled";
static NSString *const kVHD_AC_SwipeDir       = @"VHD_AC_SwipeDir";        // 0=up,2=down,1=left,3=right
static NSString *const kVHD_AC_SwipeMinMs     = @"VHD_AC_SwipeMinMs";      // min interval
static NSString *const kVHD_AC_SwipeMaxMs     = @"VHD_AC_SwipeMaxMs";      // max interval
static NSString *const kVHD_AC_LoopCount      = @"VHD_AC_LoopCount";       // 0=infinite
static NSString *const kVHD_AC_ClickPoints    = @"VHD_AC_ClickPoints";     // NSArray of @{x,y,interval}
static NSString *const kVHD_AC_ActivationType = @"VHD_AC_ActivationType";  // 0=panel button, 1=3-finger, 2=3-tap

// ============================================================================
// Feed Tracker - watches TikTok's feed API calls to detect "no more videos"
// (Must be declared BEFORE AutoSwipeEngine uses it)
// ============================================================================
@interface VHDFeedTracker : NSObject
@property (nonatomic, assign) NSInteger recentFeedRequests;
@property (nonatomic, assign) NSInteger swipesSinceLastRequest;
@property (nonatomic, assign) NSInteger totalFeedRequests;
@property (nonatomic, copy)   NSDate *lastFeedRequestTime;
- (BOOL)noNewContentSinceLastN;
+ (instancetype)shared;
- (void)recordFeedRequest:(NSString *)url;
@end

// Minimal forward declaration of VHDFloatingPanel with just the method we need
// (Full @interface follows later in this file)
@interface VHDFloatingPanel (Forward)
+ (instancetype)shared;
- (void)onFeedExhausted;
@end

@implementation VHDFeedTracker
+ (instancetype)shared {
    static VHDFeedTracker *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [VHDFeedTracker new]; });
    return s;
}
- (void)recordFeedRequest:(NSString *)url {
    self.recentFeedRequests++;
    self.totalFeedRequests++;
    self.lastFeedRequestTime = [NSDate date];
    self.swipesSinceLastRequest = 0;
    vhd_ac_log(@"Feed API request: %@ (total %ld)", url, (long)self.totalFeedRequests);
}
- (BOOL)noNewContentSinceLastN {
    return self.swipesSinceLastRequest > 5 && self.totalFeedRequests > 0;
}
@end

// ============================================================================
// AutoSwipe Engine
// ============================================================================
@interface VHDAutoSwipeEngine : NSObject
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) NSInteger direction;   // 0=up, 1=left, 2=down, 3=right
@property (nonatomic, assign) NSTimeInterval minMs;
@property (nonatomic, assign) NSTimeInterval maxMs;
@property (nonatomic, assign) NSInteger loopCount;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) NSInteger currentLoop;

// Auto-stop when feed exhausted
@property (nonatomic, assign) BOOL stopWhenFeedEnds;
@property (nonatomic, assign) NSInteger noChangeCount;       // consecutive swipes without UI change
@property (nonatomic, assign) NSInteger totalSwipes;
@property (nonatomic, assign) NSTimeInterval lastSwipeTime;
@property (nonatomic, copy)   NSString *lastScreenHash;
@property (nonatomic, assign) BOOL feedExhausted;

+ (instancetype)shared;
- (void)start;
- (void)stop;
- (void)performSwipe;
- (NSString *)screenSnapshotHash;
- (void)checkFeedEndWithBefore:(NSString *)beforeHash;
@end

@implementation VHDAutoSwipeEngine
+ (instancetype)shared {
    static VHDAutoSwipeEngine *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [VHDAutoSwipeEngine new]; });
    return s;
}

- (void)start {
    [self stop];
    self.enabled = YES;
    self.currentLoop = 0;
    self.noChangeCount = 0;
    self.totalSwipes = 0;
    self.feedExhausted = NO;
    [VHDFeedTracker shared].swipesSinceLastRequest = 0;
    NSTimeInterval delay = [self nextDelay];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:delay
                                                   target:self
                                                 selector:@selector(performSwipe)
                                                 userInfo:nil
                                                  repeats:YES];
    vhd_ac_log(@"Swipe started (dir=%ld, %.0f-%.0fms, loop=%ld, stopOnEnd=%@)",
        (long)self.direction, self.minMs, self.maxMs,
        (long)self.loopCount, self.stopWhenFeedEnds ? @"YES" : @"NO");
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
    self.enabled = NO;
    vhd_ac_log(@"Swipe stopped after %ld swipes", (long)self.totalSwipes);
}

- (NSTimeInterval)nextDelay {
    if (self.minMs >= self.maxMs) return self.minMs / 1000.0;
#if VHD_AC_RANDOM_DELAY
    return (self.minMs + arc4random_uniform((uint32_t)(self.maxMs - self.minMs))) / 1000.0;
#else
    return self.minMs / 1000.0;
#endif
}

// =========================================================================
// Feed End Detection - 4 strategies combined
// =========================================================================

// Strategy 1: Screen hash comparison
// If 3 consecutive swipes produce the same screen hash, we're stuck (no more videos)
- (NSString *)screenSnapshotHash {
    // Get root view of key window + visible text labels
    UIWindow *window = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { window = w; break; }
            }
        }
        if (window) break;
    }
    if (!window) return @"";

    // Hash: collect visible labels + button states + view count
    NSMutableString *sig = [NSMutableString string];
    [self collectLabelsFromView:window signature:sig depth:0];

    // Also include top VC class name
    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    [sig appendFormat:@"|root=%@", NSStringFromClass([root class])];

    return [self md5:sig];
}

- (void)collectLabelsFromView:(UIView *)view signature:(NSMutableString *)sig depth:(int)d {
    if (d > 8) return;  // limit depth
    if (![view isKindOfClass:[UIView class]]) return;

    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UILabel class]]) {
            UILabel *l = (UILabel *)sub;
            if (l.text.length > 0 && l.text.length < 200 && l.isHidden == NO) {
                [sig appendFormat:@"L:%@;", l.text];
            }
        } else if ([sub isKindOfClass:[UIButton class]]) {
            UIButton *b = (UIButton *)sub;
            NSString *title = b.currentTitle ?: @"";
            [sig appendFormat:@"B:%@:%ld;", title, (long)b.state];
        }
        [self collectLabelsFromView:sub signature:sig depth:d+1];
    }
}

- (NSString *)md5:(NSString *)s {
    if (!s) return @"";
    const char *cstr = [s UTF8String];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(cstr, (CC_LONG)strlen(cstr), digest);
    NSMutableString *out = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [out appendFormat:@"%02x", digest[i]];
    }
    // Truncate to 32 chars for storage efficiency
    return [out substringToIndex:MIN(32, (int)[out length])];
}

// Strategy 2: View hierarchy snapshot
// Capture view tree signature before/after swipe
- (BOOL)viewTreeChanged:(NSString *)beforeHash {
    NSString *afterHash = [self screenSnapshotHash];
    return ![afterHash isEqualToString:beforeHash];
}

// Strategy 3: Try to detect "no more videos" UI elements
- (BOOL)detectEndIndicators {
    // Look for specific labels that TikTok shows at end of feed
    static NSArray<NSString *> *endKeywords = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        endKeywords = @[
            @"No more videos",
            @"You're all caught up",
            @"You've seen all",
            @"That's everything",
            @"Đã xem hết",
            @"Hết video",
            @"Bạn đã xem hết",
            @"No more content",
            @"End of feed",
            @"đã xem hết video",
            @"hết video rồi"
        ];
    });

    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (![window isKeyWindow]) continue;
        if ([self findLabelContaining:window keywords:endKeywords]) {
            vhd_ac_log(@"End-of-feed indicator detected");
            return YES;
        }
    }
    return NO;
}

- (BOOL)findLabelContaining:(UIView *)view keywords:(NSArray *)kws {
    if ([view isKindOfClass:[UILabel class]]) {
        NSString *txt = [(UILabel *)view text] ?: @"";
        for (NSString *kw in kws) {
            if ([txt rangeOfString:kw options:NSCaseInsensitiveSearch].location != NSNotFound) {
                return YES;
            }
        }
    }
    for (UIView *sub in view.subviews) {
        if ([self findLabelContaining:sub keywords:kws]) return YES;
    }
    return NO;
}

// Strategy 4: Network call detection (best, but requires hooking NSURLSession)
// We'll add a hook later - placeholder here
- (BOOL)detectNoNewContentRequest {
    // If hook hasn't received new feed request in last N swipes, assume exhausted
    // This is updated by VHDFeedTracker (defined later)
    return [[VHDFeedTracker shared] noNewContentSinceLastN];
}

// =========================================================================

- (void)performSwipe {
    if (self.loopCount > 0 && self.currentLoop >= self.loopCount) {
        [self stop];
        return;
    }
    self.currentLoop++;

    // Capture before
    NSString *beforeHash = [self screenSnapshotHash];

    // Synthesize swipe via UIApplication sendAction
    UIWindow *window = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { window = w; break; }
            }
        }
        if (window) break;
    }
    if (!window) return;

    CGRect bounds = window.bounds;
    CGPoint start, end;

    switch (self.direction) {
        case 0: // up
            start = CGPointMake(bounds.size.width/2, bounds.size.height * 0.75);
            end   = CGPointMake(bounds.size.width/2, bounds.size.height * 0.25);
            break;
        case 1: // left
            start = CGPointMake(bounds.size.width * 0.85, bounds.size.height/2);
            end   = CGPointMake(bounds.size.width * 0.15, bounds.size.height/2);
            break;
        case 2: // down
            start = CGPointMake(bounds.size.width/2, bounds.size.height * 0.25);
            end   = CGPointMake(bounds.size.width/2, bounds.size.height * 0.75);
            break;
        case 3: // right
            start = CGPointMake(bounds.size.width * 0.15, bounds.size.height/2);
            end   = CGPointMake(bounds.size.width * 0.85, bounds.size.height/2);
            break;
        default:
            start = CGPointMake(bounds.size.width/2, bounds.size.height * 0.75);
            end   = CGPointMake(bounds.size.width/2, bounds.size.height * 0.25);
    }

    [self synthesizeSwipeFrom:start to:end in:window];
    self.totalSwipes++;
    [VHDFeedTracker shared].swipesSinceLastRequest++;
    vhd_ac_log(@"Swipe %ld: (%.0f,%.0f)→(%.0f,%.0f)",
        (long)self.totalSwipes, start.x, start.y, end.x, end.y);

    // Check feed end after short delay (let UI settle)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.6 * NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{
        [self checkFeedEndWithBefore:beforeHash];
    });

    // Reschedule with new random delay
    [self.timer invalidate];
    NSTimeInterval next = [self nextDelay];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:next
                                                   target:self
                                                 selector:@selector(performSwipe)
                                                 userInfo:nil
                                                  repeats:YES];
}

- (void)checkFeedEndWithBefore:(NSString *)beforeHash {
    if (!self.enabled || !self.stopWhenFeedEnds) return;

    BOOL changed = [self viewTreeChanged:beforeHash];

    // Strategy 1: same hash N times in a row = stuck
    if (!changed) {
        self.noChangeCount++;
        vhd_ac_log(@"No UI change detected (%ld/3)", (long)self.noChangeCount);
        if (self.noChangeCount >= 3) {
            [self onFeedExhausted:@"Same UI after 3 swipes"];
            return;
        }
    } else {
        self.noChangeCount = 0;
    }

    // Strategy 3: explicit end-of-feed UI
    if ([self detectEndIndicators]) {
        [self onFeedExhausted:@"End-of-feed UI detected"];
        return;
    }

    // Strategy 4: no new feed request in last N swipes
    if ([self detectNoNewContentRequest] && self.totalSwipes > 10) {
        [self onFeedExhausted:@"No new feed request from server"];
        return;
    }
}

- (void)onFeedExhausted:(NSString *)reason {
    if (self.feedExhausted) return;
    self.feedExhausted = YES;
    vhd_ac_log(@"🔥 FEED EXHAUSTED: %@ (total swipes: %ld)", reason, (long)self.totalSwipes);
    [self stop];
    [[VHDFloatingPanel shared] onFeedExhausted];
}

- (void)synthesizeSwipeFrom:(CGPoint)from to:(CGPoint)to in:(UIWindow *)window {
    // Use CGEventCreateMouseEvent via private API - safer: use UIWindow sendEvent
    UITouch *touch = [self fakeTouchAt:from phase:UITouchPhaseBegan in:window];
    [self dispatchTouch:touch phase:UITouchPhaseBegan at:from in:window];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.05 * NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{
        [self dispatchTouch:touch phase:UITouchPhaseMoved at:to in:window];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.05 * NSEC_PER_SEC),
            dispatch_get_main_queue(), ^{
            [self dispatchTouch:touch phase:UITouchPhaseEnded at:to in:window];
        });
    });
}

- (UITouch *)fakeTouchAt:(CGPoint)point phase:(UITouchPhase)phase in:(UIWindow *)window {
    UITouch *touch = [UITouch new];
    [touch setValue:window forKey:@"_window"];
    [touch setValue:@(phase) forKey:@"_phase"];
    [touch setValue:@(0) forKey:@"_tapCount"];
    [touch setValue:[NSDate date] forKey:@"_timestamp"];
    CGPoint loc = [window convertPoint:point fromView:nil];
    [touch setValue:[NSValue valueWithBytes:&loc objCType:@encode(CGPoint)] forKey:@"_locationInWindow"];
    return touch;
}

- (void)dispatchTouch:(UITouch *)touch phase:(UITouchPhase)phase at:(CGPoint)point in:(UIWindow *)window {
    [touch setValue:@(phase) forKey:@"_phase"];
    CGPoint loc = [window convertPoint:point fromView:nil];
    [touch setValue:[NSValue valueWithBytes:&loc objCType:@encode(CGPoint)] forKey:@"_locationInWindow"];

    UIEvent *event = [UIEvent new];
    [event setValue:window forKey:@"_keyWindow"];

    NSSet *touches = [NSSet setWithObject:touch];
    [event setValue:touches forKey:@"_touchesEvent"];

    [window sendEvent:event];
}
@end

// (VHDFeedTracker moved to top - see line ~55)

// ============================================================================
// AutoClick Engine
// ============================================================================
@interface VHDAutoClickEngine : NSObject
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *points;  // {x,y,intervalMs}
@property (nonatomic, strong) NSMutableArray<NSTimer *> *timers;
@property (nonatomic, assign) BOOL enabled;

+ (instancetype)shared;
- (void)start;
- (void)stop;
- (void)reloadPoints;
@end

@implementation VHDAutoClickEngine
+ (instancetype)shared {
    static VHDAutoClickEngine *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [VHDAutoClickEngine new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _points = [NSMutableArray array];
        _timers = [NSMutableArray array];
    }
    return self;
}

- (void)reloadPoints {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kVHD_AC_ClickPoints];
    [self.points removeAllObjects];
    if ([saved isKindOfClass:[NSArray class]]) {
        for (NSDictionary *p in saved) {
            if ([p isKindOfClass:[NSDictionary class]]) {
                [self.points addObject:p];
            }
        }
    }
}

- (void)start {
    [self stop];
    [self reloadPoints];
    if (self.points.count == 0) {
        vhd_ac_log(@"No click points set");
        return;
    }
    self.enabled = YES;
    for (NSDictionary *p in self.points) {
        CGFloat x = [p[@"x"] floatValue];
        CGFloat y = [p[@"y"] floatValue];
        NSTimeInterval ms = [p[@"interval"] doubleValue];
        if (ms <= 0) ms = 1000;

        NSTimer *t = [NSTimer scheduledTimerWithTimeInterval:ms / 1000.0
                                                        target:self
                                                      selector:@selector(performClick)
                                                      userInfo:@{@"x":@(x),@"y":@(y)}
                                                       repeats:YES];
        [self.timers addObject:t];
    }
    vhd_ac_log(@"Click started: %lu points", (unsigned long)self.points.count);
}

- (void)stop {
    for (NSTimer *t in self.timers) [t invalidate];
    [self.timers removeAllObjects];
    self.enabled = NO;
    vhd_ac_log(@"Click stopped");
}

- (void)performClick {
    UIWindow *window = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { window = w; break; }
            }
        }
        if (window) break;
    }
    if (!window) return;

    CGPoint point = CGPointMake(0, 0);
    // Get caller info
    NSDictionary *info = nil;
    // Use current invocation
    UIWindow *target = window;
    CGFloat screenScale = target.screen.scale;
    CGFloat pxX = 0, pxY = 0;
    for (NSTimer *t in self.timers) {
        if ([t isValid]) {
            // Just use first timer info for now
        }
    }
    // We don't have direct access to timer userInfo from here, so use a simpler approach
    // Iterate stored points sequentially
    static NSInteger idx = 0;
    if (self.points.count > 0) {
        NSDictionary *p = self.points[idx % self.points.count];
        idx++;
        pxX = [p[@"x"] floatValue];
        pxY = [p[@"y"] floatValue];
    } else return;

    CGPoint pt = CGPointMake(pxX, pxY);
    UITouch *touch = [UITouch new];
    [touch setValue:target forKey:@"_window"];
    [touch setValue:@(UITouchPhaseBegan) forKey:@"_phase"];
    [touch setValue:@(1) forKey:@"_tapCount"];
    [touch setValue:[NSDate date] forKey:@"_timestamp"];
    CGPoint loc = [target convertPoint:pt fromView:nil];
    [touch setValue:[NSValue valueWithBytes:&loc objCType:@encode(CGPoint)] forKey:@"_locationInWindow"];

    UIEvent *event = [UIEvent new];
    [event setValue:target forKey:@"_keyWindow"];
    NSSet *touches = [NSSet setWithObject:touch];
    [event setValue:touches forKey:@"_touchesEvent"];
    [target sendEvent:event];

    // End immediately
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.02 * NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{
        [touch setValue:@(UITouchPhaseEnded) forKey:@"_phase"];
        [target sendEvent:event];
    });
    vhd_ac_log(@"Click at (%.0f,%.0f)", pt.x, pt.y);
}
@end

// ============================================================================
// Floating Control Panel (UIWindow riêng, level cao nhất)
// ============================================================================
@interface VHDFloatingPanel : UIWindow
@property (nonatomic, strong) UIButton *mainButton;
@property (nonatomic, strong) UIView *panelView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *swipeBtn, *clickBtn;
@property (nonatomic, strong) UISegmentedControl *dirControl;
@property (nonatomic, strong) UITextField *minField, *maxField, *loopField;
@property (nonatomic, strong) UIButton *addPointBtn;
@property (nonatomic, strong) UISwitch *stopOnEndSwitch;
@property (nonatomic, strong) UILabel *stopOnEndLabel;
@property (nonatomic, assign) CGPoint panelTouchOffset;
- (void)onFeedExhausted;
- (void)recTap; // dummy for associated object key
@end

@implementation VHDFloatingPanel

+ (instancetype)shared {
    static VHDFloatingPanel *s; static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[VHDFloatingPanel alloc] initWithFrame:CGRectMake([UIScreen mainScreen].bounds.size.width - 60, 100, 50, 50)];
        s.backgroundColor = [UIColor clearColor];
        s.windowLevel = UIWindowLevelAlert + 100;
    });
    return s;
}

// Dummy implementation for @selector(recTap) used as associated object key
- (void)recTap {}

- (void)show {
    if (self.hidden) {
        self.hidden = NO;
        [self buildUI];
    }
}

- (void)hide {
    self.hidden = YES;
}

- (void)toggle {
    if (self.hidden) [self show]; else [self hide];
}

- (void)buildUI {
    [self.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    // Main floating button
    self.mainButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.mainButton.frame = self.bounds;
    self.mainButton.layer.cornerRadius = 25;
    self.mainButton.backgroundColor = [UIColor systemPinkColor];
    [self.mainButton setTitle:@"⚡" forState:UIControlStateNormal];
    [self.mainButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.mainButton.titleLabel.font = [UIFont systemFontOfSize:24];
    [self.mainButton addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.mainButton];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    [self.mainButton addGestureRecognizer:pan];

    // Panel (initially hidden)
    self.panelView = [[UIView alloc] initWithFrame:CGRectMake(20, [UIScreen mainScreen].bounds.size.height - 320, [UIScreen mainScreen].bounds.size.width - 40, 280)];
    self.panelView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    self.panelView.layer.cornerRadius = 14;
    self.panelView.hidden = YES;
    [self addSubview:self.panelView];

    [self buildPanelContent];
}

- (void)buildPanelContent {
    UIView *p = self.panelView;
    CGFloat y = 12;
    UILabel *title = [UILabel new];
    title.text = @"VibeTokHD Auto Controller";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:14];
    title.frame = CGRectMake(12, y, p.bounds.size.width - 24, 20);
    [p addSubview:title];
    y += 30;

    // Status
    self.statusLabel = [UILabel new];
    self.statusLabel.text = @"Idle";
    self.statusLabel.textColor = [UIColor systemGreenColor];
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.frame = CGRectMake(12, y, p.bounds.size.width - 24, 18);
    [p addSubview:self.statusLabel];
    y += 24;

    // Direction
    self.dirControl = [[UISegmentedControl alloc] initWithItems:@[@"↑", @"←", @"↓", @"→"]];
    self.dirControl.selectedSegmentIndex = 0;
    self.dirControl.frame = CGRectMake(12, y, 220, 28);
    [self.dirControl addTarget:self action:@selector(directionChanged) forControlEvents:UIControlEventValueChanged];
    [p addSubview:self.dirControl];
    y += 36;

    // Interval min/max
    UILabel *minL = [UILabel new]; minL.text = @"Min ms"; minL.textColor = [UIColor whiteColor];
    minL.font = [UIFont systemFontOfSize:11]; minL.frame = CGRectMake(12, y, 50, 20);
    [p addSubview:minL];
    self.minField = [UITextField new];
    self.minField.text = @"800";
    self.minField.borderStyle = UITextBorderStyleRoundedRect;
    self.minField.textColor = [UIColor whiteColor];
    self.minField.keyboardType = UIKeyboardTypeNumberPad;
    self.minField.frame = CGRectMake(12, y + 22, 80, 28);
    [p addSubview:self.minField];

    UILabel *maxL = [UILabel new]; maxL.text = @"Max ms"; maxL.textColor = [UIColor whiteColor];
    maxL.font = [UIFont systemFontOfSize:11]; maxL.frame = CGRectMake(110, y, 50, 20);
    [p addSubview:maxL];
    self.maxField = [UITextField new];
    self.maxField.text = @"1500";
    self.maxField.borderStyle = UITextBorderStyleRoundedRect;
    self.maxField.textColor = [UIColor whiteColor];
    self.maxField.keyboardType = UIKeyboardTypeNumberPad;
    self.maxField.frame = CGRectMake(110, y + 22, 80, 28);
    [p addSubview:self.maxField];

    UILabel *loopL = [UILabel new]; loopL.text = @"Loop (0=∞)"; loopL.textColor = [UIColor whiteColor];
    loopL.font = [UIFont systemFontOfSize:11]; loopL.frame = CGRectMake(208, y, 100, 20);
    [p addSubview:loopL];
    self.loopField = [UITextField new];
    self.loopField.text = @"0";
    self.loopField.borderStyle = UITextBorderStyleRoundedRect;
    self.loopField.textColor = [UIColor whiteColor];
    self.loopField.keyboardType = UIKeyboardTypeNumberPad;
    self.loopField.frame = CGRectMake(208, y + 22, 80, 28);
    [p addSubview:self.loopField];
    y += 60;

    // Buttons
    self.swipeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.swipeBtn.frame = CGRectMake(12, y, 130, 36);
    self.swipeBtn.layer.cornerRadius = 8;
    self.swipeBtn.backgroundColor = [UIColor systemBlueColor];
    [self.swipeBtn setTitle:@"Start Swipe" forState:UIControlStateNormal];
    [self.swipeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.swipeBtn addTarget:self action:@selector(toggleSwipe) forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:self.swipeBtn];

    self.clickBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.clickBtn.frame = CGRectMake(150, y, 130, 36);
    self.clickBtn.layer.cornerRadius = 8;
    self.clickBtn.backgroundColor = [UIColor systemOrangeColor];
    [self.clickBtn setTitle:@"Start Click" forState:UIControlStateNormal];
    [self.clickBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.clickBtn addTarget:self action:@selector(toggleClick) forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:self.clickBtn];
    y += 46;

    // "Stop when feed ends" switch
    self.stopOnEndLabel = [UILabel new];
    self.stopOnEndLabel.text = @"Dừng khi hết video";
    self.stopOnEndLabel.textColor = [UIColor whiteColor];
    self.stopOnEndLabel.font = [UIFont systemFontOfSize:13];
    self.stopOnEndLabel.frame = CGRectMake(12, y, 200, 20);
    [p addSubview:self.stopOnEndLabel];

    self.stopOnEndSwitch = [UISwitch new];
    self.stopOnEndSwitch.on = YES;
    self.stopOnEndSwitch.frame = CGRectMake(p.bounds.size.width - 64, y - 4, 0, 0);
    [p addSubview:self.stopOnEndSwitch];
    y += 28;

    self.addPointBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.addPointBtn.frame = CGRectMake(12, y, p.bounds.size.width - 24, 32);
    self.addPointBtn.layer.cornerRadius = 8;
    self.addPointBtn.backgroundColor = [UIColor systemPurpleColor];
    [self.addPointBtn setTitle:@"+ Add Click Point (next tap)" forState:UIControlStateNormal];
    [self.addPointBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.addPointBtn addTarget:self action:@selector(addClickPoint) forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:self.addPointBtn];
    y += 38;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(12, y, p.bounds.size.width - 24, 28);
    [close setTitle:@"✕ Close Panel" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:13];
    [close addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:close];
}

- (void)directionChanged {
    [[NSUserDefaults standardUserDefaults] setInteger:self.dirControl.selectedSegmentIndex forKey:kVHD_AC_SwipeDir];
}

- (void)togglePanel {
    self.panelView.hidden = !self.panelView.hidden;
    if (!self.panelView.hidden) {
        [self updateStatus];
    }
}

- (void)updateStatus {
    NSString *status = @"Idle";
    if ([VHDAutoSwipeEngine shared].enabled) status = @"Swiping...";
    if ([VHDAutoClickEngine shared].enabled) status = [status stringByAppendingString:@" + Clicking"];
    self.statusLabel.text = status;
}

- (void)toggleSwipe {
    VHDAutoSwipeEngine *e = [VHDAutoSwipeEngine shared];
    if (e.enabled) {
        [e stop];
        [self.swipeBtn setTitle:@"Start Swipe" forState:UIControlStateNormal];
        self.swipeBtn.backgroundColor = [UIColor systemBlueColor];
    } else {
        e.direction = self.dirControl.selectedSegmentIndex;
        e.minMs = [self.minField.text doubleValue];
        e.maxMs = [self.maxField.text doubleValue];
        e.loopCount = [self.loopField.text integerValue];
        e.stopWhenFeedEnds = self.stopOnEndSwitch.isOn;
        if (e.minMs <= 0) e.minMs = 800;
        if (e.maxMs < e.minMs) e.maxMs = e.minMs + 200;
        [e start];
        [self.swipeBtn setTitle:@"Stop Swipe" forState:UIControlStateNormal];
        self.swipeBtn.backgroundColor = [UIColor systemRedColor];
    }
    [self updateStatus];
}

- (void)toggleClick {
    VHDAutoClickEngine *e = [VHDAutoClickEngine shared];
    if (e.enabled) {
        [e stop];
        [self.clickBtn setTitle:@"Start Click" forState:UIControlStateNormal];
        self.clickBtn.backgroundColor = [UIColor systemOrangeColor];
    } else {
        [e start];
        [self.clickBtn setTitle:@"Stop Click" forState:UIControlStateNormal];
        self.clickBtn.backgroundColor = [UIColor systemRedColor];
    }
    [self updateStatus];
}

- (void)addClickPoint {
    self.addPointBtn.enabled = NO;
    [self.addPointBtn setTitle:@"Tap anywhere in app to record..." forState:UIControlStateNormal];
    self.addPointBtn.backgroundColor = [UIColor systemGreenColor];

    // Listen for next tap on main window
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{
        // Add a one-shot gesture recognizer
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) {
                        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
                            initWithTarget:self action:@selector(handleRecordedTap:)];
                        tap.numberOfTapsRequired = 1;
                        tap.cancelsTouchesInView = NO;
                        tap.delaysTouchesBegan = NO;
                        [w addGestureRecognizer:tap];
                        // Save reference to remove later
                        objc_setAssociatedObject(self, @selector(recTap), tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        break;
                    }
                }
                break;
            }
        }
    });
}

- (void)handleRecordedTap:(UITapGestureRecognizer *)gr {
    UITapGestureRecognizer *orig = objc_getAssociatedObject(self, @selector(recTap));
    if (orig) [gr.view removeGestureRecognizer:orig];
    objc_setAssociatedObject(self, @selector(recTap), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    CGPoint pt = [gr locationInView:gr.view];
    NSArray *existing = [[NSUserDefaults standardUserDefaults] arrayForKey:kVHD_AC_ClickPoints];
    NSMutableArray *arr;
    if ([existing isKindOfClass:[NSArray class]]) {
        arr = [existing mutableCopy];
    } else {
        arr = [NSMutableArray array];
    }
    [arr addObject:@{@"x":@(pt.x), @"y":@(pt.y), @"interval":@(1000)}];
    [[NSUserDefaults standardUserDefaults] setObject:arr forKey:kVHD_AC_ClickPoints];

    self.addPointBtn.enabled = YES;
    [self.addPointBtn setTitle:[NSString stringWithFormat:@"+ Added (%.0f,%.0f) - tap again", pt.x, pt.y]
        forState:UIControlStateNormal];
    self.addPointBtn.backgroundColor = [UIColor systemPurpleColor];

    vhd_ac_log(@"Added click point (%.0f,%.0f)", pt.x, pt.y);
}

- (void)handlePan:(UIPanGestureRecognizer *)gr {
    CGPoint translation = [gr translationInView:self];
    if (gr.state == UIGestureRecognizerStateBegan) {
        self.panelTouchOffset = CGPointMake(self.frame.origin.x, self.frame.origin.y);
    }
    self.frame = CGRectMake(
        self.panelTouchOffset.x + translation.x,
        self.panelTouchOffset.y + translation.y,
        self.frame.size.width,
        self.frame.size.height);
}

- (void)onFeedExhausted {
    // Update UI
    self.statusLabel.text = @"🔥 Hết video rồi!";
    self.statusLabel.textColor = [UIColor systemRedColor];
    [self.swipeBtn setTitle:@"Feed hết" forState:UIControlStateNormal];
    self.swipeBtn.backgroundColor = [UIColor darkGrayColor];
    self.swipeBtn.enabled = NO;

    // Show notification banner (optional toast)
    [self showToast:@"🔥 Đã xem hết video - Auto Swipe đã dừng"];

    // Auto close panel after 3s
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3.0 * NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{
        self.swipeBtn.enabled = YES;
        [self.swipeBtn setTitle:@"Start Swipe" forState:UIControlStateNormal];
        self.swipeBtn.backgroundColor = [UIColor systemBlueColor];
        self.statusLabel.text = @"Idle";
        self.statusLabel.textColor = [UIColor systemGreenColor];
    });
}

- (void)showToast:(NSString *)msg {
    UILabel *toast = [UILabel new];
    toast.text = msg;
    toast.textAlignment = NSTextAlignmentCenter;
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    toast.layer.cornerRadius = 8;
    toast.clipsToBounds = YES;
    toast.font = [UIFont systemFontOfSize:13];
    toast.numberOfLines = 0;
    toast.frame = CGRectMake(0, 60, [UIScreen mainScreen].bounds.size.width, 50);
    [self addSubview:toast];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.5 * NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 animations:^{
            toast.alpha = 0;
        } completion:^(BOOL finished) {
            [toast removeFromSuperview];
        }];
    });
}
@end

// ============================================================================
// Activation: 3-finger tap to toggle panel
// ============================================================================
@interface VHDActivationMonitor : NSObject
@end

@implementation VHDActivationMonitor
+ (void)load {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3.0 * NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) {
                        [self installGestureOnWindow:w];
                        return;
                    }
                }
            }
        }
    });
}

+ (void)installGestureOnWindow:(UIWindow *)window {
    UITapGestureRecognizer *tripleFinger = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(tripleFingerTap:)];
    tripleFinger.numberOfTouchesRequired = 3;
    tripleFinger.numberOfTapsRequired = 1;
    tripleFinger.cancelsTouchesInView = NO;
    [window addGestureRecognizer:tripleFinger];

    UITapGestureRecognizer *tripleTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(tripleTap:)];
    tripleTap.numberOfTouchesRequired = 1;
    tripleTap.numberOfTapsRequired = 3;
    tripleTap.cancelsTouchesInView = NO;
    [window addGestureRecognizer:tripleTap];
}

+ (void)tripleFingerTap:(UITapGestureRecognizer *)gr {
    vhd_ac_log(@"3-finger tap activation");
    [[VHDFloatingPanel shared] toggle];
}

+ (void)tripleTap:(UITapGestureRecognizer *)gr {
    vhd_ac_log(@"3-tap activation");
    [[VHDFloatingPanel shared] toggle];
}
@end

// ============================================================================
// Profile Save/Load
// ============================================================================
@interface VHDProfile : NSObject
+ (void)saveToDefaults;
+ (void)loadFromDefaults;
@end

@implementation VHDProfile
+ (void)saveToDefaults {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setInteger:[VHDAutoSwipeEngine shared].direction forKey:kVHD_AC_SwipeDir];
    [d setDouble:[VHDAutoSwipeEngine shared].minMs forKey:kVHD_AC_SwipeMinMs];
    [d setDouble:[VHDAutoSwipeEngine shared].maxMs forKey:kVHD_AC_SwipeMaxMs];
    [d setInteger:[VHDAutoSwipeEngine shared].loopCount forKey:kVHD_AC_LoopCount];
    [d synchronize];
    vhd_ac_log(@"Profile saved");
}

+ (void)loadFromDefaults {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [VHDAutoSwipeEngine shared].direction = [d integerForKey:kVHD_AC_SwipeDir];
    [VHDAutoSwipeEngine shared].minMs = [d doubleForKey:kVHD_AC_SwipeMinMs];
    [VHDAutoSwipeEngine shared].maxMs = [d doubleForKey:kVHD_AC_SwipeMaxMs];
    [VHDAutoSwipeEngine shared].loopCount = [d integerForKey:kVHD_AC_LoopCount];
    vhd_ac_log(@"Profile loaded");
}
@end

// ============================================================================
// Init
// ============================================================================
%ctor {
    NSLog(@"[VHD-AC] ============================================");
    NSLog(@"[VHD-AC] VibeTokHD AutoClicker loaded");
    NSLog(@"[VHD-AC] Activation: 3-finger tap or 3-tap to open panel");
    NSLog(@"[VHD-AC] ============================================");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{
        [VHDProfile loadFromDefaults];
    });
}

// ============================================================================
// HOOK: NSURLSession - watch feed API requests
// ============================================================================
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    NSString *url = request.URL.absoluteString;
    // TikTok feed endpoints - varies by version but usually contains "aweme" or "feed"
    if ([url containsString:@"feed"] || [url containsString:@"aweme"] ||
        [url containsString:@"recommend"] || [url containsString:@"api/item/list"]) {
        [[VHDFeedTracker shared] recordFeedRequest:url];
    }
    return %orig;
}

%end