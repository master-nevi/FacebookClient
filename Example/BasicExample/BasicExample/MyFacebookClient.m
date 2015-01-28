//
//  MyFacebookClient.m
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

#import "MyFacebookClient.h"
#import <FacebookSDK/FacebookSDK.h>
#import "FacebookClient_Protected.h"

@implementation MyFacebookClient

+ (NSArray *)readPermissionsForLogin {
    return @[@"public_profile", @"email", @"user_friends"];
}

+ (FCRetryableFBRequestConnection *)postMessageToOwnWallWithMessage:(NSString *)message completion:(FCFacebookAPICompletionHandler)completion {
    BOOL usePassiveBehavior = NO;
    
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if ( message ) {
        [params setValue:message forKey:@"message"];
    }
    FBRequest *request = [FBRequest requestWithGraphPath:@"me/feed" parameters:params HTTPMethod:@"POST"];
    
    FCRetryableFBRequestConnection *connection = [self performRequest:request isRead:NO usePassiveBehavior:usePassiveBehavior completion:^(id result, NSError *error) {
        if (!error && result && [result valueForKey:@"id"]) {
            if (completion) {
                completion([result valueForKey:@"id"], nil);
            }
        }
        else {
            if (completion) {
                completion(nil, error);
            }
        }
    }];
    
    return connection;
}

+ (FCRetryableFBRequestConnection *)getFriendsWithCompletion:(FCFacebookAPICompletionHandler)completion {
    BOOL usePassiveBehavior = NO;
    
    FBRequest *request = [FBRequest requestWithGraphPath:@"me/friends" parameters:nil HTTPMethod:nil];
    
    FCRetryableFBRequestConnection *connection = [self performRequest:request isRead:YES usePassiveBehavior:usePassiveBehavior completion:completion];
    
    return connection;
}

@end
