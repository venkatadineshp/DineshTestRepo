//
//  ApptentiveMetrics.m
//  ApptentiveMetrics
//
//  Created by Andrew Wooster on 12/27/11.
//  Copyright (c) 2011 Apptentive. All rights reserved.
//

#import "ApptentiveMetrics.h"

#import "ATAppConfigurationUpdater.h"
#import "ATBackend.h"
#import "ATFeedbackMetrics.h"
#import "ATData.h"
#import "ATEvent.h"
#import "ATMessageCenterMetrics.h"
#import "ATMetric.h"
#import "ATRecordTask.h"
#import "ATRecordRequestTask.h"
#import "ATSurveyMetrics.h"
#import "ATTaskQueue.h"
#import "ATEngagementBackend.h"

// Engagement event labels

static NSString *ATInteractionAppEventLabelLaunch = @"launch";
static NSString *ATInteractionAppEventLabelExit = @"exit";

// Legacy metric event labels

static NSString *ATMetricNameFeedbackDialogLaunch = @"feedback_dialog.launch";
static NSString *ATMetricNameFeedbackDialogCancel = @"feedback_dialog.cancel";
static NSString *ATMetricNameFeedbackDialogSubmit = @"feedback_dialog.submit";

static NSString *ATMetricNameSurveyLaunch = @"survey.launch";
static NSString *ATMetricNameSurveyCancel = @"survey.cancel";
static NSString *ATMetricNameSurveySubmit = @"survey.submit";
static NSString *ATMetricNameSurveyAnswerQuestion = @"survey.question_response";

static NSString *ATMetricNameMessageCenterLaunch = @"message_center.launch";
static NSString *ATMetricNameMessageCenterClose = @"message_center.close";
static NSString *ATMetricNameMessageCenterAttach = @"message_center.attach";
static NSString *ATMetricNameMessageCenterRead = @"message_center.read";
static NSString *ATMetricNameMessageCenterSend = @"message_center.send";

static NSString *ATMetricNameMessageCenterIntroLaunch = @"message_center.intro.launch";
static NSString *ATMetricNameMessageCenterIntroSend = @"message_center.intro.send";
static NSString *ATMetricNameMessageCenterIntroCancel = @"message_center.intro.cancel";
static NSString *ATMetricNameMessageCenterThankYouLaunch = @"message_center.thank_you.launch";
static NSString *ATMetricNameMessageCenterThankYouMessages = @"message_center.thank_you.messages";
static NSString *ATMetricNameMessageCenterThankYouClose = @"message_center.thank_you.close";

@interface ApptentiveMetrics (Private)
- (void)addLaunchMetric;
- (ATFeedbackWindowType)windowTypeFromNotification:(NSNotification *)notification;
- (void)feedbackDidShowWindow:(NSNotification *)notification;
- (void)feedbackDidHideWindow:(NSNotification *)notification;

- (ATSurveyEvent)surveyEventTypeFromNotification:(NSNotification *)notification;
- (void)surveyDidShow:(NSNotification *)notification;
- (void)surveyDidHide:(NSNotification *)notification;
- (void)surveyDidAnswerQuestion:(NSNotification *)notification;

- (void)appWillTerminate:(NSNotification *)notification;
- (void)appDidEnterBackground:(NSNotification *)notification;
- (void)appWillEnterForeground:(NSNotification *)notification;

- (void)messageCenterDidLaunch:(NSNotification *)notification;
- (void)messageCenterDidClose:(NSNotification *)notification;
- (void)messageCenterDidAttach:(NSNotification *)notification;
- (void)messageCenterDidRead:(NSNotification *)notification;
- (void)messageCenterDidSend:(NSNotification *)notification;

- (void)messageCenterIntroDidLaunch:(NSNotification *)notification;
- (void)messageCenterIntroDidSend:(NSNotification *)notification;
- (void)messageCenterIntroDidCancel:(NSNotification *)notification;
- (void)messageCenterIntroThankYouDidLaunch:(NSNotification *)notification;
- (void)messageCenterIntroThankYouHitMessages:(NSNotification *)notification;
- (void)messageCenterIntroThankYouDidClose:(NSNotification *)notification;

- (void)preferencesChanged:(NSNotification *)notification;

- (void)updateWithCurrentPreferences;
@end

@implementation ApptentiveMetrics

+ (ApptentiveMetrics *)sharedMetrics {
	static ApptentiveMetrics *sharedSingleton = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedSingleton = [[ApptentiveMetrics alloc] init];
	});
	return sharedSingleton;
}

+ (void)registerDefaults {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSDictionary *defaultPreferences = 
	[NSDictionary dictionaryWithObjectsAndKeys:
	 [NSNumber numberWithBool:YES], ATAppConfigurationMetricsEnabledPreferenceKey,
	 nil];
	[defaults registerDefaults:defaultPreferences];
}


- (void)addMetricWithName:(NSString *)name info:(NSDictionary *)userInfo {
	[self addMetricWithName:name info:userInfo customData:nil extendedData:nil];
}

- (void)addMetricWithName:(NSString *)name info:(NSDictionary *)userInfo customData:(NSDictionary *)customData extendedData:(NSArray *)extendedData {
	if (metricsEnabled == NO) {
		return;
	}
	ATEvent *event = (ATEvent *)[ATData newEntityNamed:@"ATEvent"];
	[event setup];
	event.label = name;
	
	if (userInfo) {
		[event addEntriesFromDictionary:@{@"data": userInfo}];
	}
	if (customData) {
		[event addEntriesFromDictionary:@{@"custom_data": customData}];
	}

	if (extendedData) {
		for (NSDictionary *data in extendedData) {
			// Extended data items are not added for key "extended_data", but rather for key of extended data type: "time", "location", etc.
			[event addEntriesFromDictionary:data];
		}
	}
	
	if (![ATData save]) {
		[event release], event = nil;
		return;
	}
	
	ATRecordRequestTask *task = [[ATRecordRequestTask alloc] init];
	[task setTaskProvider:event];
	[[ATTaskQueue sharedTaskQueue] addTask:task];
	[event release], event = nil;
	[task release], task = nil;
}

- (void)backendBecameAvailable:(NSNotification *)notification {
	@autoreleasepool {
		[[NSNotificationCenter defaultCenter] removeObserver:self name:ATBackendBecameReadyNotification object:nil];
		
		[ApptentiveMetrics registerDefaults];
		[self updateWithCurrentPreferences];
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(feedbackDidShowWindow:) name:ATFeedbackDidShowWindowNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(feedbackDidHideWindow:) name:ATFeedbackDidHideWindowNotification object:nil];
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(surveyDidShow:) name:ATSurveyDidShowWindowNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(surveyDidHide:) name:ATSurveyDidHideWindowNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(surveyDidAnswerQuestion:) name:ATSurveyDidAnswerQuestionNotification object:nil];
		
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(preferencesChanged:) name:ATConfigurationPreferencesChangedNotification object:nil];
		
#if TARGET_OS_IPHONE
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillTerminate:) name:UIApplicationWillTerminateNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
#elif TARGET_OS_MAC
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
#endif
		
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messageCenterDidLaunch:) name:ATMessageCenterDidShowNotification object:nil];
		[self performSelector:@selector(addLaunchMetric) withObject:nil afterDelay:0.1];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messageCenterDidClose:) name:ATMessageCenterDidHideNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messageCenterDidAttach:) name:ATMessageCenterDidAttachNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messageCenterDidRead:) name:ATMessageCenterDidReadNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messageCenterDidSend:) name:ATMessageCenterDidSendNotification object:nil];
		
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messageCenterIntroDidLaunch:) name:ATMessageCenterIntroDidShowNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messageCenterIntroDidSend:) name:ATMessageCenterIntroDidSendNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messageCenterIntroDidCancel:) name:ATMessageCenterIntroDidCancelNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messageCenterIntroThankYouDidLaunch:) name:ATMessageCenterIntroThankYouDidShowNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messageCenterIntroThankYouHitMessages:) name:ATMessageCenterIntroThankYouHitMessagesNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messageCenterIntroThankYouDidClose:) name:ATMessageCenterIntroThankYouDidCloseNotification object:nil];
	}
}

- (id)init {
	self = [super init];
	if (self) {
		metricsEnabled = NO;
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(backendBecameAvailable:) name:ATBackendBecameReadyNotification object:nil];
	}
	
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

- (BOOL)upgradeLegacyMetric:(ATMetric *)metric {
	if (metricsEnabled == NO) {
		return NO;
	}
	
	ATEvent *event = (ATEvent *)[ATData newEntityNamed:@"ATEvent"];
	[event setup];
	event.label = metric.name;
	[event addEntriesFromDictionary:[metric info]];
	if (![ATData save]) {
		[event release], event = nil;
		return NO;
	}
	
	ATRecordRequestTask *task = [[ATRecordRequestTask alloc] init];
	[task setTaskProvider:event];
	[[ATTaskQueue sharedTaskQueue] addTask:task];
	[event release], event = nil;
	[task release], task = nil;
	return YES;
}
@end



@implementation ApptentiveMetrics (Private)
- (void)addLaunchMetric {
	@autoreleasepool {
		[[ATEngagementBackend sharedBackend] engageApptentiveAppEvent:ATInteractionAppEventLabelLaunch userInfo:nil];
	}
}

- (ATFeedbackWindowType)windowTypeFromNotification:(NSNotification *)notification {
	ATFeedbackWindowType windowType = ATFeedbackWindowTypeFeedback;
	if ([[notification userInfo] objectForKey:ATFeedbackWindowTypeKey]) {
		windowType = [(NSNumber *)[[notification userInfo] objectForKey:ATFeedbackWindowTypeKey] intValue];
	}
	if (windowType != ATFeedbackWindowTypeFeedback && windowType != ATFeedbackWindowTypeInfo) {
		ATLogError(@"Unknown window type: %d", windowType);
	}
	return windowType;
}

- (void)feedbackDidShowWindow:(NSNotification *)notification {
	NSString *name = nil;
	ATFeedbackWindowType windowType = [self windowTypeFromNotification:notification];
	
	if (windowType == ATFeedbackWindowTypeFeedback) {
		name = ATMetricNameFeedbackDialogLaunch;
	} else if (windowType == ATFeedbackWindowTypeInfo) {
		name = nil;
	}
	
	if (name != nil) {
		[self addMetricWithName:name info:nil];
	}
}

- (void)feedbackDidHideWindow:(NSNotification *)notification {
	ATFeedbackWindowType windowType = [self windowTypeFromNotification:notification];
	ATFeedbackEvent event = ATFeedbackEventTappedCancel;
	if ([[notification userInfo] objectForKey:ATFeedbackWindowHideEventKey]) {
		event = [(NSNumber *)[[notification userInfo] objectForKey:ATFeedbackWindowHideEventKey] intValue];
	}
	
	if (windowType == ATFeedbackWindowTypeFeedback) {
		if (event == ATFeedbackEventTappedCancel) {
			[self addMetricWithName:ATMetricNameFeedbackDialogCancel info:nil];
		} else if (event == ATFeedbackEventTappedSend) {
			[self addMetricWithName:ATMetricNameFeedbackDialogSubmit info:nil];
		}
	} else if (windowType == ATFeedbackWindowTypeInfo) {
		// pass, for now
	}
}

- (ATSurveyEvent)surveyEventTypeFromNotification:(NSNotification *)notification {
	ATSurveyEvent event = ATSurveyEventUnknown;
	if ([[notification userInfo] objectForKey:ATSurveyMetricsEventKey]) {
		event = [(NSNumber *)[[notification userInfo] objectForKey:ATSurveyMetricsEventKey] intValue];
	}
	if (event != ATSurveyEventTappedSend && event != ATSurveyEventTappedCancel && event != ATSurveyEventAnsweredQuestion) {
		event = ATSurveyEventUnknown;
		ATLogError(@"Unknown survey event type: %d", event);
	}
	return event;
}

- (void)surveyDidShow:(NSNotification *)notification {
	NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
	NSString *surveyID = [[notification userInfo] objectForKey:ATSurveyMetricsSurveyIDKey];
	if (surveyID != nil) {
		[info setObject:surveyID forKey:@"id"];
	}
	[self addMetricWithName:ATMetricNameSurveyLaunch info:info];
	[info release], info = nil;
}

- (void)surveyDidHide:(NSNotification *)notification {
	NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
	NSString *surveyID = [[notification userInfo] objectForKey:ATSurveyMetricsSurveyIDKey];
	if (surveyID != nil) {
		[info setObject:surveyID forKey:@"id"];
	}
	ATSurveyEvent eventType = [self surveyEventTypeFromNotification:notification];
	
	if (eventType == ATSurveyEventTappedSend) {
		[self addMetricWithName:ATMetricNameSurveySubmit info:info];
	} else if (eventType == ATSurveyEventTappedCancel) {
		[self addMetricWithName:ATMetricNameSurveyCancel info:info];
	}
	
	[info release], info = nil;
}

- (void)surveyDidAnswerQuestion:(NSNotification *)notification {
	NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
	NSString *surveyID = [[notification userInfo] objectForKey:ATSurveyMetricsSurveyIDKey];
	NSString *questionID = [[notification userInfo] objectForKey:ATSurveyMetricsSurveyQuestionIDKey];
	if (surveyID != nil) {
		[info setObject:surveyID forKey:@"survey_id"];
	}
	if (questionID != nil) {
		[info setObject:questionID forKey:@"id"];
	}
	ATSurveyEvent eventType = [self surveyEventTypeFromNotification:notification];
	if (eventType == ATSurveyEventAnsweredQuestion) {
		[self addMetricWithName:ATMetricNameSurveyAnswerQuestion info:info];
	}
	
	[info release], info = nil;
}

- (void)appWillTerminate:(NSNotification *)notification {
	[[ATEngagementBackend sharedBackend] engageApptentiveAppEvent:ATInteractionAppEventLabelExit userInfo:nil];
}

- (void)appDidEnterBackground:(NSNotification *)notification {
	[[ATEngagementBackend sharedBackend] engageApptentiveAppEvent:ATInteractionAppEventLabelExit userInfo:nil];
}

- (void)appWillEnterForeground:(NSNotification *)notification {
	[[ATEngagementBackend sharedBackend] engageApptentiveAppEvent:ATInteractionAppEventLabelLaunch userInfo:nil];
}

- (void)messageCenterDidLaunch:(NSNotification *)notification {
	[self addMetricWithName:ATMetricNameMessageCenterLaunch info:nil];
}

- (void)messageCenterDidClose:(NSNotification *)notification {
	[self addMetricWithName:ATMetricNameMessageCenterClose info:nil];
}

- (void)messageCenterDidAttach:(NSNotification *)notification {
	[self addMetricWithName:ATMetricNameMessageCenterAttach info:nil];
}

- (void)messageCenterDidRead:(NSNotification *)notification {
	NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
	NSString *messageID = [[notification userInfo] objectForKey:ATMessageCenterMessageIDKey];
	if (messageID != nil) {
		info[@"message_id"] = messageID;
	}
	[self addMetricWithName:ATMetricNameMessageCenterRead info:info];
	[info release], info = nil;
}

- (void)messageCenterDidSend:(NSNotification *)notification {
	NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
	NSString *nonce = [[notification userInfo] objectForKey:ATMessageCenterMessageNonceKey];
	if (nonce != nil) {
		info[@"nonce"] = nonce;
	}
	[self addMetricWithName:ATMetricNameMessageCenterSend info:info];
	[info release], info = nil;
}

- (void)messageCenterIntroDidLaunch:(NSNotification *)notification {
	[self addMetricWithName:ATMetricNameMessageCenterIntroLaunch info:nil];
}

- (void)messageCenterIntroDidSend:(NSNotification *)notification {
	NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
	NSString *nonce = [[notification userInfo] objectForKey:ATMessageCenterMessageNonceKey];
	if (nonce != nil) {
		info[@"nonce"] = nonce;
	}
	[self addMetricWithName:ATMetricNameMessageCenterIntroSend info:info];
	[info release], info = nil;
}

- (void)messageCenterIntroDidCancel:(NSNotification *)notification {
	[self addMetricWithName:ATMetricNameMessageCenterIntroCancel info:nil];
}

- (void)messageCenterIntroThankYouDidLaunch:(NSNotification *)notification {
	[self addMetricWithName:ATMetricNameMessageCenterThankYouLaunch info:nil];
}

- (void)messageCenterIntroThankYouHitMessages:(NSNotification *)notification {
	[self addMetricWithName:ATMetricNameMessageCenterThankYouMessages info:nil];
}

- (void)messageCenterIntroThankYouDidClose:(NSNotification *)notification {
	[self addMetricWithName:ATMetricNameMessageCenterThankYouClose info:nil];
}

- (void)preferencesChanged:(NSNotification *)notification {
	[self updateWithCurrentPreferences];
}

- (void)updateWithCurrentPreferences {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	NSNumber *enabled = [defaults objectForKey:ATAppConfigurationMetricsEnabledPreferenceKey];
	if (enabled) {
		metricsEnabled = [enabled boolValue];
	}
}
@end
