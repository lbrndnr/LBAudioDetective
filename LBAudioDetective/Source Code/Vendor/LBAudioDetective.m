//
//  LBAudioDetective.m
//  LBAudioDetective
//
//  Created by Laurin Brandner on 21.04.13.
//  Copyright (c) 2013 Laurin Brandner. All rights reserved.
//

#import <AudioUnit/AudioUnit.h>
#import <Accelerate/Accelerate.h>
#import "LBAudioDetective.h"

SInt32 AudioStreamBytesPerSample(AudioStreamBasicDescription asbd) {
    return asbd.mBytesPerFrame/asbd.mChannelsPerFrame;
}

const UInt32 kLBAudioDetectiveWindowSize = 512; // 0.5 KB

typedef struct LBAudioDetective {
    AUGraph graph;
    AudioUnit rioUnit;
    
    AudioStreamBasicDescription recordingFormat;
    AudioStreamBasicDescription processingFormat;
    
    ExtAudioFileRef inputFile;
    ExtAudioFileRef outputFile;
    
    LBAudioDetectiveIdentificationUnit* identificationUnits;
    Float32 minAmpltiude;
    UInt32 identificationUnitCount;
    UInt32 maxIdentificationUnitCount;
    
    Float32* pitchSteps;
    UInt32 pitchStepsCount;
    
    LBAudioDetectiveCallback callback;
    __unsafe_unretained id callbackHelper;
    
    struct FFT {
        void* buffer;
        FFTSetup setup;
        COMPLEX_SPLIT A;
        UInt32 log2n;
        UInt32 n;
        UInt32 nOver2;
        UInt32 index;
    } FFT;
} LBAudioDetective;

void LBAudioDetectiveInitializeGraph(LBAudioDetectiveRef inDetective);
void LBAudioDetectiveReset(LBAudioDetectiveRef inDetective);
void LBAudioDetectiveClean(LBAudioDetectiveRef inDetective);
OSStatus LBAudioDetectiveMicrophoneOutput(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList* ioData);

void LBAudioDetectiveAnalyseIfFrameFull(LBAudioDetectiveRef inDetective, UInt32 inNumberFrames, AudioBufferList inData, AudioStreamBasicDescription inDataFormat);
void LBAudioDetectiveAnalyse(LBAudioDetectiveRef inDetective, void* inBuffer, UInt32 inNumberFrames, AudioStreamBasicDescription inDataFormat);
Boolean LBAudioDetectiveIdentificationUnitAddFrequency(LBAudioDetectiveIdentificationUnit* identification, Float32 frequency, Float32 magnitude, UInt32 index);

UInt32 LBAudioDetectivePitchRange(LBAudioDetectiveRef inDetective, Float32 pitch);
Boolean LBAudioDetectiveConvertToFormat(void* inBuffer, UInt32 inBufferSize, AudioStreamBasicDescription inFromFormat, AudioStreamBasicDescription inToFormat, void* outBuffer);

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
    LBAudioDetective* instance = (LBAudioDetective*)malloc(sizeof(LBAudioDetective));
    memset(instance, 0, sizeof(LBAudioDetective));
    
    instance->recordingFormat = LBAudioDetectiveDefaultRecordingFormat();
    instance->processingFormat = LBAudioDetectiveDefaultProcessingFormat();

    instance->FFT.log2n = log2(kLBAudioDetectiveWindowSize);
    instance->FFT.n = (1 << instance->FFT.log2n);
    LBAssert(instance->FFT.n == kLBAudioDetectiveWindowSize);
    
    instance->FFT.nOver2 = kLBAudioDetectiveWindowSize/2;
	instance->FFT.A.realp = (float *)malloc(instance->FFT.nOver2*sizeof(Float32));
	instance->FFT.A.imagp = (float *)malloc(instance->FFT.nOver2*sizeof(Float32));
	instance->FFT.setup = vDSP_create_fftsetup(instance->FFT.log2n, FFT_RADIX2);
    
    return instance;
}

void LBAudioDetectiveDispose(LBAudioDetectiveRef inDetective) {
    LBAudioDetectiveStopProcessing(inDetective);
    
    AUGraphUninitialize(inDetective->graph);
    AUGraphClose(inDetective->graph);
    
    ExtAudioFileDispose(inDetective->inputFile);
    ExtAudioFileDispose(inDetective->outputFile);
    
    free(inDetective->identificationUnits);
    
    free(inDetective->pitchSteps);
    
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

LBAudioDetectiveIdentificationUnit* LBAudioDetectiveGetIdentificationUnits(LBAudioDetectiveRef inDetective, UInt32* outUnitNumber) {
    *outUnitNumber = inDetective->identificationUnitCount;
    return inDetective->identificationUnits;
}

Float32 LBAudioDetectiveGetMinAmplitude(LBAudioDetectiveRef inDetective) {
    return inDetective->minAmpltiude;
}

Float32* LBAudioDetectiveGetPitchSteps(LBAudioDetectiveRef inDetective, UInt32* outPitchStepsCount) {
    *outPitchStepsCount = inDetective->pitchStepsCount;
    return inDetective->pitchSteps;
}

#pragma mark -
#pragma mark Setters

void LBAudioDetectiveSetRecordingFormat(LBAudioDetectiveRef inDetective, AudioStreamBasicDescription inStreamFormat) {
    inDetective->recordingFormat = inStreamFormat;
}

void LBAudioDetectiveSetProcessingFormat(LBAudioDetectiveRef inDetective, AudioStreamBasicDescription inStreamFormat) {
    inDetective->processingFormat = inStreamFormat;
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

void LBAudioDetectiveSetMinAmpltitude(LBAudioDetectiveRef inDetective, Float32 inMinAmplitude) {
    inDetective->minAmpltiude = inMinAmplitude;
}

void LBAudioDetectiveSetPitchSteps(LBAudioDetectiveRef inDetective, Float32* inPitchSteps, UInt32 inPitchStepsCount) {
    Float32* pitchSteps = (Float32*)malloc(sizeof(Float32)*inPitchStepsCount);
    for (int i = 0; i < inPitchStepsCount; i++) {
        pitchSteps[i] = inPitchSteps[i];
    }
    
    inDetective->pitchSteps = pitchSteps;
    inDetective->pitchStepsCount = inPitchStepsCount;
}

#pragma mark -
#pragma mark Other Methods

void LBAudioDetectiveProcessAudioURL(LBAudioDetectiveRef inDetective, NSURL* inFileURL) {
    LBAudioDetectiveReset(inDetective);
    
    if (inDetective->inputFile) {
        ExtAudioFileDispose(inDetective->inputFile);
        inDetective->inputFile = NULL;
    }
    
    OSStatus error = ExtAudioFileOpenURL((__bridge CFURLRef)(inFileURL), &inDetective->inputFile);
    LBErrorCheck(error);
    
    error = ExtAudioFileSetProperty(inDetective->inputFile, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &inDetective->processingFormat);
    LBErrorCheck(error);
    
    UInt32 numberFrames = kLBAudioDetectiveWindowSize;
    AudioBufferList bufferList;
    Float32 samples[numberFrames]; // A large enough size to not have to worry about buffer overrun
    memset(&samples, 0, sizeof(samples));
    
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mData = samples;
    bufferList.mBuffers[0].mNumberChannels = inDetective->processingFormat.mChannelsPerFrame;
    bufferList.mBuffers[0].mDataByteSize = numberFrames*AudioStreamBytesPerSample(inDetective->processingFormat);
    
    UInt32 readNumberFrames = numberFrames;
    while (readNumberFrames != 0) {
        error = ExtAudioFileRead(inDetective->inputFile, &readNumberFrames, &bufferList);
        LBErrorCheck(error);
        
        if (readNumberFrames == numberFrames) {
            LBAudioDetectiveAnalyse(inDetective, bufferList.mBuffers[0].mData, readNumberFrames, inDetective->processingFormat);
        }
    }
    
    LBAudioDetectiveClean(inDetective);
}

void LBAudioDetectiveProcess(LBAudioDetectiveRef inDetective, UInt32 inIdentificationUnitCount, LBAudioDetectiveCallback inCallback, id inCallbackHelper) {
    inDetective->maxIdentificationUnitCount = inIdentificationUnitCount;
    inDetective->callback = inCallback;
    inDetective->callbackHelper = inCallbackHelper;
    LBAudioDetectiveStartProcessing(inDetective);
}

void LBAudioDetectiveStartProcessing(LBAudioDetectiveRef inDetective) {
    if (inDetective->graph == NULL || inDetective->rioUnit == NULL) {
        LBAudioDetectiveInitializeGraph(inDetective);
    }
    
    LBAudioDetectiveReset(inDetective);
    
    AUGraphStart(inDetective->graph);
}

void LBAudioDetectiveStopProcessing(LBAudioDetectiveRef inDetective) {
    AUGraphStop(inDetective->graph);
    LBAudioDetectiveClean(inDetective);
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
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)  
    
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
    
#endif
}

void LBAudioDetectiveReset(LBAudioDetectiveRef inDetective) {
    inDetective->identificationUnitCount = 0;
    free(inDetective->identificationUnits);
    inDetective->identificationUnits = NULL;
    free(inDetective->FFT.buffer);
    inDetective->FFT.buffer = (void*)malloc(kLBAudioDetectiveWindowSize*sizeof(SInt16));
    inDetective->FFT.index = 0;
}

void LBAudioDetectiveClean(LBAudioDetectiveRef inDetective) {
    free(inDetective->FFT.buffer);
    inDetective->FFT.buffer = NULL;
    inDetective->FFT.index = 0;
    inDetective->maxIdentificationUnitCount = 0;
    inDetective->callback = NULL;
    inDetective->callbackHelper = nil;
}

OSStatus LBAudioDetectiveMicrophoneOutput(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList* ioData) {
    LBAudioDetective* inDetective = (LBAudioDetective*)inRefCon;
    OSStatus error = noErr;
    
    // Allocate the buffer that holds the data
    AudioBufferList bufferList;
    SInt16 samples[inNumberFrames]; // A large enough size to not have to worry about buffer overrun
    memset(&samples, 0, sizeof(samples));
    
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
    
    LBAudioDetectiveAnalyseIfFrameFull(inDetective, inNumberFrames, bufferList, inDetective->recordingFormat);
    
    return error;
}

void LBAudioDetectiveAnalyseIfFrameFull(LBAudioDetectiveRef inDetective, UInt32 inNumberFrames, AudioBufferList inData, AudioStreamBasicDescription inDataFormat) {
    UInt32 read = kLBAudioDetectiveWindowSize-inDetective->FFT.index;
	if (read > inNumberFrames) {
		memcpy(inDetective->FFT.buffer+inDetective->FFT.index, inData.mBuffers[0].mData, inNumberFrames*AudioStreamBytesPerSample(inDataFormat));
		inDetective->FFT.index += inNumberFrames;
	}
    else {
        memcpy(inDetective->FFT.buffer+inDetective->FFT.index, inData.mBuffers[0].mData, read*AudioStreamBytesPerSample(inDataFormat));
        LBAudioDetectiveAnalyse(inDetective, inDetective->FFT.buffer, inData.mBuffers[0].mDataByteSize/AudioStreamBytesPerSample(inDetective->recordingFormat), inDetective->recordingFormat);
        
        memset(inDetective->FFT.buffer, 0, sizeof(inDetective->FFT.buffer));
        inDetective->FFT.index = 0;
    }
}

void LBAudioDetectiveAnalyse(LBAudioDetectiveRef inDetective, void* inBuffer, UInt32 inNumberFrames, AudioStreamBasicDescription inDataFormat) {
    Float32 outputBuffer[inNumberFrames];
    Boolean converted = LBAudioDetectiveConvertToFormat(inBuffer, inNumberFrames, inDataFormat, inDetective->processingFormat, (float*)outputBuffer);
    if (!converted) {
        memcpy(outputBuffer, inBuffer, inNumberFrames);
    }
    
    /*
     Look at the real signal as an interleaved complex vector by casting it.
     Then call the transformation function vDSP_ctoz to get a split complex
     vector, which for a real signal, divides into an even-odd configuration.
     */
    vDSP_ctoz((COMPLEX*)outputBuffer, 2, &inDetective->FFT.A, 1, inDetective->FFT.nOver2);
    
    // Carry out a Forward FFT transform.
    vDSP_fft_zrip(inDetective->FFT.setup, &inDetective->FFT.A, 1, inDetective->FFT.log2n, FFT_FORWARD);
    
    // The output signal is now in a split real form. Use the vDSP_ztoc to get a split real vector.
    vDSP_ztoc(&inDetective->FFT.A, 1, (COMPLEX *)outputBuffer, 2, inDetective->FFT.nOver2);
    
    // Determine the dominant frequency by taking the magnitude squared and saving the bin which it resides in
    LBAudioDetectiveIdentificationUnit identification = {0};
    memset(&identification, 0, sizeof(LBAudioDetectiveIdentificationUnit));
    
    for (int i = 0; i < inDetective->FFT.n; i += 2) {
        Float32 magnitude = (outputBuffer[i]*outputBuffer[i])+(outputBuffer[i+1]*outputBuffer[i+1]);
        
        if (magnitude >= inDetective->minAmpltiude) {
            UInt32 bin = (i+1)/2;
            Float32 frequency = bin*(inDetective->processingFormat.mSampleRate/inNumberFrames);
            UInt32 idx = LBAudioDetectivePitchRange(inDetective, frequency);
            
            LBAudioDetectiveIdentificationUnitAddFrequency(&identification, frequency, magnitude, idx);
        }
    }
    
    UInt32 unitSize = sizeof(LBAudioDetectiveIdentificationUnit);
    inDetective->identificationUnitCount++;
    inDetective->identificationUnits = (LBAudioDetectiveIdentificationUnit*)realloc(inDetective->identificationUnits, inDetective->identificationUnitCount*unitSize);
    inDetective->identificationUnits[inDetective->identificationUnitCount-1] = identification;
    
    if (inDetective->identificationUnitCount == inDetective->maxIdentificationUnitCount) {
        if (inDetective->callback) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                inDetective->callback(inDetective, inDetective->callbackHelper);
            });
        }
        
        LBAudioDetectiveStopProcessing(inDetective);
    }
}

Boolean LBAudioDetectiveIdentificationUnitAddFrequency(LBAudioDetectiveIdentificationUnit* identification, Float32 frequency, Float32 magnitude, UInt32 index) {
    if ((magnitude > identification->magnitudes[index]) && frequency) {
        identification->magnitudes[index] = magnitude;
        identification->frequencies[index] = frequency;
        
        return TRUE;
    }
    
    return FALSE;
}

#pragma mark -
#pragma mark Utilities

UInt32 LBAudioDetectivePitchRange(LBAudioDetectiveRef inDetective, Float32 pitch) {
    UInt32 count = inDetective->pitchStepsCount;
    for (int i = 0; i < count; i++) {
        if (pitch < inDetective->pitchSteps[i]) {
            return i;
        }
    }
    
    return count;
}

Boolean LBAudioDetectiveConvertToFormat(void* inBuffer, UInt32 inBufferSize, AudioStreamBasicDescription inFromFormat, AudioStreamBasicDescription inToFormat, void* outBuffer) {
    if (inFromFormat.mSampleRate == inToFormat.mSampleRate && inFromFormat.mFormatFlags == inToFormat.mFormatFlags && inFromFormat.mBytesPerFrame == inToFormat.mBytesPerFrame) {
        return FALSE;
    }
    
	UInt32 inSize = inBufferSize*AudioStreamBytesPerSample(inFromFormat);
	UInt32 outSize = inBufferSize*AudioStreamBytesPerSample(inToFormat);
    
    AudioConverterRef converter;
	OSStatus error = AudioConverterNew(&inFromFormat, &inToFormat, &converter);
    LBErrorCheck(error);
    
	error = AudioConverterConvertBuffer(converter, inSize, inBuffer, &outSize, outBuffer);
    LBErrorCheck(error);
    
    error = AudioConverterDispose(converter);
    LBErrorCheck(error);
    
    return TRUE;
}

#pragma mark -
#pragma mark Comparison

UInt32 LBAudioDetectiveCompareAudioURLs(LBAudioDetectiveRef inDetective, NSURL* inFileURL1, NSURL* inFileURL2) {
    LBAudioDetectiveProcessAudioURL(inDetective, inFileURL1);
    
    UInt32 unitCount1;
    LBAudioDetectiveIdentificationUnit* units1 = LBAudioDetectiveGetIdentificationUnits(inDetective, &unitCount1);
    
    LBAudioDetectiveProcessAudioURL(inDetective, inFileURL2);
    
    UInt32 unitCount2;
    LBAudioDetectiveIdentificationUnit* units2 = LBAudioDetectiveGetIdentificationUnits(inDetective, &unitCount2);
    
    return LBAudioDetectiveCompareAudioUnits(units1, unitCount1, units2, unitCount2);
}

UInt32 LBAudioDetectiveCompareAudioUnits(LBAudioDetectiveIdentificationUnit* units1, UInt32 unitCount1, LBAudioDetectiveIdentificationUnit* units2, UInt32 unitCount2) {
    if (!units1 || unitCount1 == 0 || !units2 || unitCount2 == 0) {
        return 0;
    }
    
    NSInteger range = 100;
    NSMutableDictionary* offsetDictionary = [NSMutableDictionary new];
    
    for (UInt32 i1 = 0; i1 < unitCount1; i1++) {
        for (UInt32 i2 = 0; i2 < unitCount2; i2++) {
            NSInteger match0 = fabsf(units1[i1].frequencies[0] - units2[i2].frequencies[0]);
            NSInteger match1 = fabsf(units1[i1].frequencies[1] - units2[i2].frequencies[1]);
            NSInteger match2 = fabsf(units1[i1].frequencies[2] - units2[i2].frequencies[2]);
            NSInteger match3 = fabsf(units1[i1].frequencies[3] - units2[i2].frequencies[3]);
            NSInteger match4 = fabsf(units1[i1].frequencies[4] - units2[i2].frequencies[4]);
            
            if ((match0 + match1 + match2 + match3 + match4) < 400) {
                SInt32 index = i1-i2;
                
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
        }
    }
    
    __block UInt32 matches = 0;
    [offsetDictionary enumerateKeysAndObjectsUsingBlock:^(NSNumber* offset, NSNumber* count, BOOL *stop) {
        if (count.integerValue > 3) {
            matches += count.unsignedIntegerValue;
        }
    }];
    
    return matches;
}

#pragma mark -
