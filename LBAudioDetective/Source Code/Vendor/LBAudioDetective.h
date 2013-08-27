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

extern const UInt32 kLBAudioDetectiveDefaultWindowSize;
extern const UInt32 kLBAudioDetectiveDefaultAnalysisStride;

typedef struct LBAudioDetective *LBAudioDetectiveRef;
typedef void(*LBAudioDetectiveCallback)(LBAudioDetectiveRef outDetective, id callbackHelper);

#pragma mark (De)Allocation

LBAudioDetectiveRef LBAudioDetectiveNew();
void LBAudioDetectiveDispose(LBAudioDetectiveRef inDetective);

#pragma mark -
#pragma mark Getters

AudioStreamBasicDescription LBAudioDetectiveDefaultRecordingFormat();
AudioStreamBasicDescription LBAudioDetectiveDefaultProcessingFormat();

AudioStreamBasicDescription LBAudioDetectiveGetRecordingFormat(LBAudioDetectiveRef inDetective);
AudioStreamBasicDescription LBAudioDetectiveGetProcessingFormat(LBAudioDetectiveRef inDetective);
Float32 LBAudioDetectiveGetMinAmplitude(LBAudioDetectiveRef inDetective);
Float32* LBAudioDetectiveGetPitchSteps(LBAudioDetectiveRef inDetective, UInt32* outPitchStepsCount);
UInt32 LBAudioDetectiveGetWindowSize(LBAudioDetectiveRef inDetective);
UInt32 LBAudioDetectiveGetAnalysisStride(LBAudioDetectiveRef inDetective);

LBAudioDetectiveIdentificationUnit* LBAudioDetectiveGetIdentificationUnits(LBAudioDetectiveRef inDetective, UInt32* outUnitNumber);

#pragma mark -
#pragma mark Setters

void LBAudioDetectiveSetRecordingFormat(LBAudioDetectiveRef inDetective, AudioStreamBasicDescription inStreamFormat);
void LBAudioDetectiveSetProcessingFormat(LBAudioDetectiveRef inDetective, AudioStreamBasicDescription inStreamFormat);
void LBAudioDetectiveSetMinAmpltitude(LBAudioDetectiveRef inDetective, Float32 inMinAmplitude);
void LBAudioDetectiveSetPitchSteps(LBAudioDetectiveRef inDetective, Float32* inPitchSteps, UInt32 inPitchStepsCount);
void LBAudioDetectiveSetWindowSize(LBAudioDetectiveRef inDetective, UInt32 inWindowSize);
void LBAudioDetectiveSetAnalysisStride(LBAudioDetectiveRef inDetective, UInt32 inAnalysisStride);

void LBAudioDetectiveSetWriteAudioToURL(LBAudioDetectiveRef inDetective, NSURL* inFileURL);

#pragma mark -
#pragma mark Processing

void LBAudioDetectiveProcessAudioURL(LBAudioDetectiveRef inDetective, NSURL* inFileURL);

void LBAudioDetectiveProcess(LBAudioDetectiveRef inDetective, UInt32 inIdentificationUnitCount, LBAudioDetectiveCallback inCallback, id inCallbackHelper);
void LBAudioDetectiveStartProcessing(LBAudioDetectiveRef inDetective);
void LBAudioDetectiveStopProcessing(LBAudioDetectiveRef inDetective);

void LBAudioDetectiveResumeProcessing(LBAudioDetectiveRef inDetective);
void LBAudioDetectivePauseProcessing(LBAudioDetectiveRef inDetective);

#pragma mark -
#pragma mark Comparison

UInt32 LBAudioDetectiveCompareAudioURLs(LBAudioDetectiveRef inDetective, NSURL* inFileURL1, NSURL* inFileURL2);
UInt32 LBAudioDetectiveCompareAudioUnits(LBAudioDetectiveIdentificationUnit* units1, UInt32 unitCount1, LBAudioDetectiveIdentificationUnit* units2, UInt32 unitCount2);

#pragma mark -