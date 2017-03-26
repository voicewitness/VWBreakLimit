//
//  VWDownloadListViewController.m
//  VWBreakLimit
//
//  Created by VoiceWitness on 2017/3/22.
//  Copyright © 2017年 voicewitness. All rights reserved.
//

#import "VWDownloadListViewController.h"
#import "VWDownloadCell.h"
#import <AFNetworking/AFNetworking.h>
#import "VWLimitBreaker.h"

#define Byte_M (1024*1024.0f)
#define Byte_K 1024.0f

@interface VWDownloadListViewController ()<UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) VWDownloadCell *cell;

@property (nonatomic, strong) NSMutableArray *tasks;

@property (nonatomic, strong) AFHTTPSessionManager *manager;

@property (nonatomic, strong) NSTimer *timer;

@property (nonatomic, assign) int64_t lastCompletedCount;

@property (nonatomic, assign) int64_t currentCompletedCount;

@property (nonatomic, assign) int64_t totalUnitCount;

@end

@implementation VWDownloadListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addTask)];
    self.navigationController.navigationBar.tintColor = [UIColor redColor];
    // Do any additional setup after loading the view.
    VWDownloadCell *cell = [[[NSBundle mainBundle]loadNibNamed:@"VWDownloadCell" owner:self options:nil]lastObject];
    self.cell = cell;
    self.tasks = [NSMutableArray new];
    self.manager = [AFHTTPSessionManager manager];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    NSTimer *timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer * _Nonnull timer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.cell.speedLabel.text = [NSString stringWithFormat:@"%.2fKB/s",(self.currentCompletedCount-self.lastCompletedCount)/Byte_K];
            self.lastCompletedCount = self.currentCompletedCount;
        });
    }];
    [[NSRunLoop mainRunLoop]addTimer:timer forMode:NSRunLoopCommonModes];
    [timer setFireDate:[NSDate distantFuture]];
    self.timer = timer;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)addTask {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"add" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.font = [UIFont systemFontOfSize:13];
        textField.textColor = [UIColor blackColor];
    }];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"ok" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self GET:alert.textFields.firstObject.text];
    }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"cancel" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
    }];
    [alert addAction:okAction];
    [alert addAction:cancelAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)GET:(NSString *)URLString {
    [self.timer setFireDate:[NSDate date]];
    VWLimitBreaker.logLevel = VWLogLevelAll;
    VWLimitBreaker *breaker = [VWLimitBreaker new];
    [breaker downloadWithMethod:@"GET" URLString:URLString bandwidth:2*Bytes_M limit:200*Bytes_K progress:^(NSProgress *downloadProgress) {
        
        NSLog(@"mainprogress completed: %zd",downloadProgress.completedUnitCount);
        int64_t completedUnitCount = downloadProgress.completedUnitCount;
        int64_t totalUnitCount = downloadProgress.totalUnitCount;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.currentCompletedCount = completedUnitCount;
            self.totalUnitCount = totalUnitCount;
            self.cell.fileSizeLabel.text = [NSString stringWithFormat:@"%fMB/%fMB",completedUnitCount/Byte_M,totalUnitCount/Byte_M];
            self.cell.progressView.progress = completedUnitCount/totalUnitCount;
        });
    } completionHandler:^(NSURL *filePath, NSError *error) {
        self.timer = nil;
    }];
    [self.tasks removeAllObjects];
    [self.tasks addObject:URLString?:@""];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.tasks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 200;
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
