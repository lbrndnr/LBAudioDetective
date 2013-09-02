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
}

-(void)tearDown {
    LBAudioDetectiveDispose(self.detective);
    
    [super tearDown];
}

-(void)testIdentification {
    NSBundle* bundle = [NSBundle mainBundle];
    NSArray* birds = @[@"Amsel", @"Blaumeise", @"Buchfink", @"Haussperling", @"Kohlmeise", @"Rabenkraehe"];
    
    [birds enumerateObjectsUsingBlock:^(NSString* originalBird, NSUInteger idx, BOOL *stop) {
        NSURL* originalURL = [bundle URLForResource:[originalBird stringByAppendingString:@"_org"] withExtension:@"caf"];
        
        __block Float32 maxMatch = 0.0f;
        __block Boolean failed = FALSE;
        
        [birds enumerateObjectsUsingBlock:^(NSString* sequenceBird, NSUInteger idx, BOOL *stop) {
            NSURL* sequenceURL = [bundle URLForResource:sequenceBird withExtension:@"caf"];
            Float32 match = LBAudioDetectiveCompareAudioURLs(self.detective, originalURL, sequenceURL, 0);
            
            Boolean same = FALSE;
            NSString* originalName = originalBird;
            NSString* sequenceName = sequenceBird;
            if ([originalBird isEqualToString:sequenceBird]) {
                same = TRUE;
                originalName = [originalName uppercaseString];
                sequenceName = [sequenceName uppercaseString];
            }
            
            if (maxMatch < match) {
                maxMatch = match;
                failed = !same;
            }
            
            NSLog(@"Identification(%@-%@):%2.2f%%", originalName, sequenceName, match*100.0);
        }];
        
        if (failed) {
            XCTFail(@"%@ didn't match the best", originalBird);
        }
    }];
}

-(void)testFingerprintVersatility {
    NSURL* originalURL = [[NSBundle mainBundle] URLForResource:@"Amsel" withExtension:@"caf"];
    
    LBAudioDetectiveProcessAudioURL(self.detective, originalURL);
    LBAudioDetectiveFingerprintRef fingerprint1 = LBAudioDetectiveGetFingerprint(self.detective);
    
    LBAudioDetectiveRef differentDetective = LBAudioDetectiveNew();
    LBAudioDetectiveProcessAudioURL(differentDetective, originalURL);
    LBAudioDetectiveFingerprintRef fingerprint2 = LBAudioDetectiveGetFingerprint(differentDetective);
    
    if (!LBAudioDetectiveFingerprintEqualToFingerprint(fingerprint1, fingerprint2)) {
        Float32 match = LBAudioDetectiveFingerprintCompareToFingerprint(fingerprint1, fingerprint2, 0);
        XCTFail(@"Couldn't create persisting fingerprints for Amsel:%2f%%", match*100.0);
    }
    
    LBAudioDetectiveDispose(differentDetective);
}

-(void)testFingerprintComparison {
    NSURL* originalURL = [[NSBundle mainBundle] URLForResource:@"Amsel" withExtension:@"caf"];
    
    LBAudioDetectiveProcessAudioURL(self.detective, originalURL);
    LBAudioDetectiveFingerprintRef fingerprint = LBAudioDetectiveGetFingerprint(self.detective);
    LBAudioDetectiveFingerprintRef copy = LBAudioDetectiveFingerprintCopy(fingerprint);
    
    if (!LBAudioDetectiveFingerprintEqualToFingerprint(fingerprint, copy)) {
        Float32 match = LBAudioDetectiveFingerprintCompareToFingerprint(fingerprint, copy, 0);
        XCTFail(@"Couldn't create persisting fingerprints for Amsel:%2f%%", match*100.0);
    }
}

@end
