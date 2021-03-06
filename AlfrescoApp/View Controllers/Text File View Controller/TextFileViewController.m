/*******************************************************************************
 * Copyright (C) 2005-2014 Alfresco Software Limited.
 * 
 * This file is part of the Alfresco Mobile iOS App.
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *  
 *  http://www.apache.org/licenses/LICENSE-2.0
 * 
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 ******************************************************************************/
 
#import "TextFileViewController.h"
#import "UniversalDevice.h"
#import "UploadFormViewController.h"
#import "DownloadManager.h"
#import "SyncManager.h"
#import "MBProgressHud.h"
#import "ConnectivityManager.h"

static NSString * const kTextFileMimeType = @"text/plain";

@interface TextFileViewController () <NSFileManagerDelegate, UITextViewDelegate>

@property (nonatomic, strong) AlfrescoFolder *uploadDestinationFolder;
@property (nonatomic, strong) AlfrescoDocument *editingDocument;
@property (nonatomic, strong) NSString *documentContentPath;
@property (nonatomic, strong) id<AlfrescoSession> session;
@property (nonatomic, strong) AlfrescoDocumentFolderService *documentFolderService;
@property (nonatomic, weak) id<UploadFormViewControllerDelegate> uploadFormViewControllerDelegate;
@property (nonatomic, weak) UITextView *textView;
@property (nonatomic, strong) NSString *temporaryFilePath;

@end

@implementation TextFileViewController

- (instancetype)initWithUploadFileDestinationFolder:(AlfrescoFolder *)uploadFolder session:(id<AlfrescoSession>)session delegate:(id<UploadFormViewControllerDelegate>)delegate
{
    self = [self init];
    if (self)
    {
        self.uploadDestinationFolder = uploadFolder;
        self.session = session;
        self.uploadFormViewControllerDelegate = delegate;
        [self registerForNotifications];
    }
    return self;
}

- (instancetype)initWithEditDocument:(AlfrescoDocument *)document contentFilePath:(NSString *)contentPath session:(id<AlfrescoSession>)session
{
    self = [super init];
    if (self)
    {
        self.editingDocument = document;
        self.documentContentPath = contentPath;
        self.session = session;
        self.documentFolderService = [[AlfrescoDocumentFolderService alloc] initWithSession:self.session];
        [self registerForNotifications];
    }
    return self;
}

- (void)dealloc
{
    [self deleteTemporaryFile];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadView
{
    UIView *view = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    UITextView *textView = [[UITextView alloc] initWithFrame:view.frame];
    textView.delegate = self;
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view addSubview:textView];
    self.textView = textView;
    
    NSDictionary *views = NSDictionaryOfVariableBindings(textView);
    [view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|[textView]|" options:NSLayoutFormatAlignAllTop | NSLayoutFormatAlignAllBottom metrics:nil views:views]];
    [view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[textView]|" options:NSLayoutFormatAlignAllBaseline metrics:nil views:views]];
    
    view.autoresizesSubviews = YES;
    self.view = view;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.title = self.editingDocument ? self.editingDocument.name : NSLocalizedString(@"createtextfile.title", @"Create Text File");
    NSString *rightBarButtonTitle = self.editingDocument ? NSLocalizedString(@"document.edit.button.save", @"Save") : NSLocalizedString(@"Next", @"Next");
    NSString *leftBarButtonTitle = self.editingDocument ? NSLocalizedString(@"document.edit.button.discard", @"Discard") : NSLocalizedString(@"Cancel", @"Cancel");
    
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithTitle:leftBarButtonTitle style:UIBarButtonItemStylePlain target:self action:@selector(cancelButtonPressed:)];
    self.navigationItem.leftBarButtonItem = cancelButton;
    
    UIBarButtonItem *nextButton = [[UIBarButtonItem alloc] initWithTitle:rightBarButtonTitle style:UIBarButtonItemStylePlain target:self action:@selector(nextButtonPressed:)];
    self.navigationItem.rightBarButtonItem = nextButton;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    
    if (self.documentContentPath)
    {
        NSError *error = nil;
        NSString *fileContent = [[NSString alloc] initWithContentsOfFile:self.documentContentPath usedEncoding:NULL error:&error];
        if (!error)
        {
            self.textView.text = fileContent;
        }
    }
    
    [self createTemporaryFile];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.textView becomeFirstResponder];
    });
}

#pragma mark - Private Functions

- (void)registerForNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWasShown:) name:UIKeyboardDidShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)createTemporaryFile
{
    if (self.editingDocument)
    {
        NSString *temporaryFilePath  = [self.documentContentPath stringByReplacingOccurrencesOfString:self.documentContentPath.lastPathComponent withString:self.editingDocument.name];
        
        NSError *temporaryFileError = nil;
        [[AlfrescoFileManager sharedManager] copyItemAtPath:self.documentContentPath toPath:temporaryFilePath error:&temporaryFileError];
        
        if (temporaryFileError)
        {
            AlfrescoLogError(@"Unable to copy file from location: %@ to %@", self.documentContentPath, temporaryFileError);
        }
        
        self.temporaryFilePath = temporaryFilePath;
    }
    else
    {
        AlfrescoLogError(@"The editing node is nil. The temporary file could not be created");
    }
}

- (void)updateSourceFileFromTemporaryFile
{
    NSError *updateError = nil;
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    fileManager.delegate = self;
    [fileManager moveItemAtPath:self.temporaryFilePath toPath:self.documentContentPath error:&updateError];
    
    if (updateError)
    {
        AlfrescoLogError(@"Unable to overwrite file at path: %@ with file at path: %@", self.documentContentPath, self.temporaryFilePath);
    }
}

- (void)deleteTemporaryFile
{
    if ([[AlfrescoFileManager sharedManager] fileExistsAtPath:self.temporaryFilePath])
    {
        NSError *temporaryFileDeleteError = nil;
        [[AlfrescoFileManager sharedManager] removeItemAtPath:self.temporaryFilePath error:&temporaryFileDeleteError];
        
        if (temporaryFileDeleteError)
        {
            AlfrescoLogError(@"Unable to delete document at path: %@", self.temporaryFilePath);
        }
        
        self.temporaryFilePath = nil;
    }
}

- (void)cancelButtonPressed:(id)sender
{
    void (^dismissController)(void) = ^{
        [self dismissViewControllerAnimated:YES completion:nil];
    };
    
    if (self.textView.text.length > 0)
    {
        BOOL shouldShowAlertView = false;
        
        //we check to see if we are in editing mode
        if((self.editingDocument) && (self.documentContentPath))
        {
            NSError *error = nil;
            NSString *fileContent = [[NSString alloc] initWithContentsOfFile:self.documentContentPath usedEncoding:NULL error:&error];
            if(error == nil)
            {
                shouldShowAlertView = !(self.textView.text.length == fileContent.length);
            }
        }
        else
        {
            //this is a new file and it has some text entered by the user; we want to ask him if he wants to discard
            shouldShowAlertView = YES;
        }
        
        if(shouldShowAlertView)
        {
            NSString *alertTitleKey = self.editingDocument ? @"document.edit.button.discard" : @"createtextfile.dismiss.confirmation.title";
            NSString *alertMessageKey = self.editingDocument ? @"document.edit.dismiss.confirmation.message" : @"createtextfile.dismiss.confirmation.message";
            
            UIAlertView *confirmationAlert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(alertTitleKey, @"Discard Title")
                                                                        message:NSLocalizedString(alertMessageKey, @"Discard Message")
                                                                       delegate:self
                                                              cancelButtonTitle:NSLocalizedString(@"document.edit.discard", @"Discard")
                                                              otherButtonTitles:NSLocalizedString(@"document.edit.continue.editing", @"Continue Editing"), nil];
            [confirmationAlert showWithCompletionBlock:^(NSUInteger buttonIndex, BOOL isCancelButton) {
                if (isCancelButton)
                {
                    dismissController();
                }
            }];
        }
        else
        {
            dismissController();
        }
    }
    else
    {
        dismissController();
    }
}

- (void)nextButtonPressed:(id)sender
{
    NSString *text = self.textView.text;
    NSData *textData = [text dataUsingEncoding:NSUTF8StringEncoding];
    AlfrescoContentFile *contentFile = [[AlfrescoContentFile alloc] initWithData:textData mimeType:kTextFileMimeType];
    
    if (self.editingDocument)
    {
        SyncManager *syncManager = [SyncManager sharedManager];
        BOOL isSyncDocument = [syncManager isNodeInSyncList:self.editingDocument];
        [text writeToFile:self.temporaryFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
        if (isSyncDocument)
        {
            NSString *syncContentPath = [syncManager contentPathForNode:self.editingDocument];
            [text writeToFile:syncContentPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            
            [syncManager retrySyncForDocument:self.editingDocument completionBlock:^{
                
                AlfrescoDocument *document = (AlfrescoDocument *)[syncManager alfrescoNodeForIdentifier:self.editingDocument.identifier];
                [[NSNotificationCenter defaultCenter] postNotificationName:kAlfrescoDocumentEditedNotification object:document];
            }];
            [self dismissViewControllerAnimated:YES completion:nil];
        }
        else
        {
            MBProgressHUD *progressHUD = [[MBProgressHUD alloc] initWithView:self.view];
            progressHUD.mode = MBProgressHUDModeDeterminate;
            [progressHUD show:YES];
            
            [self.documentFolderService updateContentOfDocument:self.editingDocument contentFile:contentFile completionBlock:^(AlfrescoDocument *document, NSError *error) {
                [progressHUD hide:YES];
                if (document)
                {
                    [self updateSourceFileFromTemporaryFile];
                    [[NSNotificationCenter defaultCenter] postNotificationName:kAlfrescoDocumentEditedNotification object:document];
                    [self dismissViewControllerAnimated:YES completion:nil];
                }
                else
                {
                    UIAlertView *confirmDeletion = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"document.edit.failed.title", @"Edit Document Save Failed Title")
                                                                              message:NSLocalizedString(@"document.edit.savefailed.message", @"Edit Document Save Failed Message")
                                                                             delegate:self
                                                                    cancelButtonTitle:NSLocalizedString(@"Cancel", @"Cancel")
                                                                    otherButtonTitles:NSLocalizedString(@"document.edit.button.save", @"Save to Local Files"), nil];
                    [confirmDeletion showWithCompletionBlock:^(NSUInteger buttonIndex, BOOL isCancelButton) {
                        if (!isCancelButton)
                        {
                            [[DownloadManager sharedManager] saveDocument:self.editingDocument contentPath:self.temporaryFilePath showOverrideAlert:false completionBlock:^(NSString *filePath) {
                                [self dismissViewControllerAnimated:YES completion:^{
                                    displayInformationMessage([NSString stringWithFormat:NSLocalizedString(@"download.success-as.message", @"Download succeeded"), filePath.lastPathComponent]);
                                }];
                            }];
                        }
                    }];
                }
            } progressBlock:^(unsigned long long bytesTransferred, unsigned long long bytesTotal) {
                // Update progress HUD
                progressHUD.progress = (bytesTotal != 0) ? (float)bytesTransferred / (float)bytesTotal : 0;
            }];
        }
    }
    else
    {
        UploadFormViewController *uploadFormController = [[UploadFormViewController alloc] initWithSession:self.session
                                                                                         uploadContentFile:contentFile
                                                                                                  inFolder:self.uploadDestinationFolder
                                                                                            uploadFormType:UploadFormTypeDocument
                                                                                                  delegate:self.uploadFormViewControllerDelegate];
        [self.navigationController pushViewController:uploadFormController animated:YES];
    }
}

#pragma mark - Keyboard Managment

- (void)keyboardWasShown:(NSNotification *)notification
{
    NSDictionary *info = [notification userInfo];
    CGRect keyboardRectForScreen = [[info objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue];
    
    UIEdgeInsets textViewInsets = self.textView.contentInset;
    textViewInsets.bottom = [self calculateBottomInsetForTextViewUsingKeyboardFrame:keyboardRectForScreen];
    self.textView.contentInset = textViewInsets;
    self.textView.scrollIndicatorInsets = textViewInsets;
}

- (void)keyboardWillHide:(NSNotification *)notification
{
    [UIView animateWithDuration:0.3 animations:^{
        UIEdgeInsets textViewInsets = self.textView.contentInset;
        textViewInsets.bottom = 0.0f;
        self.textView.contentInset = textViewInsets;
        self.textView.scrollIndicatorInsets = textViewInsets;
    }];
}

- (CGFloat)calculateBottomInsetForTextViewUsingKeyboardFrame:(CGRect)keyboardFrame
{
    CGRect keyboardRectForView = [self.view convertRect:keyboardFrame fromView:self.view.window];
    CGSize kbSize = keyboardRectForView.size;
    UIView *mainAppView = [[UniversalDevice revealViewController] view];
    CGRect viewFrame = self.view.frame;
    CGRect viewFrameRelativeToMainController = [self.view convertRect:viewFrame toView:mainAppView];
    
    return (viewFrameRelativeToMainController.origin.y + viewFrame.size.height) - (mainAppView.frame.size.height - kbSize.height);
}

#pragma mark - UITextViewDelegate Functions

- (void)textViewDidChange:(UITextView *)textView
{
    NSString *trimmedText = [textView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmedText length] > 0)
    {
        self.navigationItem.rightBarButtonItem.enabled = YES;
    }
    else
    {
        self.navigationItem.rightBarButtonItem.enabled = NO;
    }
}

//
// http://craigipedia.blogspot.ca/2013/09/last-lines-of-uitextview-may-scroll.html
//
- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    [textView scrollRangeToVisible:range];
    
    if ([text isEqualToString:@"\n"])
    {
        [UIView animateWithDuration:0.2 animations:^{
            [textView setContentOffset:CGPointMake(textView.contentOffset.x, textView.contentOffset.y + 20)];
        }];
    }
    
    return YES;
}

#pragma mark - NSFileManagerDelegate methods

- (BOOL)fileManager:(NSFileManager *)fileManager shouldProceedAfterError:(NSError *)error movingItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath
{
    return (error.code == NSFileWriteFileExistsError);
}

@end
