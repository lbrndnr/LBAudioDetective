//
//  LBAudioDetectiveTests.m
//  LBAudioDetectiveTests
//
//  Created by Laurin Brandner on 24.08.13.
//  Copyright (c) 2013 Laurin Brandner. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "LBAudioDetective.h"

@interface LBAudioDetectiveTests : XCTestCase

@property (nonatomic) LBAudioDetectiveRef detective;

@end
@implementation LBAudioDetectiveTests

-(void)setUp {
    [super setUp];
    
    self.detective = LBAudioDetectiveNew();
    Float32 pitches[4];
    pitches[0] = 4000.0f;
    pitches[1] = 8000.0f;
    pitches[2] = 12000.0f;
    pitches[3] = 16000.0f;
    LBAudioDetectiveSetPitchSteps(self.detective, pitches, 4);
}

-(void)tearDown {
    LBAudioDetectiveDispose(self.detective);
    
    [super tearDown];
}

-(void)testIdentification {
    NSBundle* bundle = [NSBundle mainBundle];
    NSArray* birds = @[@"Amsel", @"Blaumeise", @"Buchfink", @"Haussperling", @"Kohlmeise", @"Rabenkraehe"];
    
    [birds enumerateObjectsUsingBlock:^(NSString* originalBird, NSUInteger idx, BOOL *stop) {
        NSURL* originalURL = [bundle URLForResource:originalBird withExtension:@"mp3"];
        
        [birds enumerateObjectsUsingBlock:^(NSString* sequenceBird, NSUInteger idx, BOOL *stop) {
            NSURL* sequenceURL = [bundle URLForResource:sequenceBird withExtension:@"caf"];
            UInt32 match = LBAudioDetectiveCompareAudioURLs(self.detective, originalURL, sequenceURL);
            
            NSString* originalName = originalBird;
            NSString* sequenceName = sequenceBird;
            if ([originalBird isEqualToString:sequenceBird]) {
                originalName = [originalName uppercaseString];
                sequenceName = [sequenceName uppercaseString];
            }
            NSLog(@"Identification(%@-%@):%u", originalName, sequenceName, (unsigned int)match);
        }];
    }];
}

@end
