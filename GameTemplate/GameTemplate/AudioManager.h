#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioManager : NSObject
+ (instancetype)shared;
@property (nonatomic) float musicVolume;
@property (nonatomic) float effectsVolume;
- (void)playMusicNamed:(NSString *)name;
- (void)playMusicNamed:(NSString *)name looping:(BOOL)looping;
- (void)playEffectNamed:(NSString *)name;
- (void)pause;
- (void)resume;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
