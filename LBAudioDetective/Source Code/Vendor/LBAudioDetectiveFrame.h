//
//  LBAudioDetectiveFrame.h
//  LBAudioDetective
//
//  Created by Laurin Brandner on 28.08.13.
//  Copyright (c) 2013 Laurin Brandner. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef struct LBAudioDetectiveFrame *LBAudioDetectiveFrameRef;

#pragma mark (De)Allocation

LBAudioDetectiveFrameRef LBAudioDetectiveFrameNew(UInt32 inRowCount);
void LBAudioDetectiveFrameDispose(LBAudioDetectiveFrameRef inFrame);

LBAudioDetectiveFrameRef LBAudioDetectiveFrameCopy(LBAudioDetectiveFrameRef inFrame);

#pragma mark -
#pragma mark Getters

UInt32 LBAudioDetectiveFrameGetNumberOfRows(LBAudioDetectiveFrameRef inFrame);

Float32* LBAudioDetectiveFrameGetRow(LBAudioDetectiveFrameRef inFrame, UInt32 inRowIndex);
Float32 LBAudioDetectiveFrameGetValue(LBAudioDetectiveFrameRef inFrame, UInt32 inRowIndex, UInt32 inColumnIndex);

#pragma mark -
#pragma mark Setters

void LBAudioDetectiveFrameSetRow(LBAudioDetectiveFrameRef inFrame, Float32* inRow, UInt32 inRowIndex, UInt32 inCount);

#pragma mark -
#pragma mark Other Methods

void LBAudioDetectiveFrameDecompose(LBAudioDetectiveFrameRef inFrame);
size_t LBAudioDetectiveFrameFingerprintSize(LBAudioDetectiveFrameRef inFrame);
UInt32 LBAudioDetectiveFrameFingerprintLength(LBAudioDetectiveFrameRef inFrame);
void LBAudioDetectiveFrameExtractFingerprint(LBAudioDetectiveFrameRef inFrame, UInt32 inNumberOfWavelets, Boolean* outFingerprint, UInt32* outFingerprintLength);

Boolean LBAudioDetectiveFrameEqualToFrame(LBAudioDetectiveFrameRef inFrame1, LBAudioDetectiveFrameRef inFrame2);

#pragma mark -