//
//  ViewController.m
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

#import "ViewController.h"
#import <FacebookSDK/FacebookSDK.h>
#import "NSError+FCError.h"
#import "MyFacebookClient.h"

@interface ViewController ()

@end

@implementation ViewController {
    __weak IBOutlet UITextField *_appIdField;
    __weak IBOutlet UIButton *_logInButton;
    __weak IBOutlet UITextField *_postField;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    UITapGestureRecognizer *tapToDismiss = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    [self.view addGestureRecognizer:tapToDismiss];
    
    NSString *lastUsedFacebookAppID = [[NSUserDefaults standardUserDefaults] stringForKey:@"lastUsedFacebookID"];
    if (lastUsedFacebookAppID.length) {
        _appIdField.text = lastUsedFacebookAppID;
        [MyFacebookClient configureFacebookWithApplicationID:lastUsedFacebookAppID useV1:NO];
        
        [MyFacebookClient logInWithUsePassiveBehavior:YES completion:^(id profile, NSError *error) {
            BOOL accessGranted = error ? NO : YES;
            NSLog(@"Facebook status: %@", accessGranted ? @"Access granted" : @"Access denied");
            [_logInButton setSelected:accessGranted];
        }];
    }
}

#pragma mark - IBActions

- (IBAction)linkWithFacebookButtonTapped:(id)sender {
    [sender setSelected:![sender isSelected]];
    
    NSString *facebookAppID = _appIdField.text;
    if (facebookAppID.length) {
        [[NSUserDefaults standardUserDefaults] setObject:facebookAppID forKey:@"lastUsedFacebookID"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [MyFacebookClient configureFacebookWithApplicationID:facebookAppID useV1:NO];
    }
    
    BOOL isAttemptingLogIn = [sender isSelected];
    
    if (isAttemptingLogIn) {
        [MyFacebookClient logInWithCompletion:^(id profile, NSError *error) {
            if (error) {
                [sender setSelected:NO];
                
                if (error.shouldInformUser) {
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Facebook"
                                                                    message:@"Login failed!\nPlease try again."
                                                                   delegate:self
                                                          cancelButtonTitle:@"OK" otherButtonTitles:nil];
                    [alert show];
                }
            }
            else {
                NSLog(@"%@", profile);
            }
        }];
    }
    else {
        [FacebookClient logOut];
    }
    
}

- (IBAction)getUserNameButtonTapped:(id)sender {
    [MyFacebookClient getUserProfileWithUsePassiveBehavior:NO completion:^(id result, NSError *error) {
        NSLog(@"%@", [result description]);
    }];
}

- (IBAction)postToWallButtonTapped:(id)sender {
    [MyFacebookClient postMessageToOwnWallWithMessage:_postField.text completion:^(id result, NSError *error) {
        NSLog(@"%@", [result description]);
    }];
}

- (IBAction)logFriendsButtonTapped:(id)sender {
    [MyFacebookClient getFriendsWithCompletion:^(id result, NSError *error) {
        NSLog(@"%@", [result description]);
    }];
}

#pragma mark - Internal lib

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

@end
