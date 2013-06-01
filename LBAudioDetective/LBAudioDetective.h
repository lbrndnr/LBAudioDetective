//
//  LBAudioDetective.h
//  LBAudioDetective
//
//  Created by Laurin Brandner on 21.04.13.
//  Copyright (c) 2013 Laurin Brandner. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

typedef struct LBAudioDetectiveIdentificationUnit {
    Float32 magnitudes[5];
    Float32 frequencies[5];
} LBAudioDetectiveIdentificationUnit;

typedef struct LBAudioDetective *LBAudioDetectiveRef;

#pragma mark (De)Allocation

LBAudioDetectiveRef LBAudioDetectiveNew();
void LBAudioDetectiveDispose(LBAudioDetectiveRef detective);

#pragma mark -
#pragma mark Getters

AudioStreamBasicDescription LBAudioDetectiveDefaultFormat();
AudioStreamBasicDescription LBAudioDetectiveGetFormat(LBAudioDetectiveRef detective);
LBAudioDetectiveIdentificationUnit* LBAudioDetectiveGetIdentificationUnits(LBAudioDetectiveRef detective, UInt32* outUnitNumber);

#pragma mark -
#pragma mark Setters

void LBAudioDetectiveSetFormat(LBAudioDetectiveRef detective, AudioStreamBasicDescription inStreamFormat);
void LBAudioDetectiveSetWriteAudioToURL(LBAudioDetectiveRef detective, NSURL* inFileURL);

#pragma mark -
#pragma mark Processing

void LBAudioDetectiveProcessAudioURL(LBAudioDetectiveRef detective, NSURL* inFileURL);

void LBAudioDetectiveStartProcessing(LBAudioDetectiveRef detective);
void LBAudioDetectiveStopProcessing(LBAudioDetectiveRef detective);

void LBAudioDetectiveResumeProcessing(LBAudioDetectiveRef detective);
void LBAudioDetectivePauseProcessing(LBAudioDetectiveRef detective);

#pragma mark -