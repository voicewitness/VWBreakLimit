//
//  VWBreakLimitManager.m
//  VWBreakLimit
//
//  Created by VoiceWitness on 2017/3/23.
//  Copyright © 2017年 voicewitness. All rights reserved.
//

#import "VWLimitBreaker.h"
#import <AFNetworking/AFNetworking.h>
#import "VWFileHelper.h"


#define VWLog(baseLevel, format, ...) if([[VWLimitBreaker class]logLevel]>baseLevel)NSLog(format, ##__VA_ARGS__)

typedef void (^VWBreakerTaskProgressBlock)(NSProgress *progress);

typedef void (^VWBreakerCompletionHandler)(NSURL *filePath, NSError *error);

typedef void (^AFCompletionHandler)(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error);

typedef NS_ENUM(NSInteger, BreakerRunningState) {
    BreakerRunningStateWait,
    BreakerRunningStateLeading,
    BreakerRunningStateLeadingEnd,
    BreakerRunningStateDispatched,
    BreakerRunningStateCompleted,
    BreakerRunningStateCompletedError
};

@interface VWSessionTaskInfo : NSObject

@property (nonatomic) BOOL fileReady;

@property (nonatomic, copy) NSURL *desitnation;

@property (nonatomic, copy) AFCompletionHandler completionHandler;

@property (nonatomic, copy) VWBreakerTaskProgressBlock downloadProgressBlock;

@property (nonatomic, weak) NSURLSessionDownloadTask *task;

@property (nonatomic, strong) NSError *error;

@end

@implementation VWSessionTaskInfo

@end

@interface VWBreakerTask()

@property (nonatomic, strong) NSMutableDictionary *mutableSessionTaskInfosKeyedByTaskIdentifier;

@property (nonatomic, strong) NSMutableArray *taskIdentifierQueue;

@property (nonatomic, strong) NSMutableArray *observedTasksProgress;

@property (nonatomic, strong) NSMutableArray *mutableFailedTaskInfos;

@property (nonatomic, strong) NSProgress *downloadProgress;

@property (nonatomic) double limit;

@property (nonatomic) double bandwidth;

@property (nonatomic) double totalUnitCount;

@property (nonatomic) NSUInteger expectedTasksCount;

@property (nonatomic) BreakerRunningState state;

@property (nonatomic, strong) NSString *URLString;

@property (nonatomic, strong) NSString *method;

@property (nonatomic, copy) VWBreakerTaskProgressBlock downloadProgressBlock;

@property (nonatomic, copy) VWBreakerCompletionHandler completionHandler;

@property (nonatomic, copy) NSURL *cacheDirecotry;

//@property (nonatomic, strong) NSMutableArray *garbageFilePaths;

@property (nonatomic, copy) NSURL *destination;

//@property (nonatomic) NSUInteger maximumActiveDownloads;

@end

@implementation VWBreakerTask {
    dispatch_queue_t _statisticsQueue;
//    dispatch_queue_t _sessionTasksCompetionQueue;
    dispatch_queue_t _ioQueue;
}

static NSURL *_sysCacheDirectory;

- (instancetype)initWithMethod:(NSString *)method URLString:(NSString *)URLString bandwidth:(double)bandwidth limit:(double)limit AFManager:(AFHTTPSessionManager *)manager destination:(NSURL *)destination progress:(void(^)(NSProgress *progress))progressBlock completionHandler:(VWBreakerCompletionHandler)completionHandler {
    self = [super init];
    if (!manager) {
        manager = [AFHTTPSessionManager manager];
    }
    _statisticsQueue = dispatch_queue_create("com.voicewh.limitbreak.statistics", DISPATCH_QUEUE_CONCURRENT);
//    _sessionTasksCompetionQueue = dispatch_queue_create("com.voicewh.limitbreak.sessiontasks", DISPATCH_QUEUE_CONCURRENT);
    _ioQueue = dispatch_queue_create("com.voicewh.limitbreak.io", DISPATCH_QUEUE_CONCURRENT);
    NSProgress *downloadProgress = [[NSProgress alloc]initWithParent:nil userInfo:nil];
    [downloadProgress addObserver:self forKeyPath:NSStringFromSelector(@selector(fractionCompleted)) options:NSKeyValueObservingOptionNew context:NULL];
    self.downloadProgress = downloadProgress;
    
    self.mutableSessionTaskInfosKeyedByTaskIdentifier = [NSMutableDictionary new];
    self.taskIdentifierQueue = [NSMutableArray new];
    self.observedTasksProgress = [NSMutableArray new];
    self.mutableFailedTaskInfos = [NSMutableArray new];
    
    NSTimeInterval timestamp = [[NSDate date]timeIntervalSince1970];
    [self createDirectoryBasedTimestamp:timestamp];
    
    self.manager = manager;
    self.method = method;
    self.URLString = URLString;
    self.bandwidth = bandwidth;
    self.limit = limit;
    self.destination = destination;
//    self.maximumActiveDownloads = 1;
    self.downloadProgressBlock = progressBlock;
    self.completionHandler = completionHandler;
    
//    self.leadingState = BreakerRunningStateLeading;
//    dispatch_async(dispatch_get_main_queue(), ^{
//        [self leadWayWithMethod:method URLString:URLString success:^(int64_t totalUnitCount) {
//            self.totalUnitCount = totalUnitCount;
//        } failed:^(NSError *error) {
//        }];
//    });
    
    return self;
}

- (void)createDirectoryBasedTimestamp:(double)timestamp {
//    dispatch_barrier_async(_ioQueue, ^{
        NSFileManager *fileManager = [NSFileManager defaultManager];
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            _sysCacheDirectory = [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask]lastObject];
        });
        NSURL *directory = [_sysCacheDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"%zd",timestamp] isDirectory:YES];
        if (![fileManager fileExistsAtPath:[directory absoluteString]]) {
            NSError *creationError = nil;
            [fileManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&creationError];
            if (creationError) {
                VWLog(VWLogLevelProcedure,@"\n>>>>>>>>>>>>\ncreate directory error:%@\n<<<<<<<<<<<<", creationError);
            }
            self.cacheDirecotry = directory;
        } else {
            [self createDirectoryBasedTimestamp:timestamp+1];
        }
//    });
}

- (void)resume {
    if (self.state != BreakerRunningStateWait &&
        self.state != BreakerRunningStateCompleted &&
        self.state != BreakerRunningStateCompletedError) {
        VWLog(VWLogLevelProcedure,@"\n>>>>>>>>>>>>\nbreaker task is already running\n<<<<<<<<<<<<");
        return;
    }
    VWLog(VWLogLevelProcedure,@"\n>>>>>>>>>>>>\nbreaker task resumed\n<<<<<<<<<<<<");
    [self leadWayWithMethod:self.method URLString:self.URLString success:^(int64_t totalUnitCount) {
        VWLog(VWLogLevelProcedure,@"\n>>>>>>>>>>>>\nleading task ended\n<<<<<<<<<<<<");
            self.totalUnitCount = totalUnitCount;
            self.downloadProgress.totalUnitCount = totalUnitCount;
            [self dispatchWithMethod:self.method URLString:self.URLString bandwidth:self.bandwidth limit:self.limit totalCount:self.totalUnitCount];
    } failed:^(NSError *error) {
        VWLog(VWLogLevelProcedure,@"\n>>>>>>>>>>>>\nleading task failed:%@\n<<<<<<<<<<<<",error);
    }];
}

- (void)leadWayWithMethod:(NSString *)method URLString:(NSString *)URLString success:(void(^)(int64_t totalUnitCount))successHandler failed:(void(^)(NSError *error))failureHandler {
    self.state = BreakerRunningStateLeading;
    VWSessionTaskInfo *info = [VWSessionTaskInfo new];
    __weak typeof(info) winfo = info;
    info.downloadProgressBlock = ^(NSProgress * _Nonnull downloadProgress) {
        __strong typeof(winfo) info = winfo;
        [info.task cancel];
        if (self.state == BreakerRunningStateLeading) {
            self.state = BreakerRunningStateLeadingEnd;
            !successHandler?:successHandler(downloadProgress.totalUnitCount);
        }
    };
    NSMutableURLRequest *leaderRequest = [self.manager.requestSerializer requestWithMethod:method URLString:URLString parameters:nil error:nil];
    NSURLSessionDownloadTask *leaderTask = [self.manager downloadTaskWithRequest:leaderRequest progress:^(NSProgress * _Nonnull downloadProgress) {
        info.downloadProgressBlock(downloadProgress);
    } destination:nil completionHandler:^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
        if (error && error.code!=-999) {
            self.state = BreakerRunningStateCompletedError;
            !failureHandler?:failureHandler(error);
        } else {
            // if file is tiny, no need for breaker
            self.destination = [self.cacheDirecotry URLByAppendingPathComponent:response.suggestedFilename];
            self.state = BreakerRunningStateCompleted;
        }
    }];
    info.task = leaderTask;
    [leaderTask resume];
}

- (void)dispatchWithMethod:(NSString *)method URLString:(NSString *)URLString bandwidth:(double)bandwidth limit:(double)limit totalCount:(int64_t)totalCount {
    
    VWLog(VWLogLevelProcedure,@"\n>>>>>>>>>>>>\nstart dispatching session tasks\n<<<<<<<<<<<<");
    NSUInteger tasksCount = round(bandwidth/limit);
    self.expectedTasksCount = tasksCount;
    int64_t dataCount = totalCount;
    int64_t perTaskDataCount = dataCount/tasksCount;
    for (NSInteger i = 0; i < tasksCount; i++) {
        int64_t start = perTaskDataCount * i;
        int64_t end = perTaskDataCount * (i+1) - 1;
        if (i == tasksCount-1 && end < dataCount-1) {
            end = dataCount-1;
        }
        NSURL *taskDestination = [self.cacheDirecotry URLByAppendingPathComponent:[NSString stringWithFormat:@"tmp%ld",i]];
        
        VWLog(VWLogLevelProcedure,@"\n>>>>>>>>>>>>\nbuilding session task index:%zd\n<<<<<<<<<<<<",i);
        VWLog(VWLogLevelElementInfo,@"\ntask destination:%@",[taskDestination absoluteString]);
        NSURLSessionDownloadTask *task = [self downloadTaskWithMethod:method URLString:URLString start:start end:end destination:taskDestination];
//        task.taskDescription = [self taskDescriptionForTask:task];
        [self.taskIdentifierQueue addObject:@(task.taskIdentifier)];
//        if (self.taskIdentifierQueue.count == 1) {
            [task resume];
//        }
        
    }
    self.state = BreakerRunningStateDispatched;
    VWLog(VWLogLevelProcedure,@"\n>>>>>>>>>>>>\nend dispatching session tasks, count:%zd\n<<<<<<<<<<<<",tasksCount);
}

- (NSMutableURLRequest *)requestWithMethod:(NSString *)method URLString:(NSString *)URLString start:(int64_t)start end:(int64_t)end {
    NSMutableURLRequest *mutableReqeust = [self.manager.requestSerializer requestWithMethod:method URLString:URLString parameters:nil error:nil];
    [mutableReqeust setValue:[NSString stringWithFormat:@"bytes=%lld-%lld", start, end] forHTTPHeaderField:@"Range"];
    VWLog(VWLogLevelElementInfo,@"\nrequest:%@ start:%lld end:%lld\n", mutableReqeust, start, end);
    return mutableReqeust;
}

- (NSURLSessionDownloadTask *)downloadTaskWithMethod:(NSString *)method URLString:(NSString *)URLString start:(int64_t)start end:(int64_t)end destination:(NSURL *)destination{
    VWSessionTaskInfo *info = [VWSessionTaskInfo new];
    info.desitnation = destination;
    __weak typeof(info) winfo = info;
    info.completionHandler = ^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
        __strong typeof(winfo) info = winfo;
        VWLog(VWLogLevelAll,@"response:%@", response);
        if (error) {
            info.error = error;
            [self.mutableFailedTaskInfos addObject:info];
            VWLog(VWLogLevelProcedure,@"\n>>>>>>>>>>>>\ntask error:%@\n<<<<<<<<<<<<", error);
        } else {
            VWLog(VWLogLevelProcedure,@"\n>>>>>>>>>>>>\ntask succeed\n<<<<<<<<<<<<");
            [self downloadTaskCompleted:info.task];
        }
    };
    NSMutableURLRequest *mutableRequest = [self requestWithMethod:method URLString:URLString start:start end:end];
    NSURLSessionDownloadTask *task = [self.manager downloadTaskWithRequest:mutableRequest progress:^(NSProgress * _Nonnull downloadProgress) {
        VWLog(VWLogLevelElementInfo,@"progree:%p completed:%lld",downloadProgress,downloadProgress.completedUnitCount);
        [self updateProgress:downloadProgress];
    } destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
        return destination;
    } completionHandler:info.completionHandler];
    info.task = task;
    [self.mutableSessionTaskInfosKeyedByTaskIdentifier setObject:info forKey:@(task.taskIdentifier)];
    task.taskDescription = [self taskDescriptionForTask:task];
    VWLog(VWLogLevelElementInfo,@"task:%@", task);
    return task;
}

- (NSString *)taskDescriptionForTask:(NSURLSessionTask *)task {
    return [NSString stringWithFormat:@"%p",task];
}

- (void)downloadTaskCompleted:(NSURLSessionDownloadTask *)task {
    [self downloadTaskFileNeedMerge:task];
}

- (void)downloadTaskFileNeedMerge:(NSURLSessionDownloadTask *)task {
    self.expectedTasksCount--;
    VWSessionTaskInfo *info = self.mutableSessionTaskInfosKeyedByTaskIdentifier[@(task.taskIdentifier)];
    info.fileReady = YES;
    [self downloadTaskFileNeedMergeWithTaskIdentifier:task.taskIdentifier];
}

- (void)downloadTaskFileNeedMergeWithTaskIdentifier:(NSUInteger)identifier {
    VWSessionTaskInfo *info = self.mutableSessionTaskInfosKeyedByTaskIdentifier[@(identifier)];
    if ([self.mutableFailedTaskInfos containsObject:info]) {
        // add retry logic if need
        self.state = BreakerRunningStateCompletedError;
        !self.completionHandler?:self.completionHandler(nil, info.error);
        VWLog(VWLogLevelProcedure,@"\n>>>>>>>>>>>>\nbreakertask completed error:%@\n<<<<<<<<<<<<",info.error);
        return;
    }
    if([self.taskIdentifierQueue indexOfObject:@(identifier)]==0 && info.fileReady) {
        dispatch_barrier_async(_ioQueue, ^{
            if([self.taskIdentifierQueue indexOfObject:@(identifier)]!=NSNotFound) {
                VWLog(VWLogLevelProcedure,@"\n>>>>>>>>>>>>\nmerge downloaded file task identifier:%zd\n<<<<<<<<<<<<", identifier);
                NSError *mergeError = nil;
                [VWFileHelper mergeFileFromURL:info.desitnation toURL:self.destination error:&mergeError];
                if (mergeError) {
                    VWLog(VWLogLevelProcedure,@"\n>>>>>>>>>>>>\nmerge error:%@\n<<<<<<<<<<<<", mergeError);
                } else {
                    VWLog(VWLogLevelProcedure,@"\n>>>>>>>>>>>>\nmerge succeed\n<<<<<<<<<<<<");
                }
                [self cleanDownloadTaskWithIdentifier:identifier];
            }
            if (self.expectedTasksCount == 0) {
                self.state = BreakerRunningStateCompleted;
                !self.completionHandler?:self.completionHandler(self.destination, nil);
                VWLog(VWLogLevelProcedure,@"\n>>>>>>>>>>>>\nbreakertask completed\n<<<<<<<<<<<<");
            } else {
                [self downloadTaskFileNeedMergeWithTaskIdentifier:[self.taskIdentifierQueue.firstObject unsignedIntegerValue]];
            }
        });
    }
}

- (void)updateProgress:(NSProgress *)progress {
    if (DISPATCH_EXPECT(![self.observedTasksProgress containsObject:progress],0)) {
        self.downloadProgress.completedUnitCount += progress.completedUnitCount;
        [self.observedTasksProgress addObject:progress];
        [progress addObserver:self forKeyPath:@"completedUnitCount" options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:NULL];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([self.observedTasksProgress containsObject:object]) {
        int64_t newValue = [change[NSKeyValueChangeNewKey] longLongValue];
        int64_t oldValue = [change[NSKeyValueChangeOldKey] longLongValue];
        VWLog(VWLogLevelAll,@"\n>>>>>>>>>>>>\nupdating sub progress:%@\n<<<<<<<<<<<<",self.downloadProgress);
        if (DISPATCH_EXPECT([(NSProgress *)object totalUnitCount] == newValue, 0)) {
            [object removeObserver:self forKeyPath:@"completedUnitCount"];
        }
        dispatch_barrier_async(_statisticsQueue, ^{
            self.downloadProgress.completedUnitCount += newValue - oldValue;
        });
    } else if([object isEqual:self.downloadProgress]) {
        
        VWLog(VWLogLevelRunningDetail,@"\n>>>>>>>>>>>>\nupdating main progress:%@\n<<<<<<<<<<<<",self.downloadProgress);
        !self.downloadProgressBlock?:self.downloadProgressBlock(object);
    }
}

- (void)cleanDownloadTaskWithIdentifier:(NSUInteger)identifier {
    [self.mutableSessionTaskInfosKeyedByTaskIdentifier removeObjectForKey:@(identifier)];
    [self.taskIdentifierQueue removeObject:@(identifier)];
}

@end

@interface VWLimitBreaker()

@property (nonatomic, strong) NSMutableArray<VWBreakerTask *> *tasks;

@end

static VWLogLevel _logLevel;

@implementation VWLimitBreaker

+ (instancetype)breaker {
    return [[self alloc]init];
}

- (void)downloadWithMethod:(NSString *)method URLString:(NSString *)URLString bandwidth:(double)bandwidth limit:(double)limit progress:(void (^)(NSProgress *downloadProgress))downloadProgress completionHandler:(void(^)(NSURL *filePath, NSError *error))completionHandler {
    
    VWBreakerTask *task = [[VWBreakerTask alloc]initWithMethod:method URLString:URLString bandwidth:bandwidth limit:limit AFManager:nil destination:nil progress:downloadProgress completionHandler:completionHandler];
    [self.tasks addObject:task];
    [task resume];
}

+ (VWLogLevel)logLevel {
    return _logLevel;
}

+ (void)setLogLevel:(VWLogLevel)logLevel {
    _logLevel = logLevel;
}


@end
