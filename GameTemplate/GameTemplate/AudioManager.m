#import "AudioManager.h"
#import <AVFoundation/AVFoundation.h>

@interface AudioManager ()
@property (nonatomic, strong) AVAudioPlayer *musicPlayer;
@property (nonatomic, strong) AVAudioPlayer *effectsPlayer;
@property (nonatomic, copy) NSString *currentTrack;
@property (nonatomic) BOOL currentTrackLoops;
@end

@implementation AudioManager

+ (instancetype)shared {
    static AudioManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [AudioManager new]; });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        _musicVolume = [defaults objectForKey:@"musicVolume"] ? [defaults floatForKey:@"musicVolume"] : 0.75f;
        _effectsVolume = [defaults objectForKey:@"effectsVolume"] ? [defaults floatForKey:@"effectsVolume"] : 0.8f;
        AVAudioSession *session = AVAudioSession.sharedInstance;
        [session setCategory:AVAudioSessionCategoryAmbient mode:AVAudioSessionModeDefault options:0 error:nil];
        [session setActive:YES error:nil];
    }
    return self;
}

- (void)setMusicVolume:(float)musicVolume {
    _musicVolume = fminf(1, fmaxf(0, musicVolume));
    self.musicPlayer.volume = _musicVolume;
    [NSUserDefaults.standardUserDefaults setFloat:_musicVolume forKey:@"musicVolume"];
}

- (void)setEffectsVolume:(float)effectsVolume {
    _effectsVolume = fminf(1, fmaxf(0, effectsVolume));
    [NSUserDefaults.standardUserDefaults setFloat:_effectsVolume forKey:@"effectsVolume"];
}

- (NSURL *)URLForTrack:(NSString *)name {
    NSArray<NSString *> *folders = @[ @"Resources/Audio/BGM", @"Resources/Audio/Endings", @"Audio/BGM", @"Audio/Endings", @"Resources" ];
    for (NSString *folder in folders) {
        NSURL *url = [NSBundle.mainBundle URLForResource:name withExtension:@"mp3" subdirectory:folder];
        if (url) { return url; }
    }
    return [NSBundle.mainBundle URLForResource:name withExtension:@"mp3"];
}

- (void)playMusicNamed:(NSString *)name {
    [self playMusicNamed:name looping:YES];
}

- (void)playMusicNamed:(NSString *)name looping:(BOOL)looping {
    if (name.length == 0 || ([name isEqualToString:self.currentTrack] && looping == self.currentTrackLoops)) { return; }
    NSURL *url = [self URLForTrack:name];
    if (!url) { return; }
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:nil];
    player.numberOfLoops = looping ? -1 : 0;
    player.volume = 0;
    [player prepareToPlay];
    [player play];
    AVAudioPlayer *oldPlayer = self.musicPlayer;
    self.musicPlayer = player;
    self.currentTrack = name;
    self.currentTrackLoops = looping;
    // AVAudioPlayer's native ramp keeps scene changes cinematic even when UIKit
    // is not animating (for example, while the app is resuming in the background).
    [oldPlayer setVolume:0 fadeDuration:0.65];
    [player setVolume:self.musicVolume fadeDuration:0.72];
    if (oldPlayer) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [oldPlayer stop];
        });
    }
}

- (void)playEffectNamed:(NSString *)name {
    if (name.length == 0 || self.effectsVolume <= 0.001f) { return; }
    NSURL *url = [NSBundle.mainBundle URLForResource:name withExtension:@"wav"];
    if (!url) { return; }
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:nil];
    player.numberOfLoops = 0;
    player.volume = self.effectsVolume;
    [player prepareToPlay];
    self.effectsPlayer = player;
    [player play];
}

- (void)pause { [self.musicPlayer pause]; }
- (void)resume { [self.musicPlayer play]; }
- (void)stop { [self.musicPlayer stop]; self.currentTrack = nil; self.currentTrackLoops = NO; }

@end
