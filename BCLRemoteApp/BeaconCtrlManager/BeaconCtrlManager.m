//
//  BeaconCtrlManager.m
//  BCLRemoteApp
//
// Copyright (c) 2015, Upnext Technologies Sp. z o.o.
// All rights reserved.
//
// This source code is licensed under the BSD 3-Clause License found in the
// LICENSE.txt file in the root directory of this source tree.
//

#import "BeaconCtrlManager.h"
#import "AppDelegate.h"
#import <BeaconCtrl/BCLBeaconCtrl.h>
#import <BeaconCtrl/BCLBeacon.h>
#import <BeaconCtrl/BCLTrigger.h>
#import <SSKeychain/SSKeychain.h>

NSString * const BeaconManagerReadyForSetupNotification = @"BeaconManagerReadyForSetupNotification";
NSString * const BeaconManagerDidLogoutNotification = @"BeaconManagerDidLogoutpNotification";
NSString * const BeaconManagerDidFetchBeaconCtrlConfigurationNotification = @"BeaconManagerDidFetchBeaconCtrlConfigurationNotification";
NSString * const BeaconManagerClosestBeaconDidChangeNotification = @"BeaconManagerClosestBeaconDidChangeNotification";
NSString * const BeaconManagerCurrentZoneDidChangeNotification = @"BeaconManagerCurrentZoneDidChangeNotification";
NSString * const BeaconManagerPropertiesUpdateDidStartNotification = @"BeaconManagerPropertiesUpdateDidStartNotification";
NSString * const BeaconManagerPropertiesUpdateDidFinishNotification = @"BeaconManagerPropertiesUpdateDidFinishNotification";
NSString * const BeaconManagerFirmwareUpdateDidStartNotification = @"BeaconManagerFirmwareUpdateDidStartNotification";
NSString * const BeaconManagerFirmwareUpdateDidProgressNotification = @"BeaconManagerFirmwareUpdateDidProgresstNotification";
NSString * const BeaconManagerFirmwareUpdateDidFinishNotification = @"BeaconManagerFirmwareUpdateDidFinishNotification";
+// Test local API App credentials:
 +// UID:    eb3b5a29d2ae86a90ff4dce44da9725c0a91e40b95a180460a9355124844e08c
 +// Secret: ea41a5f1551c2ab992a21dc00cb6b0b9f3aaa4b0976bcee25a4f0ccf3d1c9d02
 +// Test local API S2S API App credentials:
 +// UID:    c450dcc61b722175e49e2750d5e872eb7c9dc40e67f88ab78aca32b9cc15c020
 +NSString * const API_SERVER_UUID = @"e2578487540bbedeea1f5222252441a8585225e0dc5c419e0ecfb3a96fa4bd86";
 +// Secret: 1fd6ef3a820532440b912032c3936c2e1c3ba3271e163c48ae36fe2d506661e1
 +NSString * const API_SERVER_SECRET = @"ec96ca3da391dec26f03e20d0158f5a4f74112d4297bf63e2fa2276dfb6491f4";
 +@interface BeaconCtrlManager () <BCLBeaconCtrlDelegate>

@property (nonatomic, copy) NSString *pushNotificationDeviceToken;
@property (nonatomic) BCLBeaconCtrlPushEnvironment pushEnvironment;

@property (nonatomic, readwrite) BOOL isReadyForSetup;
@property (nonatomic, readwrite) BOOL isAutomaticBeaconCtrlRefreshMuted;

@property (nonatomic, strong) NSTimer *refetchConfigurationTimer;

@end

@implementation BeaconCtrlManager

- (instancetype)init
{
    if (self = [super init]) {
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(didRegisterForRemoteNotifications:) name:BCLApplicationDidRegisterForRemoteNotificationsNotification object:nil];
        [nc addObserver:self selector:@selector(didFailToRegisterRegisterForRemoteNotifications:) name:BCLApplicationDidFailToRegisterForRemoteNotificationsNotification object:nil];
        
        NSUserDefaults *stantardUserDefaults = [NSUserDefaults standardUserDefaults];
        
        [stantardUserDefaults setInteger:10 forKey:@"BCLRemoteAppMaxFloorNumber"];
        [stantardUserDefaults synchronize];
        
        _isReadyForSetup = ((AppDelegate *)[UIApplication sharedApplication].delegate).isRemoteNotificationSetupReady;
    }
    
    return self;
}

+ (instancetype)sharedManager
{
    static BeaconCtrlManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[BeaconCtrlManager alloc] init];
    });
    return sharedManager;
}

- (void)setupForExistingUserWithAutologin:(void (^)(BOOL, NSError *))completion
{
    [self setupForExistingAdminUserWithEmail:[self emailFromKeyChain] password:[self passwordFromKeychain] completion:completion];
}

- (void)setupForExistingAdminUserWithEmail:(NSString *)email password:(NSString *)password completion:(void (^)(BOOL, NSError *))completion
{
 
    self.beaconCtrlAdmin = [BCLBeaconCtrlAdmin beaconCtrlAdminWithCliendId:API_SERVER_UUID clientSecret:API_SERVER_SECRET];        self.beaconCtrlAdmin = [BCLBeaconCtrlAdmin beaconCtrlAdminWithCliendId:API_SERVER_UUID clientSecret:API_SERVER_SECRET];   
   
 __weak typeof(self) weakSelf = self;
    
    [self.beaconCtrlAdmin loginAdminUserWithEmail:email password:password completion:^(BOOL success, NSError *error) {
        if (!success) {
            if (completion) {
                completion(NO, error);
            }
            return;
        }
        
        [weakSelf finishSetupForAdminUserWithEmail:email password:password completion:completion];
    }];
}

- (void)setupForNewAdminUserWithEmail:(NSString *)email password:(NSString *)password passwordConfirmation:(NSString *)passwordConfirmation completion:(void (^)(BOOL, NSError *))completion
{
    self.beaconCtrlAdmin = [BCLBeaconCtrlAdmin beaconCtrlAdminWithCliendId:API_SERVER_UUID clientSecret:API_SERVER_SECRET];
    
    __weak typeof(self) weakSelf = self;
    
    [self.beaconCtrlAdmin registerAdminUserWithEmail:email password:password passwordConfirmation:password completion:^(BOOL success, NSError *error) {
        if (!success) {
            if (completion) {
                completion(NO, error);
            }
            return;
        }
        
        [weakSelf finishSetupForAdminUserWithEmail:email password:password completion:completion];
    }];
}

- (void)refetchBeaconCtrlConfiguration:(void (^)(NSError *error))completion
{
    __weak typeof(self) weakSelf = self;
    
    [self.beaconCtrl fetchConfiguration:^(NSError *error) {
        if (!error) {
            [[NSNotificationCenter defaultCenter] postNotificationName:BeaconManagerDidFetchBeaconCtrlConfigurationNotification object:weakSelf];
        }
        
        [weakSelf.beaconCtrl updateMonitoredBeacons];
        
        if (completion) {
            completion(error);
        }
    }];
}

- (void)muteAutomaticBeaconCtrlConfigurationRefresh
{
    self.isAutomaticBeaconCtrlRefreshMuted = YES;
}

- (void)unmuteAutomaticBeaconCtrlConfigurationRefresh
{
    self.isAutomaticBeaconCtrlRefreshMuted = NO;
}

- (void)setIsReadyForSetup:(BOOL)isReadyForSetup
{
    if (_isReadyForSetup == NO && isReadyForSetup == YES) {
        [[NSNotificationCenter defaultCenter] postNotificationName:BeaconManagerReadyForSetupNotification object:self];
    }
    
    _isReadyForSetup = isReadyForSetup;
}

- (BOOL)canTryAutoLogin
{
    return [self emailFromKeyChain] && [self passwordFromKeychain];
}

- (void)createBeacon:(BCLBeacon *)beacon testActionName:(NSString *)testActionName testActionTrigger:(BCLEventType)trigger testActionAttributes:(NSArray *)testActionAttributes completion:(void (^)(BCLBeacon *, NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    
    void (^finalCompletion)(BCLBeacon *newBeacon, NSError *error) = ^void (BCLBeacon *newBeacon, NSError *error){
        if (completion) {
            if (error) {
                completion(newBeacon, error);
                return;
            }
            
            [weakSelf.beaconCtrl stopMonitoringBeacons];
            
            [weakSelf refetchBeaconCtrlConfiguration:^(NSError *error) {
                [weakSelf.beaconCtrl startMonitoringBeacons];
                
                __block BCLBeacon *updatedNewBeacon;
                
                [weakSelf.beaconCtrl.configuration.beacons enumerateObjectsUsingBlock:^(BCLBeacon *enumeratedBeacon, BOOL *beaconStop) {
                    if ([enumeratedBeacon.beaconIdentifier isEqualToString:newBeacon.beaconIdentifier]) {
                        updatedNewBeacon = enumeratedBeacon;
                        *beaconStop = YES;
                    }
                }];
                
                completion(updatedNewBeacon, error);
            }];
        }
    };
    
    [self.beaconCtrlAdmin createBeacon:beacon testActionName:testActionName testActionTrigger:trigger testActionAttributes:testActionAttributes completion:finalCompletion];
}

- (void)updateBeacon:(BCLBeacon *)beacon testActionName:(NSString *)testActionName testActionTrigger:(BCLEventType)trigger testActionAttributes:(NSArray *)testActionAttributes completion:(void (^)(BCLBeacon *, NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    
    void (^finalCompletion)(BOOL success, NSError *error) = ^void (BOOL success, NSError *error){
        if (completion) {
            if (error) {
                completion(nil, error);
                return;
            }
            
            [weakSelf refetchBeaconCtrlConfiguration:^(NSError *error) {
                __block BCLBeacon *updatedBeacon;
                
                [weakSelf.beaconCtrl.configuration.beacons enumerateObjectsUsingBlock:^(BCLBeacon *enumeratedBeacon, BOOL *beaconStop) {
                    if ([enumeratedBeacon.beaconIdentifier isEqualToString:beacon.beaconIdentifier]) {
                        updatedBeacon = enumeratedBeacon;
                        *beaconStop = YES;
                    }
                }];
                
                completion(updatedBeacon, error);
            }];
        }
    };
    
    [self.beaconCtrlAdmin updateBeacon:beacon testActionName:testActionName testActionTrigger:trigger testActionAttributes:testActionAttributes completion:finalCompletion];
}

- (void)deleteBeacon:(BCLBeacon *)beacon completion:(void (^)(BOOL success, NSError *error))completion
{
    __weak typeof(self) weakSelf = self;
    
    void (^finalCompletion)(BOOL success, NSError *error) = ^void (BOOL success, NSError *error){
        if (completion) {
            if (error) {
                completion(success, error);
                return;
            }
            
            [weakSelf.beaconCtrl stopMonitoringBeacons];
            
            [weakSelf refetchBeaconCtrlConfiguration:^(NSError *error) {
                [weakSelf.beaconCtrl startMonitoringBeacons];
                
                completion(success, error);
            }];
        }
    };
    
    [self.beaconCtrlAdmin deleteBeacon:beacon completion:finalCompletion];
}

- (void)createZone:(BCLZone *)zone completion:(void (^)(BCLZone *newZone, NSError *error))completion
{
    __weak typeof(self) weakSelf = self;
    
    void (^finalCompletion)(BCLZone *newZone, NSError *error) = ^void (BCLZone *newZone, NSError *error){
        if (completion) {
            if (error) {
                completion(newZone, error);
                return;
            }
            
            [weakSelf.beaconCtrl stopMonitoringBeacons];
            
            [weakSelf refetchBeaconCtrlConfiguration:^(NSError *error) {
                [weakSelf.beaconCtrl startMonitoringBeacons];
                
                completion(newZone, error);
            }];
        }
    };
    
    [self.beaconCtrlAdmin createZone:zone completion:finalCompletion];
}

- (void)updateZone:(BCLZone *)zone completion:(void (^)(BCLZone *updatedZone, NSError *error))completion
{
    __weak typeof(self) weakSelf = self;
    
    void (^finalCompletion)(BOOL success, NSError *error) = ^void (BOOL success, NSError *error){
        if (completion) {
            if (error) {
                completion(nil, error);
                return;
            }
            
            [weakSelf.beaconCtrl stopMonitoringBeacons];
            
            [weakSelf refetchBeaconCtrlConfiguration:^(NSError *error) {
                [weakSelf.beaconCtrl startMonitoringBeacons];
                
                __block BCLZone *updatedZone;
                
                [weakSelf.beaconCtrl.configuration.zones enumerateObjectsUsingBlock:^(BCLZone *enumeratedZone, BOOL *zoneStop) {
                    if ([enumeratedZone.zoneIdentifier isEqualToString:zone.zoneIdentifier]) {
                        updatedZone = enumeratedZone;
                        *zoneStop = YES;
                    }
                }];
                
                completion(updatedZone, error);
            }];
        }
    };
    
    [self.beaconCtrlAdmin updateZone:zone completion:finalCompletion];
}

- (void)deleteZone:(BCLZone *)zone completion:(void (^)(BOOL success, NSError *error))completion
{
    __weak typeof(self) weakSelf = self;
    
    void (^finalCompletion)(BOOL success, NSError *error) = ^void (BOOL success, NSError *error){
        if (completion) {
            if (error) {
                completion(success, error);
                return;
            }
            
            [weakSelf.beaconCtrl startMonitoringBeacons];
            
            [weakSelf refetchBeaconCtrlConfiguration:^(NSError *error) {
                [weakSelf.beaconCtrl startMonitoringBeacons];
                
                completion(success, error);
            }];
        }
    };
    
    [self.beaconCtrlAdmin deleteZone:zone completion:finalCompletion];

}

- (void)logout
{
    [self.beaconCtrl stopMonitoringBeacons];
    
    [self.beaconCtrl logout];
    [self.beaconCtrlAdmin logout];
    
    [self.refetchConfigurationTimer invalidate];
    self.refetchConfigurationTimer = nil;
    
    self.beaconCtrl.delegate = nil;

    self.beaconCtrl = nil;
    self.beaconCtrlAdmin = nil;
    
    if ([self emailFromKeyChain]) {
        [SSKeychain deletePasswordForService:[self keychainServiceName] account:[self emailFromKeyChain]];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:BeaconManagerDidLogoutNotification object:self];
}

- (BCLAction *)testActionForBeacon:(BCLBeacon *)beacon
{
    __block BCLAction *testAction;
    
    [beacon.triggers enumerateObjectsUsingBlock:^(BCLTrigger *trigger, NSUInteger triggerIdx, BOOL *triggerStop) {
        [trigger.actions enumerateObjectsUsingBlock:^(BCLAction *action, NSUInteger actionIdx, BOOL *actionStop) {
            if (action.isTestAction) {
                testAction = action;
                *triggerStop = YES;
                *actionStop = YES;
            }
        }];
    }];
    
    return testAction;
}

#pragma mark - BCLBeaconCtrlDelegate

- (void)closestObservedBeaconDidChange:(BCLBeacon *)closestBeacon
{
    [[NSNotificationCenter defaultCenter] postNotificationName:BeaconManagerClosestBeaconDidChangeNotification object:self userInfo:@{@"closestBeacon": closestBeacon ? : [NSNull null]}];
}

- (void)currentZoneDidChange:(BCLZone *)currentZone
{
    [[NSNotificationCenter defaultCenter] postNotificationName:BeaconManagerCurrentZoneDidChangeNotification object:self userInfo:@{@"currentZone": currentZone ? : [NSNull null]}];
}

- (void)didChangeObservedBeacons:(NSSet *)newObservedBeacons
{
    
}

- (BOOL)shouldAutomaticallyPerformAction:(BCLAction *)action
{
    return YES;
}

- (void)willPerformAction:(BCLAction *)action
{
    
}

- (void) didPerformAction:(BCLAction *)action
{
    [self presentTestNotification:action];
}

- (void)beaconsPropertiesUpdateDidStart:(BCLBeacon *)beacon
{
    [[NSNotificationCenter defaultCenter] postNotificationName:BeaconManagerPropertiesUpdateDidStartNotification object:self userInfo:@{@"beacon": beacon}];
}

- (void)beaconsPropertiesUpdateDidFinish:(BCLBeacon *)beacon success:(BOOL)success
{
    [self.beaconCtrlAdmin syncBeacon:beacon completion:^(NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^() {
                [[NSNotificationCenter defaultCenter] postNotificationName:BeaconManagerPropertiesUpdateDidFinishNotification object:self userInfo:@{@"beacon": beacon, @"success": @(NO)}];
            });
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^() {
            [[NSNotificationCenter defaultCenter] postNotificationName:BeaconManagerPropertiesUpdateDidFinishNotification object:self userInfo:@{@"beacon": beacon, @"success": @(YES)}];
        });
    }];
}

- (void)beaconsFirmwareUpdateDidStart:(BCLBeacon *)beacon
{
    [[NSNotificationCenter defaultCenter] postNotificationName:BeaconManagerFirmwareUpdateDidStartNotification object:self userInfo:@{@"beacon": beacon}];
}

- (void)beaconsFirmwareUpdateDidProgress:(BCLBeacon *)beacon progress:(NSUInteger)progress
{
    [[NSNotificationCenter defaultCenter] postNotificationName:BeaconManagerFirmwareUpdateDidProgressNotification object:self userInfo:@{@"beacon": beacon, @"progress": @(progress)}];
}

- (void)beaconsFirmwareUpdateDidFinish:(BCLBeacon *)beacon success:(BOOL)success
{
    [self.beaconCtrlAdmin syncBeacon:beacon completion:^(NSError *error) {
        if (error) {
            [[NSNotificationCenter defaultCenter] postNotificationName:BeaconManagerFirmwareUpdateDidFinishNotification object:self userInfo:@{@"beacon": beacon, @"success": @(NO)}];
            return;
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:BeaconManagerFirmwareUpdateDidFinishNotification object:self userInfo:@{@"beacon": beacon, @"success": @(YES)}];
    }];
}

#pragma mark - Private

- (void)presentTestNotification:(BCLAction *)action
{
    if (!action.isTestAction) {
        return;
    }
    
    NSString *notificationMessage = [action.customValues firstObject][@"value"];
    if (notificationMessage) {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Beacon notification" message:notificationMessage preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Ok"
                                                           style:UIAlertActionStyleDefault
                                                         handler:NULL];
        
        [alertController addAction:okAction];
        
        __weak typeof(self) weakSelf = self;
        
        dispatch_async(dispatch_get_main_queue(), ^() {
            [[weakSelf topViewController] presentViewController:alertController animated:YES completion:nil];
        });
    }
}

- (UIViewController *)topViewController{
    return [self topViewController:[UIApplication sharedApplication].keyWindow.rootViewController];
}

- (UIViewController *)topViewController:(UIViewController *)rootViewController
{
    if (rootViewController.presentedViewController == nil) {
        return rootViewController;
    }
    
    if ([rootViewController.presentedViewController isMemberOfClass:[UINavigationController class]]) {
        UINavigationController *navigationController = (UINavigationController *)rootViewController.presentedViewController;
        UIViewController *lastViewController = [[navigationController viewControllers] lastObject];
        return [self topViewController:lastViewController];
    }
    
    UIViewController *presentedViewController = (UIViewController *)rootViewController.presentedViewController;
    return [self topViewController:presentedViewController];
}

- (NSString *)keychainServiceName
{
    return [[NSBundle mainBundle] bundleIdentifier];
}

- (NSDictionary *)keychainAccountDictionary
{
    return [[SSKeychain accountsForService:[self keychainServiceName]] lastObject];
}

- (NSString *)emailFromKeyChain
{
    NSDictionary *keychainAccountDict = [self keychainAccountDictionary];
    
    if (keychainAccountDict) {
        return keychainAccountDict[kSSKeychainAccountKey];
    }
    
    return nil;
}

- (NSString *)passwordFromKeychain
{
    return [SSKeychain passwordForService:[self keychainServiceName] account:[self emailFromKeyChain]];;
}

- (void)didRegisterForRemoteNotifications:(NSNotification *)notification
{
    self.isReadyForSetup = YES;
    
#ifdef DEBUG
    self.pushEnvironment = BCLBeaconCtrlPushEnvironmentSandbox;
#else
    self.pushEnvironment = BCLBeaconCtrlPushEnvironmentProduction;
#endif
    self.pushNotificationDeviceToken = notification.userInfo[@"deviceToken"];
}

- (void)didFailToRegisterRegisterForRemoteNotifications:(NSNotification *)notification
{
    self.isReadyForSetup = YES;
    
    self.pushEnvironment = BCLBeaconCtrlPushEnvironmentNone;
    self.pushNotificationDeviceToken = nil;
}

- (void)finishSetupForAdminUserWithEmail:(NSString *)email password:(NSString *)password completion:(void (^)(BOOL, NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    
    [self.beaconCtrlAdmin fetchTestApplicationCredentials:^(NSString *applicationClientId, NSString *applicationClientSecret, NSError *error) {
        if (!applicationClientId || !applicationClientSecret) {
            if (completion) {
                completion(NO, error);
                return;
            }
        }

        [weakSelf.beaconCtrlAdmin fetchZoneColors:^(NSError *error) {
            if (error) {
                if (completion) {
                    completion(NO, error);
                }
                return;
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [BCLBeaconCtrl setupBeaconCtrlWithClientId:applicationClientId clientSecret:applicationClientSecret userId:email pushEnvironment:self.pushEnvironment pushToken:self.pushNotificationDeviceToken completion:^(BCLBeaconCtrl *beaconCtrl, BOOL isRestoredFromCache, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^() {
                        if (!beaconCtrl) {
                            if (completion) {
                                completion(NO, error);
                                return;
                            }
                        }
                        
                        weakSelf.beaconCtrl = beaconCtrl;
                        beaconCtrl.delegate = self;
                        
                        [beaconCtrl startMonitoringBeacons];
                        
                        [SSKeychain setPassword:password forService:[self keychainServiceName] account:email];
                        
                        weakSelf.refetchConfigurationTimer = [NSTimer scheduledTimerWithTimeInterval:60 target:weakSelf selector:@selector(refetchBeaconCtrlConfigurationTimerHandler:) userInfo:nil repeats:YES];
                        
                        NSError *beaconMonitoringError;
                        if (![beaconCtrl isBeaconCtrlReadyToProcessBeaconActions:&beaconMonitoringError]) {
                            NSLog(@"");
                        }
                        
                        if (completion) {
                            completion(YES, nil);
                        }
                    });
                }];
            });
        }];
    }];
}

- (void)refetchBeaconCtrlConfigurationTimerHandler:(NSTimer *)timer
{
    if (self.isAutomaticBeaconCtrlRefreshMuted) {
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    
    [self refetchBeaconCtrlConfiguration:^(NSError *error) {
        if (error) {
            // TODO: Handle error!
            return;
        }
    }];
}

@end
