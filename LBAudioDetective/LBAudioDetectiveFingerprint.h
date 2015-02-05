//
//  LBAudioDetectiveFingerprint.h
//  LBAudioDetective
//
//  Created by Laurin Brandner on 30.08.13.
//  Copyright (c) 2013 Laurin Brandner. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef struct LBAudioDetectiveFingerprint *LBAudioDetectiveFingerprintRef;

/**
 LBAudioDetectiveFingerprintRef is an opaque type reprensenting the final product of `LBAudioDetective`'s analysis. It consists of multiple subfingerprints which are made out of one `LBAudioDetectiveFrame`.
 */

#pragma mark (De)Allocation

/**
 Creates a LBAudioDetectiveFingerprint struct.
 
 @param inSubfingerprintLength The length of the subfingerprints
 
 @return A LBAudioDetectiveFingerprint struct
*/

LBAudioDetectiveFingerprintRef LBAudioDetectiveFingerprintNew(UInt32 inSubfingerprintLength);

/**
 Deallocates the receiver.
 
 @param inFingerprint The `LBAudioDetectiveFingerprintRef` that should be deallocated
*/

void LBAudioDetectiveFingerprintDispose(LBAudioDetectiveFingerprintRef inFingerprint);

/**
 Creates a copy of a given `LBAudioDetectiveFingerprintRef`.
 
 @param inFingerprint The `LBAudioDetectiveFingerprintRef` to be copied
 
 @return A LBAudioDetectiveFingerprint struct
*/

LBAudioDetectiveFingerprintRef LBAudioDetectiveFingerprintCopy(LBAudioDetectiveFingerprintRef inFingerprint);

#pragma mark -
#pragma mark Getters

/**
 Returns the length of the subfingerprints
 @see LBAudioDetectiveFingerprintSetSubfingerprintLength(LBAudioDetectiveFingerprintRef, UInt32*)
 
 @param inFingerprint The receiving LBAudioDetectiveFingerprint struct
 
 @return An `UInt32` indicating the length of the subfingerprints
*/

UInt32 LBAudioDetectiveFingerprintGetSubfingerprintLength(LBAudioDetectiveFingerprintRef inFingerprint);

/**
 Returns the current number of subfingerprints contained by the `LBAudioDetectiveFingerprint`
 @see LBAudioDetectiveFingerprintAddSubfingerprint(LBAudioDetectiveFingerprintRef, Boolean*)
 
 @param inFingerprint The receiving LBAudioDetectiveFingerprint struct
 
 @return An `UInt32` indicating the current number of subfingerprints
*/

UInt32 LBAudioDetectiveFingerprintGetNumberOfSubfingerprints(LBAudioDetectiveFingerprintRef inFingerprint);

/**
 Retrieves the demanded subfingerprint at the given index
 @see LBAudioDetectiveFingerprintAddSubfingerprint(LBAudioDetectiveFingerprintRef, Boolean*)
 
 @param inFingerprint The receiving LBAudioDetectiveFingerprint struct
 @param inIndex The index of the subfingerprint
 @param outSubfingerprint A `Boolean` array that is filled up with the subfingerprint
 
 @return An `UInt32` indicating the length of the subfingerprints
 */

UInt32 LBAudioDetectiveFingerprintGetSubfingerprintAtIndex(LBAudioDetectiveFingerprintRef inFingerprint, UInt32 inIndex, Boolean* outSubfingerprint);

#pragma mark -
#pragma mark Setters

/**
 Tries to set the subfingerprint length. This is only possible if no subfingerprints have been set before.
 @see LBAudioDetectiveFingerprintGetSubfingerprintLength(LBAudioDetectiveFingerprintRef)
 
 @param inFingerprint The receiving LBAudioDetectiveFingerprint struct
 @param ioSubfingerprintLength A pointer to the new length of the subfingerprints. It will be changed if the function was successful
 
 @return A `Boolean` indicating whether the new subfingerprint length could be set.
*/

Boolean LBAudioDetectiveFingerprintSetSubfingerprintLength(LBAudioDetectiveFingerprintRef inFingerprint, UInt32* ioSubfingerprintLength);

/**
 Adds a subfingerprint.
 @see LBAudioDetectiveFingerprintGetNumberOfSubfingerprints(LBAudioDetectiveFingerprintRef)
 
 @param inFingerprint The receiving LBAudioDetectiveFingerprint struct
 @param inSubfingerprint An array of `Boolean`s representing the subfingerprint
*/

void LBAudioDetectiveFingerprintAddSubfingerprint(LBAudioDetectiveFingerprintRef inFingerprint, Boolean* inSubfingerprint);

#pragma mark -
#pragma mark Other Methods

/**
 Compares two fingerprints on their equality.
 
 @param inFingerprint1 The first `LBAudioDetectiveFingerprintRef`
 @param inFingerprint2 The second `LBAudioDetectiveFingerprintRef`
 
 @return A `Boolean` indicating `TRUE` if the given `LBAudioDetectiveFingerprintRef`s are equal.
*/

Boolean LBAudioDetectiveFingerprintEqualToFingerprint(LBAudioDetectiveFingerprintRef inFingerprint1, LBAudioDetectiveFingerprintRef inFingerprint2);

/**
 This function compares two fingerprints.
 
 @param inFingerprint1 The first `LBAudioDetectiveFingerprintRef`
 @param inFingerprint2 The second `LBAudioDetectiveFingerprintRef`
 @param inRange The number of `Boolean`s that should be compared in a subfingerprint
 
 @return A `Float32` value between 0.0 and 1.0 which indicates how equal `inFingerprint2` is to `inFingerprint1`
*/

Float32 LBAudioDetectiveFingerprintCompareToFingerprint(LBAudioDetectiveFingerprintRef inFingerprint1, LBAudioDetectiveFingerprintRef inFingerprint2, UInt32 inRange);

/**
 This function compares two subfingerprints.
 
 @param inFingerprint The `LBAudioDetectiveFingerprintRef` which holds `inSubfingerprint1`
 @param inSubfingerprint1 The first `Boolean` array representing a subfingerprint
 @param inSubfingerprint2 The second `Boolean` array representing a subfingerprint
 @param inRange The number of `Boolean`s that should be taken into account during comparison
 
 @return A `Float32` value between 0.0 and 1.0 which indicates how equal `inSubfingerprint2` is to `inSubfingerprint1`
*/

Float32 LBAudioDetectiveFingerprintCompareSubfingerprints(LBAudioDetectiveFingerprintRef inFingerprint, Boolean* inSubfingerprint1, Boolean* inSubfingerprint2, UInt32 inRange);

#pragma mark -
