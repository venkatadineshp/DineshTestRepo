//
//  ATInteractionMessageCenterController.h
//  ApptentiveConnect
//
//  Created by Peter Kamb on 3/3/14.
//  Copyright (c) 2014 Apptentive, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
@class ATInteraction;

@interface ATInteractionMessageCenterController : NSObject

@property (nonatomic, retain, readonly) ATInteraction *interaction;
@property (nonatomic, retain) UIViewController *viewController;

- (id)initWithInteraction:(ATInteraction *)interaction;
- (void)showMessageCenterFromViewController:(UIViewController *)viewController;

@end
