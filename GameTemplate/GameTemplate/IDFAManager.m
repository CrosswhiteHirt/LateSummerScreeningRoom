#import "IDFAManager.h"
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>

@implementation IDFAManager

+ (instancetype)shared {
    static IDFAManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [IDFAManager new]; });
    return instance;
}

- (void)requestIDFAWithCompletion:(IDFACompletionHandler)completion {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (@available(iOS 14.0, *)) {
            [ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(ATTrackingManagerAuthorizationStatus status) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (status == ATTrackingManagerAuthorizationStatusAuthorized) {
                        completion(ASIdentifierManager.sharedManager.advertisingIdentifier.UUIDString);
                    } else {
                        completion(nil);
                    }
                });
            }];
        } else {
            completion(ASIdentifierManager.sharedManager.isAdvertisingTrackingEnabled
                       ? ASIdentifierManager.sharedManager.advertisingIdentifier.UUIDString : nil);
        }
    });
}

@end
