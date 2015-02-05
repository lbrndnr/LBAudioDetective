//
//  LBAudioDetectiveFrame.m
//  LBAudioDetective
//
//  Created by Laurin Brandner on 28.08.13.
//  Copyright (c) 2013 Laurin Brandner. All rights reserved.
//

#import "LBAudioDetectiveFrame.h"

typedef struct LBAudioDetectiveFrame {
    Float32** rows;
    UInt32 maxNumberOfRows;
    UInt32 numberOfRows;
    UInt32 rowLength;
} LBAudioDetectiveFrame;

void LBAudioDetectiveFrameDecomposeArray(Float32** ioArray, UInt32 inCount);

#pragma mark (De)Allocation

LBAudioDetectiveFrameRef LBAudioDetectiveFrameNew(UInt32 inMaxRowCount) {
    size_t size = sizeof(LBAudioDetectiveFrame);
    LBAudioDetectiveFrame* instance = malloc(size);
    memset(instance, 0, size);
    
    instance->rows = calloc(inMaxRowCount, sizeof(Float32*));
    instance->maxNumberOfRows = inMaxRowCount;
    
    return instance;
}

void LBAudioDetectiveFrameDispose(LBAudioDetectiveFrameRef inFrame) {
    if (inFrame == NULL) {
        return;
    }
    
    for (UInt32 i = 0; i < inFrame->numberOfRows; i++) {
        free(inFrame->rows[i]);
    }
    
    free(inFrame->rows);
    free(inFrame);
}

LBAudioDetectiveFrameRef LBAudioDetectiveFrameCopy(LBAudioDetectiveFrameRef inFrame) {
    LBAudioDetectiveFrame* instance = (LBAudioDetectiveFrame*)calloc(1, sizeof(LBAudioDetectiveFrame));
    
    instance->maxNumberOfRows = inFrame->maxNumberOfRows;
    instance->numberOfRows = inFrame->numberOfRows;
    instance->rowLength = inFrame->rowLength;
    instance->rows = calloc(inFrame->maxNumberOfRows, sizeof(Float32*));
    
    size_t rowSize = sizeof(Float32)*instance->rowLength;
    for (UInt32 i = 0; i < inFrame->numberOfRows; i++) {
        Float32* row = malloc(rowSize);
        memcpy(row, inFrame->rows[i], rowSize);
        instance->rows[i] = row;
    }
    
    return instance;
}

#pragma mark -
#pragma mark Getters

UInt32 LBAudioDetectiveFrameGetNumberOfRows(LBAudioDetectiveFrameRef inFrame) {
    return inFrame->numberOfRows;
}

Float32* LBAudioDetectiveFrameGetRow(LBAudioDetectiveFrameRef inFrame, UInt32 inRowIndex) {
    return inFrame->rows[inRowIndex];
}

Float32 LBAudioDetectiveFrameGetValue(LBAudioDetectiveFrameRef inFrame, UInt32 inRowIndex, UInt32 inColumnIndex) {
    return inFrame->rows[inRowIndex][inColumnIndex];
}

Boolean LBAudioDetectiveFrameFull(LBAudioDetectiveFrameRef inFrame) {
    return (inFrame->numberOfRows >= inFrame->maxNumberOfRows);
}

#pragma mark -
#pragma mark Setters

Boolean LBAudioDetectiveFrameSetRow(LBAudioDetectiveFrameRef inFrame, Float32* inRow, UInt32 inRowIndex, UInt32 inCount) {
    if (LBAudioDetectiveFrameFull(inFrame)) {
        return FALSE;
    }
    
    size_t size = sizeof(Float32)*inCount;
    Float32* newRow = (Float32*)calloc(inCount, sizeof(Float32));
    memcpy(newRow, inRow, size);
    
    inFrame->rows[inRowIndex] = newRow;
    if (inFrame->rowLength == 0) {
        inFrame->rowLength = inCount;
    }
    else {
        inFrame->rowLength = MIN(inFrame->rowLength, inCount);
    }
    
    inFrame->numberOfRows++;
    return TRUE;
}

#pragma mark -
#pragma mark Other Methods

// Haar Wavlet Decomposition Code from http://www.codeproject.com/Articles/206507/Duplicates-detector-via-audio-fingerprinting
// Decomposes the frame with the haar wavelet transform

void LBAudioDetectiveFrameDecompose(LBAudioDetectiveFrameRef inFrame) {
    for (UInt32 row = 0; row < inFrame->numberOfRows; row++) {
        LBAudioDetectiveFrameDecomposeArray(&inFrame->rows[row], inFrame->rowLength);
    }
    
    for (UInt32 col = 0; col < inFrame->rowLength; col++) {
        Float32 column[inFrame->numberOfRows];

        for (UInt32 row = 0; row < inFrame->numberOfRows; row++) {
            column[row] = inFrame->rows[row][col];
        }
        
        Float32* columnPointer = (Float32*)&column;
        LBAudioDetectiveFrameDecomposeArray(&columnPointer, inFrame->numberOfRows);
        
        for (UInt32 row = 0; row < inFrame->numberOfRows; row++) {
            inFrame->rows[row][col] = column[row];
        }
    }
}

void LBAudioDetectiveFrameDecomposeArray(Float32** ioArray, UInt32 inCount) {
    Float32* array = *ioArray;
    
    for (UInt32 i = 0; i < inCount; i++) {
        array[i] /= sqrtf(inCount);
    }
    
    Float32 tmp[inCount];
    
    while (inCount > 1) {
        inCount /= 2;
        for (UInt32 i = 0; i < inCount; i++) {
            tmp[i] = ((array[2 * i] + array[2 * i + 1]) / sqrtf(2.0f));
            tmp[inCount + i] = ((array[2 * i] - array[2 * i + 1]) / sqrtf(2.0f));
        }
        for (UInt32 i = 0; i < 2*inCount; i++) {
            array[i] = tmp[i];
        }
    }
}

size_t LBAudioDetectiveFrameFingerprintSize(LBAudioDetectiveFrameRef inFrame) {
    return inFrame->numberOfRows*inFrame->rowLength*2*sizeof(Boolean);
}

UInt32 LBAudioDetectiveFrameFingerprintLength(LBAudioDetectiveFrameRef inFrame) {
    return inFrame->numberOfRows*inFrame->rowLength*2;
}

// Creates a subfingerprint, an array of booleans, of the receiving frame

void LBAudioDetectiveFrameExtractFingerprint(LBAudioDetectiveFrameRef inFrame, UInt32 inNumberOfWavelets, Boolean* outFingerprint) {
    // USe NSMutableArray to easily sort the data according to their absolute values
    
    NSMutableArray* array = [NSMutableArray arrayWithCapacity:inFrame->numberOfRows*inFrame->rowLength];
    
    for (UInt32 row = 0; row < inFrame->numberOfRows; row++) {
        for (UInt32 column = 0; column < inFrame->rowLength; column++) {
            array[row*inFrame->rowLength+column] = @(inFrame->rows[row][column]);
        }
    }
    
    [array sortUsingComparator:^NSComparisonResult(NSNumber* obj1, NSNumber* obj2) {
        return [@(fabs(obj2.doubleValue)) compare:@(fabs(obj1.doubleValue))];
    }];
    
    // Create the boolean array and store the signs of the top 200 values in it
    
    for (UInt32 i = 0; i < inNumberOfWavelets; i++) {
        Float64 value = ((NSNumber*)array[i]).doubleValue;
        if (value > 0.0) {
            outFingerprint[2*i] = TRUE;
        }
        else if (value < 0.0) {
            outFingerprint[(2*i)+1] = TRUE;
        }
    }
}

Boolean LBAudioDetectiveFrameEqualToFrame(LBAudioDetectiveFrameRef inFrame1, LBAudioDetectiveFrameRef inFrame2) {
    if ((inFrame1->rowLength != inFrame2->rowLength) || (inFrame1->numberOfRows != inFrame2->numberOfRows)) {
        return FALSE;
    }
    
    for (UInt32 r = 0; r < inFrame1->numberOfRows ; r++) {
        if (memcmp(inFrame1->rows[r], inFrame2->rows[r], inFrame1->rowLength*sizeof(Float32)) != 0) {
//            for (UInt32 c = 0; c < inFrame1->rowLength; c++) {
//                if (inFrame1->rows[r][c] != inFrame2->rows[r][c]) {
//                    NSLog(@"r:%u c:%u %f != %f", (unsigned int)r, (unsigned int)c, inFrame1->rows[r][c], inFrame2->rows[r][c]);
//                }
//            }
            return FALSE;
        }
    }
    
    return TRUE;
}

#pragma mark -
