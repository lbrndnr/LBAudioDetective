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
#import <AudioUnit/AudioUnit.h>
#import <Accelerate/Accelerate.h>

#if defined(__cplusplus)
extern "C" {
#endif
    
#import "LBAudioDetectiveFingerprint.h"
#import "LBAudioDetectiveFrame.h"
    
    extern const UInt32 kLBAudioDetectiveDefaultWindowSize;
    extern const UInt32 kLBAudioDetectiveDefaultAnalysisStride;
    extern const UInt32 kLBAudioDetectiveDefaultNumberOfPitchSteps;
    extern const UInt32 kLBAudioDetectiveDefaultFingerprintComparisonRange;
    extern const UInt32 kLBAudioDetectiveDefaultFingerprintLength;
    
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
UInt32 LBAudioDetectiveGetNumberOfPitchSteps(LBAudioDetectiveRef inDetective);
UInt32 LBAudioDetectiveGetFingerprintLength(LBAudioDetectiveRef inDetective);
UInt32 LBAudioDetectiveGetWindowSize(LBAudioDetectiveRef inDetective);
UInt32 LBAudioDetectiveGetAnalysisStride(LBAudioDetectiveRef inDetective);

LBAudioDetectiveFingerprintRef LBAudioDetectiveGetFingerprint(LBAudioDetectiveRef inDetective);

#pragma mark -
#pragma mark Setters

void LBAudioDetectiveSetRecordingFormat(LBAudioDetectiveRef inDetective, AudioStreamBasicDescription inStreamFormat);
void LBAudioDetectiveSetProcessingFormat(LBAudioDetectiveRef inDetective, AudioStreamBasicDescription inStreamFormat);
void LBAudioDetectiveSetNumberOfPitchSteps(LBAudioDetectiveRef inDetective, UInt32 inNumberOfPitchSteps);
void LBAudioDetectiveSetFingerprintLength(LBAudioDetectiveRef inDetective, UInt32 inFingerprintLength);
void LBAudioDetectiveSetWindowSize(LBAudioDetectiveRef inDetective, UInt32 inWindowSize);
void LBAudioDetectiveSetAnalysisStride(LBAudioDetectiveRef inDetective, UInt32 inAnalysisStride);

void LBAudioDetectiveSetWriteAudioToURL(LBAudioDetectiveRef inDetective, NSURL* inFileURL);

#pragma mark -
#pragma mark Processing

void LBAudioDetectiveProcessAudioURL(LBAudioDetectiveRef inDetective, NSURL* inFileURL);

void LBAudioDetectiveProcess(LBAudioDetectiveRef inDetective, UInt32 inMaxNumberOfProcessedSamples, LBAudioDetectiveCallback inCallback, id inCallbackHelper);
void LBAudioDetectiveStartProcessing(LBAudioDetectiveRef inDetective);
void LBAudioDetectiveStopProcessing(LBAudioDetectiveRef inDetective);

void LBAudioDetectiveResumeProcessing(LBAudioDetectiveRef inDetective);
void LBAudioDetectivePauseProcessing(LBAudioDetectiveRef inDetective);

#pragma mark -
#pragma mark Comparison

Float64 LBAudioDetectiveCompareAudioURLs(LBAudioDetectiveRef inDetective, NSURL* inFileURL1, NSURL* inFileURL2, UInt32 inComparisonRange);

#pragma mark -
    
#if defined(__cplusplus)
}
#endif
