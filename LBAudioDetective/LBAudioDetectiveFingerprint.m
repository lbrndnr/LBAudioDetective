//
//  LBAudioDetectiveFingerprint.m
//  LBAudioDetective
//
//  Created by Laurin Brandner on 30.08.13.
//  Copyright (c) 2013 Laurin Brandner. All rights reserved.
//

#import "LBAudioDetectiveFingerprint.h"
typedef struct LBAudioDetectiveFingerprint {
    Boolean** subfingerprints;
    UInt32 subfingerprintLength;
    UInt32 subfingerprintCount;
} LBAudioDetectiveFingerprint;

#pragma mark (De)Allocation

LBAudioDetectiveFingerprintRef LBAudioDetectiveFingerprintNew(UInt32 inSubfingerprintLength) {
    size_t size = sizeof(LBAudioDetectiveFingerprint);
    LBAudioDetectiveFingerprint* instance = malloc(size);
    memset(instance, 0, size);
    
    instance->subfingerprintLength = inSubfingerprintLength;
    
    return instance;
}

void LBAudioDetectiveFingerprintDispose(LBAudioDetectiveFingerprintRef inFingerprint) {
    if (inFingerprint == NULL) {
        return;
    }
    
    for (UInt32 i = 0; i < inFingerprint->subfingerprintCount; i++) {
        free(inFingerprint->subfingerprints[i]);
    }
    
    free(inFingerprint->subfingerprints);
    free(inFingerprint);
}

LBAudioDetectiveFingerprintRef LBAudioDetectiveFingerprintCopy(LBAudioDetectiveFingerprintRef inFingerprint) {
    size_t size = sizeof(LBAudioDetectiveFingerprint);
    LBAudioDetectiveFingerprint* instance = malloc(size);
    memset(instance, 0, size);
    
    instance->subfingerprintLength = inFingerprint->subfingerprintLength;
    instance->subfingerprintCount = inFingerprint->subfingerprintCount;
    instance->subfingerprints = (Boolean**)calloc(instance->subfingerprintCount, sizeof(Boolean*));
    
    size = sizeof(Boolean)*instance->subfingerprintLength;
    for (UInt32 i = 0; i < instance->subfingerprintCount; i++) {
        Boolean* subfingerprint = (Boolean*)calloc(instance->subfingerprintLength, sizeof(Boolean));
        memcpy(subfingerprint, inFingerprint->subfingerprints[i], size);
        
        instance->subfingerprints[i] = subfingerprint;
    }
    
    return instance;
}

#pragma mark -
#pragma mark Getters

UInt32 LBAudioDetectiveFingerprintGetSubfingerprintLength(LBAudioDetectiveFingerprintRef inFingerprint) {
    return inFingerprint->subfingerprintLength;
}

UInt32 LBAudioDetectiveFingerprintGetNumberOfSubfingerprints(LBAudioDetectiveFingerprintRef inFingerprint) {
    return inFingerprint->subfingerprintCount;
}

UInt32 LBAudioDetectiveFingerprintGetSubfingerprintAtIndex(LBAudioDetectiveFingerprintRef inFingerprint, UInt32 inIndex, Boolean* outSubfingerprint) {
    memcpy(outSubfingerprint, inFingerprint->subfingerprints[inIndex], inFingerprint->subfingerprintLength*sizeof(Boolean));
    
    return inFingerprint->subfingerprintLength;
}

#pragma mark -
#pragma mark Setters

Boolean LBAudioDetectiveFingerprintSetSubfingerprintLength(LBAudioDetectiveFingerprintRef inFingerprint, UInt32* ioSubfingerprintLength) {
    if (inFingerprint->subfingerprintCount > 0) {
        *ioSubfingerprintLength = inFingerprint->subfingerprintLength;
        return FALSE;
    }
    
    inFingerprint->subfingerprintLength = *ioSubfingerprintLength;
    return TRUE;
}

void LBAudioDetectiveFingerprintAddSubfingerprint(LBAudioDetectiveFingerprintRef inFingerprint, Boolean* inSubfingerprint) {
    size_t size = sizeof(Boolean)*inFingerprint->subfingerprintLength;
    Boolean* newSubfingerprint = (Boolean*)calloc(inFingerprint->subfingerprintLength, sizeof(Boolean));
    memcpy(newSubfingerprint, inSubfingerprint, size);
    
    inFingerprint->subfingerprintCount++;
    size = sizeof(Boolean*)*inFingerprint->subfingerprintCount;
    inFingerprint->subfingerprints = (Boolean**)realloc(inFingerprint->subfingerprints, size);
    inFingerprint->subfingerprints[inFingerprint->subfingerprintCount-1] = newSubfingerprint;
}

#pragma mark -
#pragma mark Other Methods

Boolean LBAudioDetectiveFingerprintEqualToFingerprint(LBAudioDetectiveFingerprintRef inFingerprint1, LBAudioDetectiveFingerprintRef inFingerprint2) {
    if (inFingerprint1->subfingerprintCount != inFingerprint2->subfingerprintCount || inFingerprint1->subfingerprintLength != inFingerprint2->subfingerprintLength) {
        return FALSE;
    }
    
    for (UInt32 i = 0; i < inFingerprint1->subfingerprintCount; i++) {
        if (memcmp(inFingerprint1->subfingerprints[i], inFingerprint2->subfingerprints[i], sizeof(Boolean)*inFingerprint1->subfingerprintLength) != 0) {
            return FALSE;
        }
    }
    
    return TRUE;
}

Float32 LBAudioDetectiveFingerprintCompareToFingerprint(LBAudioDetectiveFingerprintRef inFingerprint1, LBAudioDetectiveFingerprintRef inFingerprint2, UInt32 inRange) {
    UInt32 subfingerprintCount1 = inFingerprint1->subfingerprintCount;
    UInt32 subfingerprintCount2 = inFingerprint2->subfingerprintCount;
    
    if (inFingerprint1->subfingerprintCount < inFingerprint2->subfingerprintCount) {
        LBAudioDetectiveFingerprintRef tmpFingerprint = inFingerprint1;
        inFingerprint1 = inFingerprint2;
        inFingerprint2 = tmpFingerprint;
        
        UInt32 tmpSubfingerprintCount = subfingerprintCount1;
        subfingerprintCount1 = subfingerprintCount2;
        subfingerprintCount2 = tmpSubfingerprintCount;
    }
    
    Float32 match = 0.0f;
    UInt32 offset = 0;
    
    while (offset <= subfingerprintCount1-subfingerprintCount2) {
        Float32 matchesSum = 0.0f;
        
        for (UInt32 i = 0; i < subfingerprintCount2; i++) {
            Float32 currentMatch = LBAudioDetectiveFingerprintCompareSubfingerprints(inFingerprint1, inFingerprint1->subfingerprints[i+offset], inFingerprint2->subfingerprints[i], inRange);
            matchesSum += currentMatch;
        }
        
        match = MAX(match, matchesSum/(Float32)subfingerprintCount2);
        offset++;
    }
    
    return match;
}

Float32 LBAudioDetectiveFingerprintCompareSubfingerprints(LBAudioDetectiveFingerprintRef inFingerprint, Boolean* inSubfingerprint1, Boolean* inSubfingerprint2, UInt32 inRange) {
    UInt32 possibleHits = 0;
    UInt32 hits = 0;
    
    for (UInt32 i = 0; i < MIN(inRange, inFingerprint->subfingerprintLength); i += 2) {
        Boolean sf1s1 = inSubfingerprint1[i];
        Boolean sf1s2 = inSubfingerprint1[i+1];
        
        if (sf1s1 || sf1s2) {
            possibleHits++;
            
            Boolean sf2s1 = inSubfingerprint2[i];
            Boolean sf2s2 = inSubfingerprint2[i+1];
            
            if ((sf1s1 == sf2s1) && (sf1s2 == sf2s2)) {
                hits++;
            }
        }
    }
    
    if (possibleHits <= 0) {
        return 0.0f;
    }
    
    return (Float32)hits/(Float32)possibleHits;
}

#pragma mark -
