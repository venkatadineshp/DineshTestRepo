//
//  ATEngagementManifestParser.h
//  ApptentiveConnect
//
//  Created by Peter Kamb on 8/20/13.
//  Copyright (c) 2013 Apptentive, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ATInteraction.h"
//@class ATInteraction;

@interface ATEngagementManifestParser : NSObject {
@private
	NSError *parserError;
}

- (NSDictionary *)codePointInteractionsForEngagementManifest:(NSData *)jsonManifest;
- (NSError *)parserError;

@end
