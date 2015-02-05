//
//  LBAudioDetective.m
//  LBAudioDetective
//
//  Created by Laurin Brandner on 21.04.13.
//  Copyright (c) 2013 Laurin Brandner. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <AudioUnit/AudioUnit.h>
#import <Accelerate/Accelerate.h>

#import "LBAudioDetective.h"
#import "LBAudioDetectiveFrame.h"

SInt32 AudioStreamBytesPerSample(AudioStreamBasicDescription asbd) {
    return asbd.mBytesPerFrame/asbd.mChannelsPerFrame;
}

const OSStatus kLBAudioDetectiveArgumentInvalid = 1;

const UInt32 kLBAudioDetectiveDefaultWindowSize = 2048;
const UInt32 kLBAudioDetectiveDefaultAnalysisStride = 64;
const UInt32 kLBAudioDetectiveDefaultNumberOfPitchSteps = 32;
const UInt32 kLBAudioDetectiveDefaultNumberOfRowsPerFrame = 128;
const UInt32 kLBAudioDetectiveDefaultSubfingerprintLength = 200;

typedef struct LBAudioDetective {
    AudioStreamBasicDescription processingFormat;
    ExtAudioFileRef inputFile;
    
    UInt32 subfingerprintLength;
    UInt32 windowSize;
    UInt32 analysisStride;
    UInt32 pitchStepCount;
    
    struct FFT {
        FFTSetup setup;
        COMPLEX_SPLIT A;
        UInt32 log2n;
        UInt32 n;
        UInt32 nOver2;
    } FFT;
} LBAudioDetective;

void LBAudioDetectiveSynthesizeFingerprint(LBAudioDetectiveRef inDetective, LBAudioDetectiveFrameRef* inFrames, UInt64 inNumberOfFrames, LBAudioDetectiveFingerprintRef* ioFingerprint);
OSStatus LBAudioDetectiveComputeFrequencies(LBAudioDetectiveRef inDetective, void* inSamples, UInt32 inNumberFrames, AudioStreamBasicDescription inDataFormat, UInt32 inNumberOfFrequencyBins, Float32* outData);

OSStatus LBAudioDetectiveConvertToFormat(void* inData, AudioStreamBasicDescription inFromFormat, AudioStreamBasicDescription inToFormat, UInt32 inNumberFrames, void* outData);

#pragma mark Utilites

#define LBErrorCheck(error) (LBErrorCheckOnLine(error, __LINE__))
#define LBAssert(condition) (LBErrorCheckOnLine(!condition, __LINE__))

static inline void LBErrorCheckOnLine(OSStatus error, int line) {
    if (error == noErr) {
        return;
    }
    
    char errorString[7];
    *(UInt32*)(errorString+1) = CFSwapInt32HostToBig(error);
    if (isprint(errorString[1]) && isprint(errorString[2]) && isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    }
    else {
        sprintf(errorString, "%d", (int)error);
    }
    
    fprintf(stderr, "Error %s on line %i\n", errorString, line);
}

#pragma mark -
#pragma mark (De)Allocation

LBAudioDetectiveRef LBAudioDetectiveNew() {
    size_t size = sizeof(LBAudioDetective);
    LBAudioDetective* instance = (LBAudioDetective*)malloc(size);
    memset(instance, 0, size);
    
    instance->processingFormat = LBAudioDetectiveDefaultProcessingFormat();
    
    instance->subfingerprintLength = kLBAudioDetectiveDefaultSubfingerprintLength;
    LBAudioDetectiveSetWindowSize(instance, kLBAudioDetectiveDefaultWindowSize);
    instance->analysisStride = kLBAudioDetectiveDefaultAnalysisStride;
    instance->pitchStepCount = kLBAudioDetectiveDefaultNumberOfPitchSteps;
    
    return instance;
}

OSStatus LBAudioDetectiveDispose(LBAudioDetectiveRef inDetective) {
    if (inDetective == NULL) {
        return kLBAudioDetectiveArgumentInvalid;
    }
    
    OSStatus error = noErr;
    
    if (inDetective->inputFile) {
        error = ExtAudioFileDispose(inDetective->inputFile);
        LBErrorCheck(error);
    }
    
    free(inDetective->FFT.A.realp);
    free(inDetective->FFT.A.imagp);
    vDSP_destroy_fftsetup(inDetective->FFT.setup);
    
    free(inDetective);
    
    return error;
}

#pragma mark -
#pragma mark Getters

AudioStreamBasicDescription LBAudioDetectiveDefaultProcessingFormat() {
    UInt32 bytesPerSample = sizeof(Float32);
    
	AudioStreamBasicDescription asbd = {0};
    memset(&asbd, 0, sizeof(AudioStreamBasicDescription));
	asbd.mFormatID = kAudioFormatLinearPCM;
	asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
	asbd.mBitsPerChannel = 8*bytesPerSample;
	asbd.mFramesPerPacket = 1;
	asbd.mChannelsPerFrame = 1;
	asbd.mBytesPerPacket = bytesPerSample*asbd.mFramesPerPacket;
	asbd.mBytesPerFrame = bytesPerSample*asbd.mChannelsPerFrame;
	asbd.mSampleRate = 5512.0;
    
    return asbd;
}

Float64 LBAudioDetectiveGetProcessingSampleRate(LBAudioDetectiveRef inDetective) {
    return inDetective->processingFormat.mSampleRate;
}

UInt32 LBAudioDetectiveGetNumberOfPitchSteps(LBAudioDetectiveRef inDetective) {
    return inDetective->pitchStepCount;
}

UInt32 LBAudioDetectiveGetSubfingerprintLength(LBAudioDetectiveRef inDetective) {
    return inDetective->subfingerprintLength;
}

UInt32 LBAudioDetectiveGetWindowSize(LBAudioDetectiveRef inDetective) {
    return inDetective->windowSize;
}

UInt32 LBAudioDetectiveGetAnalysisStride(LBAudioDetectiveRef inDetective) {
    return inDetective->analysisStride;
}

#pragma mark -
#pragma mark Setters

OSStatus LBAudioDetectiveSetProcessingSampleRate(LBAudioDetectiveRef inDetective, Float64 inSampleRate) {
    inDetective->processingFormat.mSampleRate = inSampleRate;
    
    return noErr;
}

OSStatus LBAudioDetectiveSetNumberOfPitchSteps(LBAudioDetectiveRef inDetective, UInt32 inNumberOfPitchSteps) {
    inDetective->pitchStepCount = inNumberOfPitchSteps;
    
    return noErr;
}

OSStatus LBAudioDetectiveSetSubfingerprintLength(LBAudioDetectiveRef inDetective, UInt32 inSubfingerprintLength) {
    inDetective->subfingerprintLength = inSubfingerprintLength;
    
    return noErr;
}

OSStatus LBAudioDetectiveSetWindowSize(LBAudioDetectiveRef inDetective, UInt32 inWindowSize) {
    OSStatus error = noErr;
    
    free(inDetective->FFT.A.realp);
    free(inDetective->FFT.A.imagp);
    vDSP_destroy_fftsetup(inDetective->FFT.setup);
    
    inDetective->windowSize = inWindowSize;
    
    inDetective->FFT.log2n = round(log2(inWindowSize));
    inDetective->FFT.n = (1 << inDetective->FFT.log2n);
    if (inDetective->FFT.n == inWindowSize) {
        error = kLBAudioDetectiveArgumentInvalid;
    }
    inDetective->FFT.nOver2 = inWindowSize/2;
    
	inDetective->FFT.A.realp = (Float32 *)calloc(inDetective->FFT.nOver2, sizeof(Float32));
	inDetective->FFT.A.imagp = (Float32 *)calloc(inDetective->FFT.nOver2, sizeof(Float32));
	inDetective->FFT.setup = vDSP_create_fftsetup(inDetective->FFT.log2n, FFT_RADIX2);
    
    return error;
}

OSStatus LBAudioDetectiveSetAnalysisStride(LBAudioDetectiveRef inDetective, UInt32 inAnalysisStride) {
    inDetective->analysisStride = inAnalysisStride;
    
    return noErr;
}

#pragma mark -
#pragma mark Other Methods

// Reads an audio file and processes it according to the set preferences

OSStatus LBAudioDetectiveProcessAudioURL(LBAudioDetectiveRef inDetective, NSURL* inFileURL, LBAudioDetectiveFingerprintRef* outFingerprint) {
    OSStatus error = noErr;
    
    if (!inFileURL) {
        error = kLBAudioDetectiveArgumentInvalid;
        return error;
    }
    
    if (inDetective->inputFile) {
        error = ExtAudioFileDispose(inDetective->inputFile);
        inDetective->inputFile = NULL;
        LBErrorCheck(error);
    }
    
    // Open the audio file in the given directory
    
    error = ExtAudioFileOpenURL((__bridge CFURLRef)(inFileURL), &inDetective->inputFile);
    LBErrorCheck(error);
    
    // Specify the format we want to read it with (PCM)
    
    error = ExtAudioFileSetProperty(inDetective->inputFile, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &inDetective->processingFormat);
    LBErrorCheck(error);
    
    // Get the length of the audio file
    
    UInt32 propertySize = sizeof(SInt64);
    SInt64 dataLength = 0;
    error = ExtAudioFileGetProperty(inDetective->inputFile, kExtAudioFileProperty_FileLengthFrames, &propertySize, &dataLength);
    LBErrorCheck(error);
    
    // Calculate the number of frames needed
    
    UInt32 numberFrames = inDetective->windowSize;
    AudioBufferList bufferList;
    Float32 samples[numberFrames]; // A large enough size to not have to worry about buffer overrun
    
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mData = samples;
    bufferList.mBuffers[0].mNumberChannels = inDetective->processingFormat.mChannelsPerFrame;
    bufferList.mBuffers[0].mDataByteSize = numberFrames*AudioStreamBytesPerSample(inDetective->processingFormat);
    
    UInt64 imageWidth = (dataLength - inDetective->windowSize)/inDetective->analysisStride;
    SInt64 offset = 0;
    UInt32 readNumberFrames = numberFrames;
    
    UInt32 f = 0;
    UInt64 framesCount = imageWidth/kLBAudioDetectiveDefaultNumberOfRowsPerFrame;
    LBAudioDetectiveFrameRef* frames = malloc(framesCount*sizeof(LBAudioDetectiveFrameRef));
    LBAudioDetectiveFrameRef currentFrame = NULL;
    UInt32 remainingData = imageWidth%kLBAudioDetectiveDefaultNumberOfRowsPerFrame;
    
    // Start reading by iterating through the data
    
    for (UInt64 i = 0; i < imageWidth-remainingData; i++) {
        UInt32 frameIndex = (i % kLBAudioDetectiveDefaultNumberOfRowsPerFrame);
        if (frameIndex == 0) {
            if (currentFrame) {
                frames[f] = currentFrame;
                f++;
            }
            
            currentFrame = LBAudioDetectiveFrameNew(kLBAudioDetectiveDefaultNumberOfRowsPerFrame);
        }
        
        // Read a window
        
        error = ExtAudioFileRead(inDetective->inputFile, &readNumberFrames, &bufferList);
        LBErrorCheck(error);
        
        // Calculate the frequencies and store it in a LBAudioDetectiveFrame
        
        Float32 data[inDetective->pitchStepCount];        
        error = LBAudioDetectiveComputeFrequencies(inDetective, bufferList.mBuffers[0].mData, readNumberFrames, inDetective->processingFormat, inDetective->pitchStepCount, data);
        LBErrorCheck(error);
        LBAudioDetectiveFrameSetRow(currentFrame, data, frameIndex, inDetective->pitchStepCount);
        
        // Go 64 sample frames further
        
        offset += inDetective->analysisStride;
        error = ExtAudioFileSeek(inDetective->inputFile, offset);
        LBErrorCheck(error);
    }
    if (currentFrame && LBAudioDetectiveFrameFull(currentFrame)) {
        frames[f] = currentFrame;
    }
    
    // Synthesise and store the fingerprint
    
    LBAudioDetectiveFingerprintRef fingerprint = LBAudioDetectiveFingerprintNew(0);
    LBAudioDetectiveSynthesizeFingerprint(inDetective, frames, framesCount, &fingerprint);
    
    *outFingerprint = fingerprint;
    
    for (UInt64 i = 0; i < framesCount; i++) {
        LBAudioDetectiveFrameDispose(frames[i]);
    }
    free(frames);
    
    return error;
}

#pragma mark -
#pragma mark Processing

// Conversion from an array of LBAudioDetectiveFrames to one LBAudioDetectivFingerprint

void LBAudioDetectiveSynthesizeFingerprint(LBAudioDetectiveRef inDetective, LBAudioDetectiveFrameRef* inFrames, UInt64 inNumberOfFrames, LBAudioDetectiveFingerprintRef* ioFingerprint) {
    for (UInt32 i = 0; i < inNumberOfFrames; i++) {
        LBAudioDetectiveFrameRef frame = inFrames[i];
        
        if (LBAudioDetectiveFrameFull(frame)) {
            LBAudioDetectiveFrameDecompose(frame);
            Boolean subfingerprint[2*inDetective->subfingerprintLength];
            memset(subfingerprint, 0, sizeof(subfingerprint));
            
            LBAudioDetectiveFrameExtractFingerprint(frame, inDetective->subfingerprintLength, subfingerprint);
            
            UInt32 subfingerprintLength = inDetective->subfingerprintLength;
            LBAudioDetectiveFingerprintSetSubfingerprintLength(*ioFingerprint, &subfingerprintLength);
            LBAudioDetectiveFingerprintAddSubfingerprint(*ioFingerprint, subfingerprint);
        }
    }
}

// Applies the FFT to the data, computes the frequencies and adds them up together

OSStatus LBAudioDetectiveComputeFrequencies(LBAudioDetectiveRef inDetective, void* inSamples, UInt32 inNumberFrames, AudioStreamBasicDescription inDataFormat, UInt32 inNumberOfFrequencyBins, Float32* outData) {
    OSStatus error = noErr;
    
    // Check first whether the format is the same, convert otherwise
    
    if (inDataFormat.mFormatFlags != inDetective->processingFormat.mFormatFlags || inDataFormat.mBytesPerFrame != inDataFormat.mBytesPerFrame) {
        Float32 convertedSamples[inNumberFrames];
        error = LBAudioDetectiveConvertToFormat(inSamples, inDataFormat, inDetective->processingFormat, inNumberFrames, convertedSamples);
        LBErrorCheck(error);
        
        error = LBAudioDetectiveComputeFrequencies(inDetective, convertedSamples, inNumberFrames, inDetective->processingFormat, inNumberOfFrequencyBins, outData);
        LBErrorCheck(error);
    }
    
    // Perform the FFT using Accelerate.framework
    
    Float32* samples = (Float32*)inSamples;

    vDSP_ctoz((COMPLEX*)samples, 2, &inDetective->FFT.A, 1, inDetective->FFT.nOver2);
    vDSP_fft_zrip(inDetective->FFT.setup, &inDetective->FFT.A, 1, inDetective->FFT.log2n, FFT_FORWARD);
    vDSP_ztoc(&inDetective->FFT.A, 1, (COMPLEX *)samples, 2, inDetective->FFT.nOver2);
    
    inDetective->FFT.A.imagp[0] = 0.0;
    
    // Calculate the ranges of the 32 categories according to the processing format
    
    UInt32 binsCount = inNumberOfFrequencyBins+1;
    Float64 maxFreq = inDetective->processingFormat.mSampleRate/2.0;
    Float64 minFreq = 318.0;
    
    Float64 logBase = exp(log(maxFreq/minFreq)/inNumberOfFrequencyBins);
    Float64 mincoef = (Float64)inDetective->windowSize/inDetective->processingFormat.mSampleRate*minFreq;
    UInt32 indices[binsCount];
    for (UInt32 j = 0; j < binsCount; j++) {
        UInt32 start = (UInt32)((pow(logBase, j)-1.0)*mincoef);
        indices[j] = start+(UInt32)mincoef;
    }
    
    UInt32 width = inNumberFrames/2.0;
    size_t size = inNumberOfFrequencyBins*sizeof(Float32*);
    memset(outData, 0, size);
    
    // Iterate through the spectrogram slice, the output of the FFT and store it in a buffer
    
    for (int i = 0; i < inNumberOfFrequencyBins; i++) {
        UInt32 lowBound = indices[i];
        UInt32 highBound = indices[i+1];
        UInt32 lowBoundIndex = ((2*lowBound)/(inDetective->processingFormat.mSampleRate/inNumberFrames))-1;
        UInt32 highBoundIndex = ((2*highBound)/(inDetective->processingFormat.mSampleRate/inNumberFrames))-1;
        Float32 p = 0.0;
        
        for (UInt32 k = lowBoundIndex; k < highBoundIndex; k++) {
            Float32 re = samples[2*k];
            Float32 img = samples[(2*k)+1];
            
            if (re > 0.0) {
                re /= (Float32)(width/2);
            }
            if (img > 0.0) {
                img /= (Float32)(width/2);
            }
            
            Float32 v = ((re*re)+(img*img));
            if (v == v && isfinite(v)) {
                // Check if v got NaN or inf
                p += v;
            }
        }
        
        outData[i] = p/(Float32)(highBound-lowBound);
    }
    
    return error;
}

#pragma mark -
#pragma mark Utilities

OSStatus LBAudioDetectiveConvertToFormat(void* inData, AudioStreamBasicDescription inFromFormat, AudioStreamBasicDescription inToFormat, UInt32 inNumberFrames, void* outData) {
    AudioConverterRef converter;
	OSStatus error = AudioConverterNew(&inFromFormat, &inToFormat, &converter);
    LBErrorCheck(error);
    
    AudioBufferList inBufferList;
    inBufferList.mNumberBuffers = 1;
    inBufferList.mBuffers[0].mNumberChannels = inFromFormat.mChannelsPerFrame;
    inBufferList.mBuffers[0].mDataByteSize = inNumberFrames*AudioStreamBytesPerSample(inFromFormat);
    inBufferList.mBuffers[0].mData = inData;
    
    AudioBufferList outBufferList;
    outBufferList.mNumberBuffers = 1;
    outBufferList.mBuffers[0].mNumberChannels = inToFormat.mChannelsPerFrame;
    outBufferList.mBuffers[0].mDataByteSize = inNumberFrames*AudioStreamBytesPerSample(inToFormat);
    outBufferList.mBuffers[0].mData = outData;
    
    error = AudioConverterConvertComplexBuffer(converter, inNumberFrames, &inBufferList, &outBufferList);
    LBErrorCheck(error);
    
    error = AudioConverterDispose(converter);
    LBErrorCheck(error);
    
    return error;
}

#pragma mark -
#pragma mark Comparison

OSStatus LBAudioDetectiveCompareAudioURLs(LBAudioDetectiveRef inDetective, NSURL* inFileURL1, NSURL* inFileURL2, UInt32 inComparisonRange, Float32* outMatch) {
    if (inComparisonRange == 0) {
        inComparisonRange = inDetective->subfingerprintLength;
    }
    
    LBAudioDetectiveFingerprintRef fingerprint1 = NULL;
    OSStatus error = noErr;
    error = LBAudioDetectiveProcessAudioURL(inDetective, inFileURL1, &fingerprint1);
    LBErrorCheck(error);
    
    LBAudioDetectiveFingerprintRef fingerprint2 = NULL;
    error = LBAudioDetectiveProcessAudioURL(inDetective, inFileURL2, &fingerprint2);
    LBErrorCheck(error);
    
    if (error == noErr) {
        *outMatch = LBAudioDetectiveFingerprintCompareToFingerprint(fingerprint1, fingerprint2, inComparisonRange);
    }
    
    LBAudioDetectiveFingerprintDispose(fingerprint1);
    LBAudioDetectiveFingerprintDispose(fingerprint2);
    
    return error;
}

#pragma mark -
