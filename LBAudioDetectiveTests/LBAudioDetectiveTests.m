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

-(NSArray*)_arrayFromAudioUnits:(LBAudioDetectiveIdentificationUnit *)units count:(NSUInteger)count;
-(NSUInteger)_matchRecordedIdentificationUnits:(NSArray *)recordedUnits withOriginalUnits:(NSArray *)originalUnits;

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
        NSURL* selectedURL = [bundle URLForResource:originalBird withExtension:@"mp3"];
        LBAudioDetectiveProcessAudioURL(self.detective, selectedURL);
        
        UInt32 unitCount2;
        LBAudioDetectiveIdentificationUnit* identificationUnits2 = LBAudioDetectiveGetIdentificationUnits(self.detective, &unitCount2);
        NSArray* originalUnits = [self _arrayFromAudioUnits:identificationUnits2 count:unitCount2];
        
        [birds enumerateObjectsUsingBlock:^(NSString* sequenceBird, NSUInteger idx, BOOL *stop) {
            NSURL* selectedURL = [bundle URLForResource:sequenceBird withExtension:@"caf"];
            LBAudioDetectiveProcessAudioURL(self.detective, selectedURL);
            
            UInt32 unitCount2;
            LBAudioDetectiveIdentificationUnit* identificationUnits2 = LBAudioDetectiveGetIdentificationUnits(self.detective, &unitCount2);
            NSArray* sequenceUnits = [self _arrayFromAudioUnits:identificationUnits2 count:unitCount2];
            
            NSUInteger match = [self _matchRecordedIdentificationUnits:sequenceUnits withOriginalUnits:originalUnits];
            
            NSString* originalName = originalBird;
            NSString* sequenceName = sequenceBird;
            if ([originalBird isEqualToString:sequenceBird]) {
                originalName = [originalName uppercaseString];
                sequenceName = [sequenceName uppercaseString];
            }
            NSLog(@"Identification(%@-%@):%u", originalName, sequenceName, match);
        }];
    }];
}

-(NSArray*)_arrayFromAudioUnits:(LBAudioDetectiveIdentificationUnit *)units count:(NSUInteger)count {
    NSMutableArray* mutableUnits = [NSMutableArray new];
    for (NSInteger i = 0; i < count; i++) {
        LBAudioDetectiveIdentificationUnit unit = units[i];
        NSInteger f0 = unit.frequencies[0];
        NSInteger f1 = unit.frequencies[1];
        NSInteger f2 = unit.frequencies[2];
        NSInteger f3 = unit.frequencies[3];
        NSInteger f4 = unit.frequencies[4];
        [mutableUnits addObject:@[@(f0-(f0%2)), @(f1-(f1%2)), @(f2-(f2%2)), @(f3-(f3%2)), @(f4-(f4%2))]];
    }
    
    return mutableUnits;
}

-(NSUInteger)_matchRecordedIdentificationUnits:(NSArray *)recordedUnits withOriginalUnits:(NSArray *)originalUnits {
    NSAssert(recordedUnits || originalUnits, @"Identification Units are nil");
    
    NSInteger range = 100;
    __block NSMutableDictionary* offsetDictionary = [NSMutableDictionary new];
    
    [originalUnits enumerateObjectsUsingBlock:^(NSArray* originalUnit, NSUInteger originalIndex, BOOL *originalStop) {
        [recordedUnits enumerateObjectsUsingBlock:^(NSArray* recordedUnit, NSUInteger recordedIndex, BOOL *recordedStop) {
            NSInteger match0 = fabsf([(NSNumber*)originalUnit[0] integerValue] - [(NSNumber*)recordedUnit[0] integerValue]);
            NSInteger match1 = fabsf([(NSNumber*)originalUnit[1] integerValue] - [(NSNumber*)recordedUnit[1] integerValue]);
            NSInteger match2 = fabsf([(NSNumber*)originalUnit[2] integerValue] - [(NSNumber*)recordedUnit[2] integerValue]);
            NSInteger match3 = fabsf([(NSNumber*)originalUnit[3] integerValue] - [(NSNumber*)recordedUnit[3] integerValue]);
            NSInteger match4 = fabsf([(NSNumber*)originalUnit[4] integerValue] - [(NSNumber*)recordedUnit[4] integerValue]);
            
            if ((match0 + match1 + match2 + match3 + match4) < 400) {
                NSInteger index = originalIndex-recordedIndex;
                
                __block NSNumber* oldOffset = nil;
                __block NSNumber* newOffset = nil;
                __block NSNumber* newCount = nil;
                
                [offsetDictionary enumerateKeysAndObjectsUsingBlock:^(NSNumber* offset, NSNumber* count, BOOL *stop) {
                    if (fabsf(offset.floatValue-index) < range) {
                        oldOffset = offset;
                        CGFloat sum = offset.floatValue*count.floatValue;
                        newCount = @(count.integerValue+1);
                        newOffset = @((sum+index)/newCount.floatValue);
                        *stop = YES;
                    }
                }];
                
                if (!newOffset || !newCount) {
                    newOffset = @(index);
                    newCount = @(1);
                }
                
                if (oldOffset) {
                    [offsetDictionary removeObjectForKey:oldOffset];
                }
                [offsetDictionary setObject:newCount forKey:newOffset];
            }
        }];
    }];
    
    __block NSUInteger matches = 0;
    [offsetDictionary enumerateKeysAndObjectsUsingBlock:^(NSNumber* offset, NSNumber* count, BOOL *stop) {
        if (count.integerValue > 3) {
            matches += count.unsignedIntegerValue;
        }
    }];
    
    return matches;
}

@end
