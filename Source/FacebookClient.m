//
//  FacebookClient.m
//
//  Copyright (c) 2015 David Robles
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

#import "FacebookClient.h"
#import <FacebookSDK/FacebookSDK.h>
#import "FCRetryableFBRequestConnection.h"
#import "NSError+FCError.h"

#define MAX_API_CALL_ATTEMPTS 2

static NSString *const kHasPreviouslyRequestedPublishPermissionsKey = @"FCHasPreviouslyRequestedPublishPermissionsKey";
static NSString *const kHasPreviouslyRequestedReadPermissionsKey = @"FCHasPreviouslyRequestedReadPermissionsKey";
static NSOperationQueue *sessionQueue = nil;

@implementation FacebookClient

#pragma mark - External API

#pragma mark - Configuration

+ (void)configureFacebookWithApplicationID:(NSString *)applicationID useV1:(BOOL)useV1 {
    [FBSettings enablePlatformCompatibility:useV1];
    [FBSettings setDefaultAppID:applicationID]; // allows us to use [FBSession openActiveSessionWithAllowLoginUI:] method. An alternative is to set the FacebookAppID key in the app bundle *.plist, this method was chosen to less pollute the bundle *.plist.
    
    NSAssert([[NSOperationQueue currentQueue] isEqual:[self sessionQueue]], @"This method should be called on the same queue reserved for dispatching FBSession operations to prevent race conditions.");
    if (![[NSOperationQueue currentQueue] isEqual:[self sessionQueue]]) {
        [[self sessionQueue] addOperationWithBlock:^{
            [FBSession activeSession];
        }];
    }
    
    [FBSession activeSession]; // initialize the fb session on a known queue
}

#pragma mark - Session thread handling

+ (NSOperationQueue *)sessionQueue {
    if (!sessionQueue) {
        sessionQueue = [NSOperationQueue mainQueue]; // use the main queue for FBSession operations
    }
    
    return sessionQueue;
}

+ (void)performFacebookSessionOperation:(FCFacebookSessionOperation)facebookSessionOperation {
    if (!facebookSessionOperation) {
        return;
    }
    
    [[self sessionQueue] addOperationWithBlock:^{
        FBSession *activeSession = [FBSession activeSession];
        
        facebookSessionOperation(activeSession);
    }];
}

#pragma mark - Open URL

+ (BOOL)handleOpenURL:(NSURL *)url sourceApplication:(id)sourceApplication {
    return [FBAppCall handleOpenURL:url sourceApplication:sourceApplication];
}

#pragma mark - Permissions

+ (NSSet *)readPermissionsForLogin {
    return [NSSet setWithArray:@[@"basic_info"]];
}

+ (NSSet *)allReadPermissions {
    return [self readPermissionsForLogin];
}

+ (NSSet *)allPublishPermissions {
    return [NSSet setWithArray:@[@"publish_actions"]];
}

#pragma mark - Login

+ (void)logInWithCompletion:(FCLoginCompletionHandler)completion {
    BOOL defaultUsePassiveBehavior = NO;
    [self logInWithUsePassiveBehavior:defaultUsePassiveBehavior completion:completion];
}

+ (void)logInWithUsePassiveBehavior:(BOOL)usePassiveBehavior completion:(FCLoginCompletionHandler)completion {
    [self performFacebookSessionOperation:^(FBSession *activeSession) {
        // attempt to synchronously open active session using cached token
        [FBSession openActiveSessionWithAllowLoginUI:NO];
        
        // passively fetch user profile data, this will also provide reassurrence that if the session was reopened from cache but is actually expired on the server, that the token will be cleared everywhere including the integrated iOS Facebook token cache
        [FBRequestConnection startForMeWithCompletionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
            // success on first try
            if (!error && result) {
                if (completion) {
                    completion(result, nil);
                }
                
                return;
            }
            
            // handle failure
            if (usePassiveBehavior) {
                // The passive login behavior is to attempt a synchronous session open without presenting the login UI. As this was done above and an error has occurred, it would take a non-passive login procedure (such as presenting the login UI) to go any further than this point, therefore return an error.
                if (completion) {
                    completion(nil, [self createErrorWithUsePassiveBehavior:usePassiveBehavior]);
                }
            }
            else {
                [self performLoginFlowWithUsePassiveBehavior:usePassiveBehavior canRetry:YES completion:completion];
            }
        }];
    }];
}

/* Discussion: 
 A retry is made available to ensure we weren't able to log in because of an expired local token cache which could exist as part of the internal iOS facebook integration or the facebook app itself. This method is designed to only be called a max of 2 times in a row. Performing it the first time will ensure that every part of the flow is up to date, and the second will retry with all the token cached in sync.
 */
+ (void)performLoginFlowWithUsePassiveBehavior:(BOOL)usePassiveBehavior canRetry:(BOOL)canRetry completion:(FCLoginCompletionHandler)completion {
    [self performFacebookSessionOperation:^(FBSession *activeSession) {
        /*
         Discussion: [FBSession openActiveSessionWithReadPermissions:allowLoginUI:completionHandler:] oddly retains it's completion handler in order to call it again if the state of the login changes during a query to Facebook; it is also called again when a permissions request returns. This is very unexpected behavior as completion blocks are normally called once per use of an API. Since the current implementation of this class expects the completion handler to only be called once per use, we unfortunately have to ensure this with a __block BOOL.
         */
        __block BOOL loginCompletionHandlerCalledAlready = NO;
        
        // if allowLoginUI is true, we are gauranteed that the user will be logged in asynchronously and completion handler will be called. In other cases the completion handler may not be called.
        [FBSession openActiveSessionWithReadPermissions:[[self readPermissionsForLogin] allObjects] allowLoginUI:YES completionHandler:^(FBSession *session, FBSessionState status, NSError *openActiveSessionError) {
            if (loginCompletionHandlerCalledAlready) {
                return;
            }
            
            loginCompletionHandlerCalledAlready = YES;
            
            if (openActiveSessionError) {
                [self handleAuthError:openActiveSessionError usePassiveBehavior:usePassiveBehavior completion:completion];
            }
            else {
                if (FB_ISSESSIONOPENWITHSTATE(status)) {
                    [FBRequestConnection startForMeWithCompletionHandler:^(FBRequestConnection *connection, id result, NSError *getProfileError) {
                        if (getProfileError && canRetry) {
                            [self performLoginFlowWithUsePassiveBehavior:usePassiveBehavior canRetry:NO completion:completion];
                            return;
                        }
                        
                        if (completion) {
                            getProfileError ? completion(nil, [self createErrorWithUsePassiveBehavior:usePassiveBehavior]) : completion(result, nil);
                        }
                    }];
                }
                else {
                    if (completion) {
                        completion(nil, [self createErrorWithUsePassiveBehavior:usePassiveBehavior]);
                    }
                }
            }
        }];
    }];
}

+ (void)logOut {
    [self performFacebookSessionOperation:^(FBSession *activeSession) {
        [FBSession.activeSession closeAndClearTokenInformation];
    }];
}

+ (BOOL)isLoggedIn {
    return FBSession.activeSession.isOpen;
}

+ (void)loginGateWithUsePassiveBehavior:(BOOL)usePassiveBehavior taskRequiringLogin:(void (^)(BOOL loggedIn))taskRequiringLogin {
    if ([self isLoggedIn]) {
        taskRequiringLogin(YES);
    }
    else {
        [self logInWithUsePassiveBehavior:usePassiveBehavior completion:^(id profile, NSError *error) {
            if (error) {
                taskRequiringLogin(NO);
            } else {
                taskRequiringLogin(YES);
            }
        }];
    }
}

#pragma mark - User profile

+ (FCRetryableFBRequestConnection *)getUserProfileWithCompletion:(FCFacebookAPICompletionHandler)completion {
    BOOL defaultUsePassiveBehavior = YES;
    return [self getUserProfileWithUsePassiveBehavior:defaultUsePassiveBehavior completion:completion];
}

+ (FCRetryableFBRequestConnection *)getUserProfileWithUsePassiveBehavior:(BOOL)usePassiveBehavior completion:(FCFacebookAPICompletionHandler)completion {
    FBRequest *request = [FBRequest requestForMe];
    FCRetryableFBRequestConnection *connection = [self performRequest:request isRead:YES usePassiveBehavior:usePassiveBehavior completion:completion];
    
    return connection;
}

#pragma mark - Core request method

+ (FCRetryableFBRequestConnection *)performRequest:(FBRequest *)request isRead:(BOOL)isRead usePassiveBehavior:(BOOL)usePassiveBehavior completion:(FCFacebookAPICompletionHandler)completion {
    BOOL requestIsRead = !([request.HTTPMethod isEqualToString:@"POST"] || [request.HTTPMethod isEqualToString:@"DELETE"]);
    if (isRead) {
        NSAssert(requestIsRead, @"Must be a GET request");
    }
    else {
        NSAssert(!requestIsRead, @"Must be a POST request");
    }
    
    FCRetryableFBRequestConnection *connection = [FCRetryableFBRequestConnection new];
    
    [self loginGateWithUsePassiveBehavior:usePassiveBehavior taskRequiringLogin:^(BOOL loggedIn) {
        if (loggedIn) {
            [connection addRequest:request completionHandler:^(NSInteger attempts, FCRetryableFBRequestConnection *connection, id result, NSError *error) {
                if (error) {
                    void (^retryBlock)(void) = attempts < MAX_API_CALL_ATTEMPTS ? ^{
                        [connection retry];
                    } : nil;
                    
                    if (isRead) {
                        [self handleReadAPICallError:error usePassiveBehavior:usePassiveBehavior retryBlock:retryBlock completion:completion];
                    }
                    else {
                        [self handlePublishAPICallError:error usePassiveBehavior:usePassiveBehavior retryBlock:retryBlock completion:completion];
                    }
                }
                else {
                    if (completion) {
                        completion(result, nil);
                    }
                }
            }];
            
            [connection start];
        }
        else {
            if (completion) {
                completion(nil, [self createErrorWithUsePassiveBehavior:usePassiveBehavior]);
            }
        }
    }];
    
    return connection;
}

#pragma mark - Internal lib

#pragma mark - Error handling

+ (NSError *)createErrorWithUsePassiveBehavior:(BOOL)usePassiveBehavior {
    return [self createErrorWithUserInfo:nil usePassiveBehavior:usePassiveBehavior];
}

+ (NSError *)createErrorWithMessage:(NSString *)message usePassiveBehavior:(BOOL)usePassiveBehavior {
    return [self createErrorWithUserInfo:@{NSLocalizedDescriptionKey: message} usePassiveBehavior:usePassiveBehavior];
}

+ (NSError *)createErrorWithUserInfo:(NSDictionary *)userInfo usePassiveBehavior:(BOOL)usePassiveBehavior {
    NSError *error = [NSError errorWithDomain:@"AZFacebookClient" code:0 userInfo:userInfo];
    error.shouldInformUser = !usePassiveBehavior;
    return error;
}

// terminates request
+ (void)handleAuthError:(NSError *)error usePassiveBehavior:(BOOL)usePassiveBehavior completion:(FCLoginCompletionHandler)completion {
    NSString *alertMessage, *alertTitle;
    
    error.shouldInformUser = !usePassiveBehavior;
    
    if (error.fberrorShouldNotifyUser) {
        // If the SDK has a message for the user, surface it.
        alertTitle = @"Something Went Wrong";
        alertMessage = error.fberrorUserMessage;
    } else if (error.fberrorCategory == FBErrorCategoryAuthenticationReopenSession) {
        // It is important to handle session closures since they can happen
        // outside of the app. You can inspect the error for more context
        // but this sample generically notifies the user.
        alertTitle = @"Session Error";
        alertMessage = @"Your current session is no longer valid. Please log in again.";
    } else if (error.fberrorCategory == FBErrorCategoryUserCancelled) {
        // The user has cancelled a login. You can inspect the error
        // for more context. For this sample, we will simply ignore it.
        NSLog(@"user cancelled login");
        
        error.shouldInformUser = NO; // no need to bother the user for explicit errors like cancelling
    } else {
        // For simplicity, this sample treats other errors blindly.
        alertTitle  = @"Unknown Error";
        alertMessage = @"Error. Please try again later.";
        NSLog(@"Unexpected error:%@", error);
    }
    
    if (alertMessage && !usePassiveBehavior) {
        [[[UIAlertView alloc] initWithTitle:alertTitle
                                    message:alertMessage
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
        
        error.shouldInformUser = NO; // user has already been informed
    }
    
    if (completion) {
        completion(nil, error);
    }
}

// terminates request
+ (void)handleReadPermissionRequestError:(NSError *)error usePassiveBehavior:(BOOL)usePassiveBehavior completion:(FCRequestPermissionCompletionHandler)completion {
    NSString *alertMessage, *alertTitle;
    
    error.shouldInformUser = !usePassiveBehavior;
    
    if (error.fberrorShouldNotifyUser) {
        // If the SDK has a message for the user, surface it.
        alertTitle = @"Something Went Wrong";
        alertMessage = error.fberrorUserMessage;
    } else {
        if (error.fberrorCategory == FBErrorCategoryUserCancelled){
            // The user has cancelled the request. You can inspect the value and
            // inner error for more context. Here we simply ignore it.
            NSLog(@"User cancelled post permissions.");
            
            error.shouldInformUser = NO; // no need to bother the user for explicit errors like cancelling
        } else {
            alertTitle = @"Permission Error";
            alertMessage = @"Unable to acquire publish permissions";
        }
    }
    
    if (alertMessage && !usePassiveBehavior) {
        [[[UIAlertView alloc] initWithTitle:alertTitle
                                    message:alertMessage
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
        
        error.shouldInformUser = NO; // user has already been informed
    }
    
    if (completion) {
        completion(error);
    }
}

// request may repeat
+ (void)handleReadAPICallError:(NSError *)error usePassiveBehavior:(BOOL)usePassiveBehavior retryBlock:(void (^)(void))retryBlockOrNil completion:(FCFacebookAPICompletionHandler)completion {
    error.shouldInformUser = !usePassiveBehavior;
    
    // Some Graph API errors are retriable. For this sample, we will have a simple
    // retry policy of one additional attempt.
    if (error.fberrorCategory == FBErrorCategoryRetry ||
        error.fberrorCategory == FBErrorCategoryThrottling) {
        // We also retry on a throttling error message. A more sophisticated app
        // should consider a back-off period.
        if (retryBlockOrNil) {
            NSLog(@"Retrying API call");
            // Recovery tactic: Call API again.
            retryBlockOrNil();
            return;
        }
    }
    
    // People can revoke post permissions on your app externally so it
    // can be worthwhile to request for permissions again at the point
    // that they are needed. This sample assumes a simple policy
    // of re-requesting permissions.
    if (error.fberrorCategory == FBErrorCategoryPermissions) {
        NSLog(@"Re-requesting permissions");
        // Recovery tactic: Ask for required permissions.
        [self requestReadPermissions:[self allReadPermissions] usePassiveBehavior:usePassiveBehavior completion:^(NSError *readPermissionsRequestError) {
            if (!readPermissionsRequestError && retryBlockOrNil) {
                retryBlockOrNil();
            }
            else {
                if (completion) {
                    completion(nil, readPermissionsRequestError);
                }
            }
        }];
        return;
    }
    
    // Users may remove facebook application from their settings while the client remains unaware of this change. Checking for this error category and attempting to reauthenticate provides a chance for recovery from this scenario.
    if (error.fberrorCategory == FBErrorCategoryAuthenticationReopenSession) {
        [self logInWithUsePassiveBehavior:usePassiveBehavior completion:^(id profile, NSError *error) {
            if (error) {
                if (completion) {
                    completion(nil, error);
                }
            }
            else {
                retryBlockOrNil();
            }
        }];
        return;
    }
    
    NSString *alertTitle, *alertMessage;
    if (error.fberrorShouldNotifyUser) {
        // If the SDK has a message for the user, surface it.
        alertTitle = @"Something Went Wrong";
        alertMessage = error.fberrorUserMessage;
    } else {
        NSLog(@"Unexpected error posting to open graph: %@", error);
        alertTitle = @"Unknown error";
        alertMessage = @"Unable to get data from Facebook. Please try again later.";
    }
    
    if (alertMessage && !usePassiveBehavior) {
        [[[UIAlertView alloc] initWithTitle:alertTitle
                                    message:alertMessage
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
        
        error.shouldInformUser = NO; // user has already been informed
    }
    
    if (completion) {
        completion(nil, error);
    }
}

// terminates request
+ (void)handlePublishPermissionRequestError:(NSError *)error usePassiveBehavior:(BOOL)usePassiveBehavior completion:(FCRequestPermissionCompletionHandler)completion {
    NSString *alertMessage, *alertTitle;
    
    error.shouldInformUser = !usePassiveBehavior;
    
    if (error.fberrorShouldNotifyUser) {
        // If the SDK has a message for the user, surface it.
        alertTitle = @"Something Went Wrong";
        alertMessage = error.fberrorUserMessage;
    } else {
        if (error.fberrorCategory == FBErrorCategoryUserCancelled){
            // The user has cancelled the request. You can inspect the value and
            // inner error for more context. Here we simply ignore it.
            NSLog(@"User cancelled post permissions.");
            
            error.shouldInformUser = NO; // no need to bother the user for explicit errors like cancelling
        } else {
            alertTitle = @"Permission Error";
            alertMessage = @"Unable to request publish permissions";
        }
    }
    
    if (alertMessage && !usePassiveBehavior) {
        [[[UIAlertView alloc] initWithTitle:alertTitle
                                    message:alertMessage
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
        
        error.shouldInformUser = NO; // user has already been informed
    }
    
    if (completion) {
        completion(error);
    }
}

// request may repeat
+ (void)handlePublishAPICallError:(NSError *)error usePassiveBehavior:(BOOL)usePassiveBehavior retryBlock:(void (^)(void))retryBlockOrNil completion:(FCFacebookAPICompletionHandler)completion {
    error.shouldInformUser = !usePassiveBehavior;
    
    // Some Graph API errors are retriable. For this sample, we will have a simple
    // retry policy of one additional attempt.
    if (error.fberrorCategory == FBErrorCategoryRetry ||
        error.fberrorCategory == FBErrorCategoryThrottling) {
        // We also retry on a throttling error message. A more sophisticated app
        // should consider a back-off period.
        if (retryBlockOrNil) {
            NSLog(@"Retrying open graph post");
            // Recovery tactic: Call API again.
            retryBlockOrNil();
            return;
        }
    }
    
    // People can revoke post permissions on your app externally so it
    // can be worthwhile to request for permissions again at the point
    // that they are needed. This sample assumes a simple policy
    // of re-requesting permissions.
    if (error.fberrorCategory == FBErrorCategoryPermissions) {
        NSLog(@"Re-requesting permissions");
        // Recovery tactic: Ask for required permissions.
        [self requestPublishPermissions:[self allPublishPermissions] usePassiveBehavior:usePassiveBehavior completion:^(NSError * publishPermissionsRequestError) {
            if (!publishPermissionsRequestError && retryBlockOrNil) {
                retryBlockOrNil();
            }
            else {
                if (completion) {
                    completion(nil, publishPermissionsRequestError);
                }
            }
        }];
        return;
    }
    
    // Users may remove facebook application from their settings while the client remains unaware of this change. Checking for this error category and attempting to reauthenticate provides a chance for recovery from this scenario.
    if (error.fberrorCategory == FBErrorCategoryAuthenticationReopenSession) {
        [self logInWithUsePassiveBehavior:usePassiveBehavior completion:^(id profile, NSError *error) {
            if (error) {
                if (completion) {
                    completion(nil, error);
                }
            }
            else {
                retryBlockOrNil();
            }
        }];
        return;
    }
    
    NSString *alertTitle, *alertMessage;
    if (error.fberrorShouldNotifyUser) {
        // If the SDK has a message for the user, surface it.
        alertTitle = @"Something Went Wrong";
        alertMessage = error.fberrorUserMessage;
    } else {
        NSLog(@"Unexpected error posting to open graph: %@", error);
        alertTitle = @"Unknown error";
        alertMessage = @"Unable to post to open graph. Please try again later.";
    }
    
    if (alertMessage && !usePassiveBehavior) {
        [[[UIAlertView alloc] initWithTitle:alertTitle
                                    message:alertMessage
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
        
        error.shouldInformUser = NO; // user has already been informed
    }
    
    if (completion) {
        completion(nil, error);
    }
}

#pragma mark - Error handling support methods

+ (void)requestReadPermissions:(NSSet *)readPermissions usePassiveBehavior:(BOOL)usePassiveBehavior completion:(FCRequestPermissionCompletionHandler)completion {
    BOOL hasPreviouslyRequestedReadPermissions = [[[NSUserDefaults standardUserDefaults] objectForKey:kHasPreviouslyRequestedReadPermissionsKey] boolValue];
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:YES] forKey:kHasPreviouslyRequestedReadPermissionsKey];
    
    // prevent passive read actions from asking for read permissions over and over.
    if (hasPreviouslyRequestedReadPermissions && usePassiveBehavior) {
        if (completion) {
            completion([self createErrorWithUsePassiveBehavior:usePassiveBehavior]);
        }
        return;
    }
    
    [FBSession.activeSession requestNewReadPermissions:[readPermissions allObjects] completionHandler:^(FBSession *session, NSError *error) {
        // It's possible to not receive an error and not acquire the desired set of permissions. I.e. publish permission request when user authenticates with facebook using the native Facebook app login flow as well as the Facebook.com via Safari app login flow.
        if (!error) {
            NSSet *currentPermissions = [NSSet setWithArray:[[session.accessTokenData dictionary] objectForKey:FBTokenInformationPermissionsKey]];
            NSSet *desiredPermissions = readPermissions;
            BOOL permissionAcquired = [desiredPermissions isSubsetOfSet:currentPermissions];
            
            if (!permissionAcquired) {
                error = [self createErrorWithUsePassiveBehavior:usePassiveBehavior];
            }
        }
        
        if (error) {
            [self handleReadPermissionRequestError:error usePassiveBehavior:usePassiveBehavior completion:completion];
        }
        else {
            if (completion) {
                completion(nil);
            }
        }
    }];
}

+ (void)requestPublishPermissions:(NSSet *)publishPermissions usePassiveBehavior:(BOOL)usePassiveBehavior completion:(FCRequestPermissionCompletionHandler)completion {
    BOOL hasPreviouslyRequestedPublishPermissions = [[[NSUserDefaults standardUserDefaults] objectForKey:kHasPreviouslyRequestedPublishPermissionsKey] boolValue];
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:YES] forKey:kHasPreviouslyRequestedPublishPermissionsKey];
    
    // prevent passive publish actions from asking for publish permissions over and over.
    if (hasPreviouslyRequestedPublishPermissions && usePassiveBehavior) {
        if (completion) {
            completion([self createErrorWithUsePassiveBehavior:usePassiveBehavior]);
        }
        return;
    }
    
    [FBSession.activeSession requestNewPublishPermissions:[publishPermissions allObjects] defaultAudience:FBSessionDefaultAudienceEveryone completionHandler:^(FBSession *session, NSError *error) {
        // It's possible to not receive an error and not acquire the desired set of permissions. I.e. publish permission request when user authenticates with facebook using the native Facebook app login flow as well as the Facebook.com via Safari app login flow.
        if (!error) {
            NSSet *currentPermissions = [NSSet setWithArray:[[session.accessTokenData dictionary] objectForKey:FBTokenInformationPermissionsKey]];
            NSSet *desiredPermissions = publishPermissions;
            BOOL permissionAcquired = [desiredPermissions isSubsetOfSet:currentPermissions];
            
            if (!permissionAcquired) {
                error = [self createErrorWithUsePassiveBehavior:usePassiveBehavior];
            }
        }
        
        if (error) {
            [self handlePublishPermissionRequestError:error usePassiveBehavior:usePassiveBehavior completion:completion];
        }
        else {
            if (completion) {
                completion(nil);
            }
        }
    }];
}

@end
