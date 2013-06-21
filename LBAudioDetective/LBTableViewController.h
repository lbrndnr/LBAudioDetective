//
//  LBViewController.h
//  LBAudioDetective
//
//  Created by Laurin Brandner on 21.04.13.
//  Copyright (c) 2013 Laurin Brandner. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "LBAudioDetective.h"
#import "AFNetworking.h"

@interface LBTableViewController : UITableViewController {
    AFHTTPClient* _client;
    LBAudioDetectiveRef _detective;
}

@property (nonatomic, strong) AFHTTPClient* client;
@property (nonatomic) LBAudioDetectiveRef detective;

@end
