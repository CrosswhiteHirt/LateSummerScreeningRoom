#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RewardedAdResult) {
    RewardedAdResultCompleted,
    RewardedAdResultUserClosed,
    RewardedAdResultUnavailable,
    RewardedAdResultFailed
};

@interface AdManager : NSObject
+ (instancetype)shared;
/// Fetches dynamic ad configuration and initializes the providers, matching the
/// supplied starter template. Safe to call more than once.
- (void)setup;
/// Called after a player explicitly confirms a rewind.
- (void)requestRewardedAdWithCompletion:(void (^)(RewardedAdResult result))completion;
@end

NS_ASSUME_NONNULL_END
