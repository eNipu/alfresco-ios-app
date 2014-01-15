//
//  Account.h
//  AlfrescoApp
//
//  Created by Tauseef Mughal on 16/09/2013.
//  Copyright (c) 2013 Alfresco. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AccountCertificate.h"

typedef NS_ENUM(NSInteger, UserAccountType)
{
    UserAccountTypeOnPremise = 0,
    UserAccountTypeCloud
};

typedef NS_ENUM(NSInteger, UserAccountStatus)
{
    UserAccountStatusActive,
    UserAccountStatusAwaitingVerification,
    UserAccountStatusConnectionError,
    UserAccountStatusInvalidCredentials
};

@interface UserAccount : NSObject <NSCoding, NSCopying>

@property (nonatomic, strong, readonly) NSString *accountIdentifier;
@property (nonatomic, strong) NSString *username;
@property (nonatomic, strong) NSString *password;
@property (nonatomic, strong) NSString *accountDescription;
@property (nonatomic, strong) NSString *serverAddress;
@property (nonatomic, strong) NSString *serverPort;
@property (nonatomic, strong) NSString *protocol;
@property (nonatomic, strong) NSString *serviceDocument;
@property (nonatomic, assign) UserAccountType accountType;
@property (nonatomic, strong) AlfrescoOAuthData *oauthData;
@property (nonatomic, strong) AccountCertificate *accountCertificate;
@property (nonatomic, assign) BOOL isSelectedAccount;
@property (nonatomic, strong) NSString *selectedNetworkId;
@property (nonatomic, strong) NSArray *accountNetworks;
@property (nonatomic, assign) UserAccountStatus accountStatus;

// cloud signup specific properties, needed for refreshing Account Statuses and resending signup request
@property (nonatomic, strong) NSString *firstName;
@property (nonatomic, strong) NSString *lastName;
@property (nonatomic, strong) NSString *cloudAccountId;
@property (nonatomic, strong) NSString *cloudAccountKey;

- (instancetype)initWithAccountType:(UserAccountType)accountType;

@end