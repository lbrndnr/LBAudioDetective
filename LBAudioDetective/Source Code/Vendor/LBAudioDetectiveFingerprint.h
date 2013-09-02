//
//  LBAudioDetectiveFingerprint.h
//  LBAudioDetective
//
//  Created by Laurin Brandner on 30.08.13.
//  Copyright (c) 2013 Laurin Brandner. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef struct LBAudioDetectiveFingerprint *LBAudioDetectiveFingerprintRef;

#pragma mark (De)Allocation

LBAudioDetectiveFingerprintRef LBAudioDetectiveFingerprintNew(UInt32 inSubfingerprintLength);
void LBAudioDetectiveFingerprintDispose(LBAudioDetectiveFingerprintRef inFingerprint);

LBAudioDetectiveFingerprintRef LBAudioDetectiveFingerprintCopy(LBAudioDetectiveFingerprintRef inFingerprint);

#pragma mark -
#pragma mark Getters

UInt32 LBAudioDetectiveFingerprintGetSubfingerprintLength(LBAudioDetectiveFingerprintRef inFingerprint);
UInt32 LBAudioDetectiveFingerprintGetNumberOfSubfingerprints(LBAudioDetectiveFingerprintRef inFingerprint);

#pragma mark -
#pragma mark Setters

Boolean LBAudioDetectiveFingerprintSetSubfingerprintLength(LBAudioDetectiveFingerprintRef inFingerprint, UInt32* ioSubfingerprintLength);
void LBAudioDetectiveFingerprintAddSubfingerprint(LBAudioDetectiveFingerprintRef inFingerprint, Boolean* inSubfingerprint);

#pragma mark -
#pragma mark Other Methods

Boolean LBAudioDetectiveFingerprintEqualToFingerprint(LBAudioDetectiveFingerprintRef inFingerprint1, LBAudioDetectiveFingerprintRef inFingerprint2);
Float32 LBAudioDetectiveFingerprintCompareToFingerprint(LBAudioDetectiveFingerprintRef inFingerprint1, LBAudioDetectiveFingerprintRef inFingerprint2, UInt32 inRange);
Float32 LBAudioDetectiveFingerprintCompareSubfingerprints(LBAudioDetectiveFingerprintRef inFingerprint, Boolean* inSubfingerprint1, Boolean* inSubfingerprint2, UInt32 inRange);

#pragma mark -
