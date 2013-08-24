//
//  LBAudioDetective.h
//  LBAudioDetective
//
//  Created by Laurin Brandner on 21.04.13.
//  Copyright (c) 2013 Laurin Brandner. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

typedef struct LBAudioDetectiveIdentificationUnit {
    Float32 magnitudes[5];
    Float32 frequencies[5];
} LBAudioDetectiveIdentificationUnit;

typedef struct LBAudioDetective *LBAudioDetectiveRef;
typedef void(*LBAudioDetectiveCallback)(LBAudioDetectiveRef outDetective, id callbackHelper);

#pragma mark (De)Allocation

LBAudioDetectiveRef LBAudioDetectiveNew();
void LBAudioDetectiveDispose(LBAudioDetectiveRef inDetective);

#pragma mark -
#pragma mark Getters

AudioStreamBasicDescription LBAudioDetectiveDefaultFormat();
AudioStreamBasicDescription LBAudioDetectiveGetFormat(LBAudioDetectiveRef inDetective);
LBAudioDetectiveIdentificationUnit* LBAudioDetectiveGetIdentificationUnits(LBAudioDetectiveRef inDetective, UInt32* outUnitNumber);
Float32 LBAudioDetectiveGetMinAmplitude(LBAudioDetectiveRef inDetective);
Float32* LBAudioDetectiveGetPitchSteps(LBAudioDetectiveRef inDetective, UInt32* outPitchStepsCount);

#pragma mark -
#pragma mark Setters

void LBAudioDetectiveSetFormat(LBAudioDetectiveRef inDetective, AudioStreamBasicDescription inStreamFormat);
void LBAudioDetectiveSetWriteAudioToURL(LBAudioDetectiveRef inDetective, NSURL* inFileURL);
void LBAudioDetectiveSetMinAmpltitude(LBAudioDetectiveRef inDetective, Float32 inMinAmplitude);
void LBAudioDetectiveSetPitchSteps(LBAudioDetectiveRef inDetective, Float32* inPitchSteps, UInt32 inPitchStepsCount);

#pragma mark -
#pragma mark Processing

void LBAudioDetectiveProcessAudioURL(LBAudioDetectiveRef inDetective, NSURL* inFileURL);

void LBAudioDetectiveProcess(LBAudioDetectiveRef inDetective, UInt32 inIdentificationUnitCount, LBAudioDetectiveCallback inCallback, id inCallbackHelper);
void LBAudioDetectiveStartProcessing(LBAudioDetectiveRef inDetective);
void LBAudioDetectiveStopProcessing(LBAudioDetectiveRef inDetective);

void LBAudioDetectiveResumeProcessing(LBAudioDetectiveRef inDetective);
void LBAudioDetectivePauseProcessing(LBAudioDetectiveRef inDetective);

#pragma mark -