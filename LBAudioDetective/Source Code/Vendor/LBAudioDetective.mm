//
//  LBAudioDetective.m
//  LBAudioDetective
//
//  Created by Laurin Brandner on 21.04.13.
//  Copyright (c) 2013 Laurin Brandner. All rights reserved.
//

#import "LBAudioDetective.h"

#include "CARingBuffer.h"

SInt32 AudioStreamBytesPerSample(AudioStreamBasicDescription asbd) {
    return asbd.mBytesPerFrame/asbd.mChannelsPerFrame;
}

const UInt32 kLBAudioDetectiveDefaultWindowSize = 2048;
const UInt32 kLBAudioDetectiveDefaultAnalysisStride = 64;
const UInt32 kLBAudioDetectiveDefaultNumberOfPitchSteps = 32;
const UInt32 kLBAudioDetectiveDefaultFingerprintComparisonRange = 150;
const UInt32 kLBAudioDetectiveDefaultSubfingerprintLength = 128;

typedef struct LBAudioDetective {
    AUGraph graph;
    AudioUnit rioUnit;
    
    AudioStreamBasicDescription recordingFormat;
    AudioStreamBasicDescription processingFormat;
    
    ExtAudioFileRef inputFile;
    ExtAudioFileRef outputFile;
    
    LBAudioDetectiveFingerprintRef fingerprint;
    
    UInt32 subfingerprintLength;
    UInt32 windowSize;
    UInt32 analysisStride;
    UInt32 pitchStepCount;
    
    CARingBuffer* ringBuffer;
    UInt32 numberOfProcessedSamplesInWindow;
    UInt32 maxNumberOfSubfingerprints;
    LBAudioDetectiveFrameRef* frames;
    UInt32 numberOfFrames;
    UInt32 numberOfRowsInLastFrame;
    
    LBAudioDetectiveCallback callback;
    __unsafe_unretained id callbackHelper;
    
    struct FFT {
        FFTSetup setup;
        COMPLEX_SPLIT A;
        UInt32 log2n;
        UInt32 n;
        UInt32 nOver2;
    } FFT;
} LBAudioDetective;

void LBAudioDetectiveInitializeGraph(LBAudioDetectiveRef inDetective);
void LBAudioDetectiveReset(LBAudioDetectiveRef inDetective, Boolean keepFingerprint);

OSStatus LBAudioDetectiveMicrophoneOutput(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList* ioData);

Boolean LBAudioDetectiveAnalyzeIfWindowFull(LBAudioDetectiveRef inDetective, UInt32 inNumberFrames, AudioBufferList inData, AudioStreamBasicDescription inDataFormat, const AudioTimeStamp* inTimeStamp, LBAudioDetectiveFrameRef ioFrame);

void LBAudioDetectiveSynthesizeFingerprint(LBAudioDetectiveRef inDetective, LBAudioDetectiveFrameRef* inFrames, UInt32 inNumberOfFrames, LBAudioDetectiveFingerprintRef* outFingerprint);
void LBAudioDetectiveComputeFrequencies(LBAudioDetectiveRef inDetective, AudioBufferList* inBufferList, UInt32 inNumberFrames, AudioStreamBasicDescription inDataFormat, UInt32 inNumberOfFrequencyBins, Float32* outData);

Boolean LBAudioDetectiveConvertToFormat(AudioBufferList* inBufferList, AudioStreamBasicDescription inFromFormat, AudioStreamBasicDescription inToFormat, UInt32 inNumberFrames, AudioBufferList* ioBufferList);

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
    
    fprintf(stderr, "Error %s on line %i", errorString, line);
    
    exit(1);
}

#pragma mark -
#pragma mark (De)Allocation

LBAudioDetectiveRef LBAudioDetectiveNew() {
    size_t size = sizeof(LBAudioDetective);
    LBAudioDetective* instance = (LBAudioDetective*)malloc(size);
    memset(instance, 0, size);
    
    instance->recordingFormat = LBAudioDetectiveDefaultRecordingFormat();
    instance->processingFormat = LBAudioDetectiveDefaultProcessingFormat();
    
    instance->subfingerprintLength = kLBAudioDetectiveDefaultSubfingerprintLength;
    LBAudioDetectiveSetWindowSize(instance, kLBAudioDetectiveDefaultWindowSize);
    instance->analysisStride = kLBAudioDetectiveDefaultAnalysisStride;
    instance->pitchStepCount = kLBAudioDetectiveDefaultNumberOfPitchSteps;
    
    return instance;
}

void LBAudioDetectiveDispose(LBAudioDetectiveRef inDetective) {
    if (inDetective == NULL) {
        return;
    }
    
    LBAudioDetectiveStopProcessing(inDetective);
    
    AUGraphUninitialize(inDetective->graph);
    AUGraphClose(inDetective->graph);
    
    ExtAudioFileDispose(inDetective->inputFile);
    ExtAudioFileDispose(inDetective->outputFile);
    
    LBAudioDetectiveFingerprintDispose(inDetective->fingerprint);
    
    free(inDetective->FFT.A.realp);
    free(inDetective->FFT.A.imagp);
    vDSP_destroy_fftsetup(inDetective->FFT.setup);
    
    free(inDetective);
}

#pragma mark -
#pragma mark Getters

AudioStreamBasicDescription LBAudioDetectiveDefaultRecordingFormat() {
    Float64 defaultSampleRate;
    
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
    AVAudioSession* session = [AVAudioSession sharedInstance];
    defaultSampleRate = session.sampleRate;
#else
    defaultSampleRate = 44100.0;
#endif
    
    UInt32 bytesPerSample = sizeof(SInt16);
    
    AudioStreamBasicDescription asbd = {0};
    memset(&asbd, 0, sizeof(AudioStreamBasicDescription));
    asbd.mFormatID = kAudioFormatLinearPCM;
	asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;
	asbd.mBitsPerChannel = 8*bytesPerSample;
	asbd.mFramesPerPacket = 1;
	asbd.mChannelsPerFrame = 1;
	asbd.mBytesPerPacket = bytesPerSample*asbd.mFramesPerPacket;
	asbd.mBytesPerFrame = bytesPerSample*asbd.mChannelsPerFrame;
    asbd.mSampleRate = defaultSampleRate;
    
    return asbd;
}

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

AudioStreamBasicDescription LBAudioDetectiveGetRecordingFormat(LBAudioDetectiveRef inDetective) {
    return inDetective->recordingFormat;
}

AudioStreamBasicDescription LBAudioDetectiveGetProcessingFormat(LBAudioDetectiveRef inDetective) {
    return inDetective->processingFormat;
}

UInt32 LBAudioDetectiveGetNumberOfPitchSteps(LBAudioDetectiveRef inDetective) {
    return inDetective->pitchStepCount;
}

UInt32 LBAudioDetectiveGetSubingerprintLength(LBAudioDetectiveRef inDetective) {
    return inDetective->subfingerprintLength;
}

UInt32 LBAudioDetectiveGetWindowSize(LBAudioDetectiveRef inDetective) {
    return inDetective->windowSize;
}

UInt32 LBAudioDetectiveGetAnalysisStride(LBAudioDetectiveRef inDetective) {
    return inDetective->analysisStride;
}

LBAudioDetectiveFingerprintRef LBAudioDetectiveGetFingerprint(LBAudioDetectiveRef inDetective) {
    return inDetective->fingerprint;
}

#pragma mark -
#pragma mark Setters

void LBAudioDetectiveSetRecordingFormat(LBAudioDetectiveRef inDetective, AudioStreamBasicDescription inStreamFormat) {
    if (inDetective->outputFile) {
        OSStatus error = noErr;
        error = ExtAudioFileSetProperty(inDetective->outputFile, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &inDetective->recordingFormat);
        LBErrorCheck(error);
    }
    
    inDetective->recordingFormat = inStreamFormat;
}

void LBAudioDetectiveSetProcessingFormat(LBAudioDetectiveRef inDetective, AudioStreamBasicDescription inStreamFormat) {
    inDetective->processingFormat = inStreamFormat;
}

void LBAudioDetectiveSetNumberOfPitchSteps(LBAudioDetectiveRef inDetective, UInt32 inNumberOfPitchSteps) {
    inDetective->pitchStepCount = inNumberOfPitchSteps;
}

void LBAudioDetectiveSetWriteAudioToURL(LBAudioDetectiveRef inDetective, NSURL* fileURL) {
    OSStatus error = noErr;
    if (fileURL) {
        error =  ExtAudioFileCreateWithURL((__bridge CFURLRef)fileURL, kAudioFileCAFType, &inDetective->recordingFormat, NULL, kAudioFileFlags_EraseFile, &inDetective->outputFile);
        LBErrorCheck(error);
        
        error = ExtAudioFileSetProperty(inDetective->outputFile, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &inDetective->recordingFormat);
        LBErrorCheck(error);
        
        error = ExtAudioFileWriteAsync(inDetective->outputFile, 0, NULL);
        LBErrorCheck(error);
    }
    else {
        error = ExtAudioFileDispose(inDetective->outputFile);
        LBErrorCheck(error);
        
        inDetective->outputFile = NULL;
    }
}

void LBAudioDetectiveSetSubfingerprintLength(LBAudioDetectiveRef inDetective, UInt32 inSubfingerprintLength) {
    inDetective->subfingerprintLength = inSubfingerprintLength;
}

void LBAudioDetectiveSetWindowSize(LBAudioDetectiveRef inDetective, UInt32 inWindowSize) {
    free(inDetective->FFT.A.realp);
    free(inDetective->FFT.A.imagp);
    vDSP_destroy_fftsetup(inDetective->FFT.setup);
    
    inDetective->windowSize = inWindowSize;
    
    inDetective->FFT.log2n = log2(inWindowSize);
    inDetective->FFT.n = (1 << inDetective->FFT.log2n);
    LBAssert(inDetective->FFT.n == inWindowSize);
    inDetective->FFT.nOver2 = inWindowSize/2;
    
	inDetective->FFT.A.realp = (Float32 *)calloc(inDetective->FFT.nOver2, sizeof(Float32));
	inDetective->FFT.A.imagp = (Float32 *)calloc(inDetective->FFT.nOver2, sizeof(Float32));
	inDetective->FFT.setup = vDSP_create_fftsetup(inDetective->FFT.log2n, FFT_RADIX2);
}

void LBAudioDetectiveSetAnalysisStride(LBAudioDetectiveRef inDetective, UInt32 inAnalysisStride) {
    inDetective->analysisStride = inAnalysisStride;
}

#pragma mark -
#pragma mark Other Methods

void LBAudioDetectiveProcessAudioURL(LBAudioDetectiveRef inDetective, NSURL* inFileURL) {
    LBAudioDetectiveReset(inDetective, FALSE);
    
    if (inDetective->inputFile) {
        ExtAudioFileDispose(inDetective->inputFile);
        inDetective->inputFile = NULL;
    }
    
    OSStatus error = ExtAudioFileOpenURL((__bridge CFURLRef)(inFileURL), &inDetective->inputFile);
    LBErrorCheck(error);
    
    error = ExtAudioFileSetProperty(inDetective->inputFile, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &inDetective->processingFormat);
    LBErrorCheck(error);
    
    UInt32 propertySize = sizeof(SInt64);
    SInt64 dataLength = 0;
    error = ExtAudioFileGetProperty(inDetective->inputFile, kExtAudioFileProperty_FileLengthFrames, &propertySize, &dataLength);
    LBErrorCheck(error);
    
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
    UInt32 framesCount = imageWidth/inDetective->subfingerprintLength;
    LBAudioDetectiveFrameRef frames[framesCount];
    LBAudioDetectiveFrameRef currentFrame = NULL;
    
    UInt32 remainingData = imageWidth%inDetective->subfingerprintLength;
    for (UInt64 i = 0; i < imageWidth-remainingData; i++) {
        UInt32 frameIndex = (i % inDetective->subfingerprintLength);
        if (frameIndex == 0) {
            if (currentFrame) {
                frames[f] = currentFrame;
                f++;
            }
            
            currentFrame = LBAudioDetectiveFrameNew(inDetective->subfingerprintLength);
        }
        
        error = ExtAudioFileRead(inDetective->inputFile, &readNumberFrames, &bufferList);
        LBErrorCheck(error);
        
        Float32 data[inDetective->pitchStepCount];
        LBAudioDetectiveComputeFrequencies(inDetective, &bufferList, readNumberFrames, inDetective->processingFormat, inDetective->pitchStepCount, data);
        LBAudioDetectiveFrameSetRow(currentFrame, data, frameIndex, inDetective->pitchStepCount);
        
        offset += inDetective->analysisStride;
        error = ExtAudioFileSeek(inDetective->inputFile, offset);
        LBErrorCheck(error);
    }
    frames[f] = currentFrame;
    
    LBAudioDetectiveFingerprintRef fingerprint = LBAudioDetectiveFingerprintNew(0);
    LBAudioDetectiveSynthesizeFingerprint(inDetective, frames, framesCount, &fingerprint);
    
    inDetective->fingerprint = fingerprint;
    
    for (UInt64 i = 0; i < framesCount; i++) {
        LBAudioDetectiveFrameDispose(frames[i]);
    }

    LBAudioDetectiveReset(inDetective, TRUE);
}

void LBAudioDetectiveProcess(LBAudioDetectiveRef inDetective, UInt32 inMaxNumberOfSubfingerprints, LBAudioDetectiveCallback inCallback, id inCallbackHelper) {
    inDetective->maxNumberOfSubfingerprints = inMaxNumberOfSubfingerprints;
    inDetective->callback = inCallback;
    inDetective->callbackHelper = inCallbackHelper;
    LBAudioDetectiveStartProcessing(inDetective);
}

void LBAudioDetectiveStartProcessing(LBAudioDetectiveRef inDetective) {
    if (inDetective->graph == NULL || inDetective->rioUnit == NULL) {
        LBAudioDetectiveInitializeGraph(inDetective);
    }
    
    LBAudioDetectiveReset(inDetective, FALSE);
    inDetective->ringBuffer = new CARingBuffer();
    inDetective->ringBuffer->Allocate(inDetective->recordingFormat.mChannelsPerFrame, inDetective->recordingFormat.mBytesPerFrame, inDetective->windowSize);
    
    AUGraphStart(inDetective->graph);
}

void LBAudioDetectiveStopProcessing(LBAudioDetectiveRef inDetective) {
    AUGraphStop(inDetective->graph);
    LBAudioDetectiveReset(inDetective, TRUE);
}

void LBAudioDetectiveResumeProcessing(LBAudioDetectiveRef inDetective) {
    LBAudioDetectiveStartProcessing(inDetective);
}

void LBAudioDetectivePauseProcessing(LBAudioDetectiveRef inDetective) {
    LBAudioDetectiveStopProcessing(inDetective);
}

#pragma mark -
#pragma mark Processing

void LBAudioDetectiveInitializeGraph(LBAudioDetectiveRef inDetective) {
    // Create new AUGraph
    OSStatus error = NewAUGraph(&inDetective->graph);
    LBErrorCheck(error);
    
    // Initialize rioNode (microphone input)
    AudioComponentDescription rioCD = {0};
    rioCD.componentType = kAudioUnitType_Output;
    rioCD.componentSubType = kAudioUnitSubType_RemoteIO;
    rioCD.componentManufacturer = kAudioUnitManufacturer_Apple;
    rioCD.componentFlags = 0;
    rioCD.componentFlagsMask = 0;
    
    AUNode rioNode;
    error = AUGraphAddNode(inDetective->graph, &rioCD, &rioNode);
    LBErrorCheck(error);
    
    // Open the graph so I can modify the audio units
    error = AUGraphOpen(inDetective->graph);
    LBErrorCheck(error);
    
    // Get initialized rioUnit
    error = AUGraphNodeInfo(inDetective->graph, rioNode, NULL, &inDetective->rioUnit);
    LBErrorCheck(error);
    
    // Set properties to rioUnit
    AudioUnitElement bus0 = 0, bus1 = 1;
    UInt32 onFlag = 1, offFlag = 0;
    UInt32 propertySize = sizeof(UInt32);
    
    // Enable microphone input
	error = AudioUnitSetProperty(inDetective->rioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, bus1, &onFlag, propertySize);
    LBErrorCheck(error);
	
    // Disable speakers output
	error = AudioUnitSetProperty(inDetective->rioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, bus0, &offFlag, propertySize);
    LBErrorCheck(error);
    
    // Set the stream format we want
    propertySize = sizeof(AudioStreamBasicDescription);
    error = AudioUnitSetProperty(inDetective->rioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, bus0, &inDetective->recordingFormat, propertySize);
    LBErrorCheck(error);
    
    error = AudioUnitSetProperty(inDetective->rioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, bus1, &inDetective->recordingFormat, propertySize);
    LBErrorCheck(error);
	
    AURenderCallbackStruct callback = {0};
    callback.inputProc = LBAudioDetectiveMicrophoneOutput;
	callback.inputProcRefCon = inDetective;
    propertySize = sizeof(AURenderCallbackStruct);
	error = AudioUnitSetProperty(inDetective->rioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, bus0, &callback, propertySize);
    LBErrorCheck(error);
    
    propertySize = sizeof(UInt32);
    error = AudioUnitSetProperty(inDetective->rioUnit, kAudioUnitProperty_ShouldAllocateBuffer, kAudioUnitScope_Output, bus1, &offFlag, propertySize);
    LBErrorCheck(error);
    
    // Initialize Graph
    error = AUGraphInitialize(inDetective->graph);
    LBErrorCheck(error);
}

void LBAudioDetectiveReset(LBAudioDetectiveRef inDetective, Boolean keepFingerprint) {
    if (!keepFingerprint) {
        LBAudioDetectiveFingerprintDispose(inDetective->fingerprint);
        inDetective->fingerprint = NULL;
    }
    
    if (inDetective->ringBuffer) {
        inDetective->ringBuffer->Deallocate();
        inDetective->ringBuffer = NULL;
    }
    
    if (inDetective->frames) {
        for (UInt32 i = 0; i < inDetective->numberOfFrames; i++) {
            LBAudioDetectiveFrameDispose(inDetective->frames[i]);
        }
        free(inDetective->frames);
        inDetective->frames = NULL;
    }
    
    inDetective->maxNumberOfSubfingerprints = 0;
    inDetective->numberOfProcessedSamplesInWindow = 0;
    inDetective->numberOfProcessedSamplesInWindow = 0;
    inDetective->numberOfFrames = 0;
    inDetective->numberOfRowsInLastFrame = 0;
    inDetective->callback = NULL;
    inDetective->callbackHelper = nil;
}

OSStatus LBAudioDetectiveMicrophoneOutput(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList* ioData) {
    LBAudioDetective* inDetective = (LBAudioDetective*)inRefCon;
    OSStatus error = noErr;
    
    AudioBufferList bufferList;
    SInt16 samples[inNumberFrames];
    memset(samples, 0, sizeof(samples));
    
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mData = samples;
    bufferList.mBuffers[0].mNumberChannels = inDetective->recordingFormat.mChannelsPerFrame;
    bufferList.mBuffers[0].mDataByteSize = inNumberFrames*AudioStreamBytesPerSample(inDetective->recordingFormat);
    
    error = AudioUnitRender(inDetective->rioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, &bufferList);
    LBErrorCheck(error);
    
    if (inDetective->outputFile) {
        error = ExtAudioFileWriteAsync(inDetective->outputFile, inNumberFrames, &bufferList);
        LBErrorCheck(error);
    }
    
    Boolean computedAllSubfingerprints = FALSE;
    if (inDetective->numberOfFrames == 0 || inDetective->numberOfRowsInLastFrame == inDetective->subfingerprintLength) {
        if (inDetective->maxNumberOfSubfingerprints > 0 && inDetective->numberOfFrames == inDetective->maxNumberOfSubfingerprints) {
            computedAllSubfingerprints = TRUE;
        }
        else {
            inDetective->numberOfFrames++;
            inDetective->frames = (LBAudioDetectiveFrameRef*)realloc(inDetective->frames, sizeof(LBAudioDetectiveFrameRef)*inDetective->numberOfFrames);
            inDetective->frames[inDetective->numberOfFrames-1] = LBAudioDetectiveFrameNew(inDetective->subfingerprintLength);
            inDetective->numberOfRowsInLastFrame = 0;
        }
    }
    
    LBAudioDetectiveFrameRef lastFrame = inDetective->frames[inDetective->numberOfFrames-1];
    Boolean success = LBAudioDetectiveAnalyzeIfWindowFull(inDetective, inNumberFrames, bufferList, inDetective->recordingFormat, inTimeStamp, lastFrame);
    if (success) {
        inDetective->numberOfRowsInLastFrame++;
    }
    
    if (computedAllSubfingerprints) {
        if (inDetective->callback) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                inDetective->callback(inDetective, inDetective->callbackHelper);
            });
        }
        
        LBAudioDetectiveStopProcessing(inDetective);
    }
    
    return error;
}

Boolean LBAudioDetectiveAnalyzeIfWindowFull(LBAudioDetectiveRef inDetective, UInt32 inNumberFrames, AudioBufferList inData, AudioStreamBasicDescription inDataFormat, const AudioTimeStamp* inTimeStamp, LBAudioDetectiveFrameRef ioFrame) {
    SInt64 delta = inDetective->windowSize-(inDetective->numberOfProcessedSamplesInWindow+inNumberFrames);
    if (delta > 0) {
        // Window is not full yet
        
        inDetective->ringBuffer->Store(&inData, inNumberFrames, inTimeStamp->mSampleTime);
        inDetective->numberOfProcessedSamplesInWindow += inNumberFrames;
    }
    else {
        // Store remaining data to the ring buffer in order to fill the window
        
        UInt32 remainingNumberFrames = (inNumberFrames+delta);
        inData.mBuffers[0].mDataByteSize = remainingNumberFrames*AudioStreamBytesPerSample(inDetective->recordingFormat);
        
        inDetective->ringBuffer->Store(&inData, remainingNumberFrames, inTimeStamp->mSampleTime);
        
        AudioBufferList bufferList;
        SInt16 samples[inDetective->windowSize];
        memset(samples, 0, sizeof(samples));
        
        bufferList.mNumberBuffers = 1;
        bufferList.mBuffers[0].mData = samples;
        bufferList.mBuffers[0].mNumberChannels = inDetective->recordingFormat.mChannelsPerFrame;
        bufferList.mBuffers[0].mDataByteSize = inDetective->windowSize*AudioStreamBytesPerSample(inDetective->recordingFormat);
        inDetective->ringBuffer->Fetch(&bufferList, inDetective->windowSize, inTimeStamp->mSampleTime-(inDetective->windowSize/inDataFormat.mSampleRate));
        
        Float32 row[inDetective->pitchStepCount];
        LBAudioDetectiveComputeFrequencies(inDetective, &bufferList, inDetective->windowSize, inDetective->recordingFormat, inDetective->pitchStepCount, row);
        LBAudioDetectiveFrameSetRow(ioFrame, row, inDetective->numberOfRowsInLastFrame, inDetective->pitchStepCount);
        
        if (delta != 0) {
            SInt16* data = (SInt16*)inData.mBuffers[0].mData;
            SInt16* truncatedData = data-delta;
            
            inData.mBuffers[0].mData = truncatedData;
            inData.mBuffers[0].mDataByteSize = -delta*AudioStreamBytesPerSample(inDetective->recordingFormat);
            
            SInt64 sampleTime = inTimeStamp->mSampleTime+(-delta/inDataFormat.mSampleRate);
            
            inDetective->ringBuffer->Store(&inData, -delta, sampleTime);
        }
        inDetective->numberOfProcessedSamplesInWindow = -delta;
        
        return TRUE;
    }
    
    return FALSE;
}

void LBAudioDetectiveSynthesizeFingerprint(LBAudioDetectiveRef inDetective, LBAudioDetectiveFrameRef* inFrames, UInt32 inNumberOfFrames, LBAudioDetectiveFingerprintRef* outFingerprint) {
    for (UInt32 i = 0; i < inNumberOfFrames; i++) {
        LBAudioDetectiveFrameRef frame = inFrames[i];
        
        LBAudioDetectiveFrameDecompose(frame);
        Boolean subfingerprint[LBAudioDetectiveFrameFingerprintLength(frame)];
        memset(subfingerprint, 0, sizeof(subfingerprint));
        
        UInt32 subfingerprintLength = 0;
        LBAudioDetectiveFrameExtractFingerprint(frame, 200, subfingerprint, &subfingerprintLength);
        
        LBAudioDetectiveFingerprintSetSubfingerprintLength(*outFingerprint, &subfingerprintLength);
        LBAudioDetectiveFingerprintAddSubfingerprint(*outFingerprint, subfingerprint);
    }
}

void LBAudioDetectiveComputeFrequencies(LBAudioDetectiveRef inDetective, AudioBufferList* inBufferList, UInt32 inNumberFrames, AudioStreamBasicDescription inDataFormat, UInt32 inNumberOfFrequencyBins, Float32* outData) {
    AudioBufferList convertedBufferList;
    convertedBufferList.mNumberBuffers = 1;
    convertedBufferList.mBuffers[0].mNumberChannels = inBufferList->mBuffers[0].mNumberChannels;
    convertedBufferList.mBuffers[0].mDataByteSize = inNumberFrames*AudioStreamBytesPerSample(inDataFormat);
    
    Float32 conversionBuffer[inNumberFrames];
    convertedBufferList.mBuffers[0].mData = conversionBuffer;
    
    Boolean converted = LBAudioDetectiveConvertToFormat(inBufferList, inDataFormat, inDetective->processingFormat, inNumberFrames, &convertedBufferList);
    if (!converted) {
        convertedBufferList.mBuffers[0].mData = inBufferList->mBuffers[0].mData;
        convertedBufferList.mBuffers[0].mDataByteSize = inBufferList->mBuffers[0].mDataByteSize;
    }
    
    /*
     Look at the real signal as an interleaved complex vector by casting it.
     Then call the transformation function vDSP_ctoz to get a split complex
     vector, which for a real signal, divides into an even-odd configuration.
     */
    vDSP_ctoz((COMPLEX*)convertedBufferList.mBuffers[0].mData, 2, &inDetective->FFT.A, 1, inDetective->FFT.nOver2);
    
    // Carry out a Forward FFT transform.
    vDSP_fft_zrip(inDetective->FFT.setup, &inDetective->FFT.A, 1, inDetective->FFT.log2n, FFT_FORWARD);
    
    // The output signal is now in a split real form. Use the vDSP_ztoc to get a split real vector.
    vDSP_ztoc(&inDetective->FFT.A, 1, (COMPLEX *)convertedBufferList.mBuffers[0].mData, 2, inDetective->FFT.nOver2);
    
    UInt32 binsCount = inNumberOfFrequencyBins+1;
    UInt32 maxFreq = inDataFormat.mSampleRate/2.0;
    UInt32 indices[binsCount];
    UInt32 step = maxFreq/binsCount;
    UInt32 freq = step;
    for (int j = 0; j < binsCount; j++) {
        indices[j] = freq;
        freq += step;
    }
    
    UInt32 width = inNumberFrames/2.0;
    size_t size = inNumberOfFrequencyBins*sizeof(Float32*);
    memset(outData, 0, size);
    
    for (int i = 0; i < inNumberOfFrequencyBins; i++) {
        UInt32 lowBound = indices[i];
        UInt32 highBound = indices[i+1];
        UInt32 lowBoundIndex = ((2*lowBound)/(inDataFormat.mSampleRate/inNumberFrames))-1;
        UInt32 highBoundIndex = ((2*highBound)/(inDataFormat.mSampleRate/inNumberFrames))-1;
        
        Float32 p = 0.0;
        
        for (UInt32 k = lowBoundIndex; k < highBoundIndex; k++) {
            Float32 re = ((Float32*)convertedBufferList.mBuffers[0].mData)[2*k]/(Float32)(width/2);
            Float32 img = ((Float32*)convertedBufferList.mBuffers[0].mData)[(2*k)+1]/(Float32)(width/2);
            Float32 v = ((re*re)+(img*img));
            
            p += v;
        }
        
        outData[i] = p/(Float32)(highBound-lowBound);
    }
}

#pragma mark -
#pragma mark Utilities

Boolean LBAudioDetectiveConvertToFormat(AudioBufferList* inBufferList, AudioStreamBasicDescription inFromFormat, AudioStreamBasicDescription inToFormat, UInt32 inNumberFrames, AudioBufferList* ioBufferList) {
    if (inFromFormat.mSampleRate == inToFormat.mSampleRate && inFromFormat.mFormatFlags == inToFormat.mFormatFlags && inFromFormat.mBytesPerFrame == inToFormat.mBytesPerFrame && inFromFormat.mChannelsPerFrame == inToFormat.mChannelsPerFrame) {
        return FALSE;
    }
    
    AudioConverterRef converter;
	OSStatus error = AudioConverterNew(&inFromFormat, &inToFormat, &converter);
    LBErrorCheck(error);
    
    if (inFromFormat.mSampleRate != inToFormat.mSampleRate || inFromFormat.mChannelsPerFrame != inToFormat.mChannelsPerFrame) {
        error = AudioConverterConvertComplexBuffer(converter, inNumberFrames, inBufferList, ioBufferList);
    }
    else {
        error = AudioConverterConvertBuffer(converter, inBufferList->mBuffers[0].mDataByteSize, &inBufferList->mBuffers[0], &inBufferList->mBuffers[0].mDataByteSize, ioBufferList);
        LBErrorCheck(error);
    }
    
    error = AudioConverterDispose(converter);
    LBErrorCheck(error);
    
    return TRUE;
}

#pragma mark -
#pragma mark Comparison

Float32 LBAudioDetectiveCompareAudioURLs(LBAudioDetectiveRef inDetective, NSURL* inFileURL1, NSURL* inFileURL2, UInt32 inComparisonRange) {
    if (inComparisonRange == 0) {
        inComparisonRange = kLBAudioDetectiveDefaultFingerprintComparisonRange;
    }
    
    LBAudioDetectiveProcessAudioURL(inDetective, inFileURL1);
    LBAudioDetectiveFingerprintRef fingerprint1 = LBAudioDetectiveFingerprintCopy(inDetective->fingerprint);
    
    LBAudioDetectiveProcessAudioURL(inDetective, inFileURL2);
    LBAudioDetectiveFingerprintRef fingerprint2 = inDetective->fingerprint;
    
    Float32 match = LBAudioDetectiveFingerprintCompareToFingerprint(fingerprint1, fingerprint2, inComparisonRange);
    
    LBAudioDetectiveFingerprintDispose(fingerprint1);
    
    return match;
}

#pragma mark -
