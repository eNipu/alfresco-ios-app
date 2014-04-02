//
//  CreateTaskViewController.m
//  AlfrescoApp
//
//  Created by Mohamad Saeedi on 20/03/2014.
//  Copyright (c) 2014 Alfresco. All rights reserved.
//

#import "CreateTaskViewController.h"
#import "TextFieldCell.h"
#import "LabelCell.h"
#import "SwitchCell.h"
#import "TaskPriorityCell.h"
#import "TaskApproversCell.h"
#import "Utility.h"
#import "ErrorDescriptions.h"
#import "MBProgressHud.h"

static CGFloat const kNavigationBarHeight = 44.0f;

@interface CreateTaskViewController ()

@property (nonatomic, strong) id<AlfrescoSession> session;
@property (nonatomic, strong) AlfrescoWorkflowService *workflowService;

@property (nonatomic, assign) WorkflowType workflowType;
@property (nonatomic, strong) NSArray *tableViewGroups;
@property (nonatomic, strong) NodePicker *nodePicker;
@property (nonatomic, strong) PeoplePicker *peoplePicker;
@property (nonatomic, strong) NSMutableArray *assignees;
@property (nonatomic, strong) NSMutableArray *attachments;
@property (nonatomic, strong) DatePickerViewController *datePickerViewController;
@property (nonatomic, strong) UIPopoverController *datePopoverController;
@property (nonatomic, strong) NSDate *dueDate;
@property (nonatomic, strong) UIBarButtonItem *createTaskButton;

@property (nonatomic, strong) UITextField *titleField;
@property (nonatomic, strong) UILabel *dueDateLabel;
@property (nonatomic, strong) UILabel *assigneesLabel;
@property (nonatomic, strong) UILabel *attachmentsLabel;
@property (nonatomic, strong) UISwitch *emailNotificationSwitch;
@property (nonatomic, strong) UISegmentedControl *prioritySegmentControl;
@property (nonatomic, strong) TaskApproversCell *approversCell;

@property (nonatomic, weak) IBOutlet UITableView *tableView;

@end

@implementation CreateTaskViewController

- (instancetype)initWithSession:(id<AlfrescoSession>)session workflowType:(WorkflowType)workflowType
{
    self = [super initWithNibName:NSStringFromClass([self class]) bundle:nil];
    if (self)
    {
        _session = session;
        _workflowType = workflowType;
        _workflowService = [[AlfrescoWorkflowService alloc] initWithSession:session];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.title = NSLocalizedString(@"task.create.title", @"Create Task");
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                  target:self
                                                                                  action:@selector(cancelButtonTapped:)];
    
    self.createTaskButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"task.create.button", @"Create")
                                                             style:UIBarButtonItemStyleDone
                                                            target:self
                                                            action:@selector(createTaskButtonTapped:)];
    self.createTaskButton.enabled = NO;
    
    self.navigationItem.leftBarButtonItem = cancelButton;
    self.navigationItem.rightBarButtonItem = self.createTaskButton;
    
    self.nodePicker = [[NodePicker alloc] initWithSession:self.session navigationController:self.navigationController];
    self.nodePicker.delegate = self;
    self.peoplePicker = [[PeoplePicker alloc] initWithSession:self.session navigationController:self.navigationController];
    self.peoplePicker.delegate = self;
    
    [self createTableViewGroups];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(textFieldDidChange:)
                                                 name:UITextFieldTextDidChangeNotification
                                               object:nil];
}

- (void)viewWillLayoutSubviews
{
    if (self.titleField.text.length == 0 && !self.titleField.isFirstResponder)
    {
        [self.titleField becomeFirstResponder];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    [self validateForm];
}

#pragma mark - Private Methods

- (void)createTableViewGroups
{
    NSArray *group1 = @[@(CreateTaskRowTypeTitle), @(CreateTaskRowTypeDueDate)];
    
    NSArray *group2 = nil;
    if (self.workflowType == WorkflowTypeAdHoc)
    {
        group2 = @[@(CreateTaskRowTypeAssignees), @(CreateTaskRowTypeAttachments)];
    }
    else
    {
        group2 = @[@(CreateTaskRowTypeAssignees), @(CreateTaskRowTypeApprovers), @(CreateTaskRowTypeAttachments)];
    }
    
    NSArray *group3 = @[@(CreateTaskRowTypePriority), @(CreateTaskRowTypeEmailNotification)];
    
    self.tableViewGroups = @[group1, group2, group3];
}

- (void)cancelButtonTapped:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)createTaskButtonTapped:(id)sender
{
    NSString *processDefinitionKey = [WorkflowHelper processDefinitionKeyForWorkflowType:self.workflowType numberOfAssignees:self.assignees.count session:self.session];
    
    MBProgressHUD *progressHUD = [[MBProgressHUD alloc] initWithView:self.tableView];
    [progressHUD show:YES];
    
    [self.workflowService retrieveProcessDefinitionWithKey:processDefinitionKey completionBlock:^(AlfrescoWorkflowProcessDefinition *processDefinition, NSError *error) {
        
        if (processDefinition)
        {
            NSString *title = [self.titleField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSNumber *priority = @(self.prioritySegmentControl.selectedSegmentIndex + 1);
            NSNumber *sendNotification = @(self.emailNotificationSwitch.isOn);
            NSDictionary *variables = nil;
            
            if (self.workflowType == WorkflowTypeReview)
            {
                NSInteger approvalRate = round((self.approversCell.stepper.value / self.assignees.count) * 100);
                variables = @{kAlfrescoWorkflowProcessApprovalRate : @(approvalRate)};
            }
            
            [self.workflowService startProcessForProcessDefinition:processDefinition
                                                              name:title
                                                          priority:priority
                                                           dueDate:self.dueDate
                                             sendEmailNotification:sendNotification
                                                         assignees:self.assignees
                                                         variables:variables
                                                       attachments:self.attachments
                                                   completionBlock:^(AlfrescoWorkflowProcess *process, NSError *error) {
                                                       
                                                       [progressHUD hide:YES];
                                                       if (error)
                                                       {
                                                           displayErrorMessageWithTitle(NSLocalizedString(@"task.create.error", @"Failed to create Task"), [ErrorDescriptions descriptionForError:error]);
                                                       }
                                                       else
                                                       {
                                                           [[NSNotificationCenter defaultCenter] postNotificationName:kAlfrescoTaskAddedNotification object:process];
                                                           [self dismissViewControllerAnimated:YES completion:^{
                                                               displayInformationMessage(NSLocalizedString(@"task.create.created", @"Task Created"));
                                                           }];
                                                       }
                                                   }];
        }
        else
        {
            [progressHUD hide:YES];
            displayErrorMessageWithTitle(NSLocalizedString(@"task.create.error", @"Failed to create Task"), [ErrorDescriptions descriptionForError:error]);
        }
    }];
}

- (void)stepperPressed:(id)sender
{
    [self updateApproversCellInfo];
}

- (void)updateApproversCellInfo
{
    NSInteger numberOfApprovers = self.approversCell.stepper.value;
    if (numberOfApprovers == 0)
    {
        numberOfApprovers = 1;
    }
    else if (numberOfApprovers > self.assignees.count)
    {
        numberOfApprovers = self.assignees.count;
    }
    
    if (self.assignees.count == 0)
    {
        self.approversCell.stepper.minimumValue = 0;
        self.approversCell.stepper.maximumValue = 0;
        self.approversCell.stepper.enabled = NO;
        self.approversCell.titleLabel.text = NSLocalizedString(@"task.create.approvers", @"Approvers");
    }
    else
    {
        self.approversCell.stepper.enabled = YES;
        self.approversCell.stepper.minimumValue = 1;
        self.approversCell.stepper.maximumValue = self.assignees.count;
        
        if (self.assignees.count == 1)
        {
            self.approversCell.titleLabel.text = [NSString stringWithFormat:@"%li of %li %@", (long)numberOfApprovers, (long)self.assignees.count, NSLocalizedString(@"task.create.approver", @"Approver")];
        }
        else
        {
            self.approversCell.titleLabel.text = [NSString stringWithFormat:@"%li of %li %@", (long)numberOfApprovers, (long)self.assignees.count, NSLocalizedString(@"task.create.approvers", @"Approvers")];
        }
    }
}

- (void)validateForm
{
    self.createTaskButton.enabled = ((self.assignees.count > 0) && (self.titleField.text.length >= 1));
}

- (void)showDatePicker:(CGRect)positionInTableView
{
    self.datePickerViewController = [[DatePickerViewController alloc] initWithDate:self.dueDate];
    self.datePickerViewController.delegate = self;
    
    if (IS_IPAD)
    {
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:self.datePickerViewController];
        
        CGSize datePickerViewSize = self.datePickerViewController.view.frame.size;
        self.datePickerViewController.preferredContentSize = CGSizeMake(datePickerViewSize.width, datePickerViewSize.height + kNavigationBarHeight);
        
        self.datePopoverController = [[UIPopoverController alloc] initWithContentViewController:navigationController];
        
        CGRect popoverRect = [self.view convertRect:positionInTableView fromView:self.tableView];
        [self.datePopoverController presentPopoverFromRect:popoverRect inView:self.view permittedArrowDirections:UIPopoverArrowDirectionUp animated:YES];
    }
    else
    {
        [self.navigationController pushViewController:self.datePickerViewController animated:YES];
    }
}

#pragma mark - DatePicker Delegate Method

- (void)datePicker:(DatePickerViewController *)datePicker selectedDate:(NSDate *)date
{
    if (self.datePickerViewController != nil)
    {
        self.dueDate = date;
        self.datePickerViewController = nil;
        [self.tableView reloadData];
        
        if (!IS_IPAD)
        {
            [self.navigationController popViewControllerAnimated:YES];
        }
    }
    
    if (self.datePopoverController)
    {
        [self.datePopoverController dismissPopoverAnimated:YES];
        self.datePopoverController = nil;
    }
}

#pragma mark - TableView Delegate and Datasource Methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.tableViewGroups.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.tableViewGroups[section] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CreateTaskRowType rowType = [self.tableViewGroups[indexPath.section][indexPath.row] integerValue];
    
    UITableViewCell *cell = nil;
    switch (rowType)
    {
        case CreateTaskRowTypeTitle:
        {
            TextFieldCell *titleCell = (TextFieldCell *)[[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([TextFieldCell class]) owner:self options:nil] lastObject];
            titleCell.titleLabel.text = NSLocalizedString(@"task.create.taskTitle", @"Task Title");
            if (self.titleField.text.length > 0)
            {
                titleCell.valueTextField.text = self.titleField.text;
            }
            else
            {
                titleCell.valueTextField.placeholder = NSLocalizedString(@"task.create.taskTitle.placeholder", @"required");
            }
            titleCell.valueTextField.returnKeyType = UIReturnKeyDone;
            titleCell.valueTextField.delegate = self;
            self.titleField = titleCell.valueTextField;
            cell = titleCell;
            break;
        }
        case CreateTaskRowTypeDueDate:
        {
            LabelCell *dueDateCell = (LabelCell *)[[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([LabelCell class]) owner:self options:nil] lastObject];
            dueDateCell.titleLabel.text = NSLocalizedString(@"task.create.duedate", @"Due On");
            if (self.dueDate)
            {
                NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                dateFormatter.dateStyle = NSDateFormatterMediumStyle;
                dueDateCell.valueLabel.text = [dateFormatter stringFromDate:self.dueDate];
            }
            else
            {
                dueDateCell.valueLabel.text = NSLocalizedString(@"task.create.duedate.placeholder", @"Due Date");
            }
            self.dueDateLabel = dueDateCell.valueLabel;
            dueDateCell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell = dueDateCell;
            break;
        }
        case CreateTaskRowTypeAssignees:
        {
            LabelCell *assigneesCell = (LabelCell *)[[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([LabelCell class]) owner:self options:nil] lastObject];
            assigneesCell.titleLabel.text = self.workflowType == WorkflowTypeAdHoc ? NSLocalizedString(@"task.create.assignee", @"Assignee") : NSLocalizedString(@"task.create.assignees", @"Assignees");
            if (self.assignees && self.assignees.count > 0)
            {
                if (self.assignees.count > 1)
                {
                    assigneesCell.valueLabel.text = [NSString stringWithFormat:@"%li %@", (long)self.assignees.count, [NSLocalizedString(@"task.create.assignees", @"Assignees") lowercaseString]];
                }
                else
                {
                    assigneesCell.valueLabel.text = [self.assignees.firstObject fullName];
                }
            }
            else
            {
                assigneesCell.valueLabel.text = NSLocalizedString(@"task.create.assignee.placeholder", @"No Assignees");
            }
            self.assigneesLabel = assigneesCell.valueLabel;
            assigneesCell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell = assigneesCell;
            break;
        }
        case CreateTaskRowTypeAttachments:
        {
            LabelCell *attachmentsCell = (LabelCell *)[[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([LabelCell class]) owner:self options:nil] lastObject];
            attachmentsCell.titleLabel.text = NSLocalizedString(@"task.create.attachments", @"attachements");
            if (self.attachments && self.attachments.count > 0)
            {
                if (self.attachments.count > 1)
                {
                    attachmentsCell.valueLabel.text = [NSString stringWithFormat:@"%li %@", (long)self.attachments.count, [NSLocalizedString(@"task.create.attachments", @"Attachments") lowercaseString]];
                }
                else
                {
                    attachmentsCell.valueLabel.text = [self.attachments.firstObject name];
                }
            }
            else
            {
                attachmentsCell.valueLabel.text = NSLocalizedString(@"task.create.attachments.placeholder", @"No Attachments");
            }
            self.attachmentsLabel = attachmentsCell.valueLabel;
            attachmentsCell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell = attachmentsCell;
            break;
        }
        case CreateTaskRowTypePriority:
        {
            TaskPriorityCell *priorityCell = (TaskPriorityCell *)[[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([TaskPriorityCell class]) owner:self options:nil] lastObject];
            priorityCell.titleLabel.text = NSLocalizedString(@"task.create.priority", @"Priority");
            [priorityCell.segmentControl setTitle:NSLocalizedString(@"task.create.priority.high", @"High") forSegmentAtIndex:0];
            [priorityCell.segmentControl setTitle:NSLocalizedString(@"task.create.priority.medium", @"Medium") forSegmentAtIndex:1];
            [priorityCell.segmentControl setTitle:NSLocalizedString(@"task.create.priority.low", @"Low") forSegmentAtIndex:2];
            
            if (self.prioritySegmentControl)
            {
                [priorityCell.segmentControl setSelectedSegmentIndex:self.prioritySegmentControl.selectedSegmentIndex];
            }
            
            self.prioritySegmentControl = priorityCell.segmentControl;
            cell = priorityCell;
            break;
        }
        case CreateTaskRowTypeEmailNotification:
        {
            SwitchCell *emailNotificationCell = (SwitchCell *)[[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([SwitchCell class]) owner:self options:nil] lastObject];
            emailNotificationCell.titleLabel.text = NSLocalizedString(@"task.create.emailnotification", @"Email Notification");
            
            if (self.emailNotificationSwitch)
            {
                [emailNotificationCell.valueSwitch setOn:self.emailNotificationSwitch.isOn animated:NO];
            }
            
            self.emailNotificationSwitch = emailNotificationCell.valueSwitch;
            cell = emailNotificationCell;
            break;
        }
        case CreateTaskRowTypeApprovers:
        {
            TaskApproversCell *approversCell = (TaskApproversCell *)[[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([TaskApproversCell class]) owner:self options:nil] lastObject];
            approversCell.stepper.value = self.approversCell.stepper.value;
            
            self.approversCell = approversCell;
            [self.approversCell.stepper addTarget:self action:@selector(stepperPressed:) forControlEvents:UIControlEventValueChanged];
            [self updateApproversCellInfo];
            cell = self.approversCell;
            break;
        }
        default:
        {
            cell = (TextFieldCell *)[[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([TextFieldCell class]) owner:self options:nil] lastObject];
            break;
        }
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    CreateTaskRowType rowType = [self.tableViewGroups[indexPath.section][indexPath.row] integerValue];
    
    if (rowType != CreateTaskRowTypeTitle)
    {
        [self.titleField resignFirstResponder];
    }
    
    switch (rowType)
    {
        case CreateTaskRowTypeAttachments:
        {
            [self.nodePicker startWithNodes:self.attachments type:NodePickerTypeDocuments mode:NodePickerModeMultiSelect];
            break;
        }
        case CreateTaskRowTypeAssignees:
        {
            PeoplePickerMode peoplePickerMode = (self.workflowType == WorkflowTypeAdHoc) ? PeoplePickerModeSingleSelect : PeoplePickerModeMultiSelect;
            [self.peoplePicker startWithPeople:self.assignees mode:peoplePickerMode modally:NO];
            break;
        }
        case CreateTaskRowTypeDueDate:
        {
            LabelCell *dueDateCell = (LabelCell *)[self.tableView cellForRowAtIndexPath:indexPath];
            CGRect dueDateLabelPosition = [self.tableView convertRect:dueDateCell.valueLabel.frame fromView:dueDateCell];
            [self showDatePicker:dueDateLabelPosition];
            break;
        }
        default:
            break;
    }
}

#pragma mark - UITextField Notification

- (void)textFieldDidChange:(NSNotification *)notification
{
    [self validateForm];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [self.titleField resignFirstResponder];
    return YES;
}

#pragma mark - NodePicker, PeoplePicker Delegate Methods

- (void)nodePicker:(NodePicker *)nodePicker didSelectNodes:(NSArray *)selectedNodes
{
    self.attachments = [selectedNodes mutableCopy];
}

- (void)peoplePicker:(PeoplePicker *)peoplePicker didSelectPeople:(NSArray *)selectedPeople
{
    self.assignees = [selectedPeople mutableCopy];
}

@end
