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

+(NSString*)stringFromFingerprint:(LBAudioDetectiveFingerprintRef)fingerprint;

@end
@implementation LBAudioDetectiveTests

+(NSString*)stringFromFingerprint:(LBAudioDetectiveFingerprintRef)fingerprint {
    NSMutableArray* array = [NSMutableArray new];
    NSUInteger subfingerprintLength = LBAudioDetectiveFingerprintGetSubfingerprintLength(fingerprint);
    for (NSUInteger i = 0; i < LBAudioDetectiveFingerprintGetNumberOfSubfingerprints(fingerprint); i++) {
        Boolean subfingerprint[subfingerprintLength];
        LBAudioDetectiveFingerprintGetSubfingerprintAtIndex(fingerprint, i, subfingerprint);
        NSMutableString* subfingerprintString = [NSMutableString new];
        for (NSUInteger j = 0; j < subfingerprintLength; j++) {
            [subfingerprintString appendString:[NSString stringWithFormat:@"%i", subfingerprint[j]]];
        }
        
        [array addObject:subfingerprintString];
    }
    
    return [array componentsJoinedByString:@"+"];
}

-(void)setUp {
    [super setUp];
    
    self.detective = LBAudioDetectiveNew();
}

-(void)tearDown {
    LBAudioDetectiveDispose(self.detective);
    
    [super tearDown];
}

// The recordings used to generate the fingerprints are from http://www.vogelwarte.ch . They have been modified and cropped.

-(void)testFingerprinting {
    NSBundle* bundle = [NSBundle bundleForClass:[self class]];
    NSArray* birds = @[@"Amsel", @"Blaumeise", @"Buchfink", @"Haussperling", @"Kohlmeise", @"Rabenkraehe", @"Zaunkoenig", @"Zilpzalp", @"Turmfalke", @"Strassentaube"];
    
    [birds enumerateObjectsUsingBlock:^(NSString* originalBird, NSUInteger idx, BOOL *stop) {
        NSURL* originalURL = [bundle URLForResource:[originalBird stringByAppendingString:@"_org"] withExtension:@"caf"];
        
        __block Float32 maxMatch = 0.0f;
        __block Boolean failed = FALSE;
        
        [birds enumerateObjectsUsingBlock:^(NSString* sequenceBird, NSUInteger idx, BOOL *stop) {
            NSURL* sequenceURL = [bundle URLForResource:sequenceBird withExtension:@"caf"];
            Float32 match = 0.0f;
            LBAudioDetectiveCompareAudioURLs(self.detective, originalURL, sequenceURL, 0, &match);
            
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

-(void)testIdentification {
    NSBundle* bundle = [NSBundle bundleForClass:[self class]];
    NSArray* birds = @[@"Amsel", @"Blaumeise", @"Buchfink", @"Haussperling", @"Kohlmeise", @"Rabenkraehe", @"Zaunkoenig", @"Zilpzalp", @"Turmfalke", @"Strassentaube"];
    
    [birds enumerateObjectsUsingBlock:^(NSString* originalBird, NSUInteger idx, BOOL *stop) {
        NSURL* originalURL = [bundle URLForResource:[originalBird stringByAppendingString:@"_org"] withExtension:@"caf"];
        
        __block Float32 maxMatch = 0.0f;
        __block Boolean failed = FALSE;
        
        [birds enumerateObjectsUsingBlock:^(NSString* sequenceBird, NSUInteger idx, BOOL *stop) {
            NSURL* sequenceURL = [bundle URLForResource:[sequenceBird stringByAppendingString:@"_dif"] withExtension:@"caf"];
            Float32 match = 0.0f;
            LBAudioDetectiveCompareAudioURLs(self.detective, originalURL, sequenceURL, 0, &match);
            
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
    for (UInt32 i = 0; i < 10; i++) {
        NSURL* originalURL = [[NSBundle mainBundle] URLForResource:@"Amsel" withExtension:@"caf"];
        
        LBAudioDetectiveProcessAudioURL(self.detective, originalURL);
        LBAudioDetectiveFingerprintRef fingerprint1 = LBAudioDetectiveGetFingerprint(self.detective);
        
        LBAudioDetectiveRef differentDetective = LBAudioDetectiveNew();
        LBAudioDetectiveProcessAudioURL(differentDetective, originalURL);
        LBAudioDetectiveFingerprintRef fingerprint2 = LBAudioDetectiveGetFingerprint(differentDetective);
        
        if (!LBAudioDetectiveFingerprintEqualToFingerprint(fingerprint1, fingerprint2)) {
            Float32 match = LBAudioDetectiveFingerprintCompareToFingerprint(fingerprint1, fingerprint2, LBAudioDetectiveFingerprintGetSubfingerprintLength(fingerprint1));
            XCTFail(@"Couldn't create persisting fingerprints for Amsel:%2f%%", match*100.0);
        }
        
        LBAudioDetectiveDispose(differentDetective);
    }
}

-(void)testFingerprintComparison {
    NSURL* originalURL = [[NSBundle mainBundle] URLForResource:@"Amsel" withExtension:@"caf"];
    
    LBAudioDetectiveProcessAudioURL(self.detective, originalURL);
    LBAudioDetectiveFingerprintRef fingerprint = LBAudioDetectiveGetFingerprint(self.detective);
    LBAudioDetectiveFingerprintRef copy = LBAudioDetectiveFingerprintCopy(fingerprint);
    
    if (!LBAudioDetectiveFingerprintEqualToFingerprint(fingerprint, copy)) {
        Float32 match = LBAudioDetectiveFingerprintCompareToFingerprint(fingerprint, copy, LBAudioDetectiveFingerprintGetSubfingerprintLength(fingerprint));
        XCTFail(@"Couldn't create persisting fingerprints for Amsel:%2f%%", match*100.0);
    }
}

-(void)testFingerprintPrints {
    NSBundle* bundle = [NSBundle mainBundle];
    NSArray* birds = @[@"Zaunkoenig", @"Zilpzalp", @"Turmfalke", @"Strassentaube", @"Amsel", @"Blaumeise", @"Buchfink", @"Haussperling", @"Kohlmeise", @"Rabenkraehe"];
    
    [birds enumerateObjectsUsingBlock:^(NSString* originalBird, NSUInteger idx, BOOL *stop) {
        NSURL* originalURL = [bundle URLForResource:[originalBird stringByAppendingString:@"_org"] withExtension:@"caf"];
        LBAudioDetectiveProcessAudioURL(self.detective, originalURL);
        LBAudioDetectiveFingerprintRef fingerprint = LBAudioDetectiveGetFingerprint(self.detective);
        NSLog(@"%@\n%@", originalBird, [LBAudioDetectiveTests stringFromFingerprint:fingerprint]);
    }];
}

@end
