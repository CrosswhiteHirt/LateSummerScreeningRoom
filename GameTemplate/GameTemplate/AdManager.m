#import "AdManager.h"
#import <UIKit/UIKit.h>
#import <YandexMobileAds/YandexMobileAds-Swift.h>

static NSString * const kAdUnitsAPI = @"https://ad-call.de123.net/app/ad/units";
static NSString * const kTestRewardedUnitID = @"demo-rewarded-yandex";

@interface AdManager () <YMARewardedAdDelegate>
@property (nonatomic, copy) NSString *unitID;
@property (nonatomic) BOOL initialized;
@property (nonatomic) BOOL initializing;
@property (nonatomic) BOOL loading;
@property (nonatomic, strong) YMARewardedAdLoader *loader;
@property (nonatomic, strong) YMARewardedAd *rewardedAd;
@property (nonatomic, strong) YMARewardedAd *presentedRewardedAd;
@property (nonatomic, copy) void (^completion)(RewardedAdResult);
@property (nonatomic, copy) void (^pendingRequestCompletion)(RewardedAdResult);
@property (nonatomic) NSUInteger pendingRequestToken;
@property (nonatomic) BOOL earnedReward;
@property (nonatomic) BOOL rewardedAdWasShown;
@end

@implementation AdManager

+ (instancetype)shared {
    static AdManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [AdManager new]; });
    return manager;
}

- (void)setup {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.unitID) self.unitID = kTestRewardedUnitID;
        if (!self.initialized && !self.initializing) {
            self.initializing = YES;
#if DEBUG
            [YMAYandexAds enableLogging];
#endif
            NSLog(@"[AdSDK] initializing Yandex Mobile Ads, test unit=%@", self.unitID);
            __weak typeof(self) weakSelf = self;
            [YMAYandexAds initializeSDKWithCompletionHandler:^{
                typeof(self) self = weakSelf;
                if (!self) return;
                self.initializing = NO;
                self.initialized = YES;
                NSLog(@"[AdSDK] initialization succeeded, version=%@", [YMAYandexAds sdkVersion].stringValue);
                [self preload];
            }];
        }
        [self fetchRemoteUnit];
    });
}

- (void)fetchRemoteUnit {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"";
    NSString *encoded = [bundleID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?bundleId=%@", kAdUnitsAPI, encoded ?: @""]];
    if (!url) return;
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || data.length == 0) { NSLog(@"[AdSDK] remote config unavailable; keeping test unit: %@", error); return; }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json[@"resultCode"] isKindOfClass:NSNumber.class] || [json[@"resultCode"] integerValue] != 0) return;
        for (NSDictionary *platform in json[@"data"][@"adUnits"]) {
            if (![platform[@"platform"] isEqualToString:@"yandex"]) continue;
            NSString *remoteUnit = [platform[@"adUnits"] firstObject][@"unitId"];
            if (![remoteUnit isKindOfClass:NSString.class] || remoteUnit.length == 0) continue;
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) self = weakSelf;
                if (!self || [self.unitID isEqualToString:remoteUnit]) return;
                self.unitID = remoteUnit; self.rewardedAd = nil;
                NSLog(@"[AdSDK] applied remote rewarded unit: %@", remoteUnit);
                [self preload];
            });
            return;
        }
    }] resume];
}

- (void)preload {
    if (!self.initialized || self.loading || self.rewardedAd || self.unitID.length == 0) return;
    self.loading = YES;
    if (!self.loader) self.loader = [YMARewardedAdLoader new];
    YMAAdRequest *request = [[YMAAdRequest alloc] initWithAdUnitID:self.unitID targeting:nil adTheme:YMAAdThemeUnspecified biddingData:nil headerBiddingData:nil parameters:nil];
    NSLog(@"[AdSDK] loading rewarded ad, unit=%@", self.unitID);
    __weak typeof(self) weakSelf = self;
    [self.loader loadAdWith:request completionHandler:^(YMARewardedAd *ad, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf; if (!self) return;
            self.loading = NO;
            if (error || !ad) {
                NSLog(@"[AdSDK] rewarded load failed: %@", error);
                [self finishPendingRequestWithResult:RewardedAdResultUnavailable];
                return;
            }
            ad.delegate = self; self.rewardedAd = ad;
            NSLog(@"[AdSDK] rewarded ad loaded successfully, unit=%@", self.unitID);
            [self presentPendingRequestIfNeeded];
        });
    }];
}

- (void)presentRewardedAdWithCompletion:(void (^)(RewardedAdResult))completion {
    if (!self.rewardedAd) { if (completion) completion(RewardedAdResultUnavailable); return; }
        UIWindow *window = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                if (candidate.isKeyWindow) { window = candidate; break; }
            }
            if (window) break;
        }
        UIViewController *vc = window.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        if (!vc) { if (completion) completion(RewardedAdResultFailed); return; }
        self.completion = completion;
        self.earnedReward = NO;
        self.rewardedAdWasShown = NO;
        YMARewardedAd *ad = self.rewardedAd; self.rewardedAd = nil;
        // YMARewardedAd.delegate is weak. Keep the presented wrapper alive or
        // the ad UI may remain visible while every lifecycle callback is lost.
        self.presentedRewardedAd = ad;
        [ad showFromViewController:vc];
}

- (void)finishPendingRequestWithResult:(RewardedAdResult)result {
    void (^completion)(RewardedAdResult) = self.pendingRequestCompletion;
    self.pendingRequestCompletion = nil;
    if (completion) completion(result);
}

- (void)presentPendingRequestIfNeeded {
    void (^completion)(RewardedAdResult) = self.pendingRequestCompletion;
    if (!completion || !self.rewardedAd) { return; }
    self.pendingRequestCompletion = nil;
    [self presentRewardedAdWithCompletion:completion];
}

- (void)finishPresentedRequestWithResult:(RewardedAdResult)result {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self finishPresentedRequestWithResult:result]; });
        return;
    }
    void (^completion)(RewardedAdResult) = self.completion;
    self.completion = nil;
    if (completion) completion(result);
}

- (void)requestRewardedAdWithCompletion:(void (^)(RewardedAdResult))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.rewardedAd) { [self presentRewardedAdWithCompletion:completion]; return; }
        // There can only be one full-screen rewarded presentation at once.
        // Finish a superseded request rather than leaving its scene paused.
        [self finishPendingRequestWithResult:RewardedAdResultUnavailable];
        self.pendingRequestCompletion = completion;
        NSUInteger token = ++self.pendingRequestToken;
        [self setup];
        [self preload];
        NSLog(@"[AdSDK] waiting for rewarded ad before rewind");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.pendingRequestToken == token && self.pendingRequestCompletion) {
                NSLog(@"[AdSDK] rewarded ad wait timed out; allowing offline fallback");
                [self finishPendingRequestWithResult:RewardedAdResultUnavailable];
            }
        });
    });
}

- (void)rewardedAd:(YMARewardedAd *)ad didReward:(id<YMAReward>)reward {
    // The SDK can send this while its full-screen view is still presented.
    // Defer the game transition until dismissal so the destination is visible
    // immediately after the player closes the rewarded ad.
    NSLog(@"[AdSDK] reward earned");
    self.earnedReward = YES;
}
- (void)rewardedAdDidShow:(YMARewardedAd *)ad {
    NSLog(@"[AdSDK] rewarded ad shown");
    self.rewardedAdWasShown = YES;
    // The Yandex close callback can be absent for some full-screen creative
    // variants. Commit the pending navigation once the ad is actually on
    // screen; it remains visually covered until the player closes the ad.
    [self finishPresentedRequestWithResult:RewardedAdResultCompleted];
}
- (void)rewardedAdDidClick:(YMARewardedAd *)ad { NSLog(@"[AdSDK] rewarded ad clicked"); }
- (void)rewardedAd:(YMARewardedAd *)ad didTrackImpressionWithData:(id<YMAImpressionData>)data { NSLog(@"[AdSDK] rewarded impression tracked"); }
- (void)rewardedAdDidDismiss:(YMARewardedAd *)ad {
    // Some valid rewarded placements do not invoke didReward consistently.
    // A successfully presented and dismissed ad still unlocks the requested
    // rewind so the player is never stranded on the confirmation overlay.
    [self finishPresentedRequestWithResult:(self.earnedReward || self.rewardedAdWasShown) ? RewardedAdResultCompleted : RewardedAdResultUserClosed];
    self.earnedReward = NO;
    self.rewardedAdWasShown = NO;
    self.presentedRewardedAd = nil;
    [self preload];
}
- (void)rewardedAd:(YMARewardedAd *)ad didFailToShowWithError:(NSError *)error {
    NSLog(@"[AdSDK] show failed: %@", error);
    [self finishPresentedRequestWithResult:RewardedAdResultFailed];
    self.earnedReward = NO;
    self.rewardedAdWasShown = NO;
    self.presentedRewardedAd = nil;
    [self preload];
}
@end
