//
//  LBViewController.m
//  LBAudioDetective
//
//  Created by Laurin Brandner on 21.04.13.
//  Copyright (c) 2013 Laurin Brandner. All rights reserved.
//

#import "LBTableViewController.h"
#import "LBAudioDetective.h"
#import <AVFoundation/AVFoundation.h>

NSString* const kLBTableViewCellIdentifier = @"LBTableViewCellIdentifier";

const NSInteger kLBTableViewActionSheetTagPlayOrProcess = 1;
const NSInteger kLBTableViewActionSheetTagSaveOrProcess = 2;

@interface LBTableViewController () <UIActionSheetDelegate> {
    LBAudioDetectiveRef _detective;
    NSFileManager* _manager;
    AVAudioPlayer* _player;
    NSDictionary* _userData;
}

@property (nonatomic) LBAudioDetectiveRef detective;
@property (nonatomic, strong) NSFileManager* manager;
@property (nonatomic, strong) AVAudioPlayer* player;
@property (nonatomic, strong) NSDictionary* userData;

@property (nonatomic, readonly) NSURL* applicationDocumentDirectory;

-(NSURL*)_URLForRecording:(NSInteger)recording;

-(void)_startProcessing:(id)sender;
-(void)_stopProcessing:(id)sender;

-(NSArray*)_arrayFromAudioUnits:(LBAudioDetectiveIdentificationUnit*)units count:(NSUInteger)count;
-(void)_saveIdentificationUnits:(NSArray*)units;
-(NSArray*)_savedIdentificationUnit;
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
        self.manager = [NSFileManager new];
        self.detective = LBAudioDetectiveNew();
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
    self.userData = @{@"URL": URL};
    
    UIActionSheet* sheet = [[UIActionSheet alloc] initWithTitle:@"Action" delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Play", @"Process", @"Send", nil];
    sheet.tag = kLBTableViewActionSheetTagPlayOrProcess;
    [sheet showInView:self.tableView];
    
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
    UIActionSheet* sheet = [[UIActionSheet alloc] initWithTitle:@"Action" delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Save", @"Process", nil];
    sheet.tag = kLBTableViewActionSheetTagSaveOrProcess;
    [sheet showInView:self.tableView];
}

-(void)_stopProcessing:(id)sender {
    LBAudioDetectiveStopProcessing(self.detective);
    
    UInt32 unitCount;
    LBAudioDetectiveIdentificationUnit* identificationUnits = LBAudioDetectiveGetIdentificationUnits(self.detective, &unitCount);
    
    if ([(NSNumber*)self.userData[@"Process"] boolValue]) {
        NSUInteger match = [self _matchRecordedIdentificationUnits:[self _arrayFromAudioUnits:identificationUnits count:unitCount] withOriginalUnits:[self _savedIdentificationUnit]];
        NSLog(@"Audio Analysis Matches:%u", match);
        UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"Audio Analysis" message:[NSString stringWithFormat:@"There were %u hits", match] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alertView show];
    }
    else {
        [self _saveIdentificationUnits:[self _arrayFromAudioUnits:identificationUnits count:unitCount]];
    }
    
    UIBarButtonItem* processItem = self.navigationItem.rightBarButtonItem;
    processItem.title = @"Process";
    processItem.action = @selector(_startProcessing:);
    
    [self.tableView reloadData];
    self.userData = nil;
}

-(NSUInteger)_matchRecordedIdentificationUnits:(NSArray *)recordedUnits withOriginalUnits:(NSArray *)originalUnits {
    NSAssert(recordedUnits || originalUnits, @"Identification Units are nil");
    
    __block NSMutableDictionary* offsetDictionary = [NSMutableDictionary new];
    [originalUnits enumerateObjectsUsingBlock:^(NSArray* originalUnit, NSUInteger originalIndex, BOOL *stop) {
        [recordedUnits enumerateObjectsUsingBlock:^(NSArray* recordedUnit, NSUInteger recordedIndex, BOOL *stop) {
            float match0 = fabsf([(NSNumber*)originalUnit[0] floatValue] - [(NSNumber*)recordedUnit[0] floatValue]);
            float match1 = fabsf([(NSNumber*)originalUnit[1] floatValue] - [(NSNumber*)recordedUnit[1] floatValue]);
            float match2 = fabsf([(NSNumber*)originalUnit[2] floatValue] - [(NSNumber*)recordedUnit[2] floatValue]);
            float match3 = fabsf([(NSNumber*)originalUnit[3] floatValue] - [(NSNumber*)recordedUnit[3] floatValue]);
            float match4 = fabsf([(NSNumber*)originalUnit[4] floatValue] - [(NSNumber*)recordedUnit[4] floatValue]);
            
            if (match0 < 0.5f && match1 < 0.5f && match2 < 0.5f && match3 < 0.5f && match4 < 0.5f) {
                NSNumber* offset = @(originalIndex-recordedIndex);
                NSNumber* matches = offsetDictionary[offset];
                
                [offsetDictionary setObject:@(1+matches.integerValue) forKey:offset];
            }
        }];
    }];
    
    __block NSUInteger matches = 0;
    [offsetDictionary enumerateKeysAndObjectsUsingBlock:^(NSNumber* offset, NSNumber* obj, BOOL *stop) {
        if (obj.integerValue > 1) {
             matches += obj.unsignedIntegerValue;
        }
    }];
    
    return matches;
}

-(void)_identifyRecordedIdentificationUnits:(NSArray *)units answer:(void (^)(NSString *))completion {
    NSMutableString* string = [NSMutableString new];
    for (NSArray* unit in units) {
        [string appendFormat:@"%i-%i-%i-%i-%i", [(NSNumber*)unit[0] integerValue], [(NSNumber*)unit[1] integerValue], [(NSNumber*)unit[2] integerValue], [(NSNumber*)unit[3] integerValue], [(NSNumber*)unit[4] integerValue]];
    }
    
#if TARGET_IPHONE_SIMULATOR
    NSURL* URL = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:3000/birds/identify.json?data=%@", string]];
#else
    NSURL* URL = [NSURL URLWithString:[NSString stringWithFormat:@"http://whistles.herokuapp.com/birds/identify.json?data=%@", string]];
#endif
    
    NSURLRequest* request = [NSURLRequest requestWithURL:URL];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue new] completionHandler:^(NSURLResponse* response, NSData* data, NSError* error) {
        NSDictionary* JSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        completion(JSON[@"name"]);
    }];
}

-(NSArray*)_arrayFromAudioUnits:(LBAudioDetectiveIdentificationUnit *)units count:(NSUInteger)count {
    NSMutableArray* mutableUnits = [NSMutableArray new];
    for (NSInteger i = 0; i < count; i++) {
        LBAudioDetectiveIdentificationUnit unit = units[i];
        [mutableUnits addObject:@[@(unit.frequencies[0]), @(unit.frequencies[1]), @(unit.frequencies[2]), @(unit.frequencies[3]), @(unit.frequencies[4])]];
    }
    
    return mutableUnits;
}

-(NSArray*)_savedIdentificationUnit {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    return [defaults arrayForKey:@"bird"];
}

-(void)_saveIdentificationUnits:(NSArray *)units {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:units forKey:@"bird"];
    [defaults synchronize];
}

#pragma mark -
#pragma mark UIActionSheetDelegate

-(void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {    
    if (actionSheet.tag == kLBTableViewActionSheetTagPlayOrProcess) {
        NSURL* URL = self.userData[@"URL"];
        
        if (buttonIndex == 0) {
            NSError* error;
            
            self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:URL error:&error];
            if (error) {
                NSLog(@"Error playing file:%@", error);
            }
            else {
                [self.player play];
            }
        }
        else if (buttonIndex == 1) {
            LBAudioDetectiveProcessAudioURL(self.detective, URL);
            
            UInt32 unitCount;
            LBAudioDetectiveIdentificationUnit* identificationUnits = LBAudioDetectiveGetIdentificationUnits(self.detective, &unitCount);
            
            NSUInteger match = [self _matchRecordedIdentificationUnits:[self _arrayFromAudioUnits:identificationUnits count:unitCount] withOriginalUnits:[self _savedIdentificationUnit]];
            NSLog(@"Audio Analysis Matches:%u", match);
            UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"Audio Analysis" message:[NSString stringWithFormat:@"There were %u hits", match] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
            [alertView show];
        }
        else if (buttonIndex == 2) {
            LBAudioDetectiveProcessAudioURL(self.detective, URL);
            
            UInt32 unitCount;
            LBAudioDetectiveIdentificationUnit* identificationUnits = LBAudioDetectiveGetIdentificationUnits(self.detective, &unitCount);
            [self _identifyRecordedIdentificationUnits:[self _arrayFromAudioUnits:identificationUnits count:unitCount] answer:^(NSString* name) {
                dispatch_sync(dispatch_get_main_queue(), ^{
                    UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"Audio Analysis" message:[NSString stringWithFormat:@"It's a %@", name] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
                    [alertView show];
                });
            }];
        }
        
        self.userData = nil;
    }
    else if (buttonIndex != 2) {
        self.userData = @{@"Process": @(buttonIndex)};
        
        LBAudioDetectiveSetWriteAudioToURL(self.detective, [self _URLForRecording:[self.tableView numberOfRowsInSection:0]]);
        LBAudioDetectiveStartProcessing(self.detective);
        
        UIBarButtonItem* processItem = self.navigationItem.rightBarButtonItem;
        processItem.title = @"Stop";
        processItem.action = @selector(_stopProcessing:);
        
        if (buttonIndex == 1) {
            [self performSelector:@selector(_stopProcessing:) withObject:processItem afterDelay:2.0f];
        }
    }
}

#pragma mark -

@end
