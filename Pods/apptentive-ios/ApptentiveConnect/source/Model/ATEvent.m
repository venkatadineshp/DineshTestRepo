//
//  ATEvent.m
//  ApptentiveConnect
//
//  Created by Andrew Wooster on 2/13/13.
//  Copyright (c) 2013 Apptentive, Inc. All rights reserved.
//

#import "ATEvent.h"
#import "ATData.h"
#import "ATWebClient+Metrics.h"

@interface ATEvent ()
- (NSDictionary *)dictionaryForCurrentData;
- (NSData *)dataForDictionary:(NSDictionary *)dictionary;
@end

@implementation ATEvent

@dynamic pendingEventID;
@dynamic dictionaryData;
@dynamic label;

+ (NSObject *)newInstanceWithJSON:(NSDictionary *)json {
	NSAssert(NO, @"Abstract method called.");
	return nil;
}

- (void)updateWithJSON:(NSDictionary *)json {
	[super updateWithJSON:json];
}

- (NSDictionary *)apiJSON {
	NSDictionary *parentJSON = [super apiJSON];
	NSMutableDictionary *result = [[[NSMutableDictionary alloc] init] autorelease];

	if (parentJSON) {
		[result addEntriesFromDictionary:parentJSON];
	}
	if (self.label != nil) {
		result[@"label"] = self.label;
	}
	if (self.dictionaryData) {
		NSDictionary *dictionary = [self dictionaryForCurrentData];
		[result addEntriesFromDictionary:dictionary];
	}
	
	if (self.pendingEventID != nil) {
		result[@"nonce"] = self.pendingEventID;
	}
	
	// Monitor that the Event payload has not been dropped on retry
	if (!result) {
		ATLogError(@"Event json should not be nil.");
	}
	if (result.count == 0) {
		ATLogError(@"Event json should return a result.");
	}
	if (!result[@"label"]) {
		ATLogError(@"Event json should include a `label`.");
	}
	if (!result[@"nonce"]) {
		ATLogError(@"Event json should include a `nonce`.");
	}
		
	return @{@"event": result};
}

- (void)setup {
	if ([self isClientCreationTimeEmpty]) {
		[self updateClientCreationTime];
	}
	if (self.pendingEventID == nil) {
		CFUUIDRef uuidRef = CFUUIDCreate(NULL);
		CFStringRef uuidStringRef = CFUUIDCreateString(NULL, uuidRef);
		
		self.pendingEventID = [NSString stringWithFormat:@"event:%@", (NSString *)uuidStringRef];
		
		CFRelease(uuidRef), uuidRef = NULL;
		CFRelease(uuidStringRef), uuidStringRef = NULL;
	}
}

- (void)addEntriesFromDictionary:(NSDictionary *)incomingDictionary {
	NSDictionary *dictionary = [self dictionaryForCurrentData];
	NSMutableDictionary *mutableDictionary = nil;
	if (dictionary == nil) {
		mutableDictionary = [NSMutableDictionary dictionary];
	} else {
		mutableDictionary = [[dictionary mutableCopy] autorelease];
	}
	if (incomingDictionary != nil) {
		[mutableDictionary addEntriesFromDictionary:incomingDictionary];
	}
	[self setDictionaryData:[self dataForDictionary:mutableDictionary]];
}

#pragma mark Private
- (NSDictionary *)dictionaryForCurrentData {
	if (self.dictionaryData == nil) {
		return @{};
	} else {
		NSDictionary *result = nil;
		@try {
			result = [NSKeyedUnarchiver unarchiveObjectWithData:self.dictionaryData];
		} @catch (NSException *exception) {
			ATLogError(@"Unable to unarchive event: %@", exception);
		}
		return result;
	}
}

- (NSData *)dataForDictionary:(NSDictionary *)dictionary {
	if (dictionary == nil) {
		return nil;
	} else {
		return [NSKeyedArchiver archivedDataWithRootObject:dictionary];
	}
}

#pragma mark ATRequestTaskprovider
- (NSURL *)managedObjectURIRepresentationForTask:(ATRecordRequestTask *)task {
	return [[self objectID] URIRepresentation];
}

- (void)cleanupAfterTask:(ATRecordRequestTask *)task {
	[ATData deleteManagedObject:self];
}

- (ATAPIRequest *)requestForTask:(ATRecordRequestTask *)task {
	return [[ATWebClient sharedClient] requestForSendingEvent:self];
}

- (ATRecordRequestTaskResult)taskResultForTask:(ATRecordRequestTask *)task withRequest:(ATAPIRequest *)request withResult:(id)result {
	//ATLogInfo(@"Successfully sent event: %@ %@", self, result);
	return ATRecordRequestTaskFinishedResult;
}
@end
