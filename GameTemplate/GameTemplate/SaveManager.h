#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SaveManager : NSObject
+ (instancetype)shared;
- (nullable NSDictionary *)autosave;
- (nullable NSDictionary *)manualSave;
- (void)writeAutosave:(NSDictionary *)payload;
- (void)writeManualSave:(NSDictionary *)payload;
- (BOOL)hasSave;
- (BOOL)shouldStartFresh;
- (void)setShouldStartFresh:(BOOL)shouldStartFresh;
- (void)unlockEnding:(NSString *)endingID;
- (NSSet<NSString *> *)unlockedEndings;
@end

NS_ASSUME_NONNULL_END
