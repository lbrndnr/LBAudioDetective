//
//  LBAppDelegate.m
//  LBAudioDetective
//
//  Created by Laurin Brandner on 21.04.13.
//  Copyright (c) 2013 Laurin Brandner. All rights reserved.
//

#import <AudioToolbox/AudioToolbox.h>
#import "LBAppDelegate.h"
#import "LBTableViewController.h"

@implementation LBAppDelegate

-(BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Set up audio session (get access to hardware by specifying want I need)
    OSStatus error = AudioSessionInitialize(NULL, kCFRunLoopDefaultMode, NULL, NULL);
    NSAssert(error == noErr, @"AudioSessionInitialize");
    
	UInt32 category = kAudioSessionCategory_PlayAndRecord;
    UInt32 propertySize = sizeof(UInt32);
    error = AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, propertySize, &category);
    NSAssert(error == noErr, @"AudioSessionSetProperty");
    
    UInt32 route = kAudioSessionOverrideAudioRoute_Speaker;
    AudioSessionSetProperty (kAudioSessionProperty_OverrideAudioRoute, propertySize, &route);
    NSAssert(error == noErr, @"AudioSessionSetProperty");
    
    error = AudioSessionSetActive(TRUE);
    NSAssert(error == noErr, @"AudioSessionSetActive");
    
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[LBTableViewController new]];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
