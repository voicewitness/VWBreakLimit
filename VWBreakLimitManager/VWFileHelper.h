//
//  VWFileHelper.h
//  VWBreakLimit
//
//  Created by VoiceWitness on 25/03/2017.
//  Copyright © 2017 voicewitness. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface VWFileHelper : NSObject

+ (void)mergeFileFromPath:(NSString *)from toPath:(NSString *)to;

+ (void)mergeFileFromURL:(NSURL *)from toURL:(NSURL *)to error:(NSError **)error;

@end
