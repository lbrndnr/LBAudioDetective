//
//  LBAudioDetectiveFrame.h
//  LBAudioDetective
//
//  Created by Laurin Brandner on 28.08.13.
//  Copyright (c) 2013 Laurin Brandner. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef struct LBAudioDetectiveFrame *LBAudioDetectiveFrameRef;

/**
 LBAudioDetectiveFrameRef is an internal type used by LBAudioDetective to handle the FFT.
*/

#pragma mark (De)Allocation

/**
 Creates a LBAudioDetectiveFrame struct.
 
 @param inRowCount The number of rows
 
 @return A LBAudioDetectiveFrame struct
*/

LBAudioDetectiveFrameRef LBAudioDetectiveFrameNew(UInt32 inMaxRowCount);

/**
 Deallocates the receiver.
 
 @param inFrame The `LBAudioDetectiveFrameRef` that should be deallocated
*/

void LBAudioDetectiveFrameDispose(LBAudioDetectiveFrameRef inFrame);

/**
 Creates a copy of a given `LBAudioDetectiveFrameRef`.
 
 @param inFrame The `LBAudioDetectiveFrameRef` to be copied
 
 @return A LBAudioDetectiveFrame struct
*/

LBAudioDetectiveFrameRef LBAudioDetectiveFrameCopy(LBAudioDetectiveFrameRef inFrame);

#pragma mark -
#pragma mark Getters

/**
 Returns the current number of rows.
 @see LBAudioDetectiveFrameSetNumberOfRows(LBAudioDetectiveFrameRef, UInt32)
 
 @param inFrame The receiving LBAudioDetectiveFrame struct
 
 @return An `UInt32` indicating the number of rows
*/

UInt32 LBAudioDetectiveFrameGetNumberOfRows(LBAudioDetectiveFrameRef inFrame);

/**
 Returns a specific row.
 @see LBAudioDetectiveFrameSetRow(LBAudioDetectiveFrameRef, Float32*, UInt32, UInt32)
 
 @param inFrame The receiving LBAudioDetectiveFrame struct
 @param inRowIndex The index of the demanded row
 
 @return A `Float32 array representing the row
*/

Float32* LBAudioDetectiveFrameGetRow(LBAudioDetectiveFrameRef inFrame, UInt32 inRowIndex);

/**
 Returns a specific value in a given row at a given index.
 
 @param inFrame The receiving LBAudioDetectiveFrame struct
 @param inRowIndex The index of the demanded row
 @param inColumnIndex The index of in demanded row
 
 @return A `Float32` representing the value
*/

Float32 LBAudioDetectiveFrameGetValue(LBAudioDetectiveFrameRef inFrame, UInt32 inRowIndex, UInt32 inColumnIndex);

/**
 Returns a `Boolean` flag indicating if the receiver is full
 
 @param inFrame The receiving LBAudioDetectiveFrame struct
 
 @return A `Boolean`
 */

Boolean LBAudioDetectiveFrameFull(LBAudioDetectiveFrameRef inFrame);

#pragma mark -
#pragma mark Setters

/**
 Sets a row at a given index.
 @see LBAudioDetectiveFrameGetRow(LBAudioDetectiveFrameRef, UInt32)
 
 @param inFrame The receiving LBAudioDetectiveFrame struct
 @param inRow The `Float32` array with a length of `inCount`
 @param inRowIndex The index of the new row
 @param inCount The length of `inRow`
 
 @return A `Boolean` representing the success of the invocation
*/

Boolean LBAudioDetectiveFrameSetRow(LBAudioDetectiveFrameRef inFrame, Float32* inRow, UInt32 inRowIndex, UInt32 inCount);

#pragma mark -
#pragma mark Other Methods

/**
 Applies a Haar-Wavelet Transform to the `LBAudioDetectiveFrameRef`.
 
 @param inFrame The receiving LBAudioDetectiveFrame struct
*/

void LBAudioDetectiveFrameDecompose(LBAudioDetectiveFrameRef inFrame);

/**
 Computes the size of the fingerprint at the current state.
 
 @param inFrame The receiving LBAudioDetectiveFrame struct
 
 @return A `size_t` value representing the size of the resulting fingerprint
*/

size_t LBAudioDetectiveFrameFingerprintSize(LBAudioDetectiveFrameRef inFrame);

/**
 Computes the length of the fingerprint at the current state.
 
 @param inFrame The receiving LBAudioDetectiveFrame struct
 
 @return A `UInt32` value representing the length of the resulting fingerprint
*/

UInt32 LBAudioDetectiveFrameFingerprintLength(LBAudioDetectiveFrameRef inFrame);

/**
 Extracts the fingerprint at the current state. The wavelets will first be ordered according to their magnitude.
 
 @param inFrame The receiving LBAudioDetectiveFrame struct
 @param inNumberOfWavelets The number of flags that will be taken into account
 @param outFingerprint An array of `Boolean`s at a given length representing a fingerprint for this `LBAudioDetectiveFrameRef`
*/

void LBAudioDetectiveFrameExtractFingerprint(LBAudioDetectiveFrameRef inFrame, UInt32 inNumberOfWavelets, Boolean* outFingerprint);

/**
 Compares two frames on their equality.
 
 @param inFrame1 The first `LBAudioDetectiveFrameRef`
 @param inFrame2 The second `LBAudioDetectiveFrameRef`
 
 @return A `Boolean` indicating `TRUE` if the given `LBAudioDetectiveFrameRef`s are equal.
*/

Boolean LBAudioDetectiveFrameEqualToFrame(LBAudioDetectiveFrameRef inFrame1, LBAudioDetectiveFrameRef inFrame2);

#pragma mark -