//
//  VWDownloadCell.h
//  VWBreakLimit
//
//  Created by VoiceWitness on 2017/3/22.
//  Copyright © 2017年 voicewitness. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface VWDownloadCell : UITableViewCell
@property (weak, nonatomic) IBOutlet UIProgressView *progressView;
@property (weak, nonatomic) IBOutlet UILabel *fileSizeLabel;
@property (weak, nonatomic) IBOutlet UILabel *speedLabel;

@end
