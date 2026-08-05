#import "GameScene.h"
#import "StoryEngine.h"
#import "SaveManager.h"
#import "AudioManager.h"
#import "AdManager.h"
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, GameScreen) {
    GameScreenTitle,
    GameScreenStory,
    GameScreenGallery,
    GameScreenSettings,
    GameScreenLog,
    GameScreenRewind,
    GameScreenEnding,
    GameScreenCredits
};

@interface GameScene ()
@property (nonatomic) GameScreen screen;
@property (nonatomic, strong) StoryEngine *engine;
@property (nonatomic, strong) SKSpriteNode *backgroundNode;
@property (nonatomic, strong) SKSpriteNode *portraitNode;
@property (nonatomic, strong) SKNode *dialogueTextNode;
@property (nonatomic, strong) SKNode *choiceNode;
@property (nonatomic, strong) SKNode *overlayNode;
@property (nonatomic, strong) SKLabelNode *continueHint;
@property (nonatomic, copy) NSString *revealingText;
@property (nonatomic) BOOL textRevealing;
@property (nonatomic) BOOL autoMode;
@property (nonatomic) UIEdgeInsets safeInsets;
@property (nonatomic, copy) NSString *endingID;
@property (nonatomic, weak) SKShapeNode *activeButton;
@property (nonatomic, copy) NSString *activeSliderKey;
@property (nonatomic) BOOL endingComplete;
@property (nonatomic) NSInteger pendingRewindIndex;
@property (nonatomic) NSInteger pendingTreeChapterIndex;
@property (nonatomic) GameScreen screenBeforeOverlay;
@property (nonatomic, copy) NSString *lastSpeaker;
@property (nonatomic, copy) NSString *pendingLogNodeID;
@property (nonatomic, copy) NSString *pendingJumpNodeID;
@property (nonatomic) BOOL galleryOpenedFromStory;
@property (nonatomic, strong) SKNode *logContentNode;
@property (nonatomic) CGFloat logScrollOffset;
@property (nonatomic) CGFloat logMaximumScrollOffset;
@property (nonatomic) CGPoint logTouchStart;
@property (nonatomic) CGFloat logTouchStartOffset;
@property (nonatomic) BOOL trackingLogScroll;
@property (nonatomic) BOOL draggedLog;
@property (nonatomic, copy) NSArray<NSString *> *treeChapterNodeIDs;
@property (nonatomic, strong) SKNode *treeContentNode;
@property (nonatomic) CGFloat treeScrollOffset;
@property (nonatomic) CGFloat treeMaximumScrollOffset;
@property (nonatomic) CGFloat treeViewportTop;
@property (nonatomic) CGFloat treeViewportBottom;
@property (nonatomic) CGPoint treeTouchStart;
@property (nonatomic) CGFloat treeTouchStartOffset;
@property (nonatomic) BOOL trackingTreeScroll;
@property (nonatomic) BOOL draggedTree;
@property (nonatomic) NSInteger mysteryGuideTapCount;
@property (nonatomic, copy) NSArray<NSString *> *treeSceneNodeIDs;
@property (nonatomic) BOOL titleTransitionInProgress;
@property (nonatomic) BOOL hiddenEndingCreditsPlaying;
// These indexes are derived once per StoryEngine load.  They keep rewinds,
// log pruning and ending jumps from repeatedly scanning the whole story graph
// on the main thread.
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<NSString *> *> *predecessorNodeIDs;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *endingStartNodeIDs;
@end

@implementation GameScene

- (void)didMoveToView:(SKView *)view {
    self.anchorPoint = CGPointZero;
    self.backgroundColor = SKColor.blackColor;
    self.scaleMode = SKSceneScaleModeResizeFill;
    self.safeInsets = view.safeAreaInsets;
    [self installDefaults];
    [self showTitleScreen];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveForLifecycleChange) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveForLifecycleChange) name:UIApplicationDidEnterBackgroundNotification object:nil];
#if DEBUG
    if ([NSProcessInfo.processInfo.arguments containsObject:@"-StoryPreview"]) { [self startNewGame]; }
#endif
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)saveForLifecycleChange {
    if (self.engine) { [self persistAutosave]; }
}

- (void)didChangeSize:(CGSize)oldSize {
    [super didChangeSize:oldSize];
    self.safeInsets = self.view.safeAreaInsets;
    if (oldSize.width > 0 && oldSize.height > 0) {
        switch (self.screen) {
            case GameScreenStory: [self presentCurrentNode]; break;
            case GameScreenGallery: [self showGallery]; break;
            case GameScreenSettings: [self showSettings]; break;
            case GameScreenCredits: [self showHiddenEndingCredits]; break;
            default: [self showTitleScreen]; break;
        }
    }
}

- (void)updateSafeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    if (UIEdgeInsetsEqualToEdgeInsets(self.safeInsets, safeAreaInsets)) { return; }
    self.safeInsets = safeAreaInsets;
    if (self.size.width <= 0 || self.size.height <= 0) { return; }
    switch (self.screen) {
        case GameScreenStory: [self presentCurrentNode]; break;
        case GameScreenGallery: [self showGallery]; break;
        case GameScreenSettings: [self showSettings]; break;
        case GameScreenCredits: [self showHiddenEndingCredits]; break;
        default: [self showTitleScreen]; break;
    }
}

#pragma mark - Construction helpers

// A small, code-only visual system.  Keeping these values together makes the
// UI feel like one screen-language instead of a collection of dark rectangles.
- (SKColor *)uiInkColor {
    return [SKColor colorWithRed:0.025 green:0.067 blue:0.094 alpha:1.0];
}

- (SKColor *)uiPanelColor:(CGFloat)alpha {
    return [SKColor colorWithRed:0.035 green:0.105 blue:0.145 alpha:alpha];
}

- (SKColor *)uiLineColor:(CGFloat)alpha {
    return [SKColor colorWithRed:0.54 green:0.69 blue:0.73 alpha:alpha];
}

- (SKColor *)uiTextColor:(CGFloat)alpha {
    return [SKColor colorWithRed:0.94 green:0.92 blue:0.85 alpha:alpha];
}

- (SKColor *)uiAccentColor:(CGFloat)alpha {
    return [SKColor colorWithRed:0.78 green:0.57 blue:0.31 alpha:alpha];
}

- (void)installDefaults {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (![defaults boolForKey:@"LateSummerSettingsInitialized"]) {
        [defaults setFloat:0.75 forKey:@"musicVolume"];
        [defaults setFloat:0.80 forKey:@"effectsVolume"];
        [defaults setFloat:0.55 forKey:@"textSpeed"];
        [defaults setFloat:0.45 forKey:@"autoInterval"];
        [defaults setBool:NO forKey:@"allowUnreadSkip"];
        [defaults setBool:NO forKey:@"reduceMotion"];
        [defaults setBool:YES forKey:@"LateSummerSettingsInitialized"];
    }
}

- (SKLabelNode *)label:(NSString *)text size:(CGFloat)size weight:(NSString *)weight {
    // Avenir's Latin metrics are clearer and more compact for the English
    // edition. Select it automatically for labels still requesting PingFang.
    if ([weight hasPrefix:@"PingFang"] && [text canBeConvertedToEncoding:NSASCIIStringEncoding]) {
        weight = [weight containsString:@"Semibold"] ? @"AvenirNext-DemiBold" : ([weight containsString:@"Medium"] ? @"AvenirNext-Medium" : @"AvenirNext-Regular");
    }
    SKLabelNode *label = [SKLabelNode labelNodeWithFontNamed:weight];
    label.text = text;
    label.fontSize = size;
    label.fontColor = [self uiTextColor:1.0];
    label.verticalAlignmentMode = SKLabelVerticalAlignmentModeCenter;
    label.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    return label;
}

- (SKShapeNode *)button:(NSString *)name title:(NSString *)title size:(CGSize)size primary:(BOOL)primary {
    SKShapeNode *button = [SKShapeNode shapeNodeWithRectOfSize:size cornerRadius:7];
    button.name = name;
    button.fillColor = primary ? [self uiPanelColor:0.94] : [self uiInkColor];
    button.strokeColor = [self uiLineColor:primary ? 0.76 : 0.38];
    button.lineWidth = 1;
    button.userData = [@{ @"primary": @(primary) } mutableCopy];

    SKLabelNode *label = [self label:title size:MIN(16, size.height * 0.35) weight:@"AvenirNext-Medium"];
    label.name = name;
    label.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    label.position = CGPointMake(0, -1);
    [button addChild:label];
    return button;
}

// English chapter titles can be much longer. Keep them compact and inset.
- (SKShapeNode *)memoryTreeChapterButton:(NSString *)name title:(NSString *)title size:(CGSize)size primary:(BOOL)primary {
    SKShapeNode *button = [SKShapeNode shapeNodeWithRectOfSize:size cornerRadius:7];
    button.name = name;
    button.fillColor = primary ? [self uiPanelColor:0.96] : [self uiInkColor];
    button.strokeColor = [self uiLineColor:primary ? 0.78 : 0.40];
    button.lineWidth = 1;
    button.userData = [@{ @"primary": @(primary) } mutableCopy];

    // Keep the type comfortably large, while reserving enough vertical inset
    // for the outline even on the smallest supported portrait screens.
    SKLabelNode *label = [self label:title size:MIN(15, MAX(13, size.height * 0.42)) weight:@"AvenirNext-Medium"];
    label.name = name;
    label.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    label.verticalAlignmentMode = SKLabelVerticalAlignmentModeCenter;
    label.position = CGPointMake(0, -1);
    [button addChild:label];
    return button;
}

- (SKShapeNode *)buttonAncestorAtPoint:(CGPoint)point {
    SKNode *node = [self nodeAtPoint:point];
    while (node) {
        if ([node isKindOfClass:[SKShapeNode class]] && node.name.length > 0) { return (SKShapeNode *)node; }
        node = node.parent;
    }
    return nil;
}

- (void)setButton:(SKShapeNode *)button highlighted:(BOOL)highlighted {
    if (!button) { return; }
    BOOL primary = [button.userData[@"primary"] boolValue];
    BOOL choice = [button.userData[@"choice"] boolValue];
    BOOL compact = [button.userData[@"compact"] boolValue];
    if (primary) {
        // Keep ON states visibly semantic: this is the original active-state
        // treatment used by AUTO and the Settings toggles.
        button.fillColor = highlighted ? [SKColor colorWithRed:0.16 green:0.46 blue:0.62 alpha:1.0] : [SKColor colorWithRed:0.10 green:0.31 blue:0.42 alpha:0.96];
        button.strokeColor = [SKColor colorWithWhite:1 alpha:highlighted ? 0.90 : 0.72];
    } else {
        button.fillColor = compact ? [self uiPanelColor:highlighted ? 0.96 : 0.76] : (highlighted ? [self uiPanelColor:0.98] : [self uiInkColor]);
        button.strokeColor = compact ? SKColor.clearColor : (choice && highlighted ? [self uiAccentColor:0.92] : [self uiLineColor:highlighted ? 0.86 : 0.38]);
    }
}

- (void)pressButton:(SKShapeNode *)button {
    if (!button || button == self.activeButton) { return; }
    [self releaseActiveButtonAnimated:NO];
    self.activeButton = button;
    [self setButton:button highlighted:YES];
    [button removeActionForKey:@"buttonPress"];
    [button runAction:[SKAction scaleTo:0.94 duration:0.055] withKey:@"buttonPress"];
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"reduceMotion"]) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [feedback prepare];
        [feedback impactOccurred];
    }
}

- (void)releaseActiveButtonAnimated:(BOOL)animated {
    SKShapeNode *button = self.activeButton;
    self.activeButton = nil;
    if (!button) { return; }
    [self setButton:button highlighted:NO];
    [button removeActionForKey:@"buttonPress"];
    SKAction *scale = [SKAction scaleTo:1 duration:animated ? 0.13 : 0.04];
    if (animated && ![NSUserDefaults.standardUserDefaults boolForKey:@"reduceMotion"]) {
        [button runAction:[SKAction sequence:@[scale, [SKAction scaleTo:1.025 duration:0.045], [SKAction scaleTo:1 duration:0.055]]] withKey:@"buttonRelease"];
    } else { [button runAction:scale withKey:@"buttonRelease"]; }
}

- (void)setBackgroundNamed:(NSString *)name immediate:(BOOL)immediate {
    [self setBackgroundNamed:name fallbackName:nil immediate:immediate];
}

- (void)setBackgroundNamed:(NSString *)name fallbackName:(NSString *)fallbackName immediate:(BOOL)immediate {
    if (name.length == 0) { name = fallbackName; }
    if (name.length == 0 || [self.backgroundNode.name isEqualToString:name]) { return; }

    // `textureWithImageNamed:` fails silently when an asset was not included in
    // the target.  Previously that left the previous CG on screen, which made
    // the new-student epilogue appear to ignore its CG entirely.  Try the
    // requested CG first, then use the node's ordinary background as a visible
    // fallback instead of retaining stale artwork.
    SKTexture *texture = [SKTexture textureWithImageNamed:name];
    if (texture.size.width <= 1 && fallbackName.length > 0 && ![name isEqualToString:fallbackName]) {
        name = fallbackName;
        texture = [SKTexture textureWithImageNamed:name];
    }
    if (texture.size.width <= 1) { return; }
    SKSpriteNode *newNode = [SKSpriteNode spriteNodeWithTexture:texture];
    newNode.name = name;
    newNode.position = CGPointMake(self.size.width / 2, self.size.height / 2);
    CGFloat scale = MAX(self.size.width / texture.size.width, self.size.height / texture.size.height);
    newNode.size = CGSizeMake(texture.size.width * scale, texture.size.height * scale);
    newNode.zPosition = -20;
    newNode.alpha = immediate ? 1 : 0;
    [self addChild:newNode];
    SKSpriteNode *old = self.backgroundNode;
    self.backgroundNode = newNode;
    if (!immediate && ![NSUserDefaults.standardUserDefaults boolForKey:@"reduceMotion"]) {
        [newNode runAction:[SKAction fadeInWithDuration:0.55]];
        [old runAction:[SKAction sequence:@[[SKAction fadeOutWithDuration:0.55], [SKAction removeFromParent]]]];
    } else {
        newNode.alpha = 1;
        [old removeFromParent];
    }
}

- (NSArray<NSString *> *)wrappedLines:(NSString *)text maxWidth:(CGFloat)maxWidth fontSize:(CGFloat)fontSize maxLines:(NSInteger)maxLines {
    if (text.length == 0) { return @[]; }
    NSMutableArray *lines = [NSMutableArray array];
    NSMutableString *line = [NSMutableString string];
    NSArray *paragraphs = [text componentsSeparatedByString:@"\n"];
    UIFont *font = [UIFont fontWithName:@"AvenirNext-Regular" size:fontSize] ?: [UIFont systemFontOfSize:fontSize];
    NSDictionary *attributes = @{ NSFontAttributeName: font };
    for (NSString *paragraph in paragraphs) {
        NSArray *words = [paragraph canBeConvertedToEncoding:NSASCIIStringEncoding] ? [paragraph componentsSeparatedByString:@" "] : nil;
        if (words.count > 1) {
            for (NSString *word in words) {
                NSString *candidate = line.length ? [NSString stringWithFormat:@"%@ %@", line, word] : word;
                if ([candidate sizeWithAttributes:attributes].width > maxWidth && line.length) { [lines addObject:[line copy]]; [line setString:word]; }
                else { [line setString:candidate]; }
            }
        } else {
            NSUInteger capacity = MAX((NSUInteger)1, floor(maxWidth / MAX(fontSize * 0.56, 1)));
            for (NSUInteger index = 0; index < paragraph.length; index += capacity) {
                if (line.length) { [lines addObject:[line copy]]; [line setString:@""]; }
                [lines addObject:[paragraph substringWithRange:NSMakeRange(index, MIN((NSUInteger)capacity, paragraph.length - index))]];
            }
        }
        if (line.length) { [lines addObject:[line copy]]; [line setString:@""]; }
    }
    if (maxLines > 0 && lines.count > maxLines) {
        NSMutableArray *trimmed = [[lines subarrayWithRange:NSMakeRange(0, maxLines)] mutableCopy];
        trimmed[maxLines - 1] = [trimmed[maxLines - 1] stringByAppendingString:@"…"];
        return trimmed;
    }
    return lines;
}

- (void)addLines:(NSArray<NSString *> *)lines toNode:(SKNode *)node width:(CGFloat)width fontSize:(CGFloat)fontSize color:(SKColor *)color {
    for (NSInteger index = 0; index < (NSInteger)lines.count; index++) {
        SKLabelNode *label = [self label:lines[index] size:fontSize weight:@"PingFangSC-Regular"];
        label.fontColor = color;
        label.position = CGPointMake(-width / 2, -index * (fontSize + 9));
        [node addChild:label];
    }
}

- (CGFloat)fontSizeForText:(NSString *)text width:(CGFloat)width maxLines:(NSInteger)maxLines preferredSize:(CGFloat)preferredSize {
    if (maxLines == 0 || text.length == 0) { return preferredSize; }
    // Test the full sentence, not the typewriter prefix, so text never jumps
    // as it appears. English uses more horizontal space than the source text.
    for (CGFloat size = preferredSize; size >= 12; size -= 0.5) {
        if ([self wrappedLines:text maxWidth:width fontSize:size maxLines:0].count <= maxLines) return size;
    }
    return 12;
}

- (SKNode *)namedAncestorAtPoint:(CGPoint)point {
    SKNode *node = [self nodeAtPoint:point];
    while (node && node.name.length == 0) { node = node.parent; }
    return node;
}

#pragma mark - Title

- (void)showTitleScreen {
    self.screen = GameScreenTitle;
    self.autoMode = NO;
    [self cancelTransientStoryWork];
    [self removeAllChildren];
    self.backgroundNode = nil;
    [self setBackgroundNamed:@"environment_home_background" immediate:YES];
    [[AudioManager shared] playMusicNamed:@"M01_title_theme"];

    SKSpriteNode *shade = [SKSpriteNode spriteNodeWithColor:[SKColor colorWithWhite:0 alpha:0.38] size:self.size];
    shade.position = CGPointMake(self.size.width / 2, self.size.height / 2);
    shade.zPosition = -10;
    [self addChild:shade];

    CGFloat top = self.size.height - self.safeInsets.top;
    SKLabelNode *eyebrow = [self label:@"INTERACTIVE CINEMATIC NOVEL" size:11 weight:@"AvenirNext-DemiBold"];
    eyebrow.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    eyebrow.fontColor = [SKColor colorWithRed:0.72 green:0.88 blue:0.96 alpha:0.9];
    eyebrow.position = CGPointMake(self.size.width / 2, top - 93);
    [self addChild:eyebrow];
    SKLabelNode *title = [self label:@"THE END-OF-SUMMER SCREENING ROOM" size:MIN(16, MAX(14, self.size.width * 0.045)) weight:@"AvenirNext-DemiBold"];
    title.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    title.position = CGPointMake(self.size.width / 2, top - 140);
    [self addChild:title];
    SKLabelNode *subtitle = [self label:@"A CINEMATIC MYSTERY OF MEMORY AND FILM" size:10 weight:@"AvenirNext-Medium"];
    subtitle.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    subtitle.position = CGPointMake(self.size.width / 2, top - 178);
    [self addChild:subtitle];

    CGFloat buttonWidth = MIN(self.size.width - 62, 310);
    BOOL shouldStartFresh = !SaveManager.shared.hasSave || SaveManager.shared.shouldStartFresh || self.endingComplete;
    SKShapeNode *play = [self button:@"play_primary" title:shouldStartFresh ? @"START NEW GAME" : @"RESUME" size:CGSizeMake(buttonWidth, 48) primary:YES];
    CGFloat bottom = self.safeInsets.bottom + 84;
    play.position = CGPointMake(self.size.width / 2, bottom + 55);
    [self addChild:play];
    SKShapeNode *memories = [self button:@"gallery" title:@"MEMORY TREE" size:CGSizeMake((buttonWidth - 8) / 2, 40) primary:NO];
    memories.position = CGPointMake(self.size.width / 2 - (buttonWidth + 8) / 4, bottom);
    [self addChild:memories];
    SKShapeNode *settings = [self button:@"settings" title:@"SETTINGS" size:CGSizeMake((buttonWidth - 8) / 2, 40) primary:NO];
    settings.position = CGPointMake(self.size.width / 2 + (buttonWidth + 8) / 4, bottom);
    [self addChild:settings];
    SKLabelNode *tagline = [self label:@"Before the school is demolished, we must screen a film" size:10 weight:@"AvenirNext-Regular"];
    tagline.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    tagline.position = CGPointMake(self.size.width / 2, bottom + 140);
    tagline.fontColor = [SKColor colorWithWhite:1 alpha:0.78];
    [self addChild:tagline];
    SKLabelNode *taglineTwo = [self label:@"no one remembers making." size:10 weight:@"AvenirNext-Regular"];
    taglineTwo.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    taglineTwo.position = CGPointMake(self.size.width / 2, bottom + 125);
    taglineTwo.fontColor = tagline.fontColor;
    [self addChild:taglineTwo];
}

#pragma mark - Story

- (BOOL)loadEngineFromPayload:(NSDictionary *)payload {
    NSError *error;
    NSDictionary *state = [payload[@"state"] isKindOfClass:[NSDictionary class]] ? payload[@"state"] : nil;
    self.engine = [[StoryEngine alloc] initWithSavedState:state error:&error];
    if (!self.engine || self.engine.validationErrors.count) {
        [self showNotice:error.localizedDescription ?: @"Story data validation failed."];
        return NO;
    }
    [self rebuildStoryIndexes];
    return YES;
}

// SpriteKit actions on the scene itself survive removeAllChildren.  Leaving a
// typewriter/auto action alive while entering the tree could advance the story
// behind the gallery, which looked like dropped taps or a frozen tree.
- (void)cancelTransientStoryWork {
    [self removeActionForKey:@"autoAdvance"];
    [self.dialogueTextNode removeActionForKey:@"typewriter"];
    self.textRevealing = NO;
    self.revealingText = nil;
    self.trackingTreeScroll = NO;
    self.trackingLogScroll = NO;
    self.activeSliderKey = nil;
    [self releaseActiveButtonAnimated:NO];
}

- (void)rebuildStoryIndexes {
    NSDictionary<NSString *, NSDictionary *> *nodes = self.engine.content[@"nodes"];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *predecessors = [NSMutableDictionary dictionaryWithCapacity:nodes.count];
    NSMutableDictionary<NSString *, NSString *> *endingStarts = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *firstNumbers = [NSMutableDictionary dictionary];

    void (^addPredecessor)(NSString *, NSString *) = ^(NSString *targetID, NSString *sourceID) {
        if (targetID.length == 0 || sourceID.length == 0 || !nodes[targetID]) { return; }
        NSMutableArray<NSString *> *sources = predecessors[targetID];
        if (!sources) { sources = [NSMutableArray array]; predecessors[targetID] = sources; }
        [sources addObject:sourceID];
    };
    for (NSString *nodeID in nodes) {
        NSDictionary *node = nodes[nodeID];
        if ([node[@"next"] isKindOfClass:NSString.class]) { addPredecessor(node[@"next"], nodeID); }
        NSDictionary *conditional = node[@"conditionalNext"];
        if ([conditional[@"target"] isKindOfClass:NSString.class]) { addPredecessor(conditional[@"target"], nodeID); }
        if ([conditional[@"fallback"] isKindOfClass:NSString.class]) { addPredecessor(conditional[@"fallback"], nodeID); }
        for (NSDictionary *option in node[@"options"] ?: @[]) {
            if ([option[@"target"] isKindOfClass:NSString.class]) { addPredecessor(option[@"target"], nodeID); }
        }

        NSString *endingID = node[@"endingID"];
        NSString *chapter = node[@"chapter"];
        NSString *scene = node[@"scene"];
        if (endingID.length == 0 || chapter.length == 0 || scene.length == 0) { continue; }
        NSString *sceneKey = [chapter stringByAppendingFormat:@"|||%@", scene];
        NSString *startID = endingStarts[endingID];
        NSNumber *startNumber = firstNumbers[endingID];
        NSInteger number = nodeID.length > 1 ? [[nodeID substringFromIndex:1] integerValue] : NSIntegerMax;
        // The ending marker may be the final node.  Save its scene key now;
        // the second pass below resolves the first playable node in that scene.
        if (!startID || number < startNumber.integerValue) {
            endingStarts[endingID] = sceneKey;
            firstNumbers[endingID] = @(number);
        }
    }
    // Resolve each ending scene to its earliest node.  This is a one-time
    // O(nodes × endings) setup instead of doing the same scan per tap.
    for (NSString *endingID in endingStarts.allKeys.copy) {
        NSString *sceneKey = endingStarts[endingID];
        NSString *bestID = nil;
        NSInteger bestNumber = NSIntegerMax;
        for (NSString *nodeID in nodes) {
            NSDictionary *node = nodes[nodeID];
            NSString *key = [node[@"chapter"] stringByAppendingFormat:@"|||%@", node[@"scene"] ?: @""];
            if (![key isEqualToString:sceneKey]) { continue; }
            NSInteger number = nodeID.length > 1 ? [[nodeID substringFromIndex:1] integerValue] : NSIntegerMax;
            if (number < bestNumber) { bestNumber = number; bestID = nodeID; }
        }
        if (bestID) { endingStarts[endingID] = bestID; } else { [endingStarts removeObjectForKey:endingID]; }
    }
    self.predecessorNodeIDs = predecessors;
    self.endingStartNodeIDs = endingStarts;
}

- (void)startNewGame {
    if (![self loadEngineFromPayload:@{}]) { return; }
    [self.engine startNewGame];
    self.endingComplete = NO;
    [SaveManager.shared setShouldStartFresh:NO];
    self.screen = GameScreenStory;
    [self persistAutosave];
    [self presentCurrentNode];
    [self playStoryEntrance:YES];
}

- (void)continueGame {
    NSDictionary *payload = SaveManager.shared.autosave ?: SaveManager.shared.manualSave;
    if (!payload || ![self loadEngineFromPayload:payload]) { return; }
    self.screen = GameScreenStory;
    [self presentCurrentNode];
    [self playStoryEntrance:NO];
}

// The projection screen in the title art is the visual doorway into the story.
// Hold the title for a beat, push into that screen, then use a white-out to
// conceal the first story scene being assembled underneath it.
- (void)transitionFromTitleToStoryStartingNewGame:(BOOL)newGame {
    if (self.titleTransitionInProgress) { return; }
    self.titleTransitionInProgress = YES;

    if ([NSUserDefaults.standardUserDefaults boolForKey:@"reduceMotion"]) {
        self.titleTransitionInProgress = NO;
        if (newGame) { [self startNewGame]; } else { [self continueGame]; }
        return;
    }

    CGPoint screenCenter = CGPointMake(self.size.width * 0.57, self.size.height * 0.54);
    CGPoint sceneCenter = CGPointMake(self.size.width / 2, self.size.height / 2);
    CGFloat zoom = 2.35;
    CGPoint zoomedBackgroundCenter = CGPointMake(sceneCenter.x - (screenCenter.x - sceneCenter.x) * (zoom - 1),
                                                  sceneCenter.y - (screenCenter.y - sceneCenter.y) * (zoom - 1));
    [self.backgroundNode runAction:[SKAction group:@[
        [SKAction scaleTo:zoom duration:0.48],
        [SKAction moveTo:zoomedBackgroundCenter duration:0.48]
    ]] withKey:@"titleScreenZoom"];
    for (SKNode *child in self.children.copy) {
        if (child != self.backgroundNode) { [child runAction:[SKAction fadeOutWithDuration:0.20]]; }
    }

    SKSpriteNode *whiteVeil = [SKSpriteNode spriteNodeWithColor:SKColor.whiteColor size:self.size];
    whiteVeil.position = sceneCenter;
    whiteVeil.zPosition = 500;
    whiteVeil.alpha = 0;
    [self addChild:whiteVeil];
    __weak typeof(self) weakSelf = self;
    [whiteVeil runAction:[SKAction sequence:@[
        [SKAction waitForDuration:0.22],
        [SKAction fadeInWithDuration:0.30],
        [SKAction runBlock:^{
            GameScene *scene = weakSelf;
            if (!scene) { return; }
            [scene removeAllChildren];
            scene.backgroundNode = nil;
            if (newGame) { [scene startNewGame]; } else { [scene continueGame]; }

            SKSpriteNode *revealVeil = [SKSpriteNode spriteNodeWithColor:SKColor.whiteColor size:scene.size];
            revealVeil.position = CGPointMake(scene.size.width / 2, scene.size.height / 2);
            revealVeil.zPosition = 500;
            [scene addChild:revealVeil];
            [revealVeil runAction:[SKAction sequence:@[
                [SKAction fadeOutWithDuration:0.42],
                [SKAction runBlock:^{ scene.titleTransitionInProgress = NO; }],
                [SKAction removeFromParent]
            ]]];
        }]
    ]]];
}

- (void)clearSceneKeepingBackground:(BOOL)keepBackground {
    for (SKNode *child in [self.children copy]) {
        if (keepBackground && child == self.backgroundNode) { continue; }
        [child removeFromParent];
    }
    self.portraitNode = nil;
    self.choiceNode = nil;
    self.dialogueTextNode = nil;
    self.overlayNode = nil;
}

- (void)recordDisplayedDialogueForNode:(NSDictionary *)node {
    NSString *text = [self displayTextForNode:node];
    NSString *nodeID = self.engine.state.currentNodeID;
    if (text.length == 0 || nodeID.length == 0 || [node[@"type"] isEqualToString:@"event"]) { return; }
    if ([text containsString:@"FaceTruth"] || [text containsString:@"TrustFriends"] || [text containsString:@"EmpathyChinatsu"]) { return; }
    for (NSDictionary *entry in self.engine.state.dialogueLog) {
        if ([entry[@"nodeID"] isEqualToString:nodeID]) { return; }
    }
    [self.engine.state.dialogueLog addObject:@{
        @"speaker": node[@"speaker"] ?: @"",
        @"text": text,
        @"nodeID": nodeID
    }];
    [self persistAutosave];
}

- (void)presentCurrentNode {
    self.screen = GameScreenStory;
    NSDictionary *node = self.engine.currentNode;
    // Textless nodes are structural markers. Advance through them so the
    // following spoken line takes their place instead of showing an empty
    // dialogue panel. Choices remain visible because their options are UI.
    while (node && [self displayTextForNode:node].length == 0 &&
           ![node[@"type"] isEqualToString:@"choice"] &&
           ![node[@"type"] isEqualToString:@"ending"]) {
        node = [self.engine advance];
    }
    if (!node) { [self showEndingCompletion]; return; }
    // An ending marker may intentionally have no line. Finalize it directly
    // rather than requiring a tap on an otherwise empty dialogue panel.
    if ([node[@"type"] isEqualToString:@"ending"] && [self displayTextForNode:node].length == 0) {
        self.endingID = node[@"endingID"];
        [SaveManager.shared unlockEnding:self.endingID];
        [self persistAutosave];
        [self showEndingCompletion];
        return;
    }
    // The title screen's RESUME action restores this exact node.  Persist only
    // after structural nodes above have been resolved, so a quit immediately
    // after advancing never resumes on the previous line.
    [self persistAutosave];
    [self clearSceneKeepingBackground:YES];
    // A CG is a complete composed frame, including any characters it depicts.
    // It replaces the environmental background instead of being layered under
    // portraits, preventing duplicate character art in cinematic beats.
    NSString *cgName = node[@"cg"];
    NSString *backgroundName = node[@"background"] ?: @"environment_home_background";
    [self setBackgroundNamed:cgName fallbackName:backgroundName immediate:self.backgroundNode == nil];
    [[AudioManager shared] playMusicNamed:node[@"bgm"] ?: @"M02_back_to_chomi_zaka"];
    [self addStoryControlsForNode:node];
    [self addPortraitsForNode:node];
    [self addDialogueForNode:node];
    if ([node[@"type"] isEqualToString:@"choice"]) { [self addChoices:node[@"options"]]; }
    if ([node[@"effect"] isEqualToString:@"flash"] && ![NSUserDefaults.standardUserDefaults boolForKey:@"reduceMotion"]) { [self flash]; }
    if ([node[@"autosave"] boolValue]) { [self persistAutosave]; }
    if ([node[@"type"] isEqualToString:@"ending"]) {
        self.endingID = node[@"endingID"];
        [SaveManager.shared unlockEnding:self.endingID];
        [self persistAutosave];
    }
}

- (void)addStoryControlsForNode:(NSDictionary *)node {
    CGFloat bottom = self.safeInsets.bottom + 12;
    CGFloat panelHeight = [node[@"type"] isEqualToString:@"choice"] ? 126 : 178;
    CGFloat y = bottom + panelHeight + 19;
    NSArray *items = @[ @[@"menu", @"MENU"], @[@"log", @"LOG"], @[@"tree", @"TREE"], @[@"auto", @"AUTO"], @[@"skip", @"SKIP"] ];
    CGFloat gap = 5;
    CGFloat width = (self.size.width - 28 - gap * (items.count - 1)) / items.count;
    SKShapeNode *controlRail = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(self.size.width - 28, 35) cornerRadius:8];
    controlRail.position = CGPointMake(self.size.width / 2, y);
    controlRail.fillColor = [self uiInkColor];
    controlRail.strokeColor = [self uiLineColor:0.40];
    controlRail.lineWidth = 1;
    controlRail.zPosition = 49;
    [self addChild:controlRail];
    for (NSInteger i = 0; i < (NSInteger)items.count; i++) {
        BOOL skipDisabled = [items[i][0] isEqualToString:@"skip"] && (![self.engine isCurrentNodeRead] || [self.engine alreadyReadChoiceAfterCurrentNode] == nil);
        SKShapeNode *button = [self button:skipDisabled ? @"skip_disabled" : items[i][0] title:items[i][1] size:CGSizeMake(width, 29) primary:[items[i][0] isEqualToString:@"auto"] && self.autoMode];
        button.position = CGPointMake(14 + width / 2 + i * (width + gap), y);
        button.userData[@"compact"] = @YES;
        [self setButton:button highlighted:NO];
        if (skipDisabled) button.alpha = 0.28;
        button.zPosition = 50;
        [self addChild:button];
    }
    NSString *chapterText = [self displayChapter:node[@"chapter"]];
    NSString *sceneText = [self displaySceneForNode:node];
    NSString *progressText = sceneText.length ? [NSString stringWithFormat:@"%@  ·  %@", chapterText, sceneText] : chapterText;
    SKLabelNode *progress = [self label:progressText size:9 weight:@"PingFangSC-Medium"];
    progress.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
    progress.position = CGPointMake(self.size.width - 15, y + 23);
    progress.fontColor = [SKColor colorWithWhite:1 alpha:0.72];
    progress.zPosition = 50;
    [self addChild:progress];
}

- (NSString *)displayChapter:(NSString *)chapter {
    NSRange marker = [chapter rangeOfString:@"、"];
    NSString *display = marker.location == NSNotFound ? (chapter ?: @"") : [chapter substringFromIndex:marker.location + 1];
    // Ending classifications are internal metadata and should not leak into
    // the in-game chapter/progress labels.
    display = [display stringByReplacingOccurrencesOfString:@"Hidden Ending: " withString:@""];
    return display;
}

- (NSString *)displaySceneForNode:(NSDictionary *)node {
    NSString *scene = [node[@"scene"] isKindOfClass:NSString.class] ? node[@"scene"] : @"";
    if (scene.length == 0) { return @""; }
    // Chapter transition nodes carry the previous scene for story routing,
    // while the actual scene marker repeats its title in `text`.  Only the
    // latter is a real scene heading and should appear in the progress UI.
    if ([node[@"type"] isEqualToString:@"chapter"] && ![node[@"text"] isEqualToString:scene]) {
        return @"";
    }
    if ([scene hasPrefix:@"Ending"] || [scene isEqualToString:@"Unlock Conditions"]) { return @""; }
    return scene;
}

- (NSString *)displayTextForNode:(NSDictionary *)node {
    NSString *text = node[@"text"] ?: @"";
    // Chapter marker nodes reuse the chapter title as their dialogue text.
    // Keep the numeric outline prefix in metadata, but omit it in the
    // dialogue box (and in the history log) so the title reads naturally.
    if ([node[@"type"] isEqualToString:@"chapter"] ||
        (text.length > 0 && [text isEqualToString:node[@"chapter"]])) {
        return [self displayChapter:text];
    }
    return text;
}

- (NSString *)portraitBaseForSpeaker:(NSString *)speaker fallback:(NSString *)fallback {
    BOOL child = [speaker localizedCaseInsensitiveContainsString:@"young"] || [speaker localizedCaseInsensitiveContainsString:@"child"];
    if ([speaker localizedCaseInsensitiveContainsString:@"akari"]) return child ? @"akari_child" : @"akari";
    if ([speaker localizedCaseInsensitiveContainsString:@"shiori"]) return child ? @"shiori_child" : @"shiori";
    if ([speaker localizedCaseInsensitiveContainsString:@"yuma"]) return child ? @"yuma_child" : @"yuma";
    if ([speaker localizedCaseInsensitiveContainsString:@"chinatsu"] || [speaker localizedCaseInsensitiveContainsString:@"girl"]) return @"chinatsu";
    if ([speaker localizedCaseInsensitiveContainsString:@"riku"]) return child ? @"riku_child" : @"riku";
    return fallback;
}

- (NSString *)portraitForSpeaker:(NSString *)speaker text:(NSString *)text fallback:(NSString *)fallback alternate:(BOOL)alternate {
    (void)alternate;
    NSString *base = [self portraitBaseForSpeaker:speaker fallback:nil];
    if (base.length == 0) { return fallback; }
    NSString *neutral = [base stringByAppendingString:@"_neutral"];
    if ([base isEqualToString:@"akari"]) neutral = @"akari_talking";
    if ([base isEqualToString:@"shiori"]) neutral = @"portrait_shiori";
    if ([base isEqualToString:@"yuma"]) neutral = @"portrait_yuma";
    if ([base isEqualToString:@"chinatsu"]) neutral = @"chinatsu_talking";
    if ([base isEqualToString:@"riku"]) neutral = @"riku_neutral";
    if (text.length == 0) { return neutral; }

    // The dispatch table's emotion/action cues are applied to each node's
    // actual line, keeping a character from being stuck on one portrait.
    NSString *emotion = nil;
    if ([text localizedCaseInsensitiveContainsString:@"sorry"] || [text localizedCaseInsensitiveContainsString:@"goodbye"] || [text localizedCaseInsensitiveContainsString:@"lost"] || [text localizedCaseInsensitiveContainsString:@"cry"]) {
        emotion = @"sad";
    } else if ([text localizedCaseInsensitiveContainsString:@"afraid"] || [text localizedCaseInsensitiveContainsString:@"worry"] || [text localizedCaseInsensitiveContainsString:@"typhoon"] || [text localizedCaseInsensitiveContainsString:@"danger"]) {
        emotion = @"worried";
    } else if ([text containsString:@"?"] || [text localizedCaseInsensitiveContainsString:@"what"] || [text localizedCaseInsensitiveContainsString:@"really"] || [text localizedCaseInsensitiveContainsString:@"sudden"]) {
        emotion = @"surprised";
    } else if ([text localizedCaseInsensitiveContainsString:@"thank"] || [text localizedCaseInsensitiveContainsString:@"smile"] || [text localizedCaseInsensitiveContainsString:@"happy"] || [text localizedCaseInsensitiveContainsString:@"finally"]) {
        emotion = @"happy";
    }
    if (emotion.length) { return [NSString stringWithFormat:@"%@_%@", base, emotion]; }

    if ([text localizedCaseInsensitiveContainsString:@"look"] || [text localizedCaseInsensitiveContainsString:@"read"] || [text localizedCaseInsensitiveContainsString:@"investigat"] || [text localizedCaseInsensitiveContainsString:@"film"]) {
        return [base stringByAppendingString:@"_action_observe"];
    }
    if ([text length] > 20 || [text localizedCaseInsensitiveContainsString:@"wave"] || [text localizedCaseInsensitiveContainsString:@"hand"] || [text localizedCaseInsensitiveContainsString:@"point"]) {
        return [base stringByAppendingString:@"_action_dialogue"];
    }
    return neutral;
}

- (CGFloat)portraitXForSpeaker:(NSString *)speaker {
    if ([speaker localizedCaseInsensitiveContainsString:@"akari"] || [speaker localizedCaseInsensitiveContainsString:@"shiori"]) return 0.30;
    return 0.70;
}

- (void)addPortraitNamed:(NSString *)name position:(CGFloat)x active:(BOOL)active alternate:(BOOL)alternate {
    if (name.length == 0 || [name containsString:@"reference"] || [name hasPrefix:@"character_"]) { return; }
    SKTexture *texture = [SKTexture textureWithImageNamed:name];
    if (texture.size.height <= 1) { return; }
    SKSpriteNode *portrait = [SKSpriteNode spriteNodeWithTexture:texture];
    CGFloat height = MIN(self.size.height * 0.62, 540);
    CGFloat scale = height / texture.size.height;
    portrait.size = CGSizeMake(texture.size.width * scale, height);
    // Let the lower body sit behind the dialogue box instead of forcing a full figure above it.
    portrait.position = CGPointMake(self.size.width * x, self.safeInsets.bottom + 24 + height * 0.34);
    portrait.zPosition = 3; portrait.alpha = 1;
    portrait.color = SKColor.blackColor; portrait.colorBlendFactor = active ? 0 : 0.48;
    if (alternate && ![NSUserDefaults.standardUserDefaults boolForKey:@"reduceMotion"]) {
        [portrait runAction:[SKAction repeatActionForever:[SKAction sequence:@[[SKAction moveByX:0 y:4 duration:0.7], [SKAction moveByX:0 y:-4 duration:0.7]]]] withKey:@"portraitBreath"];
    }
    [self addChild:portrait];
    if (active) self.portraitNode = portrait;
}

- (void)addPortraitsForNode:(NSDictionary *)node {
    if ([node[@"cg"] length] > 0) { self.lastSpeaker = nil; return; }
    NSString *speaker = node[@"speaker"] ?: @"";
    BOOL isCharacter = [self portraitBaseForSpeaker:speaker fallback:nil].length > 0;
    if (!isCharacter) { self.lastSpeaker = nil; return; }
    BOOL vary = (self.engine.state.dialogueLog.count % 5 == 0);
    if (self.lastSpeaker.length && ![self.lastSpeaker isEqualToString:speaker]) {
        // Keep a previous speaker only when they occupy the opposite side.
        // Two full-body cut-outs in the same slot create the doubled silhouette
        // seen during same-side speaker changes.
        CGFloat previousX = [self portraitXForSpeaker:self.lastSpeaker];
        CGFloat currentX = [self portraitXForSpeaker:speaker];
        if (fabs(previousX - currentX) > 0.1) {
            [self addPortraitNamed:[self portraitForSpeaker:self.lastSpeaker text:nil fallback:nil alternate:NO] position:previousX active:NO alternate:NO];
        }
    }
    NSString *portrait = [self portraitForSpeaker:speaker text:node[@"text"] fallback:node[@"portrait"] alternate:vary];
    [self addPortraitNamed:portrait position:[self portraitXForSpeaker:speaker] active:YES alternate:vary];
    if (speaker.length) self.lastSpeaker = speaker;
}

- (void)addDialogueForNode:(NSDictionary *)node {
    BOOL choice = [node[@"type"] isEqualToString:@"choice"];
    CGFloat bottom = self.safeInsets.bottom + 12;
    CGFloat panelHeight = choice ? 126 : 178;
    CGFloat sideInset = MAX(20, MAX(self.safeInsets.left, self.safeInsets.right) + 12);
    CGFloat width = self.size.width - sideInset * 2;
    CGFloat horizontalInset = 18;
    SKShapeNode *panel = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(width, panelHeight) cornerRadius:10];
    panel.fillColor = [self uiPanelColor:0.90];
    panel.strokeColor = [self uiLineColor:0.42];
    panel.lineWidth = 1;
    panel.position = CGPointMake(self.size.width / 2, bottom + panelHeight / 2);
    panel.zPosition = 20;
    [self addChild:panel];
    NSString *speaker = node[@"speaker"];
    if (speaker.length) {
        SKShapeNode *nameTab = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(MIN(116, MAX(76, speaker.length * 19 + 28)), 25) cornerRadius:6];
        nameTab.fillColor = [self uiInkColor];
        nameTab.strokeColor = [self uiLineColor:0.44];
        nameTab.lineWidth = 1;
        nameTab.position = CGPointMake(-width / 2 + horizontalInset + nameTab.frame.size.width / 2, panelHeight / 2 - 29);
        [panel addChild:nameTab];
        SKLabelNode *speakerLabel = [self label:speaker size:15 weight:@"PingFangSC-Semibold"];
        speakerLabel.fontColor = [self uiTextColor:0.97];
        speakerLabel.position = CGPointMake(-width / 2 + horizontalInset + 12, panelHeight / 2 - 29);
        [panel addChild:speakerLabel];
    }
    self.dialogueTextNode = [SKNode node];
    self.dialogueTextNode.position = CGPointMake(0, panelHeight / 2 - (speaker.length ? 56 : 33));
    [panel addChild:self.dialogueTextNode];
    self.continueHint = [self label:@"CONTINUE  •" size:9 weight:@"AvenirNext-Medium"];
    self.continueHint.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
    self.continueHint.position = CGPointMake(width / 2 - horizontalInset, -panelHeight / 2 + 15);
    self.continueHint.fontColor = [self uiTextColor:0.58];
    self.continueHint.alpha = 0;
    [panel addChild:self.continueHint];
    [self beginReveal:[self displayTextForNode:node] width:width - horizontalInset * 2 maxLines:choice ? 2 : 5];
}

- (void)beginReveal:(NSString *)text width:(CGFloat)width maxLines:(NSInteger)maxLines {
    self.revealingText = text;
    self.textRevealing = YES;
    [self renderDialoguePrefix:@"" width:width maxLines:maxLines];
    if (text.length == 0) { [self finishRevealWithWidth:width maxLines:maxLines]; return; }
    __block NSUInteger index = 0;
    __weak typeof(self) weakSelf = self;
    CGFloat speed = [NSUserDefaults.standardUserDefaults floatForKey:@"textSpeed"];
    NSTimeInterval interval = MAX(0.008, 0.055 - speed * 0.047);
    SKAction *tick = [SKAction sequence:@[[SKAction waitForDuration:interval], [SKAction runBlock:^{
        GameScene *scene = weakSelf;
        if (!scene || !scene.textRevealing) { return; }
        index++;
        [scene renderDialoguePrefix:[scene.revealingText substringToIndex:MIN(index, scene.revealingText.length)] width:width maxLines:maxLines];
        if (index >= scene.revealingText.length) { [scene finishRevealWithWidth:width maxLines:maxLines]; }
    }]]];
    [self.dialogueTextNode runAction:[SKAction repeatAction:tick count:text.length] withKey:@"typewriter"];
}

- (void)renderDialoguePrefix:(NSString *)text width:(CGFloat)width maxLines:(NSInteger)maxLines {
    [self.dialogueTextNode removeAllChildren];
    CGFloat size = [self fontSizeForText:self.revealingText width:width maxLines:maxLines preferredSize:17];
    NSArray *lines = [self wrappedLines:text maxWidth:width fontSize:size maxLines:maxLines];
    [self addLines:lines toNode:self.dialogueTextNode width:width fontSize:size color:[SKColor colorWithRed:0.96 green:0.97 blue:0.99 alpha:1]];
}

- (void)finishRevealWithWidth:(CGFloat)width maxLines:(NSInteger)maxLines {
    self.textRevealing = NO;
    [self.dialogueTextNode removeActionForKey:@"typewriter"];
    [self renderDialoguePrefix:self.revealingText width:width maxLines:maxLines];
    if (![self.engine.currentNode[@"type"] isEqualToString:@"choice"]) { self.continueHint.alpha = 1; }
    [self scheduleAutoAdvance];
}

- (void)scheduleAutoAdvance {
    [self removeActionForKey:@"autoAdvance"];
    if (self.autoMode && !self.textRevealing && ![self.engine.currentNode[@"type"] isEqualToString:@"choice"] && ![self.engine.currentNode[@"type"] isEqualToString:@"ending"]) {
        NSString *nodeID = self.engine.state.currentNodeID;
        __weak typeof(self) weakSelf = self;
        NSTimeInterval delay = 0.7 + [NSUserDefaults.standardUserDefaults floatForKey:@"autoInterval"] * 3.3;
        [self runAction:[SKAction sequence:@[[SKAction waitForDuration:delay], [SKAction runBlock:^{
            GameScene *scene = weakSelf;
            if (scene.autoMode && [scene.engine.state.currentNodeID isEqualToString:nodeID]) { [scene advanceStory]; }
        }]]] withKey:@"autoAdvance"];
    }
}

- (void)updateAutoButtonAppearance {
    SKShapeNode *button = (SKShapeNode *)[self childNodeWithName:@"//auto"];
    if (![button isKindOfClass:SKShapeNode.class]) return;
    button.userData[@"primary"] = @(self.autoMode);
    [self setButton:button highlighted:NO];
}

- (void)addChoices:(NSArray<NSDictionary *> *)options {
    self.choiceNode = [SKNode node];
    self.choiceNode.zPosition = 30;
    CGFloat dialogueTop = self.safeInsets.bottom + 12 + 126;
    CGFloat availableHeight = self.size.height - self.safeInsets.top - dialogueTop - 68;
    CGFloat height = MIN(58, MAX(44, availableHeight / MAX(1, options.count) - 8));
    CGFloat groupHeight = options.count * height + MAX(0, options.count - 1) * 8;
    CGFloat startY = dialogueTop + 68 + (availableHeight - groupHeight) / 2 + groupHeight - height / 2;
    CGFloat sideInset = MAX(24, MAX(self.safeInsets.left, self.safeInsets.right) + 16);
    CGFloat width = self.size.width - sideInset * 2;
    for (NSInteger i = 0; i < (NSInteger)options.count; i++) {
        SKShapeNode *button = [self button:[NSString stringWithFormat:@"choice_%ld", (long)i] title:@"" size:CGSizeMake(width, height) primary:NO];
        button.position = CGPointMake(self.size.width / 2, startY - i * (height + 8));
        button.userData[@"choice"] = @YES;
        SKLabelNode *number = [self label:[NSString stringWithFormat:@"%ld", (long)i + 1] size:12 weight:@"AvenirNext-DemiBold"];
        number.fontColor = [self uiTextColor:0.72];
        number.position = CGPointMake(-width / 2 + 28, 0);
        [button addChild:number];
        NSString *choiceText = options[i][@"text"] ?: @"";
        CGFloat choiceSize = [self fontSizeForText:choiceText width:width - 58 maxLines:2 preferredSize:14];
        NSArray *lines = [self wrappedLines:choiceText maxWidth:width - 58 fontSize:choiceSize maxLines:2];
        for (NSInteger lineIndex = 0; lineIndex < (NSInteger)lines.count; lineIndex++) {
            SKLabelNode *line = [self label:lines[lineIndex] size:choiceSize weight:@"AvenirNext-Medium"];
            line.position = CGPointMake(-width / 2 + 42, (lines.count - 1) * (choiceSize * 0.58) - lineIndex * (choiceSize + 3));
            line.name = button.name;
            [button addChild:line];
        }
        [self.choiceNode addChild:button];
    }
    [self addChild:self.choiceNode];
}

- (void)advanceStory {
    [self removeActionForKey:@"autoAdvance"];
    // The line currently on screen becomes history only when the player
    // advances past it. This keeps the active line out of LOG.
    [self recordDisplayedDialogueForNode:self.engine.currentNode];
    NSDictionary *next = [self.engine advance];
    if (!next) { [self showEndingCompletion]; return; }
    [self presentCurrentNode];
}

- (void)selectChoice:(NSInteger)index {
    [self recordDisplayedDialogueForNode:self.engine.currentNode];
    [self.engine selectChoiceAtIndex:index];
    [self persistAutosave];
    [self presentCurrentNode];
}

- (void)persistAutosave { [SaveManager.shared writeAutosave:self.engine.savePayload]; }

- (NSSet<NSString *> *)ancestorNodeIDsForNodeID:(NSString *)targetID {
    if (targetID.length == 0) { return [NSSet set]; }
    NSMutableSet<NSString *> *ids = [NSMutableSet setWithObject:targetID];
    NSMutableArray<NSString *> *pending = [NSMutableArray arrayWithObject:targetID];
    while (pending.count) {
        NSString *nodeID = pending.lastObject;
        [pending removeLastObject];
        for (NSString *predecessorID in self.predecessorNodeIDs[nodeID] ?: @[]) {
            if (![ids containsObject:predecessorID]) {
                [ids addObject:predecessorID];
                [pending addObject:predecessorID];
            }
        }
    }
    return ids;
}

- (void)pruneDialogueLogForCurrentNode {
    NSSet<NSString *> *ancestors = [self ancestorNodeIDsForNodeID:self.engine.state.currentNodeID];
    for (NSInteger index = (NSInteger)self.engine.state.dialogueLog.count - 1; index >= 0; index--) {
        NSDictionary *entry = self.engine.state.dialogueLog[index];
        NSString *nodeID = entry[@"nodeID"];
        if ([nodeID isEqualToString:self.engine.state.currentNodeID] || ![ancestors containsObject:nodeID]) {
            [self.engine.state.dialogueLog removeObjectAtIndex:index];
        }
    }
}

#pragma mark - Overlays

- (void)showLog {
    self.screen = GameScreenLog;
    [self showOverlayPanelWithTitle:@"DIALOGUE LOG"];
    NSMutableArray<NSDictionary *> *log = [self.engine.state.dialogueLog mutableCopy];
    // Remove route-debug prose that may still exist in an older save.
    for (NSInteger index = (NSInteger)log.count - 1; index >= 0; index--) {
        NSString *text = log[index][@"text"];
        if ([text containsString:@"FaceTruth"] || [text containsString:@"TrustFriends"] || [text containsString:@"EmpathyChinatsu"] || [text localizedCaseInsensitiveContainsString:@"true ending route"] || [text localizedCaseInsensitiveContainsString:@"hidden ending"]) {
            [log removeObjectAtIndex:index];
        }
    }
    // LOG is a view of the active timeline, not a global archive. When the
    // player is on an earlier line/chapter, hide the current line and any
    // entries that belong to a later branch or later point in the story.
    NSSet<NSString *> *ancestors = [self ancestorNodeIDsForNodeID:self.engine.state.currentNodeID];
    for (NSInteger index = (NSInteger)log.count - 1; index >= 0; index--) {
        NSString *nodeID = log[index][@"nodeID"];
        if ([nodeID isEqualToString:self.engine.state.currentNodeID] || ![ancestors containsObject:nodeID]) [log removeObjectAtIndex:index];
    }
    if (log.count != self.engine.state.dialogueLog.count) {
        [self.engine.state.dialogueLog removeAllObjects];
        [self.engine.state.dialogueLog addObjectsFromArray:log];
        [self persistAutosave];
    }
    if (log.count == 0) {
        SKLabelNode *empty = [self label:@"No dialogue has been recorded yet." size:13 weight:@"AvenirNext-Regular"];
        empty.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
        empty.position = CGPointMake(self.size.width / 2, self.size.height / 2); [self.overlayNode addChild:empty];
        return;
    }
    CGFloat viewportBottom = self.safeInsets.bottom + 108;
    CGFloat viewportTop = self.size.height - self.safeInsets.top - 82;
    CGFloat viewportHeight = viewportTop - viewportBottom;
    NSMutableArray<NSArray<NSString *> *> *lineSets = [NSMutableArray arrayWithCapacity:log.count];
    NSMutableArray<NSNumber *> *rowHeights = [NSMutableArray arrayWithCapacity:log.count];
    CGFloat contentHeight = 0;
    for (NSDictionary *entry in log) {
        NSArray<NSString *> *lines = [self wrappedLines:entry[@"text"] ?: @"" maxWidth:self.size.width * 0.78 fontSize:13 maxLines:0];
        [lineSets addObject:lines];
        CGFloat rowHeight = MAX(76, 51 + lines.count * 22);
        [rowHeights addObject:@(rowHeight)];
        contentHeight += rowHeight;
    }
    self.logMaximumScrollOffset = MAX(0, contentHeight - viewportHeight);
    self.logScrollOffset = 0;

    SKCropNode *crop = [SKCropNode node];
    SKShapeNode *mask = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(self.size.width - 52, viewportHeight) cornerRadius:4];
    mask.fillColor = SKColor.whiteColor;
    mask.strokeColor = SKColor.clearColor;
    mask.position = CGPointMake(self.size.width / 2, viewportBottom + viewportHeight / 2);
    crop.maskNode = mask;
    [self.overlayNode addChild:crop];

    self.logContentNode = [SKNode node];
    self.logContentNode.position = CGPointMake(0, viewportBottom);
    [crop addChild:self.logContentNode];
    CGFloat y = contentHeight;
    for (NSInteger i = 0; i < (NSInteger)log.count; i++) {
        NSDictionary *entry = log[i];
        CGFloat rowHeight = rowHeights[i].doubleValue;
        y -= rowHeight;
        SKShapeNode *entryButton = [self button:[NSString stringWithFormat:@"log_entry_%@", entry[@"nodeID"] ?: @""] title:@"" size:CGSizeMake(self.size.width * 0.79, rowHeight - 4) primary:NO];
        entryButton.position = CGPointMake(self.size.width / 2, y + rowHeight / 2); [self.logContentNode addChild:entryButton];
        NSString *speakerName = [entry[@"speaker"] isKindOfClass:[NSString class]] && [entry[@"speaker"] length] ? entry[@"speaker"] : @"NARRATION";
        SKLabelNode *speaker = [self label:speakerName size:10 weight:@"AvenirNext-DemiBold"];
        speaker.fontColor = [SKColor colorWithRed:0.52 green:0.80 blue:0.93 alpha:1];
        speaker.position = CGPointMake(self.size.width * 0.11, y + rowHeight - 16);
        [self.logContentNode addChild:speaker];
        NSArray<NSString *> *lines = lineSets[i];
        SKNode *textNode = [SKNode node];
        textNode.position = CGPointMake(self.size.width / 2, y + rowHeight - 35);
        [self addLines:lines toNode:textNode width:self.size.width * 0.78 fontSize:13 color:[SKColor colorWithWhite:1 alpha:0.9]];
        [self.logContentNode addChild:textNode];
    }
    SKLabelNode *hint = [self label:@"Swipe up to view later dialogue" size:9 weight:@"AvenirNext-Medium"];
    hint.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    hint.position = CGPointMake(self.size.width / 2, viewportBottom - 13);
    hint.fontColor = [SKColor colorWithWhite:1 alpha:0.55];
    [self.overlayNode addChild:hint];
}

- (void)showMenuConfirmation {
    self.screenBeforeOverlay = GameScreenStory;
    self.overlayNode = [SKNode node]; self.overlayNode.zPosition = 100;
    SKSpriteNode *dim = [SKSpriteNode spriteNodeWithColor:[SKColor colorWithWhite:0 alpha:0.68] size:self.size]; dim.position = CGPointMake(self.size.width / 2, self.size.height / 2); [self.overlayNode addChild:dim];
    CGFloat panelWidth = MIN(300, self.size.width - 48);
    SKShapeNode *panel = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(panelWidth, 156) cornerRadius:10];
    panel.position = CGPointMake(self.size.width / 2, self.size.height / 2); panel.fillColor = [self uiPanelColor:0.99]; panel.strokeColor = [self uiLineColor:0.45]; panel.lineWidth = 1; [self.overlayNode addChild:panel];
    SKShapeNode *returnButton = [self button:@"menu_confirm" title:@"RETURN TO TITLE" size:CGSizeMake(190, 36) primary:YES]; returnButton.position = CGPointMake(self.size.width / 2, self.size.height / 2 + 22); [self.overlayNode addChild:returnButton];
    SKShapeNode *resume = [self button:@"overlay_close" title:@"RESUME" size:CGSizeMake(190, 36) primary:NO]; resume.position = CGPointMake(self.size.width / 2, self.size.height / 2 - 25); [self.overlayNode addChild:resume];
    [self addChild:self.overlayNode];
}

- (void)showCreditsSkipConfirmation {
    // Match MENU's compact confirmation panel. This deliberately does not
    // pause the credits reel or audio; the overlay sits above the live ending.
    self.screenBeforeOverlay = GameScreenCredits;
    self.overlayNode = [SKNode node]; self.overlayNode.zPosition = 100;
    SKSpriteNode *dim = [SKSpriteNode spriteNodeWithColor:[SKColor colorWithWhite:0 alpha:0.68] size:self.size];
    dim.position = CGPointMake(self.size.width / 2, self.size.height / 2);
    [self.overlayNode addChild:dim];
    CGFloat panelWidth = MIN(300, self.size.width - 48);
    SKShapeNode *panel = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(panelWidth, 156) cornerRadius:10];
    panel.position = CGPointMake(self.size.width / 2, self.size.height / 2);
    panel.fillColor = [self uiPanelColor:0.99]; panel.strokeColor = [self uiLineColor:0.45]; panel.lineWidth = 1;
    [self.overlayNode addChild:panel];
    SKShapeNode *confirm = [self button:@"credits_skip_confirm" title:@"SKIP CREDITS" size:CGSizeMake(190, 36) primary:YES];
    confirm.position = CGPointMake(self.size.width / 2, self.size.height / 2 + 22);
    [self.overlayNode addChild:confirm];
    SKShapeNode *resume = [self button:@"overlay_close" title:@"RESUME" size:CGSizeMake(190, 36) primary:NO];
    resume.position = CGPointMake(self.size.width / 2, self.size.height / 2 - 25);
    [self.overlayNode addChild:resume];
    [self addChild:self.overlayNode];
}

- (void)showSkipConfirmation {
    self.screenBeforeOverlay = GameScreenStory;
    self.overlayNode = [SKNode node]; self.overlayNode.zPosition = 100;
    SKSpriteNode *dim = [SKSpriteNode spriteNodeWithColor:[SKColor colorWithWhite:0 alpha:0.68] size:self.size]; dim.position = CGPointMake(self.size.width / 2, self.size.height / 2); [self.overlayNode addChild:dim];
    CGFloat panelWidth = MIN(300, self.size.width - 48);
    SKShapeNode *panel = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(panelWidth, 156) cornerRadius:10]; panel.position = CGPointMake(self.size.width / 2, self.size.height / 2); panel.fillColor = [self uiPanelColor:0.99]; panel.strokeColor = [self uiLineColor:0.45]; panel.lineWidth = 1; [self.overlayNode addChild:panel];
    SKLabelNode *heading = [self label:@"SKIP TO NEXT CHOICE" size:14 weight:@"AvenirNext-DemiBold"]; heading.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter; heading.position = CGPointMake(self.size.width / 2, self.size.height / 2 + 48); [self.overlayNode addChild:heading];
    SKShapeNode *skip = [self button:@"skip_confirm" title:@"SKIP" size:CGSizeMake(190, 36) primary:YES]; skip.position = CGPointMake(self.size.width / 2, self.size.height / 2 + 5); [self.overlayNode addChild:skip];
    SKShapeNode *resume = [self button:@"overlay_close" title:@"RESUME" size:CGSizeMake(190, 36) primary:NO]; resume.position = CGPointMake(self.size.width / 2, self.size.height / 2 - 42); [self.overlayNode addChild:resume];
    [self addChild:self.overlayNode];
}

- (void)showConfirmationWithTitle:(NSString *)title message:(NSString *)message confirmName:(NSString *)confirmName buttonTitle:(NSString *)buttonTitle {
    self.screenBeforeOverlay = self.screen;
    [self.overlayNode removeFromParent];
    self.overlayNode = [SKNode node]; self.overlayNode.zPosition = 100;
    SKSpriteNode *dim = [SKSpriteNode spriteNodeWithColor:[SKColor colorWithWhite:0 alpha:0.68] size:self.size];
    dim.position = CGPointMake(self.size.width / 2, self.size.height / 2); [self.overlayNode addChild:dim];
    CGFloat centerY = self.size.height / 2;
    CGFloat panelWidth = MIN(310, self.size.width - 48);
    SKShapeNode *panel = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(panelWidth, 166) cornerRadius:10];
    panel.position = CGPointMake(self.size.width / 2, centerY); panel.fillColor = [self uiPanelColor:0.99]; panel.strokeColor = [self uiLineColor:0.45]; panel.lineWidth = 1; [self.overlayNode addChild:panel];
    SKLabelNode *heading = [self label:title size:14 weight:@"AvenirNext-DemiBold"];
    heading.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter; heading.position = CGPointMake(self.size.width / 2, centerY + 54); [self.overlayNode addChild:heading];
    SKLabelNode *body = [self label:message size:11 weight:@"AvenirNext-Regular"];
    body.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter; body.position = CGPointMake(self.size.width / 2, centerY + 28); body.fontColor = [self uiTextColor:0.72]; [self.overlayNode addChild:body];
    SKShapeNode *confirm = [self button:confirmName title:buttonTitle size:CGSizeMake(210, 34) primary:YES];
    confirm.position = CGPointMake(self.size.width / 2, centerY - 11); [self.overlayNode addChild:confirm];
    SKShapeNode *continueButton = [self button:@"overlay_close" title:@"CANCEL" size:CGSizeMake(210, 34) primary:NO];
    continueButton.position = CGPointMake(self.size.width / 2, centerY - 52); [self.overlayNode addChild:continueButton];
    [self addChild:self.overlayNode];
}

- (void)playStoryEntrance:(BOOL)newGame {
    if (self.titleTransitionInProgress) { return; }
    SKSpriteNode *veil = [SKSpriteNode spriteNodeWithColor:[SKColor colorWithWhite:0 alpha:1] size:self.size];
    veil.zPosition = 200; veil.position = CGPointMake(self.size.width / 2, self.size.height / 2); [self addChild:veil];
    [veil runAction:[SKAction sequence:@[[SKAction waitForDuration:0.10], [SKAction fadeOutWithDuration:newGame ? 0.52 : 0.36], [SKAction removeFromParent]]]];
}

- (void)showRewind {
    // Rewind entry intentionally lives in the Memory Tree, where the target
    // branch and the consequence of changing it are visible before an ad plays.
    [self showGallery];
}

- (void)showOverlayPanelWithTitle:(NSString *)title {
    self.screenBeforeOverlay = self.screen;
    [self.overlayNode removeFromParent];
    self.overlayNode = [SKNode node];
    self.overlayNode.zPosition = 100;
    SKSpriteNode *dim = [SKSpriteNode spriteNodeWithColor:[SKColor colorWithWhite:0 alpha:0.82] size:self.size];
    dim.position = CGPointMake(self.size.width / 2, self.size.height / 2);
    [self.overlayNode addChild:dim];
    SKShapeNode *panel = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(self.size.width - 32, self.size.height - self.safeInsets.top - self.safeInsets.bottom - 42) cornerRadius:16];
    panel.position = CGPointMake(self.size.width / 2, self.size.height / 2 + (self.safeInsets.bottom - self.safeInsets.top) / 2);
    panel.fillColor = [SKColor colorWithRed:0.025 green:0.055 blue:0.08 alpha:0.98];
    panel.strokeColor = [SKColor colorWithWhite:1 alpha:0.28];
    [self.overlayNode addChild:panel];
    SKLabelNode *heading = [self label:title size:18 weight:@"AvenirNext-DemiBold"];
    heading.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    heading.position = CGPointMake(self.size.width / 2, self.size.height - self.safeInsets.top - 57);
    [self.overlayNode addChild:heading];
    NSString *closeTitle = [title isEqualToString:@"ENDING GUIDE"] ? @"BACK" : @"RESUME";
    SKShapeNode *close = [self button:@"overlay_close" title:closeTitle size:CGSizeMake(118, 36) primary:YES];
    close.position = CGPointMake(self.size.width / 2, self.safeInsets.bottom + 63);
    [self.overlayNode addChild:close];
    [self addChild:self.overlayNode];
}

- (void)closeOverlay {
    [self.overlayNode removeFromParent];
    self.overlayNode = nil;
    if (self.screenBeforeOverlay == GameScreenGallery) {
        // Rebuilding the gallery normally starts at the prologue. Preserve
        // the user's current tree position when they cancel a jump dialog.
        CGFloat savedTreeOffset = self.treeScrollOffset;
        [self showGallery];
        self.treeScrollOffset = MIN(self.treeMaximumScrollOffset, MAX(0, savedTreeOffset));
        self.treeContentNode.position = CGPointMake(0, self.treeViewportBottom - self.treeScrollOffset);
    }
    else if (self.screenBeforeOverlay == GameScreenSettings) { [self showSettings]; }
    else if (self.screenBeforeOverlay == GameScreenCredits) { self.screen = GameScreenCredits; }
    else { self.screen = GameScreenStory; }
}

#pragma mark - Gallery and settings

- (void)showGallery {
    self.screen = GameScreenGallery;
    [self cancelTransientStoryWork];
    if (!self.engine) {
        NSDictionary *payload = SaveManager.shared.autosave;
        [self loadEngineFromPayload:payload ?: @{}];
    }
    [self removeAllChildren];
    self.backgroundNode = nil;
    [self setBackgroundNamed:@"environment_new_film_classroom_september" immediate:YES];
    SKSpriteNode *shade = [SKSpriteNode spriteNodeWithColor:[SKColor colorWithWhite:0 alpha:0.68] size:self.size];
    shade.position = CGPointMake(self.size.width / 2, self.size.height / 2); shade.zPosition = -10; [self addChild:shade];
    SKLabelNode *heading = [self label:@"MEMORY TREE" size:25 weight:@"AvenirNext-DemiBold"];
    heading.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    heading.position = CGPointMake(self.size.width / 2, self.size.height - self.safeInsets.top - 50);
    [self addChild:heading];
    SKLabelNode *scrollHint = [self label:@"Swipe to browse chapters, scenes, and endings" size:10 weight:@"AvenirNext-Regular"];
    scrollHint.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    scrollHint.position = CGPointMake(self.size.width / 2, self.size.height - self.safeInsets.top - 73);
    scrollHint.fontColor = [SKColor colorWithWhite:1 alpha:0.62];
    [self addChild:scrollHint];
    // The tree always keeps every chapter branch in a stable position. A branch
    // becomes usable once any of its nodes has been read, even after rewinding.
    NSDictionary<NSString *, NSDictionary *> *storyNodes = self.engine.content[@"nodes"];
    NSArray<NSString *> *sortedNodeIDs = [storyNodes.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        NSInteger leftNumber = left.length > 1 ? [[left substringFromIndex:1] integerValue] : NSIntegerMax;
        NSInteger rightNumber = right.length > 1 ? [[right substringFromIndex:1] integerValue] : NSIntegerMax;
        return leftNumber == rightNumber ? [left compare:right] : (leftNumber < rightNumber ? NSOrderedAscending : NSOrderedDescending);
    }];
    // Derive this from the localized content instead of relying on source-
    // language chapter names. Traversing node IDs keeps the tree chronological
    // rather than inheriting NSDictionary's undefined key order.
    NSMutableArray<NSString *> *chapters = [NSMutableArray array];
    for (NSString *storyNodeID in sortedNodeIDs) {
        NSDictionary *storyNode = storyNodes[storyNodeID];
        NSString *chapter = storyNode[@"chapter"];
        if (chapter.length && ![chapters containsObject:chapter]) [chapters addObject:chapter];
    }
    NSMutableArray<NSString *> *chapterNodeIDs = [NSMutableArray arrayWithCapacity:chapters.count];
    for (NSString *chapter in chapters) {
        BOOL chapterHasBeenRead = NO;
        NSString *chapterStartNodeID = nil;
        NSInteger chapterStartNodeNumber = NSIntegerMax;
        for (NSString *nodeID in storyNodes) {
            NSDictionary *storyNode = storyNodes[nodeID];
            if (![storyNode[@"chapter"] isEqualToString:chapter]) { continue; }
            NSInteger nodeNumber = nodeID.length > 1 ? [[nodeID substringFromIndex:1] integerValue] : NSIntegerMax;
            if (nodeNumber < chapterStartNodeNumber) {
                chapterStartNodeNumber = nodeNumber;
                chapterStartNodeID = nodeID;
            }
            if ([self.engine.state.readNodeIDs containsObject:nodeID]) { chapterHasBeenRead = YES; }
        }
        [chapterNodeIDs addObject:chapterHasBeenRead ? (chapterStartNodeID ?: @"") : @""];
    }
    self.treeChapterNodeIDs = chapterNodeIDs;
    // Unlike the old fixed tree, this content viewport grows with the number
    // of chapters, scenes and endings.  It is deliberately scrollable so type
    // can remain at a comfortable reading size on every portrait device.
    self.treeViewportTop = self.size.height - self.safeInsets.top - 86;
    self.treeViewportBottom = self.safeInsets.bottom + 118;
    CGFloat treeViewportHeight = self.treeViewportTop - self.treeViewportBottom;
    SKCropNode *treeCrop = [SKCropNode node];
    SKShapeNode *treeMask = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(self.size.width - 28, treeViewportHeight) cornerRadius:8];
    treeMask.fillColor = SKColor.whiteColor;
    treeMask.strokeColor = SKColor.clearColor;
    treeMask.position = CGPointMake(self.size.width / 2, self.treeViewportBottom + treeViewportHeight / 2);
    treeCrop.maskNode = treeMask;
    [self addChild:treeCrop];

    self.treeContentNode = [SKNode node];
    self.treeContentNode.zPosition = 3;
    [treeCrop addChild:self.treeContentNode];
    CGFloat contentWidth = MIN(self.size.width - 48, 340);
    CGFloat y = 0;
    NSMutableArray<NSString *> *sceneNodeIDs = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)chapters.count; i++) {
        NSString *chapter = chapters[i];
        NSString *nodeID = chapterNodeIDs[i];
        BOOL unlocked = nodeID.length > 0;
        y -= 27;
        SKShapeNode *chapterButton = [self memoryTreeChapterButton:(unlocked ? [NSString stringWithFormat:@"tree_chapter_%ld", (long)i] : @"tree_locked") title:[self displayChapter:chapter] size:CGSizeMake(contentWidth, 46) primary:[storyNodes[self.engine.state.currentNodeID][@"chapter"] isEqualToString:chapter]];
        chapterButton.position = CGPointMake(self.size.width / 2, y); chapterButton.alpha = unlocked ? 1 : 0.42;
        [self.treeContentNode addChild:chapterButton];
        y -= 33;

        // A chapter transition marker deliberately carries the previous
        // scene's name for routing. Only a marker whose own text equals the
        // scene name is a real scene heading; this excludes the duplicated
        // last scene of the preceding chapter.
        NSMutableArray<NSString *> *sceneNames = [NSMutableArray array];
        for (NSString *storyNodeID in sortedNodeIDs) {
            NSDictionary *storyNode = storyNodes[storyNodeID];
            NSString *sceneName = storyNode[@"scene"];
            if (![storyNode[@"chapter"] isEqualToString:chapter] || ![storyNode[@"type"] isEqualToString:@"chapter"] || !sceneName.length) { continue; }
            if ([sceneName hasPrefix:@"Ending"] || [sceneName isEqualToString:@"Unlock Conditions"]) { continue; }
            if ([storyNode[@"text"] isEqualToString:sceneName] && ![sceneNames containsObject:sceneName]) {
                [sceneNames addObject:sceneName];
            }
        }
        for (NSString *sceneName in sceneNames) {
            NSString *sceneStartNodeID = nil;
            BOOL sceneHasBeenRead = NO;
            for (NSString *storyNodeID in sortedNodeIDs) {
                NSDictionary *storyNode = storyNodes[storyNodeID];
                if (![storyNode[@"chapter"] isEqualToString:chapter] || ![storyNode[@"scene"] isEqualToString:sceneName]) { continue; }
                if (!sceneStartNodeID) { sceneStartNodeID = storyNodeID; }
                if ([self.engine.state.readNodeIDs containsObject:storyNodeID]) { sceneHasBeenRead = YES; }
            }
            NSInteger sceneIndex = sceneNodeIDs.count;
            [sceneNodeIDs addObject:(sceneHasBeenRead ? (sceneStartNodeID ?: @"") : @"")];
            y -= 18;
            SKShapeNode *sceneRow = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(contentWidth - 30, 30) cornerRadius:7];
            sceneRow.name = sceneHasBeenRead ? [NSString stringWithFormat:@"tree_scene_%ld", (long)sceneIndex] : @"tree_locked";
            sceneRow.fillColor = [SKColor colorWithWhite:0.04 alpha:0.72];
            sceneRow.strokeColor = [SKColor colorWithWhite:1 alpha:0.16]; sceneRow.lineWidth = 1;
            sceneRow.position = CGPointMake(self.size.width / 2 + 15, y); sceneRow.alpha = sceneHasBeenRead ? 1 : 0.40;
            sceneRow.userData = [@{ @"primary": @NO } mutableCopy];
            [self.treeContentNode addChild:sceneRow];
            SKShapeNode *dot = [SKShapeNode shapeNodeWithCircleOfRadius:3.5];
            dot.fillColor = sceneHasBeenRead ? [SKColor colorWithRed:0.42 green:0.76 blue:0.92 alpha:1] : [SKColor colorWithWhite:0.58 alpha:0.7];
            dot.strokeColor = SKColor.clearColor; dot.position = CGPointMake(-contentWidth / 2 + 32, 0);
            [sceneRow addChild:dot];
            SKLabelNode *sceneLabel = [self label:sceneName size:14 weight:@"PingFangSC-Medium"];
            sceneLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
            sceneLabel.position = CGPointMake(-contentWidth / 2 + 45, 0); sceneLabel.fontColor = [SKColor colorWithWhite:1 alpha:sceneHasBeenRead ? 0.88 : 0.55];
            [sceneRow addChild:sceneLabel];
            y -= 18;
        }
        y -= 13;
    }
    self.treeSceneNodeIDs = sceneNodeIDs;
    NSArray *endingIDs = @[ @"summer_only", @"no_fifth_person", @"other_side_of_sea", @"after_screening", @"letter_to_september" ];
    NSArray *titles = @[ @"Only Summer Remains", @"No Fifth Person", @"The Other Side of the Sea", @"After the Screening", @"A Letter to September" ];
    NSSet *unlocked = SaveManager.shared.unlockedEndings;
    y -= 18;
    SKLabelNode *endingHeading = [self label:@"ENDING SCREENINGS" size:17 weight:@"AvenirNext-DemiBold"];
    endingHeading.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    endingHeading.position = CGPointMake(self.size.width / 2, y); endingHeading.fontColor = [SKColor colorWithRed:0.62 green:0.85 blue:0.96 alpha:1];
    [self.treeContentNode addChild:endingHeading];
    y -= 38;
    for (NSInteger i = 0; i < (NSInteger)endingIDs.count; i++) {
        BOOL filled = [unlocked containsObject:endingIDs[i]];
        SKShapeNode *endingButton = [self button:(filled ? [NSString stringWithFormat:@"tree_ending_%@", endingIDs[i]] : @"tree_locked") title:titles[i] size:CGSizeMake(contentWidth, 46) primary:filled];
        endingButton.position = CGPointMake(self.size.width / 2, y); endingButton.alpha = filled ? 1 : 0.42;
        [self.treeContentNode addChild:endingButton];
        y -= 60;
    }
    y -= 18;
    CGFloat contentHeight = -y;
    // Convert the temporary top-down negative coordinates into the same
    // bottom-origin positive coordinate space used by LOG.  This makes the
    // scroll limits exact instead of trying to compensate for two opposing
    // coordinate conventions during every gesture.
    for (SKNode *child in self.treeContentNode.children) {
        child.position = CGPointMake(child.position.x, child.position.y + contentHeight);
    }
    self.treeMaximumScrollOffset = MAX(0, contentHeight - treeViewportHeight);
    self.treeScrollOffset = self.treeMaximumScrollOffset;
    self.treeContentNode.position = CGPointMake(0, self.treeViewportBottom - self.treeScrollOffset);

    SKLabelNode *note = [self label:@"Unlocked chapters and endings can be replayed." size:11 weight:@"AvenirNext-Regular"];
    note.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter; note.position = CGPointMake(self.size.width / 2, self.safeInsets.bottom + 88); note.fontColor = [SKColor colorWithWhite:1 alpha:0.65]; note.zPosition = 10; [self addChild:note];
    SKShapeNode *back = [self button:@"back_from_tree" title:@"BACK" size:CGSizeMake(130, 42) primary:YES];
    // A crop node clips rendering only. Keep this above its scroll content so
    // an off-screen row cannot steal the return-button tap.
    back.position = CGPointMake(self.size.width / 2, self.safeInsets.bottom + 54); back.zPosition = 20; [self addChild:back];
}

- (void)showRewindConfirmationForIndex:(NSInteger)index {
    self.pendingRewindIndex = index;
    [self showOverlayPanelWithTitle:@"REWIND THIS BRANCH?"];
    SKLabelNode *body = [self label:@"Watch a rewarded ad before returning to this checkpoint." size:12 weight:@"AvenirNext-Regular"];
    body.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter; body.position = CGPointMake(self.size.width / 2, self.size.height / 2 + 32); [self.overlayNode addChild:body];
    SKLabelNode *fallback = [self label:@"If no ad is available, the rewind is free." size:10 weight:@"AvenirNext-Regular"];
    fallback.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter; fallback.position = CGPointMake(self.size.width / 2, self.size.height / 2 + 5); fallback.fontColor = [SKColor colorWithWhite:1 alpha:0.66]; [self.overlayNode addChild:fallback];
    SKShapeNode *confirm = [self button:@"rewind_confirm" title:@"WATCH AD & REWIND" size:CGSizeMake(230, 42) primary:YES]; confirm.position = CGPointMake(self.size.width / 2, self.size.height / 2 - 60); [self.overlayNode addChild:confirm];
}

- (void)showSettings {
    self.screen = GameScreenSettings;
    [self removeAllChildren]; self.backgroundNode = nil;
    [self setBackgroundNamed:@"environment_home_background" immediate:YES];
    SKSpriteNode *shade = [SKSpriteNode spriteNodeWithColor:[SKColor colorWithWhite:0 alpha:0.76] size:self.size];
    shade.position = CGPointMake(self.size.width / 2, self.size.height / 2); shade.zPosition = -10; [self addChild:shade];
    SKLabelNode *heading = [self label:@"SETTINGS" size:26 weight:@"AvenirNext-DemiBold"];
    heading.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    heading.position = CGPointMake(self.size.width / 2, self.size.height - self.safeInsets.top - 62); [self addChild:heading];
    SKLabelNode *autosave = [self label:@"Changes are saved automatically." size:11 weight:@"AvenirNext-Regular"];
    autosave.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    autosave.position = CGPointMake(self.size.width / 2, self.size.height - self.safeInsets.top - 94);
    autosave.fontColor = [SKColor colorWithWhite:1 alpha:0.68];
    [self addChild:autosave];
    CGFloat y = self.size.height - self.safeInsets.top - 150;
    [self addSliderWithTitle:@"MUSIC VOLUME" key:@"music" value:AudioManager.shared.musicVolume y:y];
    y -= 86;
    [self addSliderWithTitle:@"EFFECTS VOLUME" key:@"effects" value:AudioManager.shared.effectsVolume y:y];
    y -= 86;
    [self addSliderWithTitle:@"TEXT SPEED" key:@"speed" value:[NSUserDefaults.standardUserDefaults floatForKey:@"textSpeed"] y:y];
    y -= 78;
    [self addSliderWithTitle:@"AUTO PLAY INTERVAL" key:@"autoInterval" value:[NSUserDefaults.standardUserDefaults floatForKey:@"autoInterval"] y:y];
    y -= 78;
    NSArray *toggles = @[@[@"ALLOW UNREAD FAST-FORWARD", @"allowUnreadSkip"], @[@"REDUCE FLASH & MOTION", @"reduceMotion"]];
    for (NSArray *toggle in toggles) {
        BOOL on = [NSUserDefaults.standardUserDefaults boolForKey:toggle[1]];
        SKLabelNode *name = [self label:toggle[0] size:13 weight:@"AvenirNext-Medium"]; name.position = CGPointMake(34, y); [self addChild:name];
        SKShapeNode *button = [self button:[NSString stringWithFormat:@"toggle_%@", toggle[1]] title:on ? @"ON" : @"OFF" size:CGSizeMake(70, 36) primary:on];
        button.position = CGPointMake(self.size.width - 55, y); [self addChild:button]; y -= 66;
    }
    SKLabelNode *privacy = [self label:@"Core story, saves and settings work offline." size:9 weight:@"AvenirNext-Regular"];
    privacy.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter; privacy.position = CGPointMake(self.size.width / 2, y - 8); privacy.fontColor = [SKColor colorWithWhite:1 alpha:0.66]; [self addChild:privacy];
    SKLabelNode *ads = [self label:@"Ads can appear only before an active rewind request." size:9 weight:@"AvenirNext-Regular"];
    ads.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter; ads.position = CGPointMake(self.size.width / 2, y - 23); ads.fontColor = privacy.fontColor; [self addChild:ads];
    // Deliberately understated: this is the entry point for the in-game
    // ending guide, discovered by tapping it five times.
    SKShapeNode *mystery = [self button:@"mystery_guide" title:@"✦" size:CGSizeMake(38, 28) primary:NO];
    mystery.alpha = 0.42;
    mystery.position = CGPointMake(self.size.width - 34, self.safeInsets.bottom + 108);
    [self addChild:mystery];
    // Keep the footer action clear of the two explanatory lines above it on
    // short devices as well as phones with a tall home-indicator safe area.
    SKShapeNode *back = [self button:@"back_title" title:@"BACK" size:CGSizeMake(130, 42) primary:YES]; back.position = CGPointMake(self.size.width / 2, self.safeInsets.bottom + 46); [self addChild:back];
}

- (void)showEndingGuide {
    self.mysteryGuideTapCount = 0;
    [self showOverlayPanelWithTitle:@"ENDING GUIDE"];
    // This overlay previously reused the dialogue renderer, whose left-origin
    // labels made the guide appear clipped to one side on some devices.  Use
    // centered, panel-bound labels for this standalone reference page.
    CGFloat width = MIN(300, self.size.width - 72);
    SKNode *guide = [SKNode node];
    guide.position = CGPointMake(self.size.width / 2, self.size.height - self.safeInsets.top - 112);
    guide.zPosition = 101;
    NSArray<NSString *> *paragraphs = @[
        @"Standard endings: at the final choice in Chapter 5:",
        @"1  Cut the accident; leave only a happy summer → Ending 1",
        @"2  Burn every reel → Ending 2",
        @"3  Keep the broken blank; do not decide Chinatsu's ending → Ending 3",
        @"4  Restore and screen all surviving footage → Ending 4",
        @"",
        @"Hidden ending: collect all six clues first:",
        @"the fifth cup, erased writer credit, scratched-out name,",
        @"water-damaged audio, blue-glass hairclip, undeveloped photo.",
        @"Investigate widely, trust Chinatsu, ask your friends, keep the clip,",
        @"enter with Yuma, and preserve the final reel.",
        @"Choose option 4 and meet all three hidden thresholds.",
        @"FaceTruth ≥ 4　TrustFriends ≥ 3　EmpathyChinatsu ≥ 4"
    ];
    CGFloat fontSize = 10.5;
    NSArray<NSString *> *lines = [self wrappedLines:[paragraphs componentsJoinedByString:@"\n"] maxWidth:width fontSize:fontSize maxLines:24];
    for (NSInteger index = 0; index < (NSInteger)lines.count; index++) {
        SKLabelNode *line = [self label:lines[index] size:fontSize weight:@"AvenirNext-Regular"];
        line.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
        line.position = CGPointMake(0, -index * 14);
        line.fontColor = [SKColor colorWithWhite:1 alpha:0.90];
        [guide addChild:line];
    }
    [self.overlayNode addChild:guide];
}

- (void)addSliderWithTitle:(NSString *)title key:(NSString *)key value:(CGFloat)value y:(CGFloat)y {
    SKLabelNode *name = [self label:title size:14 weight:@"AvenirNext-Medium"];
    name.position = CGPointMake(34, y + 20); [self addChild:name];
    NSString *valueText = [key isEqualToString:@"autoInterval"] ? [NSString stringWithFormat:@"%.1fs", 0.7 + value * 3.3] : [NSString stringWithFormat:@"%d%%", (int)round(value * 100)];
    SKLabelNode *valueLabel = [self label:valueText size:12 weight:@"AvenirNext-Medium"];
    valueLabel.name = [NSString stringWithFormat:@"slider_value_%@", key];
    valueLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
    valueLabel.position = CGPointMake(self.size.width - 34, y + 20); [self addChild:valueLabel];
    SKNode *slider = [SKNode node];
    slider.name = [NSString stringWithFormat:@"slider_%@", key];
    slider.userData = [@{ @"key": key, @"width": @(self.size.width - 68) } mutableCopy];
    slider.position = CGPointMake(self.size.width / 2, y - 5);
    CGFloat width = [slider.userData[@"width"] floatValue];
    SKShapeNode *track = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(width, 8) cornerRadius:4];
    track.fillColor = [SKColor colorWithWhite:1 alpha:0.20]; track.strokeColor = SKColor.clearColor;
    [slider addChild:track];
    SKShapeNode *fill = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(2, 8) cornerRadius:4];
    fill.name = @"fill"; fill.fillColor = [SKColor colorWithRed:0.30 green:0.70 blue:0.95 alpha:1]; fill.strokeColor = SKColor.clearColor;
    [slider addChild:fill];
    SKShapeNode *thumb = [SKShapeNode shapeNodeWithCircleOfRadius:12];
    thumb.name = @"thumb"; thumb.fillColor = [SKColor colorWithRed:0.86 green:0.96 blue:1 alpha:1]; thumb.strokeColor = [SKColor colorWithRed:0.15 green:0.40 blue:0.60 alpha:1]; thumb.lineWidth = 2;
    [slider addChild:thumb];
    [self addChild:slider];
    [self setSliderKey:key value:value];
}

- (void)setSliderKey:(NSString *)key value:(CGFloat)value {
    value = MIN(1, MAX(0, value));
    if ([key isEqualToString:@"music"]) { AudioManager.shared.musicVolume = value; }
    else if ([key isEqualToString:@"effects"]) { AudioManager.shared.effectsVolume = value; }
    else if ([key isEqualToString:@"autoInterval"]) { [NSUserDefaults.standardUserDefaults setFloat:value forKey:@"autoInterval"]; }
    else { [NSUserDefaults.standardUserDefaults setFloat:value forKey:@"textSpeed"]; }
    SKNode *slider = [self childNodeWithName:[NSString stringWithFormat:@"//slider_%@", key]];
    if (!slider) { return; }
    CGFloat width = [slider.userData[@"width"] floatValue];
    SKShapeNode *fill = (SKShapeNode *)[slider childNodeWithName:@"fill"];
    SKShapeNode *thumb = (SKShapeNode *)[slider childNodeWithName:@"thumb"];
    CGFloat fillWidth = MAX(2, width * value);
    CGPathRef fillPath = CGPathCreateWithRoundedRect(CGRectMake(-fillWidth / 2, -4, fillWidth, 8), 4, 4, NULL);
    fill.path = fillPath;
    CGPathRelease(fillPath);
    fill.position = CGPointMake(-width / 2 + fillWidth / 2, 0);
    thumb.position = CGPointMake(-width / 2 + width * value, 0);
    SKLabelNode *label = (SKLabelNode *)[self childNodeWithName:[NSString stringWithFormat:@"//slider_value_%@", key]];
    label.text = [key isEqualToString:@"autoInterval"] ? [NSString stringWithFormat:@"%.1fs", 0.7 + value * 3.3] : [NSString stringWithFormat:@"%d%%", (int)round(value * 100)];
}

- (void)toggleSettingNamed:(NSString *)name {
    NSString *key = [name substringFromIndex:@"toggle_".length];
    [NSUserDefaults.standardUserDefaults setBool:![NSUserDefaults.standardUserDefaults boolForKey:key] forKey:key];
    [self showSettings];
}

- (void)showEndingCompletion {
    if ([self.endingID isEqualToString:@"letter_to_september"] && !self.hiddenEndingCreditsPlaying) {
        [self showHiddenEndingCredits];
        return;
    }
    [self showEndingCompletionScreen];
}

- (void)showEndingCompletionScreen {
    BOOL wasPlayingHiddenEndingCredits = self.hiddenEndingCreditsPlaying;
    self.hiddenEndingCreditsPlaying = NO;
    [self removeActionForKey:@"hiddenEndingCreditsFinish"];
    if (wasPlayingHiddenEndingCredits) { [[AudioManager shared] stop]; }
    self.screen = GameScreenEnding;
    self.endingComplete = YES;
    [SaveManager.shared setShouldStartFresh:YES];
    [self persistAutosave];
    [self clearSceneKeepingBackground:YES];
    SKSpriteNode *shade = [SKSpriteNode spriteNodeWithColor:SKColor.blackColor size:self.size];
    shade.position = CGPointMake(self.size.width / 2, self.size.height / 2); shade.zPosition = 5; shade.alpha = 0; [self addChild:shade];
    SKNode *completionContent = [SKNode node]; completionContent.alpha = 0; completionContent.zPosition = 10; [self addChild:completionContent];
    SKLabelNode *end = [self label:@"SCREENING COMPLETE" size:22 weight:@"AvenirNext-DemiBold"]; end.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter; end.position = CGPointMake(self.size.width / 2, self.size.height * 0.60); [completionContent addChild:end];
    SKLabelNode *count = [self label:[NSString stringWithFormat:@"%lu of 5 endings unlocked", (unsigned long)SaveManager.shared.unlockedEndings.count] size:13 weight:@"AvenirNext-Regular"]; count.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter; count.position = CGPointMake(self.size.width / 2, self.size.height * 0.54); [completionContent addChild:count];
    SKShapeNode *gallery = [self button:@"gallery" title:@"VIEW MEMORIES" size:CGSizeMake(240, 45) primary:YES]; gallery.position = CGPointMake(self.size.width / 2, self.size.height * 0.40); [completionContent addChild:gallery];
    SKShapeNode *menu = [self button:@"back_title" title:@"TITLE SCREEN" size:CGSizeMake(240, 45) primary:NO]; menu.position = CGPointMake(self.size.width / 2, self.size.height * 0.32); [completionContent addChild:menu];
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"reduceMotion"]) {
        shade.alpha = 1;
        completionContent.alpha = 1;
    } else {
        [shade runAction:[SKAction sequence:@[
            [SKAction fadeInWithDuration:0.65],
            [SKAction runBlock:^{ [completionContent runAction:[SKAction fadeInWithDuration:0.24]]; }]
        ]]];
    }
}

- (void)addCreditsText:(NSString *)text toNode:(SKNode *)node x:(CGFloat)x y:(CGFloat)y size:(CGFloat)size weight:(NSString *)weight alpha:(CGFloat)alpha {
    SKLabelNode *label = [self label:text size:size weight:weight];
    label.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    label.position = CGPointMake(x, y);
    label.fontColor = [SKColor colorWithWhite:1 alpha:alpha];
    [node addChild:label];
}

- (CGFloat)addCreditsImageNamed:(NSString *)imageName toNode:(SKNode *)node top:(CGFloat)top {
    SKTexture *texture = [SKTexture textureWithImageNamed:imageName];
    if (texture.size.width <= 1) { return top; }
    CGFloat width = self.size.width * 0.72;
    CGFloat height = width * texture.size.height / texture.size.width;
    SKSpriteNode *image = [SKSpriteNode spriteNodeWithTexture:texture];
    image.size = CGSizeMake(width, height);
    image.position = CGPointMake(self.size.width / 2, top - height / 2);
    image.alpha = 0.92;
    [node addChild:image];
    SKShapeNode *frame = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(width + 10, height + 10) cornerRadius:2];
    frame.position = image.position;
    frame.strokeColor = [SKColor colorWithWhite:1 alpha:0.42];
    frame.lineWidth = 1;
    frame.fillColor = SKColor.clearColor;
    [node addChild:frame];
    return top - height - 118;
}

- (void)showHiddenEndingCredits {
    static const NSTimeInterval kCreditsDuration = 323.0;
    static const NSTimeInterval kFinalPhotoHoldDuration = 6.0;
    static const NSTimeInterval kCreditsRollDuration = kCreditsDuration - kFinalPhotoHoldDuration;
    self.screen = GameScreenCredits;
    self.hiddenEndingCreditsPlaying = YES;
    self.endingComplete = YES;
    [self cancelTransientStoryWork];
    [SaveManager.shared setShouldStartFresh:YES];
    [self persistAutosave];
    [self removeActionForKey:@"hiddenEndingCreditsFinish"];
    [self removeAllChildren];
    self.backgroundNode = nil;
    self.portraitNode = nil;
    self.choiceNode = nil;
    self.dialogueTextNode = nil;
    self.overlayNode = nil;
    self.backgroundColor = SKColor.blackColor;
    [[AudioManager shared] playMusicNamed:@"E07_last_thirty_seconds" looping:NO];

    SKNode *roll = [SKNode node];
    roll.name = @"hidden_ending_credits_roll";
    roll.zPosition = 10;
    [self addChild:roll];

    // The longer reel gives the 5:23 song enough readable material to carry;
    // the credits should feel like a real film ending, not a slow empty crawl.
    CGFloat contentHeight = MAX(6400, self.size.height + 5550);
    CGFloat y = contentHeight - 90;
    CGFloat center = self.size.width / 2;
    [self addCreditsText:@"THE END-OF-SUMMER SCREENING ROOM" toNode:roll x:center y:y size:19 weight:@"AvenirNext-DemiBold" alpha:1];
    y -= 34;
    [self addCreditsText:@"THE LAST THIRTY SECONDS" toNode:roll x:center y:y size:12 weight:@"AvenirNext-Regular" alpha:0.76];
    y -= 175;

    NSArray<NSString *> *images = @[
        @"cg_main_01_first_screening",
        @"EndingCreditsFiveYears",
        @"cg_main_05_rain_headphones",
        @"EndingCreditsBlueHairclip",
        @"EndingCreditsFilmCanister",
        @"cg_end5_02_five_preparing",
        @"cg_end5_03_face_camera",
        @"cg_end4_01_restoration_table"
    ];
    NSArray<NSArray<NSString *> *> *creditBlocks = @[
        @[ @"CAST", @"Shiori  ·  Akari  ·  Chinatsu  ·  Riku  ·  Yuma" ],
        @[ @"STORY & SCENARIO", @"Lihua  ·  ChatGPT" ],
        @[ @"ART & VISUAL DESIGN", @"ChatGPT  ·  Doubao" ],
        @[ @"PROP & COSTUME DESIGN", @"ChatGPT" ],
        @[ @"FILM & EDITING", @"Lihua  ·  ChatGPT" ],
        @[ @"PROGRAMMING", @"Lihua  ·  ChatGPT" ],
        @[ @"MUSIC & SOUND", @"Suno  ·  ElevenLabs" ],
        @[ @"SPECIAL THANKS", @"To everyone who stayed until the end." ]
    ];
    for (NSInteger index = 0; index < (NSInteger)creditBlocks.count; index++) {
        if (index < (NSInteger)images.count) { y = [self addCreditsImageNamed:images[index] toNode:roll top:y]; }
        NSArray<NSString *> *block = creditBlocks[index];
        [self addCreditsText:block[0] toNode:roll x:center y:y size:12 weight:@"AvenirNext-DemiBold" alpha:0.95];
        y -= 28;
        [self addCreditsText:block[1] toNode:roll x:center y:y size:11 weight:@"AvenirNext-Regular" alpha:0.72];
        y -= 170;
        if (index == 1) {
            [self addCreditsText:@"Thank you for walking with them through the summer." toNode:roll x:center y:y size:13 weight:@"AvenirNext-Regular" alpha:0.90];
            y -= 155;
        }
        if (index == 7) {
            [self addCreditsText:@"All characters, places, and events in this work are fictional." toNode:roll x:center y:y size:11 weight:@"AvenirNext-Regular" alpha:0.68];
            y -= 42;
            [self addCreditsText:@"During a typhoon, stay indoors and avoid unnecessary travel." toNode:roll x:center y:y size:11 weight:@"AvenirNext-Regular" alpha:0.82];
            y -= 28;
            [self addCreditsText:@"Follow weather alerts issued by your local authorities." toNode:roll x:center y:y size:11 weight:@"AvenirNext-Regular" alpha:0.68];
            y -= 155;
        }
    }

    [self addCreditsText:@"THANK YOU FOR WATCHING" toNode:roll x:center y:y size:14 weight:@"AvenirNext-DemiBold" alpha:1];
    y -= 72;
    [self addCreditsText:@"SEPTEMBER 1" toNode:roll x:center y:y size:10 weight:@"AvenirNext-Regular" alpha:0.70];
    y -= 52;
    [self addCreditsText:@"See you after the summer." toNode:roll x:center y:y size:12 weight:@"AvenirNext-Regular" alpha:0.88];
    y -= 145;
    // The September 1 group photo is intentionally the final content in the
    // reel. Nothing follows it, so it remains the emotional end frame.
    SKTexture *finalPhotoTexture = [SKTexture textureWithImageNamed:@"EndingCreditsSeptemberFirst"];
    CGFloat finalPhotoWidth = self.size.width * 0.72;
    CGFloat finalPhotoHeight = finalPhotoTexture.size.width > 1 ? finalPhotoWidth * finalPhotoTexture.size.height / finalPhotoTexture.size.width : 0;
    CGFloat finalPhotoCenterY = y - finalPhotoHeight / 2;
    y = [self addCreditsImageNamed:@"EndingCreditsSeptemberFirst" toNode:roll top:y];

    // Move a single credits reel upward at a constant speed. The last six
    // seconds are reserved for the final group photo to settle at screen
    // center instead of scrolling off the viewport.
    roll.position = CGPointMake(0, -contentHeight);
    CGFloat finalRollY = self.size.height / 2 - finalPhotoCenterY;
    [roll runAction:[SKAction sequence:@[
        [SKAction moveTo:CGPointMake(0, finalRollY) duration:kCreditsRollDuration],
        [SKAction waitForDuration:kFinalPhotoHoldDuration]
    ]]];

    SKShapeNode *skip = [self button:@"credits_skip" title:@"SKIP CREDITS" size:CGSizeMake(132, 28) primary:NO];
    skip.position = CGPointMake(center, self.safeInsets.bottom + 28);
    skip.zPosition = 30;
    skip.alpha = 0.64;
    [self addChild:skip];
    [self runAction:[SKAction sequence:@[
        [SKAction waitForDuration:kCreditsDuration],
        [SKAction runBlock:^{ [self transitionToTitleAfterCredits]; }]
    ]] withKey:@"hiddenEndingCreditsFinish"];
}

- (void)transitionToTitleAfterCredits {
    [self removeActionForKey:@"hiddenEndingCreditsFinish"];
    [[AudioManager shared] stop];
    SKSpriteNode *fadeOut = [SKSpriteNode spriteNodeWithColor:SKColor.blackColor size:self.size];
    fadeOut.position = CGPointMake(self.size.width / 2, self.size.height / 2);
    fadeOut.zPosition = 500;
    fadeOut.alpha = 0;
    [self addChild:fadeOut];
    [fadeOut runAction:[SKAction sequence:@[
        [SKAction fadeInWithDuration:1.0],
        [SKAction runBlock:^{
            [self showTitleScreen];
            SKSpriteNode *reveal = [SKSpriteNode spriteNodeWithColor:SKColor.blackColor size:self.size];
            reveal.position = CGPointMake(self.size.width / 2, self.size.height / 2);
            reveal.zPosition = 500;
            [self addChild:reveal];
            [reveal runAction:[SKAction sequence:@[
                [SKAction fadeOutWithDuration:0.9],
                [SKAction removeFromParent]
            ]]];
        }]
    ]] withKey:@"creditsToTitleFade"];
}

- (void)showNotice:(NSString *)message {
    SKLabelNode *notice = [self label:message size:11 weight:@"AvenirNext-Medium"];
    notice.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    notice.position = CGPointMake(self.size.width / 2, self.safeInsets.bottom + 18);
    notice.zPosition = 200; notice.fontColor = [SKColor colorWithRed:0.75 green:0.90 blue:1 alpha:1];
    [self addChild:notice];
    [notice runAction:[SKAction sequence:@[[SKAction waitForDuration:2], [SKAction fadeOutWithDuration:0.3], [SKAction removeFromParent]]]];
}

- (void)flash {
    SKSpriteNode *flash = [SKSpriteNode spriteNodeWithColor:SKColor.whiteColor size:self.size];
    flash.position = CGPointMake(self.size.width / 2, self.size.height / 2); flash.zPosition = 90; flash.alpha = 0; [self addChild:flash];
    [flash runAction:[SKAction sequence:@[[SKAction fadeAlphaTo:0.75 duration:0.07], [SKAction fadeOutWithDuration:0.28], [SKAction removeFromParent]]]];
}

#pragma mark - Touches

- (SKNode *)sliderAncestorAtPoint:(CGPoint)point {
    SKNode *node = [self nodeAtPoint:point];
    while (node) {
        if ([node.name hasPrefix:@"slider_"]) { return node; }
        node = node.parent;
    }
    return nil;
}

- (void)updateActiveSliderAtPoint:(CGPoint)point {
    if (self.activeSliderKey.length == 0) { return; }
    SKNode *slider = [self childNodeWithName:[NSString stringWithFormat:@"//slider_%@", self.activeSliderKey]];
    if (!slider) { return; }
    CGPoint local = [self convertPoint:point toNode:slider];
    CGFloat width = [slider.userData[@"width"] floatValue];
    [self setSliderKey:self.activeSliderKey value:(local.x + width / 2) / width];
}

- (void)performActionForName:(NSString *)name {
    if ([name isEqualToString:@"credits_skip"] && self.screen == GameScreenCredits) {
        [self showCreditsSkipConfirmation];
        return;
    }
    if ([name isEqualToString:@"credits_skip_confirm"] && self.screen == GameScreenCredits) {
        [self.overlayNode removeFromParent];
        self.overlayNode = nil;
        [self transitionToTitleAfterCredits];
        return;
    }
    if (self.screen == GameScreenSettings && ![name isEqualToString:@"mystery_guide"]) {
        self.mysteryGuideTapCount = 0;
    }
    if ([name isEqualToString:@"overlay_close"]) { [self closeOverlay]; return; }
    if ([name isEqualToString:@"rewind_confirm"]) {
        NSInteger index = self.pendingRewindIndex;
        [[AudioManager shared] pause];
        __weak typeof(self) weakSelf = self;
        [[AdManager shared] requestRewardedAdWithCompletion:^(RewardedAdResult result) {
            GameScene *scene = weakSelf;
            [[AudioManager shared] resume];
            if (!scene || result == RewardedAdResultUserClosed) { return; }
            if ([scene.engine rewindToCheckpointAtIndex:index]) {
                [scene persistAutosave];
                [scene.overlayNode removeFromParent];
                [scene presentCurrentNode];
            }
        }];
        return;
    }
    if ([name isEqualToString:@"tree_chapter_confirm"]) {
        NSInteger index = self.pendingTreeChapterIndex;
        NSString *nodeID = index >= 0 && index < (NSInteger)self.treeChapterNodeIDs.count ? self.treeChapterNodeIDs[index] : nil;
        if (nodeID.length && self.engine.content[@"nodes"][nodeID]) {
            [self showNotice:@"Loading rewarded ad…"];
            [[AudioManager shared] pause];
            __weak typeof(self) weakSelf = self;
            [[AdManager shared] requestRewardedAdWithCompletion:^(RewardedAdResult result) {
                GameScene *scene = weakSelf;
                NSLog(@"[MemoryTree] chapter ad finished, result=%ld target=%@", (long)result, nodeID);
                [[AudioManager shared] resume];
                // A closed ad cancels this jump; no-fill/network failures keep
                // the original offline-friendly chapter navigation behavior.
                if (!scene || result == RewardedAdResultUserClosed) return;
                scene.engine.state.currentNodeID = nodeID;
                scene.endingComplete = NO;
                [scene pruneDialogueLogForCurrentNode];
                [scene persistAutosave];
                [scene.overlayNode removeFromParent]; scene.overlayNode = nil;
                [scene presentCurrentNode];
                NSLog(@"[MemoryTree] chapter jump committed, current=%@", scene.engine.state.currentNodeID);
            }];
        }
        return;
    }
    if ([name isEqualToString:@"tree_scene_confirm"]) {
        if (self.pendingJumpNodeID.length && self.engine.content[@"nodes"][self.pendingJumpNodeID]) {
            NSString *nodeID = self.pendingJumpNodeID;
            [self showNotice:@"Loading rewarded ad…"];
            [[AudioManager shared] pause];
            __weak typeof(self) weakSelf = self;
            [[AdManager shared] requestRewardedAdWithCompletion:^(RewardedAdResult result) {
                GameScene *scene = weakSelf;
                NSLog(@"[MemoryTree] scene ad finished, result=%ld target=%@", (long)result, nodeID);
                [[AudioManager shared] resume];
                if (!scene || result == RewardedAdResultUserClosed) { return; }
                scene.engine.state.currentNodeID = nodeID;
                scene.endingComplete = NO;
                [scene pruneDialogueLogForCurrentNode];
                [scene persistAutosave];
                [scene.overlayNode removeFromParent]; scene.overlayNode = nil;
                [scene presentCurrentNode];
                NSLog(@"[MemoryTree] scene jump committed, current=%@", scene.engine.state.currentNodeID);
            }];
        }
        return;
    }
    if ([name hasPrefix:@"tree_scene_"]) {
        NSInteger index = [[[name componentsSeparatedByString:@"_"] lastObject] integerValue];
        NSString *nodeID = index >= 0 && index < (NSInteger)self.treeSceneNodeIDs.count ? self.treeSceneNodeIDs[index] : nil;
        if (nodeID.length && self.engine.content[@"nodes"][nodeID]) {
            self.pendingJumpNodeID = nodeID;
            [self showConfirmationWithTitle:@"JUMP TO SCENE?" message:@"Resume this scene from its opening line." confirmName:@"tree_scene_confirm" buttonTitle:@"JUMP TO SCENE"];
        }
        return;
    }
    if ([name hasPrefix:@"tree_chapter_"]) {
        NSInteger index = [[[name componentsSeparatedByString:@"_"] lastObject] integerValue];
        NSString *nodeID = index >= 0 && index < (NSInteger)self.treeChapterNodeIDs.count ? self.treeChapterNodeIDs[index] : nil;
        if (nodeID.length && self.engine.content[@"nodes"][nodeID]) {
            self.pendingTreeChapterIndex = index;
            [self showConfirmationWithTitle:@"JUMP TO CHAPTER?" message:@"Resume this chapter from its opening scene." confirmName:@"tree_chapter_confirm" buttonTitle:@"JUMP TO CHAPTER"];
        }
        return;
    }
    if ([name hasPrefix:@"tree_ending_"]) {
        NSString *endingID = [name substringFromIndex:@"tree_ending_".length];
        self.pendingJumpNodeID = self.endingStartNodeIDs[endingID];
        if (self.pendingJumpNodeID.length) {
            [self showConfirmationWithTitle:@"JUMP TO ENDING?" message:@"Start this unlocked ending again from its opening scene." confirmName:@"ending_jump_confirm" buttonTitle:@"START ENDING"];
        } else {
            [self showNotice:@"This ending is unavailable in the current story data."];
        }
        return;
    }
    if ([name isEqualToString:@"ending_jump_confirm"]) {
        if (self.pendingJumpNodeID.length && self.engine.content[@"nodes"][self.pendingJumpNodeID]) {
            [self cancelTransientStoryWork];
            self.engine.state.currentNodeID = self.pendingJumpNodeID;
            self.endingID = nil;
            self.endingComplete = NO;
            self.hiddenEndingCreditsPlaying = NO;
            [self pruneDialogueLogForCurrentNode];
            [self persistAutosave];
            [self.overlayNode removeFromParent];
            self.overlayNode = nil;
            [self presentCurrentNode];
        }
        return;
    }
    if ([name isEqualToString:@"tree_locked"]) { [self showNotice:@"This branch has not been reached yet."]; return; }
    if ([name isEqualToString:@"play_primary"]) {
        BOOL newGame = !SaveManager.shared.hasSave || SaveManager.shared.shouldStartFresh || self.endingComplete;
        [self transitionFromTitleToStoryStartingNewGame:newGame];
        return;
    }
    if ([name isEqualToString:@"gallery"] || [name isEqualToString:@"tree"]) { self.galleryOpenedFromStory = (self.screen == GameScreenStory); [self showGallery]; return; }
    if ([name isEqualToString:@"settings"]) { [self showSettings]; return; }
    if ([name isEqualToString:@"mystery_guide"]) {
        self.mysteryGuideTapCount += 1;
        if (self.mysteryGuideTapCount >= 5) { [self showEndingGuide]; }
        return;
    }
    if ([name hasPrefix:@"toggle_"]) { [self toggleSettingNamed:name]; return; }
    if ([name isEqualToString:@"back_from_tree"]) { if (self.galleryOpenedFromStory && self.engine) { self.screen = GameScreenStory; [self presentCurrentNode]; } else { [self showTitleScreen]; } return; }
    if ([name isEqualToString:@"back_title"]) { [self saveForLifecycleChange]; [self showTitleScreen]; return; }
    if ([name hasPrefix:@"log_entry_"]) { self.pendingLogNodeID = [name substringFromIndex:@"log_entry_".length]; [self showConfirmationWithTitle:@"JUMP TO THIS LINE?" message:@"This returns to the selected line in the current branch." confirmName:@"log_jump_confirm" buttonTitle:@"JUMP TO LINE"]; return; }
    if ([name isEqualToString:@"log_jump_confirm"]) {
        if (self.engine.content[@"nodes"][self.pendingLogNodeID]) {
            self.engine.state.currentNodeID = self.pendingLogNodeID;
            [self pruneDialogueLogForCurrentNode];
            [self persistAutosave];
            [self.overlayNode removeFromParent]; self.overlayNode = nil;
            [self presentCurrentNode];
        }
        return;
    }
    if (self.screen != GameScreenStory) { return; }
    if ([name isEqualToString:@"menu"]) { [self showMenuConfirmation]; return; }
    if ([name isEqualToString:@"menu_confirm"]) { [self saveForLifecycleChange]; [self showTitleScreen]; return; }
    if ([name isEqualToString:@"log"]) { [self showLog]; return; }
    if ([name isEqualToString:@"auto"]) { self.autoMode = !self.autoMode; [self updateAutoButtonAppearance]; if (self.autoMode && self.textRevealing) { [self finishRevealWithWidth:self.size.width - 64 maxLines:[self.engine.currentNode[@"type"] isEqualToString:@"choice"] ? 2 : 5]; } else { [self scheduleAutoAdvance]; } return; }
    if ([name isEqualToString:@"skip"]) { [self showSkipConfirmation]; return; }
    if ([name isEqualToString:@"skip_confirm"]) {
        NSDictionary *targetChoice = [self.engine alreadyReadChoiceAfterCurrentNode];
        BOOL allowed = [self.engine isCurrentNodeRead] && targetChoice != nil;
        if (!allowed) { [self showNotice:@"SKIP is only available for choices you have already played."]; return; }
        [self.overlayNode removeFromParent]; self.overlayNode = nil;
        self.engine.state.currentNodeID = targetChoice[@"id"] ?: @"";
        [self pruneDialogueLogForCurrentNode];
        [self persistAutosave];
        [self presentCurrentNode];
        return;
    }
    if ([name hasPrefix:@"choice_"]) { [self selectChoice:[[[name componentsSeparatedByString:@"_"] lastObject] integerValue]]; return; }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint point = [touches.anyObject locationInNode:self];
    if (self.screen == GameScreenGallery && !self.overlayNode && self.treeContentNode.scene == self &&
        point.y >= self.treeViewportBottom && point.y <= self.treeViewportTop) {
        self.trackingTreeScroll = YES;
        self.draggedTree = NO;
        self.treeTouchStart = point;
        self.treeTouchStartOffset = self.treeScrollOffset;
        return;
    }
    if (self.screen == GameScreenLog && self.logContentNode.scene == self) {
        SKShapeNode *button = [self buttonAncestorAtPoint:point];
        if (![button.name isEqualToString:@"overlay_close"]) {
            self.trackingLogScroll = YES;
            self.draggedLog = NO;
            self.logTouchStart = point;
            self.logTouchStartOffset = self.logScrollOffset;
            return;
        }
    }
    SKNode *slider = [self sliderAncestorAtPoint:point];
    if (slider) {
        self.activeSliderKey = slider.userData[@"key"];
        [self updateActiveSliderAtPoint:point];
        return;
    }
    SKShapeNode *button = [self buttonAncestorAtPoint:point];
    if (button) { [self pressButton:button]; return; }
    if (self.screen != GameScreenStory) { return; }
    if (self.textRevealing) {
        CGFloat width = self.size.width - 64;
        [self finishRevealWithWidth:width maxLines:[self.engine.currentNode[@"type"] isEqualToString:@"choice"] ? 2 : 5];
    } else if (![self.engine.currentNode[@"type"] isEqualToString:@"choice"]) {
        [self advanceStory];
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint point = [touches.anyObject locationInNode:self];
    if (self.trackingTreeScroll) {
        CGFloat distance = point.y - self.treeTouchStart.y;
        if (fabs(distance) > 4) { self.draggedTree = YES; }
        // Keep the same direction convention as LOG: the finger delta is
        // subtracted from the current offset and the content follows that
        // exact movement.
        self.treeScrollOffset = MIN(self.treeMaximumScrollOffset, MAX(0, self.treeTouchStartOffset - distance));
        self.treeContentNode.position = CGPointMake(0, self.treeViewportBottom - self.treeScrollOffset);
        return;
    }
    if (self.trackingLogScroll) {
        CGFloat distance = point.y - self.logTouchStart.y;
        if (fabs(distance) > 4) { self.draggedLog = YES; }
        // Rows are laid out chronologically from top to bottom. A finger swipe
        // upward must move the content upward and reveal rows below it.
        self.logScrollOffset = MIN(self.logMaximumScrollOffset, MAX(0, self.logTouchStartOffset - distance));
        self.logContentNode.position = CGPointMake(0, self.safeInsets.bottom + 108 - self.logScrollOffset);
        return;
    }
    if (self.activeSliderKey.length) { [self updateActiveSliderAtPoint:point]; return; }
    SKShapeNode *button = [self buttonAncestorAtPoint:point];
    if (button != self.activeButton) {
        [self releaseActiveButtonAnimated:NO];
        if (button) { [self pressButton:button]; }
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.trackingTreeScroll) {
        self.trackingTreeScroll = NO;
        if (!self.draggedTree) {
            CGPoint point = [touches.anyObject locationInNode:self];
            SKShapeNode *button = [self buttonAncestorAtPoint:point];
            if ([button.name hasPrefix:@"tree_"]) {
                [AudioManager.shared playEffectNamed:@"sound"];
                [self performActionForName:button.name];
            }
        }
        return;
    }
    if (self.trackingLogScroll) {
        self.trackingLogScroll = NO;
        if (!self.draggedLog) {
            CGPoint point = [touches.anyObject locationInNode:self];
            SKShapeNode *button = [self buttonAncestorAtPoint:point];
            if ([button.name hasPrefix:@"log_entry_"]) {
                [AudioManager.shared playEffectNamed:@"sound"];
                [self performActionForName:button.name];
            }
        }
        return;
    }
    if (self.activeSliderKey.length) { self.activeSliderKey = nil; return; }
    SKShapeNode *pressed = self.activeButton;
    NSString *name = pressed.name;
    [self releaseActiveButtonAnimated:YES];
    if (name.length) {
        [AudioManager.shared playEffectNamed:@"sound"];
        [self performActionForName:name];
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.trackingTreeScroll = NO;
    self.trackingLogScroll = NO;
    self.activeSliderKey = nil;
    [self releaseActiveButtonAnimated:YES];
}

@end
