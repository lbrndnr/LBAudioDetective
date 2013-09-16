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

-(NSURL*)URLForRecording:(NSInteger)recording;

-(void)startProcessing:(id)sender;
-(void)stopProcessing:(id)sender;

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
    
    UIBarButtonItem* processItem = [[UIBarButtonItem alloc] initWithTitle:@"Process" style:UIBarButtonItemStyleBordered target:self action:@selector(startProcessing:)];
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
    
    NSMutableDictionary* matches = [NSMutableDictionary new];
    NSURL* URL = [self URLForRecording:indexPath.row];
    NSBundle* bundle = [NSBundle mainBundle];
    NSArray* birds = @[@"Amsel", @"Blaumeise", @"Buchfink", @"Haussperling", @"Kohlmeise", @"Rabenkraehe"];
    
    [birds enumerateObjectsUsingBlock:^(NSString* originalBird, NSUInteger idx, BOOL *stop) {
        NSURL* originalURL = [bundle URLForResource:[originalBird stringByAppendingString:@"_org"] withExtension:@"caf"];
        Float32 match = LBAudioDetectiveCompareAudioURLs(self.detective, originalURL, URL, 0);
        [matches setObject:@(match) forKey:originalBird];
    }];
    
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"Analysis Results" message:matches.description delegate:Nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [alertView show];
}

#pragma mark -
#pragma mark Other Methods

-(NSURL*)URLForRecording:(NSInteger)recording {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    NSString* path = [basePath stringByAppendingPathComponent:[NSString stringWithFormat:@"recording-%u.caf", recording]];
    
    return [NSURL fileURLWithPath:path];
}

-(void)startProcessing:(id)sender {
    LBAudioDetectiveSetWriteAudioToURL(self.detective, [self URLForRecording:[self.tableView numberOfRowsInSection:0]]);
    LBAudioDetectiveStartProcessing(self.detective);
    
    UIBarButtonItem* processItem = self.navigationItem.rightBarButtonItem;
    processItem.title = @"Stop";
    processItem.action = @selector(stopProcessing:);
    
    [self performSelector:@selector(stopProcessing:) withObject:nil afterDelay:4.0f];
}

-(void)stopProcessing:(id)sender {
    LBAudioDetectiveStopProcessing(self.detective);
    
    UIBarButtonItem* processItem = self.navigationItem.rightBarButtonItem;
    processItem.title = @"Process";
    processItem.action = @selector(startProcessing:);
    
    [self.tableView reloadData];
}

#pragma mark -

@end
