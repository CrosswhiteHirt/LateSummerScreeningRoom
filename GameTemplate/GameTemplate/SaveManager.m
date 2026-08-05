#import "SaveManager.h"

static NSString * const kAutosaveKey = @"LateSummerAutosaveV2";
static NSString * const kManualSaveKey = @"LateSummerManualSaveV2";
static NSString * const kEndingsKey = @"LateSummerUnlockedEndingsV2";
static NSString * const kShouldStartFreshKey = @"LateSummerShouldStartFreshV2";

@implementation SaveManager

+ (instancetype)shared {
    static SaveManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [SaveManager new]; });
    return manager;
}

- (NSDictionary *)dictionaryForKey:(NSString *)key {
    NSData *data = [[NSUserDefaults standardUserDefaults] dataForKey:key];
    if (!data) { return nil; }
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

- (void)writePayload:(NSDictionary *)payload key:(NSString *)key {
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (data) { [[NSUserDefaults standardUserDefaults] setObject:data forKey:key]; }
}

- (NSDictionary *)autosave { return [self dictionaryForKey:kAutosaveKey]; }
- (NSDictionary *)manualSave { return [self dictionaryForKey:kManualSaveKey]; }
- (void)writeAutosave:(NSDictionary *)payload { [self writePayload:payload key:kAutosaveKey]; }
- (void)writeManualSave:(NSDictionary *)payload { [self writePayload:payload key:kManualSaveKey]; }
- (BOOL)hasSave { return self.autosave != nil || self.manualSave != nil; }
- (BOOL)shouldStartFresh { return [[NSUserDefaults standardUserDefaults] boolForKey:kShouldStartFreshKey]; }
- (void)setShouldStartFresh:(BOOL)shouldStartFresh {
    [[NSUserDefaults standardUserDefaults] setBool:shouldStartFresh forKey:kShouldStartFreshKey];
}

- (void)unlockEnding:(NSString *)endingID {
    if (endingID.length == 0) { return; }
    NSMutableSet *endings = [self.unlockedEndings mutableCopy];
    [endings addObject:endingID];
    [[NSUserDefaults standardUserDefaults] setObject:endings.allObjects forKey:kEndingsKey];
}

- (NSSet<NSString *> *)unlockedEndings {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kEndingsKey] ?: @[];
    return [NSSet setWithArray:saved];
}

@end
