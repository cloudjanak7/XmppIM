//
//  RecordManager.m
//  XmppIM
//
//  Created by 任 on 2018/11/9.
//  Copyright © 2018年 RF. All rights reserved.
//

#import "RecordManager.h"


#define kChildPath @"Chat/Recoder"
#define kAmrType @"amr"
#define kMinRecordDuration 1.0  // 最短录音时间

@interface RecordManager() {
    NSDate *_startDate;
    NSDate *_endDate;
    void (^recordFinish)(NSString *recordPath);
}
@property (nonatomic, strong) NSDictionary *recordSetting;

@end

@implementation RecordManager
+ (id)shareManager {
    static id _instance ;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[self alloc] init];
    });
    return _instance;
}


#pragma mark - Getter

- (NSDictionary *)recordSetting {
    if (!_recordSetting) {
        _recordSetting = [[NSDictionary alloc] initWithObjectsAndKeys:
                          [NSNumber numberWithFloat:8000.0],AVSampleRateKey,
                          [NSNumber numberWithInt:kAudioFormatLinearPCM],AVFormatIDKey,
                          [NSNumber numberWithInt:16],AVLinearPCMBitDepthKey,
                          [NSNumber numberWithInt:1],AVNumberOfChannelsKey,
                          nil];
    }
    return _recordSetting;
}


#pragma mark - 公共方法

// 接收到的语音保存路径(文件以fileKey为名字)
- (NSString *)receiveVoicePathWithFileKey:(NSString *)fileKey {
    return [self recorderPathWithFileName:fileKey];
}

// 获取语音时长
- (NSUInteger)durationWithVideo:(NSURL *)voiceUrl {
    NSDictionary *opts = [NSDictionary dictionaryWithObject:@(NO) forKey:AVURLAssetPreferPreciseDurationAndTimingKey];
    AVURLAsset *urlAsset = [AVURLAsset URLAssetWithURL:voiceUrl options:opts]; // 初始化视频媒体文件
    NSUInteger second = 0;
    second = urlAsset.duration.value / urlAsset.duration.timescale; // 获取视频总时长,单位秒
    return second;
}


#pragma mark - 私有方法

// 录音文件路径
- (NSString *)recorderPathWithFileName:(NSString *)fileName {
    NSString *path = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:kChildPath];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirExist = [fileManager fileExistsAtPath:path];
    if (!isDirExist) {
        BOOL isCreatDir = [fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
        if (!isCreatDir) {
            NSLog(@"create folder failed");
            return nil;
        }
    }
    
    return [path stringByAppendingPathComponent:[NSString stringWithFormat:@"%@%@",fileName,kRecoderType]];
}

// 最短录音时间
- (NSTimeInterval)recordMinDuration {
    return kMinRecordDuration;
}






/*********-------录音----------************/
// 开始录音
- (void)startRecordingWithFileName:(NSString *)fileName completion:(void(^)(NSError *error))completion {
    NSError *error = nil;
    if (![[RecordManager shareManager] canRecord]) {
        UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"无法录音" message:@"请在iPhone的“设置-隐私-麦克风”选项中，允许iCom访问你的手机麦克风。" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil, nil];
        [alert show];
        if (completion) {
            error = [NSError errorWithDomain:NSLocalizedString(@"error", @"没权限") code:122 userInfo:nil];
            completion(error);
        }
        return;
    }
    if ([_recorder isRecording]) {
        [_recorder stop];
        [self cancelCurrentRecording];
        return;
    } else {
        NSString *wavFilePath = [self recorderPathWithFileName:fileName];
        NSURL *wavUrl = [[NSURL alloc] initFileURLWithPath:wavFilePath];
        // 在实例化AVAudioRecorder之前，先开启会话,否则真机上录制失败
        AVAudioSession *session = [AVAudioSession sharedInstance];
        NSError *setCategoryError = nil;
        [session setCategory:AVAudioSessionCategoryPlayAndRecord error:&setCategoryError];
        if(setCategoryError){
            NSLog(@"%@", [setCategoryError description]);
        }
        
        _recorder = [[AVAudioRecorder alloc] initWithURL:wavUrl settings:self.recordSetting error:&error];
        _recorder.meteringEnabled = YES;
        if (!_recorder || error) {
            _recorder = nil;
            if (completion) {
                error = [NSError errorWithDomain:NSLocalizedString(@"error.initRecorderFail", @"Failed to initialize AVAudioRecorder") code:123 userInfo:nil];
                completion(error);
            }
            return;
        }
        _startDate = [NSDate date];
        _recorder.meteringEnabled = YES;
        _recorder.delegate = self;
        [_recorder record];
        if (completion) {
            completion(error);
        }
    }
}

// 结束录音
- (void)stopRecordingWithCompletion:(void(^)(NSString *recordPath))completion {
    //    [self.recorder stop];
    _endDate = [NSDate date];
    if ([_recorder isRecording]) {
        if ([_endDate timeIntervalSinceDate:_startDate] < [self recordMinDuration]) {
            if (completion) {
                completion(kShortRecord);
            }
            [self.recorder stop];
            [self cancelCurrentRecording];
            sleep(1.0);//a temporary method，let it sheep a minute,because recorder generated need time，to prevented clicked quickly situation
            NSLog(@"record time duration is too short");
            return;
        }
        recordFinish = completion;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self.recorder stop];
            NSLog(@"record time duration :%f", [_endDate timeIntervalSinceDate:_startDate]);
        });
    }
}


// 是否拥有权限
- (BOOL)canRecord {
    __block BOOL bCanRecord = YES;
    if ([[[UIDevice currentDevice]systemVersion]floatValue] >= 7.0) {
        
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        if ([audioSession respondsToSelector:@selector(requestRecordPermission:)]) {
            [audioSession performSelector:@selector(requestRecordPermission:) withObject:^(BOOL granted) {
                if (granted) {
                    bCanRecord = YES;
                } else {
                    bCanRecord = NO;
                }
            }];
        }
    }
    NSLog(@"bCanRecord1 : %d",bCanRecord);
    return bCanRecord;
}

// 取消当前录制
- (void)cancelCurrentRecording {
    _recorder.delegate = nil;
    if (_recorder.recording) {
        [_recorder stop];
    }
    _recorder = nil;
    recordFinish = nil;
}


// 移除音频
- (void)removeCurrentRecordFile:(NSString *)fileName {
    [self cancelCurrentRecording];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *path = [self recorderPathWithFileName:fileName];
    BOOL isDirExist = [fileManager fileExistsAtPath:path];
    if (isDirExist) {
        [fileManager removeItemAtPath:path error:nil];
    }
}

#pragma mark - AVAudioRecorderDelegate 录音代理
// 结束录音 代理
- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder
                           successfully:(BOOL)flag {
    NSString *recordPath = [[_recorder url] path];
    // 音频转换
    NSString *amrPath = [[recordPath stringByDeletingPathExtension] stringByAppendingPathExtension:kAmrType];
    [EMVoiceConverter wavToAmr:recordPath amrSavePath:amrPath];
    if (recordFinish) {
        if (!flag) {
            recordPath = nil;
        }
        recordFinish(recordPath);
    }
    _recorder = nil;
    recordFinish = nil;
}

// 出错
- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder
                                   error:(NSError *)error {
    NSLog(@"audioRecorderEncodeErrorDidOccur");
}







#pragma mark - *********-------播放录音----------************

// 开始播放
//- (void)startPlayRecorder:(NSString *)recorderPath {
////    [self.player stop];
////    self.player = nil;  // clear previous player
//
//    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
//    NSError *err = nil;  // 加上这两句，否则声音会很小
//    [audioSession setCategory :AVAudioSessionCategoryPlayback error:&err];
//    self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:recorderPath] error:nil];
//    self.player.numberOfLoops = 0;
//    [self.player prepareToPlay];
//    self.player.delegate = self;
//    [self.player play];
//}

// 开始播放
- (void)startPlayRecorder:(NSData *)data {
    //    [self.player stop];
    //    self.player = nil;  // clear previous player
    
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSError *err = nil;  // 加上这两句，否则声音会很小
    [audioSession setCategory :AVAudioSessionCategoryPlayback error:&err];
    self.player = [[AVAudioPlayer alloc] initWithData:data error:nil];
    self.player.numberOfLoops = 0;
    [self.player prepareToPlay];
    self.player.delegate = self;
    [self.player play];
}

// 结束播放
- (void)stopPlayRecorder {
    [self.player stop];
    self.player = nil;
    self.player.delegate = nil;
}

// 暂停
- (void)pause {
    [self.player pause];
}

#pragma mark - AVAudioPlayerDelegate 播放音频代理
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player
                       successfully:(BOOL)flag {
    [self stopPlayRecorder];
    
    if (self.voiceDidPlayFinishedBlock) {
        self.voiceDidPlayFinishedBlock();
    }
}



@end
