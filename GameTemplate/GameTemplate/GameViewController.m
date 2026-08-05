//
//  GameViewController.m
//  GameTemplate
//
//  Created by tank on 5/14/26.
//

#import "GameViewController.h"
#import "GameScene.h"
#import "AdManager.h"

@implementation GameViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Load the SKScene from 'GameScene.sks'.  The title screen lays itself out
    // against the device's real bounds instead of the editor's fixed canvas.
    GameScene *scene = (GameScene *)[SKScene nodeWithFileNamed:@"GameScene"];
    SKView *skView = (SKView *)self.view;
    scene.size = skView.bounds.size;
    scene.scaleMode = SKSceneScaleModeResizeFill;
    
    // Present the scene
    [skView presentScene:scene];
    
    skView.showsFPS = NO;
    skView.showsNodeCount = NO;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self updateGameSceneSafeAreaInsets];

//    static dispatch_once_t once;
//    dispatch_once(&once, ^{
//        // Demo only: wait for the ad to finish loading after viewDidAppear.
//        // Production should trigger it from a user action or level result.
//        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)),
//                       dispatch_get_main_queue(), ^{
//            [[AdManager shared] showAd];
//        });
//    });
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self updateGameSceneSafeAreaInsets];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateGameSceneSafeAreaInsets];
}

- (void)updateGameSceneSafeAreaInsets {
    SKView *skView = (SKView *)self.view;
    GameScene *scene = [skView.scene isKindOfClass:GameScene.class] ? (GameScene *)skView.scene : nil;
    [scene updateSafeAreaInsets:self.view.safeAreaInsets];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotate { return NO; }

- (BOOL)prefersStatusBarHidden {
    return YES;
}

@end
