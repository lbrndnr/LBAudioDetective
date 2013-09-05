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

@interface LBTableViewController () <UIActionSheetDelegate>

@property (nonatomic, strong) NSFileManager* manager;
@property (nonatomic, strong) AVAudioPlayer* player;

@property (nonatomic, readonly) NSURL* applicationDocumentDirectory;

-(NSURL*)_URLForRecording:(NSInteger)recording;

-(void)_startProcessing:(id)sender;
-(void)_stopProcessing:(id)sender;

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

//-(NSArray*)_arrayFromAudioUnits:(LBAudioDetectiveIdentificationUnit *)units count:(NSUInteger)count {
//    NSMutableArray* mutableUnits = [NSMutableArray new];
//    for (NSInteger i = 0; i < count; i++) {
//        LBAudioDetectiveIdentificationUnit unit = units[i];
//        NSInteger f0 = unit.frequencies[0];
//        NSInteger f1 = unit.frequencies[1];
//        NSInteger f2 = unit.frequencies[2];
//        NSInteger f3 = unit.frequencies[3];
//        NSInteger f4 = unit.frequencies[4];
//        [mutableUnits addObject:@[@(f0-(f0%2)), @(f1-(f1%2)), @(f2-(f2%2)), @(f3-(f3%2)), @(f4-(f4%2))]];
//    }
//    
//    return mutableUnits;
//}

#pragma mark -

@end
