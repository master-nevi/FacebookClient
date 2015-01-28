//
//  FCRetryableFBRequestConnection.m
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

#import "FCRetryableFBRequestConnection.h"
#import <FacebookSDK/FBRequest.h>
#import <FacebookSDK/FBSession.h>

@interface RetryableFBRequestMetadata : NSObject

@property (nonatomic) FBRequest *request;
@property (nonatomic, copy) RetryableFBRequestHandler completionHandler;

- (instancetype)initWithRequest:(FBRequest *)request completionHandler:(RetryableFBRequestHandler)handler;

@end

@implementation RetryableFBRequestMetadata

- (instancetype)initWithRequest:(FBRequest *)request completionHandler:(RetryableFBRequestHandler)handler {
    
    if (self = [super init]) {
        self.request = request;
        self.completionHandler = handler;
    }
    return self;
}

@end

@implementation FCRetryableFBRequestConnection {
    FBRequestConnection *_connection;
    BOOL _inProgress;
    NSInteger _attempts;
    NSMutableArray *_requests;
    FCRetryableFBRequestConnection *_keepSelf; // keep strong reference until [first] async callback from Facebook
}

#pragma mark - External API

- (instancetype)init {
    if (self = [super init]) {
        _connection = [[FBRequestConnection alloc] init];
        _requests = [NSMutableArray array];
    }
    return self;
}

//- (void)dealloc {
//    if ([_requests count]) {
//        RetryableFBRequestMetadata *firstRequest = _requests[0];
//        NSLog(@"Deallocating connection for request: %@", firstRequest.request.description);
//    }
//}

- (void)addRequest:(FBRequest *)request completionHandler:(RetryableFBRequestHandler)handler {
    RetryableFBRequestMetadata *requestMetadata = [[RetryableFBRequestMetadata alloc] initWithRequest:request completionHandler:handler];
    [_requests addObject:requestMetadata];
    [self addRequestToConnection:_connection requestMetadata:requestMetadata];
}

- (void)start {
    _inProgress = YES;
    _attempts++;
    _keepSelf = self;
    
    [_connection start];
}

- (void)cancel {
    _inProgress = NO;
    
    [_connection cancel];
}

- (void)retry {
    NSAssert(!_inProgress, @"Cannot retry while a request is in progress");
    
    _connection = nil;
    
    _connection = [[FBRequestConnection alloc] init];
    
    for (RetryableFBRequestMetadata *requestMetadata in _requests) {
        FBRequest *request = requestMetadata.request;
        request.session = [FBSession activeSession];
        [self addRequestToConnection:_connection requestMetadata:requestMetadata];
    }
    
    [self start];
}

#pragma mark - Internal lib

- (void)addRequestToConnection:(FBRequestConnection *)connection requestMetadata:(RetryableFBRequestMetadata *)requestMetadata {
    __weak typeof(self) weakSelf = self;
    [connection addRequest:requestMetadata.request completionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        strongSelf->_inProgress = NO;
        if (requestMetadata.completionHandler) {
            requestMetadata.completionHandler(strongSelf->_attempts, strongSelf, result, error);
        }
        
        [strongSelf cleanUp];
    }];
}

- (void)cleanUp {
    _keepSelf = nil;
}

@end
