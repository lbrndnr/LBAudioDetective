//
//  LBAudioDetective.h
//  LBAudioDetective
//
//  Created by Laurin Brandner on 21.04.13.
//  Copyright (c) 2013 Laurin Brandner. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
    
#import "LBAudioDetectiveFingerprint.h"

extern const OSStatus kLBAudioDetectiveArgumentInvalid;

extern const UInt32 kLBAudioDetectiveDefaultWindowSize;
extern const UInt32 kLBAudioDetectiveDefaultAnalysisStride;
extern const UInt32 kLBAudioDetectiveDefaultNumberOfPitchSteps;
extern const UInt32 kLBAudioDetectiveDefaultFingerprintComparisonRange;
extern const UInt32 kLBAudioDetectiveDefaultSubfingerprintLength;
    
typedef struct LBAudioDetective *LBAudioDetectiveRef;
    
/**
 LBAudioDetectiveRef is an opaque type that creates a fingerprint from a specific audio file or recording.
 
 Function parameter paradigm:
 in-  a parameter used by the function. It shouldn't have changed when the function is performed.
 io-  a parameter used by the function. It may have changed when the function is performed.
 out- a pointer to a paramter that acts like a return value. Not setting it results in a redundant function call.
*/

#pragma mark (De)Allocation
    
/**
 Creates a LBAudioDetective struct with the default preferences set.
 
 @return A LBAudioDetective struct
*/

LBAudioDetectiveRef LBAudioDetectiveNew();
  
/**
 Deallocates the receiver
 
 @param inDetective The `LBAudioDetectiveRef` that should be deallocated
*/
    
OSStatus LBAudioDetectiveDispose(LBAudioDetectiveRef inDetective);

#pragma mark -
#pragma mark Getters
    
/**
 Returns the default `AudioStreamBasicDescription` for processing. The recording or audio file will be processed using this format if not differently specified.
 @see LBAudioDetectiveGetProcessingSampleRate(LBAudioDetectiveRef)
 @see LBAudioDetectiveSetProcessingSampleRate(LBAudioDetectiveRef, Float64)
     
 @return An `AudioStreamBasicDescription` struct
*/
    
AudioStreamBasicDescription LBAudioDetectiveDefaultProcessingFormat();
    
/**
 Returns the currently set `Float64` sample rate for processing. The recording or audio file will be processed using this format.
 @see LBAudioDetectiveDefaultProcessingFormat()
 @see LBAudioDetectiveSetProcessingSampleRate(LBAudioDetectiveRef, Float64)
 
 @param inDetective The receiving LBAudioDetective struct
     
 @return An `AudioStreamBasicDescription` struct
*/
    
Float64 LBAudioDetectiveGetProcessingSampleRate(LBAudioDetectiveRef inDetective);
    
/**
 Every frequency contained in a window analyzed using the FFT are summed up. The number of pitch steps specifies in how many ranges the pitches are separated and then added.
 @see LBAudioDetectiveSetNumberOfPitchSteps(LBAudioDetectiveRef, UInt32)
 
 @param inDetective The receiving LBAudioDetective struct
     
 @return An `UInt32` representing the number of ranges used to separate the computed pitches
*/
    
UInt32 LBAudioDetectiveGetNumberOfPitchSteps(LBAudioDetectiveRef inDetective);

/**
 The subfingerprint length specifies the number of FFT windows that are gathered into one subfingerprint.
 @see LBAudioDetectivSetSubfingerprintLength(LBAudioDetectiveRef, UInt32)
 
 @param inDetective The receiving LBAudioDetective struct
     
 @return An `UInt32` representing the number of FFT windows used for one subfingerprint
*/
    
UInt32 LBAudioDetectiveGetSubfingerprintLength(LBAudioDetectiveRef inDetective);
    
/**
 The window size represents the number of audio sample frames that are used in one FFT analysis.
 @see LBAudioDetectiveSetWindowSize(LBAudioDetectiveRef, UInt32)
     
 @param inDetective The receiving LBAudioDetective struct
     
 @return An `UInt32` representing the number of audio sample frames that are used for one FFT analysis
*/
    
UInt32 LBAudioDetectiveGetWindowSize(LBAudioDetectiveRef inDetective);
    
/**
 The analysis stride specifies the number of audio sample frames that are iterated until the next FFT analysis. So if the first FFT analysis A1 starts at the index i, A2 will computed on index+analysisStride. The default window size and analysis stride are set in such manner that the FFTs will overlap if not differently specified.
 @see LBAudioDetectiveSetAnalysisStride(LBAudioDetectiveRef, UInt32)
     
 @param inDetective The receiving LBAudioDetective struct
     
 @return An `UInt32` representing the number of audio sample frames between two FFTs
*/
    
UInt32 LBAudioDetectiveGetAnalysisStride(LBAudioDetectiveRef inDetective);
    
/**
 The length of the subfingerprints
 @see LBAudioDetectiveSetSubfingerprintLength(LBAudioDetectiveRef, UInt32)
     
 @param inDetective The receiving LBAudioDetective struct
     
 @return An `UInt32` representing the length of one subfingerprint
*/
    
UInt32 LBAudioDetectiveGetSubfingerprintLength(LBAudioDetectiveRef inDetective);

#pragma mark -
#pragma mark Setters

/**
 Sets an `AudioStreamBasicDescription` for recording. The recording will be saved in this format. The format has to be signed integer and PCM.
 @see LBAudioDetectiveDefaultRecordingFormat()
 @see LBAudioDetectiveGetRecordingSampleRate(LBAudioDetectiveRef)
     
 @param inDetective The receiving LBAudioDetective struct
 @param inStreamFormat The audio format to be used
*/
    
OSStatus LBAudioDetectiveSetRecordingSampleRate(LBAudioDetectiveRef inDetective, Float64 inSampleRate);
    
/**
 Sets an `AudioStreamBasicDescription` for processing. The recording will be processed using this format. The format has to be float and PCM.
 @see LBAudioDetectiveDefaultProcessingFormat()
 @see LBAudioDetectiveGetProcessingSampleRate(LBAudioDetectiveRef)
     
 @param inDetective The receiving LBAudioDetective struct
 @param inStreamFormat The audio format to be used
*/
    
OSStatus LBAudioDetectiveSetProcessingSampleRate(LBAudioDetectiveRef inDetective, Float64 inSampleRate);
    
/**
 Every frequency contained in a window analyzed using the FFT are summed up. The number of pitch steps specifies in how many ranges the pitches are separated and then added.
 @see LBAudioDetectiveGetNumberOfPitchSteps(LBAudioDetectiveRef)
     
 @param inDetective The receiving LBAudioDetective struct
 @param inNumberOfPitchSteps The number of pitch ranges that should be used
*/
    
OSStatus LBAudioDetectiveSetNumberOfPitchSteps(LBAudioDetectiveRef inDetective, UInt32 inNumberOfPitchSteps);
    
/**
 The subfingerprint length specifies the number of FFT windows that are gathered into one subfingerprint.
 @see LBAudioDetectivGetSubfingerprintLength(LBAudioDetectiveRef)
     
 @param inDetective The receiving LBAudioDetective struct
 @param inSubfingerprintLength The number of FFT windows that should be contained in one subfingerprint
*/

OSStatus LBAudioDetectiveSetSubfingerprintLength(LBAudioDetectiveRef inDetective, UInt32 inSubfingerprintLength);
    
/**
 The window size represents the number of audio sample frames that are used in one FFT analysis.
 @see LBAudioDetectiveGetWindowSize(LBAudioDetectiveRef)
     
 @param inDetective The receiving LBAudioDetective struct
 @param inWindowSize The size of the window used for the FFT
*/
    
OSStatus LBAudioDetectiveSetWindowSize(LBAudioDetectiveRef inDetective, UInt32 inWindowSize);
    
/**
 The analysis stride specifies the number of audio sample frames that are iterated until the next FFT analysis. So if the first FFT analysis A1 starts at the index i, A2 will computed on index+analysisStride. The default window size and analysis stride are set in such manner that the FFTs will overlap if not differently specified.
 @see LBAudioDetectiveGetAnalysisStride(LBAudioDetectiveRef)
     
 @param inDetective The receiving LBAudioDetective struct
 @param inAnalysisStride The number of audio sample frames that are skipped between two FFTs
*/
    
OSStatus LBAudioDetectiveSetAnalysisStride(LBAudioDetectiveRef inDetective, UInt32 inAnalysisStride);
    
/**
 The length of the subfingerprints
 @see LBAudioDetectiveSetSubfingerprintLength(LBAudioDetectiveRef, UInt32)
     
 @param inDetective The receiving LBAudioDetective struct
     
 @return An `UInt32` representing the length of one subfingerprint
*/
    
OSStatus LBAudioDetectiveSetSubfingerprintLength(LBAudioDetectiveRef inDetective, UInt32 inSubfingerprintLength);

#pragma mark -
#pragma mark Processing
    
/**
 This function initializes the analysis of an audio file and the synthesis of a fingerprint to the corresponding file.
 @see LBAudioDetectiveGetFingerprint(LBAudioDetectiveRef)
     
 @param inDetective The receiving LBAudioDetective struct
 @param inFileURL A file URL representing the directory to the audio file to be processed
*/

OSStatus LBAudioDetectiveProcessAudioURL(LBAudioDetectiveRef inDetective, NSURL* inFileURL, LBAudioDetectiveFingerprintRef* outFingerprint);

#pragma mark -
#pragma mark Comparison
    
/**
 This function compares two audio files. The fingerprint of `inDetective` will belong to `inFileURL2`.
 @see LBAudioDetectiveGetFingerprint(LBAudioDetectiveRef)
     
 @param inDetective The receiving LBAudioDetective struct
 @param inFileURL1 The first file URL representing the directory to the audio file to be processed
 @param inFileURL2 The second file URL representing the directory to the audio file to be processed
 @param inComparisonRange The range in which the subfingerprints should be compared
 
 @return A `Float32` value between 0.0 and 1.0 which indicates how equal `inFileURL2` is to `inFileURL1`
*/

OSStatus LBAudioDetectiveCompareAudioURLs(LBAudioDetectiveRef inDetective, NSURL* inFileURL1, NSURL* inFileURL2, UInt32 inComparisonRange, Float32* outMatch);

#pragma mark -
