//
//  VWLimitBreaker.h
//  VWBreakLimit
//
//  Created by VoiceWitness on 2017/3/23.
//  Copyright © 2017年 voicewitness. All rights reserved.
//

#import <Foundation/Foundation.h>

#define Bytes_M (1024*1024.0f)

#define Bytes_K (1024.0f)

typedef NS_ENUM(NSInteger, VWLogLevel) {
    VWLogLevelNone,
    VWLogLevelProcedure,
    VWLogLevelElementInfo,
    VWLogLevelRunningDetail,
    VWLogLevelAll
};


@class AFHTTPSessionManager;

NS_ASSUME_NONNULL_BEGIN

@interface VWBreakerTask : NSObject

@property (nonatomic, strong) AFHTTPSessionManager *manager;

@property (nonatomic, strong, nullable) dispatch_queue_t completionQueue;

@end

@interface VWLimitBreaker : NSObject

@property (nonatomic, class, assign) VWLogLevel logLevel;

//@property (nonatomic)
- (void)downloadWithMethod:(NSString *)method URLString:(NSString *)URLString bandwidth:(double)bandwidth limit:(double)limit progress:(void (^)(NSProgress *downloadProgress))downloadProgress completionHandler:(void(^)(NSURL *filePath, NSError *error))completionHandler;

@end

NS_ASSUME_NONNULL_END
