//
//  AppDelegate.h
//  BCLRemoteApp
//
// Copyright (c) 2015, Upnext Technologies Sp. z o.o.
// All rights reserved.
//
// This source code is licensed under the BSD 3-Clause License found in the
// LICENSE.txt file in the root directory of this source tree.
//

#import <UIKit/UIKit.h>

extern NSString * const BCLApplicationDidRegisterForRemoteNotificationsNotification;
extern NSString * const BCLApplicationDidFailToRegisterForRemoteNotificationsNotification;

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (nonatomic) BOOL isRemoteNotificationSetupReady;

@property (nonatomic) BOOL shouldVerifySystemSettings;
@end

