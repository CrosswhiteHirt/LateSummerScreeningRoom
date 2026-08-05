//
//  GameScene.h
//  GameTemplate
//
//  Created by tank on 5/14/26.
//

#import <SpriteKit/SpriteKit.h>

@interface GameScene : SKScene

// SKView may receive its final safe-area inset after the scene is presented
// (notably on Dynamic Island devices).  The controller forwards that update.
- (void)updateSafeAreaInsets:(UIEdgeInsets)safeAreaInsets;

@end
