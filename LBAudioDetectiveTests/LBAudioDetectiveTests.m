//
//  LBAudioDetectiveTests.m
//  LBAudioDetectiveTests
//
//  Created by Laurin Brandner on 24.08.13.
//  Copyright (c) 2013 Laurin Brandner. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "LBAudioDetective.h"
#import "LBAudioDetectiveFrame.h"

@interface LBAudioDetectiveTests : XCTestCase

@property (nonatomic) LBAudioDetectiveRef detective;

+(NSString*)stringFromFingerprint:(LBAudioDetectiveFingerprintRef)fingerprint;

@end
@implementation LBAudioDetectiveTests

+(NSString*)stringFromFingerprint:(LBAudioDetectiveFingerprintRef)fingerprint {
    NSMutableArray* array = [NSMutableArray new];
    NSUInteger subfingerprintLength = LBAudioDetectiveFingerprintGetSubfingerprintLength(fingerprint);
    for (UInt32 i = 0; i < LBAudioDetectiveFingerprintGetNumberOfSubfingerprints(fingerprint); i++) {
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

-(void)testFingerprintingWithSequenceSuffix:(NSString*)suffix {
    NSBundle* bundle = [NSBundle bundleForClass:[self class]];
    NSArray* birds = @[@"BlackBird", @"BlueTit", @"Chaffinch", @"Sparrow", @"GreatTit", @"Crow", @"Wren", @"Chiffchaff", @"Kestrel", @"Pigeon"];
    
    
    [birds enumerateObjectsUsingBlock:^(NSString* originalBird, NSUInteger idx, BOOL *stop) {
        NSURL* originalURL = [bundle URLForResource:originalBird withExtension:@"caf"];
        
        __block Float32 maxMatch = 0.0f;
        __block Boolean failed = FALSE;
        __block NSMutableDictionary* results = [NSMutableDictionary new];
        __block Float32 trueMatch = 0.0f;
        
        [birds enumerateObjectsUsingBlock:^(NSString* sequenceBird, NSUInteger idx, BOOL *stop) {
            NSURL* sequenceURL = [bundle URLForResource:[sequenceBird stringByAppendingString:suffix] withExtension:@"caf"];
            Float32 match = 0.0f;
            LBAudioDetectiveCompareAudioURLs(self.detective, originalURL, sequenceURL, 0, &match);
            
            Boolean same = FALSE;
            NSString* originalName = originalBird;
            NSString* sequenceName = sequenceBird;
            if ([originalBird isEqualToString:sequenceBird]) {
                same = TRUE;
                originalName = [originalName uppercaseString];
                sequenceName = [sequenceName uppercaseString];
                trueMatch = match*100.0f;
            }
            
            if (maxMatch < match) {
                maxMatch = match;
                failed = !same;
            }
            
            [results setObject:[NSString stringWithFormat:@"%@/%@", originalName, sequenceName] forKey:@(match*100.0f)];
        }];
        
        if (failed) {
            XCTFail(@"%@ didn't match the best", originalBird);
            
            //NSLog(@"%@->%@", [results objectForKey:@(maxMatch*100.0f)], @(maxMatch*100.0f));
        }
        NSLog(@"%@->%@", [NSString stringWithFormat:@"%@/%@", originalBird.uppercaseString, originalBird.uppercaseString], @(trueMatch));
        NSLog(@"%@", results);
    }];
}

// Test 1
-(void)testFingerprintingWithEqualBirds {
    [self testFingerprintingWithSequenceSuffix:@"_eql"];
}

// Test 2
-(void)testFingerprintingWithDifferentBirds {
    [self testFingerprintingWithSequenceSuffix:@"_dif"];
}

// Test 3.1
-(void)testFingerprintingWithBlured1Birds {
    [self testFingerprintingWithSequenceSuffix:@"_blu1"];
}

// Test 3.2
-(void)testFingerprintingWithBlured2Birds {
    [self testFingerprintingWithSequenceSuffix:@"_blu2"];
}

// Test 4
-(void)testFingerprintingWithRecordedBirds {
    [self testFingerprintingWithSequenceSuffix:@"_rec"];
}

-(void)testFingerprintVersatility {
    for (UInt32 i = 0; i < 10; i++) {
        NSURL* originalURL = [[NSBundle bundleForClass:self.class] URLForResource:@"BlackBird" withExtension:@"caf"];
        
        LBAudioDetectiveFingerprintRef fingerprint1 = NULL;
        LBAudioDetectiveProcessAudioURL(self.detective, originalURL, &fingerprint1);
        
        LBAudioDetectiveRef differentDetective = LBAudioDetectiveNew();
        LBAudioDetectiveFingerprintRef fingerprint2 = NULL;
        LBAudioDetectiveProcessAudioURL(differentDetective, originalURL, &fingerprint2);
        
        if (!LBAudioDetectiveFingerprintEqualToFingerprint(fingerprint1, fingerprint2)) {
            Float32 match = LBAudioDetectiveFingerprintCompareToFingerprint(fingerprint1, fingerprint2, LBAudioDetectiveFingerprintGetSubfingerprintLength(fingerprint1));
            XCTFail(@"Couldn't create persisting fingerprints for Amsel:%2f%%", match*100.0);
        }
        
        LBAudioDetectiveFingerprintDispose(fingerprint1);
        LBAudioDetectiveFingerprintDispose(fingerprint2);
        LBAudioDetectiveDispose(differentDetective);
    }
}

-(void)testFingerprintComparison {
    NSURL* originalURL = [[NSBundle bundleForClass:self.class] URLForResource:@"BlackBird" withExtension:@"caf"];
    
    LBAudioDetectiveFingerprintRef fingerprint = NULL;
    LBAudioDetectiveProcessAudioURL(self.detective, originalURL, &fingerprint);
    LBAudioDetectiveFingerprintRef copy = LBAudioDetectiveFingerprintCopy(fingerprint);
    
    if (!LBAudioDetectiveFingerprintEqualToFingerprint(fingerprint, copy)) {
        Float32 match = LBAudioDetectiveFingerprintCompareToFingerprint(fingerprint, copy, LBAudioDetectiveFingerprintGetSubfingerprintLength(fingerprint));
        XCTFail(@"Couldn't create persisting fingerprints for Amsel:%2f%%", match*100.0);
    }
    
    LBAudioDetectiveFingerprintDispose(fingerprint);
    LBAudioDetectiveFingerprintDispose(copy);
}

-(void)testHaarWaveletDecomposition {
    LBAudioDetectiveFrameRef frame = LBAudioDetectiveFrameNew(3);
    
    Float32 row1[] = {538, 940, 1940, 1794};
    Float32 row2[] = {1840, 213, 1320, 913};
    Float32 row3[] = {192, 591, 492, 1921};
    
    LBAudioDetectiveFrameSetRow(frame, row1, 0, 4);
    LBAudioDetectiveFrameSetRow(frame, row2, 1, 4);
    LBAudioDetectiveFrameSetRow(frame, row3, 2, 4);
    
    LBAudioDetectiveFrameDecompose(frame);
    
    for (int r = 0; r < 3; r++) {
        for (int c = 0; c < 4; c++) {
            printf("%f\t", LBAudioDetectiveFrameGetValue(frame, r, c));
        }
        printf("\n");
    }
}

@end
