#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^IDFACompletionHandler)(NSString * _Nullable idfa);

@interface IDFAManager : NSObject
+ (instancetype)shared;
- (void)requestIDFAWithCompletion:(IDFACompletionHandler)completion;
@end

NS_ASSUME_NONNULL_END
