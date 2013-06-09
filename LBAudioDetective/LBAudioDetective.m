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
    Float32 minAmpltiude;
    
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
OSStatus LBAudioDetectiveMicrophoneOutput(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList* ioData);

void LBAudioDetectiveAnalyse(LBAudioDetectiveRef inDetective, UInt32 inNumberFrames, AudioBufferList inData);
Boolean LBAudioDetectiveIdentificationUnitAddFrequency(LBAudioDetectiveIdentificationUnit* identification, Float32 frequency, Float32 magnitude, UInt32 index);

UInt32 LBAudioDetectiveRangeOfFrequency(Float32 frequency);
void LBAudioDetectiveConvertStreamFormatToFloat(void* inBuffer, UInt32 bufferSize, AudioStreamBasicDescription inFormat, float* outBuffer);

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

void LBAudioDetectiveDispose(LBAudioDetectiveRef inDetective) {
    LBAudioDetectiveStopProcessing(inDetective);
    
    AUGraphUninitialize(inDetective->graph);
    AUGraphClose(inDetective->graph);
    
    ExtAudioFileDispose(inDetective->inputFile);
    ExtAudioFileDispose(inDetective->outputFile);
    
    free(inDetective->identificationUnits);
    
    free(inDetective->FFT.A.realp);
    free(inDetective->FFT.A.imagp);
    vDSP_destroy_fftsetup(inDetective->FFT.setup);
    
    free(inDetective);
}

#pragma mark -
#pragma mark Getters

AudioStreamBasicDescription LBAudioDetectiveDefaultFormat() {
    Float64 defaultSampleRate;
    
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
    UInt32 propertySize = sizeof(Float64);
    OSStatus error = AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareSampleRate, &propertySize, &defaultSampleRate);
    LBErrorCheck(error);
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

AudioStreamBasicDescription LBAudioDetectiveGetFormat(LBAudioDetectiveRef inDetective) {
    return inDetective->streamFormat;
}

LBAudioDetectiveIdentificationUnit* LBAudioDetectiveGetIdentificationUnits(LBAudioDetectiveRef inDetective, UInt32* outUnitNumber) {
    *outUnitNumber = inDetective->identificationUnitCount;
    return inDetective->identificationUnits;
}

Float32 LBAudioDetectiveGetMinAmplitude(LBAudioDetectiveRef inDetective) {
    return inDetective->minAmpltiude;
}

#pragma mark -
#pragma mark Setters

void LBAudioDetectiveSetFormat(LBAudioDetectiveRef inDetective, AudioStreamBasicDescription inStreamFormat) {
    inDetective->streamFormat = inStreamFormat;
}

void LBAudioDetectiveSetWriteAudioToURL(LBAudioDetectiveRef inDetective, NSURL* fileURL) {
    OSStatus error = noErr;
    if (fileURL) {
        error =  ExtAudioFileCreateWithURL((__bridge CFURLRef)fileURL, kAudioFileCAFType, &inDetective->streamFormat, NULL, kAudioFileFlags_EraseFile, &inDetective->outputFile);
        LBErrorCheck(error);
        
        error = ExtAudioFileSetProperty(inDetective->outputFile, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &inDetective->streamFormat);
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

#pragma mark -
#pragma mark Other Methods

void LBAudioDetectiveProcessAudioURL(LBAudioDetectiveRef inDetective, NSURL* inFileURL) {
    LBAudioDetectiveReset(inDetective);
    
    OSStatus error = ExtAudioFileOpenURL((__bridge CFURLRef)(inFileURL), &inDetective->inputFile);
    LBErrorCheck(error);
    
    UInt32 numberFrames = kLBAudioDetectiveWindowSize;
    AudioBufferList bufferList;
    SInt16 samples[numberFrames]; // A large enough size to not have to worry about buffer overrun
    memset(&samples, 0, sizeof(samples));
    
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mData = samples;
    bufferList.mBuffers[0].mNumberChannels = inDetective->streamFormat.mChannelsPerFrame;
    bufferList.mBuffers[0].mDataByteSize = numberFrames*sizeof(SInt16);
    
    while (numberFrames != 0) {
        error = ExtAudioFileRead(inDetective->inputFile, &numberFrames, &bufferList);
        LBErrorCheck(error);
        
        LBAudioDetectiveAnalyse(inDetective, numberFrames, bufferList);
    }
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
    
    free(inDetective->FFT.buffer);
    inDetective->FFT.buffer = NULL;
    inDetective->FFT.index = 0;
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
    
    // Enable micorphone input
	error = AudioUnitSetProperty(inDetective->rioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, bus1, &onFlag, propertySize);
    LBErrorCheck(error);
	
    // Disable speakers output
	error = AudioUnitSetProperty(inDetective->rioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, bus0, &offFlag, propertySize);
    LBErrorCheck(error);
    
    // Set the stream format we want
    propertySize = sizeof(AudioStreamBasicDescription);
    error = AudioUnitSetProperty(inDetective->rioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, bus0, &inDetective->streamFormat, propertySize);
    LBErrorCheck(error);
    
    error = AudioUnitSetProperty(inDetective->rioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, bus1, &inDetective->streamFormat, propertySize);
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

void LBAudioDetectiveReset(LBAudioDetectiveRef inDetective) {
    free(inDetective->identificationUnits);
    inDetective->identificationUnits = NULL;
    inDetective->identificationUnitCount = 0;
    free(inDetective->FFT.buffer);
    inDetective->FFT.buffer = (void*)malloc(kLBAudioDetectiveWindowSize*sizeof(SInt16));
    inDetective->FFT.index = 0;
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
    bufferList.mBuffers[0].mNumberChannels = inDetective->streamFormat.mChannelsPerFrame;
    bufferList.mBuffers[0].mDataByteSize = inNumberFrames*sizeof(SInt16);
    
    error = AudioUnitRender(inDetective->rioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, &bufferList);
    LBErrorCheck(error);
    
    if (inDetective->outputFile) {
        error = ExtAudioFileWriteAsync(inDetective->outputFile, inNumberFrames, &bufferList);
        LBErrorCheck(error);
    }
    
    LBAudioDetectiveAnalyse(inDetective, inNumberFrames, bufferList);
    
    return error;
}

void LBAudioDetectiveAnalyse(LBAudioDetectiveRef inDetective, UInt32 inNumberFrames, AudioBufferList inData) {
    // Fill the buffer with our sampled data. If we fill our buffer, run the FFT
	UInt32 read = kLBAudioDetectiveWindowSize-inDetective->FFT.index;
	if (read > inNumberFrames) {
		memcpy((SInt16 *)inDetective->FFT.buffer+inDetective->FFT.index, inData.mBuffers[0].mData, inNumberFrames*sizeof(SInt16));
		inDetective->FFT.index += inNumberFrames;
	}
    else {
		// If we enter this conditional, our buffer will be filled and we should perform the FFT.
		memcpy((SInt16 *)inDetective->FFT.buffer+inDetective->FFT.index, inData.mBuffers[0].mData, read*sizeof(SInt16));
		
		// We want to deal with only floating point values here.
        float outputBuffer[kLBAudioDetectiveWindowSize];
        LBAudioDetectiveConvertStreamFormatToFloat(inDetective->FFT.buffer, kLBAudioDetectiveWindowSize, inDetective->streamFormat, (float*)outputBuffer);
		
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
                Float32 frequency = bin*(inDetective->streamFormat.mSampleRate/kLBAudioDetectiveWindowSize);
                UInt32 idx = LBAudioDetectiveRangeOfFrequency(frequency);
                
                LBAudioDetectiveIdentificationUnitAddFrequency(&identification, frequency, magnitude, idx);
            }
		}
        
        memset(inDetective->FFT.buffer, 0, sizeof(inDetective->FFT.buffer));
        inDetective->FFT.index = 0;
        inDetective->identificationUnitCount++;
        UInt32 unitSize = sizeof(LBAudioDetectiveIdentificationUnit);
        inDetective->identificationUnits = realloc(inDetective->identificationUnits, inDetective->identificationUnitCount*unitSize);
        inDetective->identificationUnits[inDetective->identificationUnitCount-1] = identification;
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

UInt32 LBAudioDetectiveRangeOfFrequency(Float32 frequency) {
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

void LBAudioDetectiveConvertStreamFormatToFloat(void* inBuffer, UInt32 bufferSize, AudioStreamBasicDescription inFormat, float* outBuffer) {
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
