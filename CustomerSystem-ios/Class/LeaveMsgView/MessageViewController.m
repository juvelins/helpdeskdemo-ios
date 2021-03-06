//
//  MessageViewController.m
//  CustomerSystem-ios
//
//  Created by EaseMob on 16/6/30.
//  Copyright © 2016年 easemob. All rights reserved.
//

#import "MessageViewController.h"

#import "EaseMob.h"
#import "SRRefreshView.h"
#import "ChatViewController.h"
#import "LeaveMsgCell.h"
#import "ConvertToCommonEmoticonsHelper.h"
#import "NSDate+Category.h"
#import "LeaveMsgDetailViewController.h"
#import "LeaveMsgDetailModel.h"
#import "EMHttpManager.h"
#import "EMIMHelper.h"

@interface MessageViewController () <UITableViewDelegate,UITableViewDataSource,EMChatManagerDelegate,SRRefreshDelegate>
{
    NSInteger _page;
    NSInteger _pageSize;
    BOOL _hasMore;
    
    NSObject *_refreshLock;
    BOOL _isRefresh;
}

@property (nonatomic, strong) NSMutableArray *dataArray;
@property (nonatomic, strong) SRRefreshView *slimeView;
@property (nonatomic, strong) NSDateFormatter *dateformatter;

@end

@implementation MessageViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = NSLocalizedString(@"title.messagebox", @"Message Box");
    
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 7.0) {
        self.edgesForExtendedLayout =  UIRectEdgeNone;
    }
    
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.tableView addSubview:self.slimeView];
    self.tableView.tableFooterView = [[UIView alloc] init];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = RGBACOLOR(238, 238, 245, 1);
    
    _pageSize = 10;
    _refreshLock = [[NSObject alloc] init];
    [self reloadLeaveMsgList];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(addMsgToList:) name:KNOTIFICATION_ADDMSG_TO_LIST object:nil];
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self registNotification];
}

-(void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self unregistNotification];
}

- (void)registNotification
{
    [self unregistNotification];
    [[EaseMob sharedInstance].chatManager addDelegate:self delegateQueue:nil];
}

- (void)unregistNotification
{
    [[EaseMob sharedInstance].chatManager removeDelegate:self];
}

- (void)dealloc
{
    [self unregistNotification];
    
    self.slimeView.delegate = nil;
    self.slimeView = nil;
    
    self.tableView.delegate = nil;
    self.tableView.dataSource = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - getter

- (NSMutableArray*)dataArray
{
    if (_dataArray == nil) {
        _dataArray = [NSMutableArray array];
    }
    return _dataArray;
}

- (SRRefreshView *)slimeView
{
    if (_slimeView == nil) {
        _slimeView = [[SRRefreshView alloc] init];
        _slimeView.delegate = self;
        _slimeView.upInset = 0;
        _slimeView.slimeMissWhenGoingBack = YES;
        _slimeView.slime.bodyColor = [UIColor grayColor];
        _slimeView.slime.skinColor = [UIColor grayColor];
        _slimeView.slime.lineWith = 1;
        _slimeView.slime.shadowBlur = 4;
        _slimeView.slime.shadowColor = [UIColor grayColor];
    }
    
    return _slimeView;
}

- (NSDateFormatter*)dateformatter
{
    if (_dateformatter == nil) {
        _dateformatter = [[NSDateFormatter alloc] init];
        [_dateformatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
        [_dateformatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    }
    return _dateformatter;
}


#pragma mark - IChatMangerDelegate

- (void)didReceiveMessage:(EMMessage *)message
{
    NSDictionary *ext = [self _getSafeDictionary:message.ext];
    if ([ext objectForKey:@"weichat"] && [[ext objectForKey:@"weichat"] objectForKey:@"notification"]) {
        EMConversation *conversation = [[EaseMob sharedInstance].chatManager conversationForChatter:message.from conversationType:eConversationTypeChat];
        [conversation removeMessageWithId:message.messageId];
        [[EaseMob sharedInstance].chatManager removeConversationByChatter:conversation.chatter deleteMessages:YES append2Chat:YES];
        
        LeaveMsgBaseModelTicket *ticket = [[LeaveMsgBaseModelTicket alloc] initWithDictionary:[[[ext objectForKey:@"weichat"] objectForKey:@"event"] objectForKey:@"ticket"]];
        
        for (LeaveMsgCommentModel *comment in _dataArray) {
            if (comment.ticketId == ticket.ticketId) {
                [self.tableView reloadData];
                return;
            }
        }
        
        [self reloadLeaveMsgList];
    }
}

- (void)didReceiveOfflineMessages:(NSArray *)offlineMessages
{
    for (EMMessage *message in offlineMessages) {
        NSDictionary *ext = [self _getSafeDictionary:message.ext];
        if ([ext objectForKey:@"weichat"] && [[ext objectForKey:@"weichat"] objectForKey:@"notification"]) {
            EMConversation *conversation = [[EaseMob sharedInstance].chatManager conversationForChatter:message.from conversationType:eConversationTypeChat];
            [conversation removeMessageWithId:message.messageId];
            [[EaseMob sharedInstance].chatManager removeConversationByChatter:conversation.chatter deleteMessages:YES append2Chat:YES];
            
            [self reloadLeaveMsgList];
        }
    }
}

#pragma mark - scrollView delegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (_slimeView) {
        [_slimeView scrollViewDidScroll];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (_slimeView) {
        [_slimeView scrollViewDidEndDraging];
    }
}

#pragma mark - slimeRefresh delegate
//加载更多
- (void)slimeRefreshStartRefresh:(SRRefreshView *)refreshView
{
    _page = 0;
    __weak typeof(self) weakSelf = self;
    [self loadAndRefreshDataWithCompletion:^(BOOL success) {
        [weakSelf.slimeView endRefresh];
    }];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (_hasMore) {
        if (section == 0) {
            return [self.dataArray count];
        } else {
            return 1;
        }
    }
    return [self.dataArray count];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if (_hasMore) {
        return 2;
    }
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *identify = @"MessageListCell";
    if (indexPath.section == 0) {
        LeaveMsgCell *cell = [tableView dequeueReusableCellWithIdentifier:identify];
        if (cell == nil) {
            cell = [[LeaveMsgCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identify];
        }
        
        
        LeaveMsgCommentModel *comment = [self.dataArray objectAtIndex:indexPath.row];
        cell.name = [NSString stringWithFormat:@"ID: %@",@(comment.ticketId)];
        cell.placeholderImage = [UIImage imageNamed:@"customer"];
        if (comment.attachments) {
            cell.detailMsg = [NSString stringWithFormat:@"%@-[%@]",comment.content,NSLocalizedString(@"leaveMessage.leavemsg.attachment", @"Attachment")];
        } else {
            cell.detailMsg = comment.content;
        }
        cell.time = [NSDate formattedTimeFromTimeInterval:[[self.dateformatter dateFromString:comment.updated_at] timeIntervalSince1970]];
        cell.placeholderImage = [UIImage imageNamed:@"message_comment"];
        cell.imageView.backgroundColor = RGBACOLOR(242, 83, 131, 1);
        return cell;
    }
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"loadMoreCell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"loadMoreCell"];
    }
    
    cell.textLabel.text = @"点击加载更多";
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        LeaveMsgCommentModel *comment = [self.dataArray objectAtIndex:indexPath.row];
        LeaveMsgDetailViewController *leaveMsgDetail = [[LeaveMsgDetailViewController alloc] initWithTicketId:comment.ticketId chatter:nil];
        [self.navigationController pushViewController:leaveMsgDetail animated:YES];
    } else {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        cell.userInteractionEnabled = NO;
        [self loadAndRefreshDataWithCompletion:^(BOOL success) {
            cell.userInteractionEnabled = YES;
        }];
    }
}

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [LeaveMsgCell tableView:tableView heightForRowAtIndexPath:indexPath];
}

#pragma mark - private

- (void)loadAndRefreshDataWithCompletion:(void (^)(BOOL success))completion
{
    @synchronized (_refreshLock) {
        if (_isRefresh) {
            return;
        }
        _isRefresh = YES;
    }
    NSDictionary *parameters = @{@"size":@(_pageSize),@"page":@(_page),@"sort":@"updatedAt,desc"};
    __weak typeof(self) weakSelf = self;
    [[EMHttpManager sharedInstance] asyncGetMessagesWithTenantId:[EMIMHelper defaultHelper].tenantId projectId:[EMIMHelper defaultHelper].projectId parameters:parameters completion:^(id responseObject, NSError *error) {
        @synchronized (_refreshLock) {
            _isRefresh = NO;
        }
        if (!error) {
            if (responseObject && [responseObject isKindOfClass:[NSDictionary class]]) {
                if (_page == 0) {
                    [weakSelf.dataArray removeAllObjects];
                }
                _page++;
                _pageSize = 10;
                if ([responseObject objectForKey:@"entities"]) {
                    NSArray *array = [responseObject objectForKey:@"entities"];
                    for (NSDictionary *entity in array) {
                        LeaveMsgCommentModel *comment = [[LeaveMsgCommentModel alloc] initWithDictionary:entity];
                        [weakSelf.dataArray addObject:comment];
                    }
                    
                    if ([array count] == _pageSize) {
                        _hasMore = YES;
                    } else {
                        _hasMore = NO;
                    }
                }
                [weakSelf.tableView reloadData];
            }
            if (completion) {
                completion(YES);
            }
        } else {
            if (completion) {
                completion(NO);
            }
        }
    }];
}

// 得到未读消息条数
- (NSInteger)unreadMessageCountByConversation:(EMConversation *)conversation
{
    NSInteger ret = 0;
    ret = conversation.unreadMessagesCount;
    return  ret;
}

// 得到最后消息文字或者类型
-(NSString *)subTitleMessageByConversation:(EMConversation *)conversation
{
    NSString *ret = @"";
    EMMessage *lastMessage = [conversation latestMessage];
    if (lastMessage) {
        id<IEMMessageBody> messageBody = lastMessage.messageBodies.lastObject;
        switch (messageBody.messageBodyType) {
            case eMessageBodyType_Image:{
                ret = NSLocalizedString(@"message.image1", @"[image]");
            } break;
            case eMessageBodyType_Text:{
                // 表情映射。
                NSString *didReceiveText = [ConvertToCommonEmoticonsHelper
                                            convertToSystemEmoticons:((EMTextMessageBody *)messageBody).text];
                ret = didReceiveText;
            } break;
            case eMessageBodyType_Voice:{
                ret = NSLocalizedString(@"message.voice1", @"[voice]");
            } break;
            case eMessageBodyType_Location: {
                ret = NSLocalizedString(@"message.location1", @"[location]");
            } break;
            case eMessageBodyType_Video: {
                ret = NSLocalizedString(@"message.video1", @"[video]");
            } break;
            default: {
            } break;
        }
    }
    return ret;
}

- (NSString*)getTicketIdWithMessage:(EMMessage*)message
{
    NSDictionary *ext = [self _getSafeDictionary:message.ext];
    if (ext) {
        if ([ext objectForKey:@"weichat"]) {
            if ([[ext objectForKey:@"weichat"] objectForKey:@"event"]) {
                if ([[[ext objectForKey:@"weichat"] objectForKey:@"event"] objectForKey:@"ticket"]) {
                    return [[[[ext objectForKey:@"weichat"] objectForKey:@"event"] objectForKey:@"ticket"] objectForKey:@"id"];
                }
            }
        }
    }
    return @"";
}

- (NSMutableDictionary*)_getSafeDictionary:(NSDictionary*)dic
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:dic];
    if ([[userInfo allKeys] count] > 0) {
        for (NSString *key in [userInfo allKeys]){
            if ([userInfo objectForKey:key] == [NSNull null]) {
                [userInfo removeObjectForKey:key];
            } else {
                if ([[userInfo objectForKey:key] isKindOfClass:[NSDictionary class]]) {
                    [userInfo setObject:[self _getSafeDictionary:[userInfo objectForKey:key]] forKey:key];
                }
            }
        }
    }
    return userInfo;
}

#pragma mark - public 

- (void)reloadLeaveMsgList
{
    _page = 0;
    [self loadAndRefreshDataWithCompletion:nil];
}

#pragma mark - notification

- (void)addMsgToList:(NSNotification*)notify
{
    if (notify.object && [notify.object isKindOfClass:[NSDictionary class]]) {
        LeaveMsgCommentModel *comment = [[LeaveMsgCommentModel alloc] initWithDictionary:notify.object];
        [self.dataArray insertObject:comment atIndex:0];
        [self.tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:0]] withRowAnimation:UITableViewRowAnimationTop];
        _pageSize++;
    }
}

@end
