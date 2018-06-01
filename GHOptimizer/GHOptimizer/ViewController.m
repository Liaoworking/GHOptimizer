//
//  ViewController.m
//  GHOptimizer
//
//  Created by Guanghui Liao on 5/30/18.
//  Copyright © 2018 liaoworking. All rights reserved.
//

#import "ViewController.h"
#import "GHNextViewController.h"
@interface ViewController ()

@end

@implementation ViewController

- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    
}


- (void)viewDidLoad {
    [super viewDidLoad];
    [self ghtesttt];
    
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    GHNextViewController *nextVC = [GHNextViewController new];
    [self presentViewController:nextVC animated:true completion:nil];
}


- (void)ghtesttt {
    [self INNerTest];
}

- (void)INNerTest {
    NSLog(@"887887887");
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
