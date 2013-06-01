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

const UInt32 kLBAudioDetectiveWindowSize = 1024; // 1 KB

typedef struct LBAudioDetective {
    AUGraph graph;
    AudioUnit rioUnit;
    
    AudioStreamBasicDescription streamFormat;

    ExtAudioFileRef inputFile;
    ExtAudioFileRef outputFile;
    
    LBAudioDetectiveIdentificationUnit* identificationUnits;
    UInt32 identificationUnitCount;
    
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

void _LBAudioDetectiveInitializeGraph(LBAudioDetectiveRef detective);
void _LBAudioDetectiveReset(LBAudioDetectiveRef detective);
OSStatus _LBAudioDetectiveMicrophoneOutput(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList* ioData);

void _LBAudioDetectiveAnalyse(LBAudioDetectiveRef detective, UInt32 inNumberFrames, AudioBufferList inData);
Boolean _LBAudioDetectiveIdentificationUnitAddFrequency(LBAudioDetectiveIdentificationUnit* identification, Float32 frequency, Float32 magnitude, UInt32 index);

UInt32 _LBAudioDetectiveRangeOfFrequency(Float32 frequency);
void _LBAudioDetectiveConvertStreamFormatToFloat(void* inBuffer, UInt32 bufferSize, AudioStreamBasicDescription inFormat, float* outBuffer);

#pragma mark Utilites

#define LBErrorCheck(error) (_LBErrorCheckOnLine(error, __LINE__))
#define LBAssert(condition) (_LBErrorCheckOnLine(!condition, __LINE__))

static inline void _LBErrorCheckOnLine(OSStatus error, int line) {
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
    
    instance->streamFormat = LBAudioDetectiveDefaultFormat();

    instance->FFT.log2n = log2(kLBAudioDetectiveWindowSize);
    instance->FFT.n = (1 << instance->FFT.log2n);
    LBAssert(instance->FFT.n == kLBAudioDetectiveWindowSize);
    
    instance->FFT.nOver2 = kLBAudioDetectiveWindowSize/2;
	instance->FFT.A.realp = (float *)malloc(instance->FFT.nOver2*sizeof(float));
	instance->FFT.A.imagp = (float *)malloc(instance->FFT.nOver2*sizeof(float));
	instance->FFT.setup = vDSP_create_fftsetup(instance->FFT.log2n, FFT_RADIX2);
    
    return instance;
}

void LBAudioDetectiveDispose(LBAudioDetectiveRef detective) {
    LBAudioDetectiveStopProcessing(detective);
    
    AUGraphUninitialize(detective->graph);
    AUGraphClose(detective->graph);
    
    ExtAudioFileDispose(detective->inputFile);
    ExtAudioFileDispose(detective->outputFile);
    
    free(detective->identificationUnits);
    
    free(detective->FFT.A.realp);
    free(detective->FFT.A.imagp);
    vDSP_destroy_fftsetup(detective->FFT.setup);
    
    free(detective);
}

#pragma mark -
#pragma mark Getters

AudioStreamBasicDescription LBAudioDetectiveDefaultFormat() {
    Float64 defaultSampleRate;
    UInt32 propertySize = sizeof(Float64);
    OSStatus error = AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareSampleRate, &propertySize, &defaultSampleRate);
    LBErrorCheck(error);
    
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

AudioStreamBasicDescription LBAudioDetectiveGetFormat(LBAudioDetectiveRef detective) {
    return detective->streamFormat;
}

LBAudioDetectiveIdentificationUnit* LBAudioDetectiveGetIdentificationUnits(LBAudioDetectiveRef detective, UInt32* outUnitNumber) {
    *outUnitNumber = detective->identificationUnitCount;
    return detective->identificationUnits;
}

#pragma mark -
#pragma mark Setters

void LBAudioDetectiveSetFormat(LBAudioDetectiveRef detective, AudioStreamBasicDescription inStreamFormat) {
    detective->streamFormat = inStreamFormat;
}

void LBAudioDetectiveSetWriteAudioToURL(LBAudioDetectiveRef detective, NSURL* fileURL) {
    OSStatus error = noErr;
    if (fileURL) {
        error =  ExtAudioFileCreateWithURL((__bridge CFURLRef)fileURL, kAudioFileCAFType, &detective->streamFormat, NULL, kAudioFileFlags_EraseFile, &detective->outputFile);
        LBErrorCheck(error);
        
        error = ExtAudioFileSetProperty(detective->outputFile, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &detective->streamFormat);
        LBErrorCheck(error);
        
        error = ExtAudioFileWriteAsync(detective->outputFile, 0, NULL);
        LBErrorCheck(error);
    }
    else {
        error = ExtAudioFileDispose(detective->outputFile);
        LBErrorCheck(error);
        
        detective->outputFile = NULL;
    }
}

#pragma mark -
#pragma mark Other Methods

void LBAudioDetectiveProcessAudioURL(LBAudioDetectiveRef detective, NSURL* inFileURL) {
    _LBAudioDetectiveReset(detective);
    
    OSStatus error = ExtAudioFileOpenURL((__bridge CFURLRef)(inFileURL), &detective->inputFile);
    LBErrorCheck(error);
    
    UInt32 numberFrames = kLBAudioDetectiveWindowSize;
    AudioBufferList bufferList;
    SInt16 samples[numberFrames]; // A large enough size to not have to worry about buffer overrun
    memset(&samples, 0, sizeof(samples));
    
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mData = samples;
    bufferList.mBuffers[0].mNumberChannels = detective->streamFormat.mChannelsPerFrame;
    bufferList.mBuffers[0].mDataByteSize = numberFrames*sizeof(SInt16);
    
    while (numberFrames != 0) {
        error = ExtAudioFileRead(detective->inputFile, &numberFrames, &bufferList);
        LBErrorCheck(error);
        
        _LBAudioDetectiveAnalyse(detective, numberFrames, bufferList);
    }
}

void LBAudioDetectiveStartProcessing(LBAudioDetectiveRef detective) {
    if (detective->graph == NULL || detective->rioUnit == NULL) {
        _LBAudioDetectiveInitializeGraph(detective);
    }
    
    _LBAudioDetectiveReset(detective);
    
    AUGraphStart(detective->graph);
}

void LBAudioDetectiveStopProcessing(LBAudioDetectiveRef detective) {
    AUGraphStop(detective->graph);
    
    free(detective->FFT.buffer);
    detective->FFT.buffer = NULL;
    detective->FFT.index = 0;
}

void LBAudioDetectiveResumeProcessing(LBAudioDetectiveRef detective) {
    LBAudioDetectiveStartProcessing(detective);
}

void LBAudioDetectivePauseProcessing(LBAudioDetectiveRef detective) {
    LBAudioDetectiveStopProcessing(detective);
}

#pragma mark -
#pragma mark Processing

void _LBAudioDetectiveInitializeGraph(LBAudioDetectiveRef detective) {    
    // Create new AUGraph
    OSStatus error = NewAUGraph(&detective->graph);
    LBErrorCheck(error);
    
    // Initialize rioNode (microphone input)
    AudioComponentDescription rioCD = {0};
    rioCD.componentType = kAudioUnitType_Output;
    rioCD.componentSubType = kAudioUnitSubType_RemoteIO;
    rioCD.componentManufacturer = kAudioUnitManufacturer_Apple;
    rioCD.componentFlags = 0;
    rioCD.componentFlagsMask = 0;

    AUNode rioNode;
    error = AUGraphAddNode(detective->graph, &rioCD, &rioNode);
    LBErrorCheck(error);

    // Open the graph so I can modify the audio units
    error = AUGraphOpen(detective->graph);
    LBErrorCheck(error);
    
    // Get initialized rioUnit
    error = AUGraphNodeInfo(detective->graph, rioNode, NULL, &detective->rioUnit);
    LBErrorCheck(error);
    
    // Set properties to rioUnit    
    AudioUnitElement bus0 = 0, bus1 = 1;
    UInt32 onFlag = 1, offFlag = 0;
    UInt32 propertySize = sizeof(UInt32);
    
    // Enable micorphone input
	error = AudioUnitSetProperty(detective->rioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, bus1, &onFlag, propertySize);
    LBErrorCheck(error);
	
    // Disable speakers output
	error = AudioUnitSetProperty(detective->rioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, bus0, &offFlag, propertySize);
    LBErrorCheck(error);
    
    // Set the stream format we want
    propertySize = sizeof(AudioStreamBasicDescription);
    error = AudioUnitSetProperty(detective->rioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, bus0, &detective->streamFormat, propertySize);
    LBErrorCheck(error);
    
    error = AudioUnitSetProperty(detective->rioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, bus1, &detective->streamFormat, propertySize);
    LBErrorCheck(error);
	
    AURenderCallbackStruct callback = {0};
    callback.inputProc = _LBAudioDetectiveMicrophoneOutput;
	callback.inputProcRefCon = detective;
    propertySize = sizeof(AURenderCallbackStruct);
	error = AudioUnitSetProperty(detective->rioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, bus0, &callback, propertySize);
    LBErrorCheck(error);
    
    propertySize = sizeof(UInt32);
    error = AudioUnitSetProperty(detective->rioUnit, kAudioUnitProperty_ShouldAllocateBuffer, kAudioUnitScope_Output, bus1, &offFlag, propertySize);
    LBErrorCheck(error);
    
    // Initialize Graph
    error = AUGraphInitialize(detective->graph);
    LBErrorCheck(error);
}

void _LBAudioDetectiveReset(LBAudioDetectiveRef detective) {
    free(detective->identificationUnits);
    detective->identificationUnits = NULL;
    detective->identificationUnitCount = 0;
    free(detective->FFT.buffer);
    detective->FFT.buffer = (void*)malloc(kLBAudioDetectiveWindowSize*sizeof(SInt16));
    detective->FFT.index = 0;
}

OSStatus _LBAudioDetectiveMicrophoneOutput(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList* ioData) {
    LBAudioDetective* detective = (LBAudioDetective*)inRefCon;
    OSStatus error = noErr;
    
    // Allocate the buffer that holds the data
    AudioBufferList bufferList;
    SInt16 samples[inNumberFrames]; // A large enough size to not have to worry about buffer overrun
    memset(&samples, 0, sizeof(samples));
    
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mData = samples;
    bufferList.mBuffers[0].mNumberChannels = detective->streamFormat.mChannelsPerFrame;
    bufferList.mBuffers[0].mDataByteSize = inNumberFrames*sizeof(SInt16);
    
    error = AudioUnitRender(detective->rioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, &bufferList);
    LBErrorCheck(error);
    
    if (detective->outputFile) {
        error = ExtAudioFileWriteAsync(detective->outputFile, inNumberFrames, &bufferList);
        LBErrorCheck(error);
    }
    
    _LBAudioDetectiveAnalyse(detective, inNumberFrames, bufferList);
    
    return error;
}

void _LBAudioDetectiveAnalyse(LBAudioDetectiveRef detective, UInt32 inNumberFrames, AudioBufferList inData) {
    // Fill the buffer with our sampled data. If we fill our buffer, run the FFT
	UInt32 read = kLBAudioDetectiveWindowSize-detective->FFT.index;
	if (read > inNumberFrames) {
		memcpy((SInt16 *)detective->FFT.buffer+detective->FFT.index, inData.mBuffers[0].mData, inNumberFrames*sizeof(SInt16));
		detective->FFT.index += inNumberFrames;
	}
    else {
		// If we enter this conditional, our buffer will be filled and we should perform the FFT.
		memcpy((SInt16 *)detective->FFT.buffer+detective->FFT.index, inData.mBuffers[0].mData, read*sizeof(SInt16));
		
		/*************** FFT ***************/
		// We want to deal with only floating point values here.
        
        float outputBuffer[kLBAudioDetectiveWindowSize];
        _LBAudioDetectiveConvertStreamFormatToFloat(detective->FFT.buffer, kLBAudioDetectiveWindowSize, detective->streamFormat, (float*)outputBuffer);
		
		/**
		 Look at the real signal as an interleaved complex vector by casting it.
		 Then call the transformation function vDSP_ctoz to get a split complex
		 vector, which for a real signal, divides into an even-odd configuration.
		 */
		vDSP_ctoz((COMPLEX*)outputBuffer, 2, &detective->FFT.A, 1, detective->FFT.nOver2);
		
		// Carry out a Forward FFT transform.
		vDSP_fft_zrip(detective->FFT.setup, &detective->FFT.A, 1, detective->FFT.log2n, FFT_FORWARD);
		
		// The output signal is now in a split real form. Use the vDSP_ztoc to get
		// a split real vector.
		vDSP_ztoc(&detective->FFT.A, 1, (COMPLEX *)outputBuffer, 2, detective->FFT.nOver2);
		
		// Determine the dominant frequency by taking the magnitude squared and saving the bin which it resides in
        
        LBAudioDetectiveIdentificationUnit identification = {0};
        memset(&identification, 0, sizeof(LBAudioDetectiveIdentificationUnit));
        
		for (int i = 0; i < detective->FFT.n; i += 2) {
			Float32 magnitude = (outputBuffer[i]*outputBuffer[i])+(outputBuffer[i+1]*outputBuffer[i+1]);
            UInt32 bin = (i+1)/2;
            Float32 frequency = bin*(detective->streamFormat.mSampleRate/kLBAudioDetectiveWindowSize);
            UInt32 idx = _LBAudioDetectiveRangeOfFrequency(frequency);
            
            _LBAudioDetectiveIdentificationUnitAddFrequency(&identification, frequency, magnitude, idx);
		}
        
        memset(detective->FFT.buffer, 0, sizeof(detective->FFT.buffer));
        detective->FFT.index = 0;
        detective->identificationUnitCount++;
        UInt32 unitSize = sizeof(LBAudioDetectiveIdentificationUnit);
        detective->identificationUnits = realloc(detective->identificationUnits, detective->identificationUnitCount*unitSize);
        detective->identificationUnits[detective->identificationUnitCount-1] = identification;
	}
}

Boolean _LBAudioDetectiveIdentificationUnitAddFrequency(LBAudioDetectiveIdentificationUnit* identification, Float32 frequency, Float32 magnitude, UInt32 index) {
    if ((magnitude > identification->magnitudes[index]) && frequency) {
        identification->magnitudes[index] = magnitude;
        identification->frequencies[index] = frequency;
        
        return TRUE;
    }
    
    return FALSE;
}

#pragma mark -
#pragma mark Utilities

UInt32 _LBAudioDetectiveRangeOfFrequency(Float32 frequency) {
    if (frequency < 40.0f) {
        return 0;
    }
    else if (frequency < 80.0f) {
        return 1;
    }
    else if (frequency < 120.0f) {
        return 2;
    }
    else if (frequency < 180.0f) {
        return 3;
    }
    
    return 4;
}

void _LBAudioDetectiveConvertStreamFormatToFloat(void* inBuffer, UInt32 bufferSize, AudioStreamBasicDescription inFormat, float* outBuffer) {
	UInt32 bytesPerSample = sizeof(float);
    
	AudioStreamBasicDescription asbd = {0};
    memset(&asbd, 0, sizeof(AudioStreamBasicDescription));
	asbd.mFormatID = kAudioFormatLinearPCM;
	asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
	asbd.mBitsPerChannel = 8*bytesPerSample;
	asbd.mFramesPerPacket = 1;
	asbd.mChannelsPerFrame = 1;
	asbd.mBytesPerPacket = bytesPerSample*asbd.mFramesPerPacket;
	asbd.mBytesPerFrame = bytesPerSample*asbd.mChannelsPerFrame;
	asbd.mSampleRate = inFormat.mSampleRate;
	
	UInt32 inSize = bufferSize*sizeof(SInt16);
	UInt32 outSize = bufferSize*sizeof(float);
    
    AudioConverterRef converter;
	OSStatus error = AudioConverterNew(&inFormat, &asbd, &converter);
    LBErrorCheck(error);
    
	error = AudioConverterConvertBuffer(converter, inSize, inBuffer, &outSize, outBuffer);
    LBErrorCheck(error);
    
    error = AudioConverterDispose(converter);
    LBErrorCheck(error);
}

#pragma mark -
