//
//  VWFileHelper.m
//  VWBreakLimit
//
//  Created by VoiceWitness on 25/03/2017.
//  Copyright © 2017 voicewitness. All rights reserved.
//

#import "VWFileHelper.h"

@implementation VWFileHelper

+ (void)mergeFileFromPath:(NSString *)from toPath:(NSString *)to {
    [self mergeFileFromURL:[NSURL fileURLWithPath:from] toURL:[NSURL fileURLWithPath:to] error:nil];
}

+ (void)mergeFileFromURL:(NSURL *)from toURL:(NSURL *)to error:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:[to path]]) {
        [fileManager moveItemAtURL:from toURL:to error:error];
        return;
    }
    NSFileHandle *writerHandle = [NSFileHandle fileHandleForUpdatingURL:to error:nil];
    [writerHandle seekToEndOfFile];
    
    NSData *readerData = [NSData dataWithContentsOfURL:from options:NSDataReadingMappedIfSafe error:nil];
    [writerHandle writeData:readerData];
    [writerHandle synchronizeFile];
}

@end
