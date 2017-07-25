//
//  LZVideoEditClipVC.m
//  laziz_Merchant
//
//  Created by biyuhuaping on 2017/4/24.
//  Copyright © 2017年 XBN. All rights reserved.
//  视频编辑页面

#import "LZVideoEditClipVC.h"
#import "LewReorderableLayout.h"            //拖动排序
#import "LZVideoEditCollectionViewCell.h"

#import "ProgressBar.h"
#import "HKMediaOperationTools.h"           //视频倒播

#import "LZVideoEditAuxiliary.h"
#import "LZVideoTools.h"

#import "GPUImage.h"
#import "GPUImageVideoCamera.h"
#import "GPUImageMovieWriter.h"
#import <AssetsLibrary/ALAssetsLibrary.h>

#import "LZPlayerView.h"

#import "LZVideoTailoringVC.h"//剪裁VC
#import "LZVideoSplitVC.h"//分割VC
#import "LZVideoSpeedVC.h"//速度VC
#import "LZVideoAdjustVC.h"//调节VC


@interface LZVideoEditClipVC ()<LewReorderableLayoutDelegate, LewReorderableLayoutDataSource, SAVideoRangeSliderDelegate>

@property (strong, nonatomic) IBOutlet GPUImageView *gpuImageView;
@property (strong, nonatomic) IBOutlet UIButton *playButton;

@property (strong, nonatomic) AVPlayer *player;
@property (strong, nonatomic) id timeObser;



@property (strong, nonatomic) IBOutlet UILabel *timeLabel;//计时显示

@property (strong, nonatomic) IBOutlet UICollectionView *collectionView;
@property (strong, nonatomic) IBOutlet UIButton *lzCopyButton;              //复制按钮
@property (strong, nonatomic) IBOutlet UIButton *lzVoiceButton;             //声音按钮
@property (strong, nonatomic) IBOutlet UIButton *lzDeleteButton;            //删除按钮
@property (strong, nonatomic) IBOutlet UILabel *hintLabel;                  //提示信息
@property (strong, nonatomic) IBOutlet UIProgressView *progressView;        //处理倒放视频进度

@property (strong, nonatomic) LZVideoEditAuxiliary *videoEditAuxiliary;
@property (assign, nonatomic) NSInteger currentSelected;
@property (strong, nonatomic) NSMutableArray *recordSegments;
@property (nonatomic, assign) __block BOOL isReverseCancel;   //取消翻转

@end

@implementation LZVideoEditClipVC

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    self.title = LZLocalizedString(@"edit_video", nil);
    _hintLabel.text = LZLocalizedString(@"all_video_delete", nil);
    self.videoEditAuxiliary = [[LZVideoEditAuxiliary alloc]init];
    self.currentSelected = 0;

    self.timeLabel.layer.masksToBounds = YES;
    self.timeLabel.layer.cornerRadius = 10;
    
    [self configNavigationBar];
    [self configCollectionView];
    
    [LZVideoTools enumPathisFilter:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.recordSegments = [NSMutableArray arrayWithArray:self.recordSession.segments];

    [self showVideo:YES];
    [self configTimeLabel];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.player pause];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - configViews
//配置navi
- (void)configNavigationBar{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.titleLabel.font = [UIFont systemFontOfSize:15];
    button.selected = NO;
    [button setTitle:LZLocalizedString(@"edit_done", @"") forState:UIControlStateNormal];
    [button setTitleColor:UIColorFromRGB(0xffffff, 1) forState:UIControlStateNormal];
    [button sizeToFit];
    button.frame = CGRectMake(0, 0, CGRectGetWidth(button.bounds), 40);
    button.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, -8);
    [button addTarget:self action:@selector(navbarRightButtonClickAction:) forControlEvents:UIControlEventTouchUpInside];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]initWithCustomView:button];
}

//配置collectionView
- (void)configCollectionView{
    LewReorderableLayout *layout = [LewReorderableLayout new];
    layout.itemSize                 = CGSizeMake(60, 60);
    layout.minimumInteritemSpacing  = 10;
    layout.minimumLineSpacing       = 10;
    layout.sectionInset             = UIEdgeInsetsMake(10, 10, 10, 10);
    layout.scrollDirection          = UICollectionViewScrollDirectionHorizontal;
    layout.delegate                 = self;
    layout.dataSource               = self;
    self.collectionView.collectionViewLayout = layout;
    [self.collectionView registerClass:[LZVideoEditCollectionViewCell class] forCellWithReuseIdentifier:@"VideoEditCollectionCell"];
}

//配置timeLabel
- (void)configTimeLabel{
    //显示总时间
    CGFloat durationSeconds = CMTimeGetSeconds(self.recordSession.assetRepresentingSegments.duration);
    int seconds = lround(durationSeconds) % 60;
    int minutes = (lround(durationSeconds) / 60) % 60;
    self.timeLabel.text = [NSString stringWithFormat:@" %02d:%02d ", minutes, seconds];
}

//选中视频
- (void)showVideo:(BOOL)isFirstTime{
    LZSessionSegment *segment = self.recordSegments[self.currentSelected];
    
    AVPlayerItem *playerItem = [[AVPlayerItem alloc]initWithURL:segment.url];
    if (isFirstTime) {
        self.player = [AVPlayer playerWithPlayerItem:playerItem];
        [self.playButton setImage:[UIImage imageNamed:@"播放"] forState:UIControlStateNormal];
    }else{
        [self.player removeTimeObserver:self.timeObser];
        [self.player replaceCurrentItemWithPlayerItem:playerItem];
        [self.player play];
        [self.playButton setImage:nil forState:UIControlStateNormal];
    }
    self.player.volume = segment.isMute?0:1;
    self.lzVoiceButton.selected = segment.isMute?YES:NO;
    
    GPUImageMovie *movieFile = [[GPUImageMovie alloc] initWithPlayerItem:playerItem];
    movieFile.playAtActualSpeed = YES;
    
    GPUImageOutput<GPUImageInput> *filter = [[GPUImageFilter alloc] init];//原图
    [filter addTarget:self.gpuImageView];
    [movieFile addTarget:filter];
    [movieFile startProcessing];
    
    WS(weakSelf);
    self.timeObser = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1.0, 1.0) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        double current = CMTimeGetSeconds(time);
        double total = CMTimeGetSeconds(segment.asset.duration);
        if (current >= total) {
            CMTime time = CMTimeMakeWithSeconds(segment.startTime, segment.duration.timescale);
            [weakSelf.player seekToTime:time];
            [weakSelf.playButton setImage:[UIImage imageNamed:@"播放"] forState:UIControlStateNormal];
        }
    }];
    
    [self didSelectPlayerItem];
}

//选中视频
- (void)didSelectPlayerItem {
    //这里遍历声音设置情况
    for (int i = 0; i < self.recordSegments.count; i++) {
        LZSessionSegment * segment = self.recordSegments[i];
        NSAssert(segment != nil, @"segment must be non-nil");
        
        if (self.currentSelected == i) {
            segment.isSelect = YES;//设置选中
        }
        else {
            segment.isSelect = NO;
        }
    }
    
    [self.collectionView reloadData];
}

#pragma mark - Event
//保存
- (void)navbarRightButtonClickAction:(UIButton*)sender {
    
    WS(weakSelf);
    dispatch_group_t serviceGroup = dispatch_group_create();
    for (int i = 0; i < weakSelf.recordSegments.count; i++) {
        DLog(@"执行剪切：%d", i);
        LZSessionSegment * segment = weakSelf.recordSegments[i];
        NSArray *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:segment.asset];
        if ([compatiblePresets containsObject:AVAssetExportPresetHighestQuality]) {
            
            NSString *filename = [NSString stringWithFormat:@"Video-%ld.m4v", (long)i];
            NSURL *tempPath = [LZVideoTools filePathWithFileName:filename isFilter:YES];
            
            CMTime start = CMTimeMakeWithSeconds(segment.startTime, segment.duration.timescale);
            CMTime duration = CMTimeMakeWithSeconds(segment.endTime - segment.startTime, segment.asset.duration.timescale);
            CMTimeRange range = CMTimeRangeMake(start, duration);
            
            dispatch_group_enter(serviceGroup);
            [LZVideoTools exportVideo:segment.asset videoComposition:nil filePath:tempPath timeRange:range completion:^(NSURL *savedPath) {
                LZSessionSegment * newSegment = [[LZSessionSegment alloc] initWithURL:tempPath filter:nil];
                DLog(@"剪切url:%@", [tempPath path]);
                [weakSelf.recordSegments removeObject:segment];
                [weakSelf.recordSegments insertObject:newSegment atIndex:i];
                dispatch_group_leave(serviceGroup);
            }];
        }
    }
    
    dispatch_group_notify(serviceGroup, dispatch_get_main_queue(),^{
        DLog(@"保存到recordSession");
        [self.recordSession removeAllSegments:NO];
        for (int i = 0; i < self.recordSegments.count; i++) {
            LZSessionSegment * segment = self.recordSegments[i];
            NSAssert(segment.url != nil, @"segment url must be non-nil");
            if (segment.url != nil) {
                [self.recordSession insertSegment:segment atIndex:i];
            }
        }
        [self.navigationController popViewControllerAnimated:YES];
    });
}

//播放或暂停
- (IBAction)lzPlayOrPause:(UIButton *)button{
    if (!(self.player.rate > 0)) {
        [self.player play];
        [self.playButton setImage:nil forState:UIControlStateNormal];
    }else{
        [self.player pause];
        [self.playButton setImage:[UIImage imageNamed:@"播放"] forState:UIControlStateNormal];
    }
}

//剪裁
- (IBAction)lzTailoringButtonAction:(id)sender {
    LZVideoTailoringVC *tailoringView = [[LZVideoTailoringVC alloc]initWithNibName:@"LZVideoTailoringVC" bundle:nil];
    tailoringView.recordSession = self.recordSession;
    tailoringView.currentSelected = self.currentSelected;
    tailoringView.recordSegments = [NSMutableArray arrayWithArray:self.recordSegments];
    [self.navigationController pushViewController:tailoringView animated:YES];
}

//分割
- (IBAction)lzSplitButtonAction:(id)sender {
    //至少1秒，才能分割
    LZSessionSegment *segment = self.recordSegments[self.currentSelected];
    if (CMTimeGetSeconds(segment.duration) < 1) {
        UIAlertView * alert = [[UIAlertView alloc] initWithTitle:LZLocalizedString(@"edit_message", nil) message:@"至少1秒，才能分割!zhoubo" delegate:nil cancelButtonTitle:nil otherButtonTitles:@"ok", nil];
        [alert show];
        return;
    }
    LZVideoSplitVC *splitView = [[LZVideoSplitVC alloc]initWithNibName:@"LZVideoSplitVC" bundle:nil];
    splitView.recordSession = self.recordSession;
    splitView.currentSelected = self.currentSelected;
    splitView.recordSegments = [NSMutableArray arrayWithArray:self.recordSegments];
    [self.navigationController pushViewController:splitView animated:YES];
}

//复制
- (IBAction)lzCopyButtonAction:(UIButton *)sender {
    if (self.recordSegments.count == 0) {
        return;
    }
    
    LZSessionSegment * segment = self.recordSegments[self.currentSelected];
    NSAssert(segment.url != nil, @"segment must be non-nil");
    
    //限制视频时长
    if (CMTimeGetSeconds(segment.duration)+[self.videoEditAuxiliary getAllVideoTimesRecordSegments:self.recordSegments] > 15) {
        UIAlertView * alert = [[UIAlertView alloc] initWithTitle:LZLocalizedString(@"edit_message", nil) message:nil delegate:nil cancelButtonTitle:nil otherButtonTitles:@"ok", nil];
        [alert show];
        return;
    }
    
    //往缓存里复制一份，同时更新self.recordSession.segments。否则重新显示此页面时，recordSegments会取不到复制的文件。
//    NSString *filename = [NSString stringWithFormat:@"Video-%ld.m4v", (long)self.recordSession.segments.count];
//    NSURL *tempPath = [LZVideoTools filePathWithFileName:filename isFilter:YES];
    NSURL *tempPath = [LZVideoTools filePathWithFilter:YES];

    [LZVideoTools exportVideo:segment.asset videoComposition:nil filePath:tempPath timeRange:kCMTimeRangeZero completion:^(NSURL *savedPath) {
        if(savedPath) {
            DLog(@"导出视频路径：%@", savedPath);
            LZSessionSegment * newSegment = [LZSessionSegment segmentWithURL:tempPath filter:segment.filter];
            [self.recordSession insertSegment:newSegment atIndex:self.currentSelected];
        }
    }];
    
    //往临时数组复制一份。
    LZSessionSegment * newSegment = [LZSessionSegment segmentWithURL:segment.url filter:segment.filter];
    NSAssert(newSegment.url != nil, @"segment must be non-nil");
    [self.recordSegments addObject:newSegment];
    
    //更新片段view
    [self.collectionView reloadData];
}

//变速
- (IBAction)lzVariableSpeedAction:(id)sender {
    LZVideoSpeedVC *viewC = [[LZVideoSpeedVC alloc]initWithNibName:@"LZVideoSpeedVC" bundle:nil];
    viewC.recordSession = self.recordSession;
    viewC.currentSelected = self.currentSelected;
    viewC.recordSegments = [NSMutableArray arrayWithArray:self.recordSegments];
    [self.navigationController pushViewController:viewC animated:YES];
}

//调节
- (IBAction)lzAdjustButtonAction:(id)sender {
    LZVideoAdjustVC *viewC = [[LZVideoAdjustVC alloc]initWithNibName:@"LZVideoAdjustVC" bundle:nil];
    viewC.recordSession = self.recordSession;
    viewC.currentSelected = self.currentSelected;
    viewC.recordSegments = [NSMutableArray arrayWithArray:self.recordSegments];
    [self.navigationController pushViewController:viewC animated:YES];
}

//声音
- (IBAction)lzVoiceButtonAction:(UIButton *)sender {
    /*LZSessionSegment * segment1 = [self.videoEditAuxiliary getCurrentSegment:self.recordSegments index:self.currentSelected];
//  AVPlayerItem *item = [LZVideoTools audioFadeOut:segment1];
    AVPlayerItem *item = [LZVideoTools videoFadeOut:segment1];
    
    [self lzAddWatermark];
    [self.playerView.player setItem:item];
    [self.playerView.player play];
    return;
     */
    

    if (self.recordSegments.count == 0) {
        return;
    }
    
    LZSessionSegment * segment = self.recordSegments[self.currentSelected];
    //判断当前片段的声音设置
    if (!segment.isMute) {
        self.player.volume = 0;
        self.lzVoiceButton.selected = YES;
        segment.isMute = YES;
    } else {
        self.player.volume = 1;
        self.lzVoiceButton.selected = NO;
        segment.isMute = NO;
    }
}

//倒放
- (IBAction)lzBackwardsButtonAction:(UIButton *)sender {
    if (self.recordSegments.count == 0) {
        return;
    }
    
    self.progressView.hidden = NO;
    self.isReverseCancel = NO;
    [self.player pause];
    [self.progressView setProgress:0];
    
    __block LZSessionSegment *segment = self.recordSegments[self.currentSelected];
    __block LZSessionSegment *newSegment = nil;
    
    NSURL *tempPath = [LZVideoTools filePathWithFileName:@"BackwardsVideo.m4v" isFilter:YES];
    
    if (segment.isReverse == YES && segment.assetSourcePath != nil) {
        newSegment = [LZSessionSegment segmentWithURL:segment.assetSourcePath filter:segment.filter];
        NSAssert(newSegment.url != nil, @"segment must be non-nil");
        if(newSegment) {
            newSegment.isReverse = NO;
            newSegment.assetSourcePath = segment.assetSourcePath;
            newSegment.assetTargetPath = segment.assetTargetPath;
            
            [self.recordSegments removeObject:segment];
            [self.recordSegments insertObject:newSegment atIndex:self.currentSelected];
            
            [self showVideo:NO];
            self.progressView.hidden = YES;
        }
    }
    else {
        WS(weakSelf);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [HKMediaOperationTools assetByReversingAsset:segment.asset videoComposition:nil duration:segment.duration outputURL:tempPath progressHandle:^(CGFloat progress) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    DLog(@"%0.2f %%", progress*100);
                    [self.progressView setProgress:progress animated:YES];
                    
                    if (progress == 1.00) {
                        [self.progressView setProgress:1 animated:YES];
                        newSegment = [LZSessionSegment segmentWithURL:tempPath filter:segment.filter];
                        newSegment.startTime = segment.startTime;
                        newSegment.endTime = segment.endTime;
                        newSegment.isSelect = segment.isSelect;
                        newSegment.isMute = segment.isMute;
                        
                        NSAssert(newSegment.url != nil, @"segment must be non-nil");
                        if(newSegment) {
                            [newSegment setIsReverse:[NSNumber numberWithBool:YES]];
                            [newSegment setAssetSourcePath:segment.url];
                            [newSegment setAssetTargetPath:[tempPath path]];
                            
                            //更新session
                            [weakSelf.recordSegments removeObject:segment];
                            [weakSelf.recordSegments insertObject:newSegment atIndex:weakSelf.currentSelected];
                            
                            [self showVideo:NO];
                            weakSelf.progressView.hidden = YES;
                        }
                    }
                });
            } cancle:&_isReverseCancel];
        });
    }
}

//添加水印
- (void)lzAddWatermark {
    CALayer *waterMark =  [CALayer layer];
    waterMark.backgroundColor = [UIColor greenColor].CGColor;
    waterMark.frame = CGRectMake(8, 8, 20, 20);
//    [self.playerView.layer addSublayer:waterMark];
}

//删除
- (IBAction)lzDeleteButtonAction:(UIButton *)sender {
    if (self.recordSegments.count == 0) {
        return;
    }
    
    if(self.recordSegments.count > 0) {
        [self.recordSegments removeObjectAtIndex:self.currentSelected];
        if (self.currentSelected >= self.recordSegments.count) {
            self.currentSelected = self.recordSegments.count-1;
        }
        [self showVideo:NO];
    }
    
    //这里不能用 else if ，因为当删掉最后一个元素后，self.recordSegments.count 就等于0，需要进入方法内执行。
    if (self.recordSegments.count == 0) {
        self.navigationItem.rightBarButtonItem.enabled = NO;
        
        [self.player pause];
        
//        self.playerView.hidden = YES;
        self.collectionView.hidden  = YES;
        
        self.lzCopyButton.hidden    = YES;
        self.lzVoiceButton.hidden   = YES;
        self.lzDeleteButton.hidden  = YES;
        
        self.hintLabel.hidden = NO;
    }
}

#pragma mark - UICollectionViewDataSource
- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.recordSegments.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identify = @"VideoEditCollectionCell";
    LZVideoEditCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:identify forIndexPath:indexPath];
    LZSessionSegment * segment = self.recordSegments[indexPath.row];
    NSAssert(segment.url != nil, @"segment must be non-nil");
    if (segment) {
        cell.imageView.image = segment.thumbnail;
        if (segment.isSelect == YES) {
            cell.markView.hidden = YES;
            cell.imageView.layer.borderWidth = 1;
            cell.imageView.layer.borderColor = [UIColor greenColor].CGColor;
        }
        else {
            cell.markView.hidden = NO;
            cell.imageView.layer.borderWidth = 0;
            cell.imageView.layer.borderColor = [UIColor clearColor].CGColor;
        }
    }
    
    return cell;
}

#pragma mark - UICollectionViewDelegate
- (void)collectionView:(UICollectionView *)collectionView itemAtIndexPath:(NSIndexPath *)fromIndexPath didMoveToIndexPath:(NSIndexPath *)toIndexPath {
    LZSessionSegment * segment = self.recordSegments[fromIndexPath.row];
    NSAssert(segment.url != nil, @"segment must be non-nil");
    [self.recordSegments removeObject:segment];
    [self.recordSegments insertObject:segment atIndex:toIndexPath.row];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (self.currentSelected == indexPath.row) {
        return;
    }
    self.currentSelected = indexPath.row;
    
    //显示当前片段
    [self showVideo:NO];
}

- (void)dealloc{
    [self.player removeTimeObserver:self.timeObser];
    DLog(@"========= dealloc =========");
}

@end
