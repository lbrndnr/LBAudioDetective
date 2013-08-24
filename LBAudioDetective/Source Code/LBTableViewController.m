//
//  LBViewController.m
//  LBAudioDetective
//
//  Created by Laurin Brandner on 21.04.13.
//  Copyright (c) 2013 Laurin Brandner. All rights reserved.
//

#import "LBTableViewController.h"
#import <AVFoundation/AVFoundation.h>

NSString* const kLBTableViewCellIdentifier = @"LBTableViewCellIdentifier";

const NSInteger kLBTableViewActionSheetTagPlayOrProcess = 1;

@interface LBTableViewController () <UIActionSheetDelegate> {
    NSFileManager* _manager;
    AVAudioPlayer* _player;
    NSDictionary* _userData;
    NSUInteger _selectedRecording;
}

@property (nonatomic, strong) NSFileManager* manager;
@property (nonatomic, strong) AVAudioPlayer* player;
@property (nonatomic, strong) NSDictionary* userData;
@property (nonatomic) NSUInteger selectedRecording;

@property (nonatomic, readonly) NSURL* applicationDocumentDirectory;

-(NSURL*)_URLForRecording:(NSInteger)recording;

-(void)_startProcessing:(id)sender;
-(void)_stopProcessing:(id)sender;

-(NSArray*)_arrayFromAudioUnits:(LBAudioDetectiveIdentificationUnit*)units count:(NSUInteger)count;
-(NSUInteger)_matchRecordedIdentificationUnits:(NSArray*)units1 withOriginalUnits:(NSArray*)units2;
-(void)_identifyRecordedIdentificationUnits:(NSArray*)units answer:(void(^)(NSString*))completion;

@end
@implementation LBTableViewController

#pragma mark Accessors

-(NSURL*)applicationDocumentDirectory {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    
    return [NSURL fileURLWithPath:basePath];
}

#pragma mark -
#pragma mark Initialization

-(id)init {
    self = [super init];
    if (self) {
        self.selectedRecording = -1;
        self.manager = [NSFileManager new];
        
        self.detective = LBAudioDetectiveNew();
        Float32 pitches[4];
        pitches[0] = 4000.0f;
        pitches[1] = 8000.0f;
        pitches[2] = 12000.0f;
        pitches[3] = 16000.0f;
        LBAudioDetectiveSetPitchSteps(self.detective, pitches, 4);
        
#if TARGET_IPHONE_SIMULATOR
        NSURL* URL = [NSURL URLWithString:@"http://localhost:3000"];
#else
        NSURL* URL = [NSURL URLWithString:@"http://whistles.herokuapp.com/"];
#endif
        
        self.client = [[AFHTTPClient alloc] initWithBaseURL:URL];
        _client.parameterEncoding = AFJSONParameterEncoding;
    }
    
    return self;
}

-(void)dealloc {
    LBAudioDetectiveDispose(self.detective);
}

#pragma mark -
#pragma mark View Lifecycle

-(void)viewDidLoad {
    [super viewDidLoad];
    
    UIBarButtonItem* processItem = [[UIBarButtonItem alloc] initWithTitle:@"Process" style:UIBarButtonItemStyleBordered target:self action:@selector(_startProcessing:)];
    self.navigationItem.rightBarButtonItem = processItem;
}

#pragma mark -
#pragma mark UITableViewDataSource

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSArray* documents = [self.manager contentsOfDirectoryAtURL:self.applicationDocumentDirectory includingPropertiesForKeys:nil options:0 error:nil];
    
    return documents.count;
}

-(UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:kLBTableViewCellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kLBTableViewCellIdentifier];
    }
    
    cell.textLabel.text = [NSString stringWithFormat:@"Recording #%i", indexPath.row];
    
    return cell;
}

#pragma mark -
#pragma mark UITableViewDelegate

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.player) {
        [self.player stop];
        self.player = nil;
    }
    
    NSURL* URL = [self _URLForRecording:indexPath.row];
    LBAudioDetectiveProcessAudioURL(self.detective, URL);
//    self.userData = @{@"URL": URL, @"index": @(indexPath.row)};
//    
//    UIActionSheet* sheet = [[UIActionSheet alloc] initWithTitle:@"Action" delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Play", @"Process", @"Send", @"Select", nil];
//    sheet.tag = kLBTableViewActionSheetTagPlayOrProcess;
//    [sheet showInView:self.tableView];
    
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark -
#pragma mark Other Methods

-(NSURL*)_URLForRecording:(NSInteger)recording {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    NSString* path = [basePath stringByAppendingPathComponent:[NSString stringWithFormat:@"recording-%u.caf", recording]];
    
    return [NSURL fileURLWithPath:path];
}

-(void)_startProcessing:(id)sender {
    LBAudioDetectiveSetWriteAudioToURL(self.detective, [self _URLForRecording:[self.tableView numberOfRowsInSection:0]]);
    LBAudioDetectiveStartProcessing(self.detective);
    
    UIBarButtonItem* processItem = self.navigationItem.rightBarButtonItem;
    processItem.title = @"Stop";
    processItem.action = @selector(_stopProcessing:);
    
    [self performSelector:@selector(_stopProcessing:) withObject:nil afterDelay:4.0f];
}

-(void)_stopProcessing:(id)sender {
    LBAudioDetectiveStopProcessing(self.detective);
    
    UIBarButtonItem* processItem = self.navigationItem.rightBarButtonItem;
    processItem.title = @"Process";
    processItem.action = @selector(_startProcessing:);
    
    [self.tableView reloadData];
    self.userData = nil;
}

-(NSUInteger)_matchRecordedIdentificationUnits:(NSArray *)recordedUnits withOriginalUnits:(NSArray *)originalUnits {
    NSAssert(recordedUnits || originalUnits, @"Identification Units are nil");
    
    NSInteger range = 100;
    __block NSMutableDictionary* offsetDictionary = [NSMutableDictionary new];
    
    [originalUnits enumerateObjectsUsingBlock:^(NSArray* originalUnit, NSUInteger originalIndex, BOOL *originalStop) {
        [recordedUnits enumerateObjectsUsingBlock:^(NSArray* recordedUnit, NSUInteger recordedIndex, BOOL *recordedStop) {
            NSInteger match0 = fabsf([(NSNumber*)originalUnit[0] integerValue] - [(NSNumber*)recordedUnit[0] integerValue]);
            NSInteger match1 = fabsf([(NSNumber*)originalUnit[1] integerValue] - [(NSNumber*)recordedUnit[1] integerValue]);
            NSInteger match2 = fabsf([(NSNumber*)originalUnit[2] integerValue] - [(NSNumber*)recordedUnit[2] integerValue]);
            NSInteger match3 = fabsf([(NSNumber*)originalUnit[3] integerValue] - [(NSNumber*)recordedUnit[3] integerValue]);
            NSInteger match4 = fabsf([(NSNumber*)originalUnit[4] integerValue] - [(NSNumber*)recordedUnit[4] integerValue]);
            
            if ((match0 + match1 + match2 + match3 + match4) < 400) {
                NSInteger index = originalIndex-recordedIndex;
                
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
        }];
    }];
    
    __block NSUInteger matches = 0;
    [offsetDictionary enumerateKeysAndObjectsUsingBlock:^(NSNumber* offset, NSNumber* count, BOOL *stop) {
        if (count.integerValue > 3) {
            matches += count.unsignedIntegerValue;
        }
    }];
    
    return matches;
}

-(void)_identifyRecordedIdentificationUnits:(NSArray *)units answer:(void (^)(NSString *))completion {
    NSMutableString* string = [NSMutableString new];
    for (NSArray* unit in units) {
        [string appendFormat:@"%i-%i-%i-%i-%i-", [(NSNumber*)unit[0] integerValue], [(NSNumber*)unit[1] integerValue], [(NSNumber*)unit[2] integerValue], [(NSNumber*)unit[3] integerValue], [(NSNumber*)unit[4] integerValue]];
    }
    
    NSDictionary* parameters = @{@"voice": string};
    NSMutableURLRequest* request = [_client requestWithMethod:@"POST" path:@"/birds/identify.json" parameters:parameters];
    AFJSONRequestOperation* operation = [AFJSONRequestOperation JSONRequestOperationWithRequest:request success:nil failure:nil];
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id JSON) {
        completion(JSON[@"name"]);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"%@", error);
        NSLog(@"%@", operation.responseString);
        completion(@"No Result");
    }];
    [_client enqueueHTTPRequestOperation:operation];
}

-(NSArray*)_arrayFromAudioUnits:(LBAudioDetectiveIdentificationUnit *)units count:(NSUInteger)count {
    NSMutableArray* mutableUnits = [NSMutableArray new];
    for (NSInteger i = 0; i < count; i++) {
        LBAudioDetectiveIdentificationUnit unit = units[i];
        NSInteger f0 = unit.frequencies[0];
        NSInteger f1 = unit.frequencies[1];
        NSInteger f2 = unit.frequencies[2];
        NSInteger f3 = unit.frequencies[3];
        NSInteger f4 = unit.frequencies[4];
        [mutableUnits addObject:@[@(f0-(f0%2)), @(f1-(f1%2)), @(f2-(f2%2)), @(f3-(f3%2)), @(f4-(f4%2))]];
    }
    
    return mutableUnits;
}

#pragma mark -
#pragma mark UIActionSheetDelegate

-(void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {    
//    if (actionSheet.tag == kLBTableViewActionSheetTagPlayOrProcess) {
//        NSURL* URL = self.userData[@"URL"];
//        
//        if (buttonIndex == 0) {
//            NSError* error;
//            
//            self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:URL error:&error];
//            if (error) {
//                NSLog(@"Error playing file:%@", error);
//            }
//            else {
//                [self.player play];
//            }
//        }
//        else if (buttonIndex == 1) {
//            LBAudioDetectiveProcessAudioURL(self.detective, URL);
//            
//            UInt32 unitCount1;
//            LBAudioDetectiveIdentificationUnit* identificationUnits1 = LBAudioDetectiveGetIdentificationUnits(self.detective, &unitCount1);
//            NSArray* array1 = [self _arrayFromAudioUnits:identificationUnits1 count:unitCount1];
//            
//            if (self.selectedRecording == -1) {
//                NSMutableDictionary* matches = [NSMutableDictionary new];
//                NSArray* birds = @[@"Amsel", @"Blaumeise", @"Buchfink", @"Haussperling", @"Kohlmeise", @"Rabenkraehe"];
//                
//                [birds enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
//                    NSURL* selectedURL = [[NSBundle mainBundle] URLForResource:obj withExtension:@"caf"];
//                    LBAudioDetectiveProcessAudioURL(self.detective, selectedURL);
//                    
//                    UInt32 unitCount2;
//                    LBAudioDetectiveIdentificationUnit* identificationUnits2 = LBAudioDetectiveGetIdentificationUnits(self.detective, &unitCount2);
//                    NSArray* array2 = [self _arrayFromAudioUnits:identificationUnits2 count:unitCount2];
//                    
//                    NSUInteger match = [self _matchRecordedIdentificationUnits:array1 withOriginalUnits:array2];
//                    [matches setObject:@(match) forKey:obj];
//                }];
//
//                UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"Audio Analysis" message:[NSString stringWithFormat:@"%@", matches] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
//                [alertView show];
//            }
//            else {
//                NSURL* selectedURL = [self _URLForRecording:self.selectedRecording];
//                LBAudioDetectiveProcessAudioURL(self.detective, selectedURL);
//                
//                NSLog(@"Comparing %@ with %@", URL.absoluteString.lastPathComponent, selectedURL.absoluteString.lastPathComponent);
//                
//                UInt32 unitCount2;
//                LBAudioDetectiveIdentificationUnit* identificationUnits2 = LBAudioDetectiveGetIdentificationUnits(self.detective, &unitCount2);
//                NSArray* array2 = [self _arrayFromAudioUnits:identificationUnits2 count:unitCount2];
//                
//                NSUInteger match = [self _matchRecordedIdentificationUnits:array1 withOriginalUnits:array2];
//                NSLog(@"Audio Analysis Matches:%u", match);
//                UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"Audio Analysis" message:[NSString stringWithFormat:@"There were %u hits", match] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
//                [alertView show];
//            }
//        }
//        else if (buttonIndex == 2) {
//            LBAudioDetectiveProcessAudioURL(self.detective, URL);
//            
//            UInt32 unitCount;
//            LBAudioDetectiveIdentificationUnit* identificationUnits = LBAudioDetectiveGetIdentificationUnits(self.detective, &unitCount);
//            [self _identifyRecordedIdentificationUnits:[self _arrayFromAudioUnits:identificationUnits count:unitCount] answer:^(NSString* name) {
//                UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"Audio Analysis" message:[NSString stringWithFormat:@"It's a %@", name] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
//                [alertView show];
//            }];
//        }
//        else if (buttonIndex == 3) {
//            self.selectedRecording = [self.userData[@"index"] integerValue];
//        }
//        
//        self.userData = nil;
//    }
}

#pragma mark -

@end
