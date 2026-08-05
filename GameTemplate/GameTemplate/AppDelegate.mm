//
//  AppDelegate.m
//  GameTemplate
//
//  Created by tank on 5/14/26.
//

#import "AppDelegate.h"
#import "IDFAManager.h"
#import "AdManager.h"
#import <TargetConditionals.h>
#if !TARGET_OS_SIMULATOR
#include "HSSecurity/HSSecSdk.hpp"
#endif

// The supplied binary-only security SDK has no simulator slice and has been
// observed crashing asynchronously on device.  Keep the game stable while its
// vendor supplies a verified XCFramework; it can be re-enabled after that.
static const BOOL kEnableHSSecurity = NO;

@interface AppDelegate ()
#if !TARGET_OS_SIMULATOR
// HSSecSdk is a C++ object.  It must remain alive after initialization because
// the SDK continues to collect/report asynchronously for the app session.
@property (nonatomic, assign) HSSecSdk *securitySDK;
#endif

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Do not initialize external SDKs while the game is constructing its
    // first SpriteKit screen. Rewarded ads initialize lazily only when a user
    // explicitly requests a rewind, and gracefully fall back when unavailable.
#if !TARGET_OS_SIMULATOR
    if (kEnableHSSecurity) {
    [[IDFAManager shared] requestIDFAWithCompletion:^(NSString * _Nullable idfa) {
        if (idfa.length > 0) {
            NSLog(@"[SecuritySDK] IDFA available; starting HSSecurity");
            if (!self.securitySDK) {
                self.securitySDK = new HSSecSdk();
            }

            // HSSetting is a C++ type with no constructor.  Value-initialize
            // it so optional fields such as reportBackend are nil instead of
            // uninitialized pointers passed into the SDK.
            HSSetting setting = {};
            setting.company = @"de";
            setting.appId = NSBundle.mainBundle.bundleIdentifier;
            setting.token = @"2oes8jd02tts";
            self.securitySDK->setUserId(UIDevice.currentDevice.identifierForVendor.UUIDString);
            BOOL initialized = self.securitySDK->initSDK(setting);
            NSLog(@"[SecuritySDK] HSSecurity initSDK result: %@", initialized ? @"YES" : @"NO");
        } else {
            NSLog(@"[SecuritySDK] IDFA unavailable; HSSecurity is not started by the supplied template");
        }
    }];
    }
#endif
    return YES;
}

- (void)dealloc {
#if !TARGET_OS_SIMULATOR
    delete _securitySDK;
#endif
}


- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
}


- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
}


- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}


@end
