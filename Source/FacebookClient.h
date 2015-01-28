//
//  FacebookClient.h
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

#import <Foundation/Foundation.h>

// Doubles as umbrella header
#import "NSError+FCError.h"
#import "FCRetryableFBRequestConnection.h"

@class FCRetryableFBRequestConnection;
@class FBRequest;
@class FBSession;

typedef void (^FCLoginCompletionHandler)(id profile, NSError *error);
typedef void (^FCRequestPermissionCompletionHandler)(NSError *error);
typedef void (^FCFacebookAPICompletionHandler)(id result, NSError *error);
typedef void (^FCFacebookSessionOperation)(FBSession *activeSession);

@interface FacebookClient : NSObject

#pragma mark - Configuration

+ (void)configureFacebookWithApplicationID:(NSString *)applicationID useV1:(BOOL)useV1; // this could be the first method called and performed on the same operation queue as the session queue.

#pragma mark - Session thread handling

+ (NSOperationQueue *)sessionQueue;
+ (void)performFacebookSessionOperation:(FCFacebookSessionOperation)facebookSessionOperation;

#pragma mark - Open URL

+ (BOOL)handleOpenURL:(NSURL *)url sourceApplication:(id)sourceApplication;

#pragma mark - Login

+ (void)logInWithCompletion:(FCLoginCompletionHandler)completion;
+ (void)logInWithUsePassiveBehavior:(BOOL)usePassiveBehavior completion:(FCLoginCompletionHandler)completion;
+ (void)logOut;
+ (BOOL)isLoggedIn;
+ (void)loginGateWithUsePassiveBehavior:(BOOL)usePassiveBehavior taskRequiringLogin:(void (^)(BOOL loggedIn))taskRequiringLogin;

#pragma mark - User profile

+ (FCRetryableFBRequestConnection *)getUserProfileWithCompletion:(FCFacebookAPICompletionHandler)completion;
+ (FCRetryableFBRequestConnection *)getUserProfileWithUsePassiveBehavior:(BOOL)usePassiveBehavior completion:(FCFacebookAPICompletionHandler)completion;

#pragma mark - Permissions

+ (void)requestReadPermissions:(NSSet *)readPermissions usePassiveBehavior:(BOOL)usePassiveBehavior completion:(FCRequestPermissionCompletionHandler)completion;
+ (void)requestPublishPermissions:(NSSet *)publishPermissions usePassiveBehavior:(BOOL)usePassiveBehavior completion:(FCRequestPermissionCompletionHandler)completion;

#pragma mark - Core request method

+ (FCRetryableFBRequestConnection *)performRequest:(FBRequest *)request isRead:(BOOL)isRead usePassiveBehavior:(BOOL)usePassiveBehavior completion:(FCFacebookAPICompletionHandler)completion;

@end
