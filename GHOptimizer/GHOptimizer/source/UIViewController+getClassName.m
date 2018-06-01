//
//  UIViewController+getClassName.m
//  GHOptimizer
//
//  Created by Guanghui Liao on 5/30/18.
//  Copyright © 2018 liaoworking. All rights reserved.
//

#import "UIViewController+getClassName.h"
#import "GHOptimizer.h"
@implementation UIViewController (getClassName)

+(void)load {
    NSLog(@"load这里加载到的类%@",NSStringFromClass(self.class));

//    [GHOptimizer forwardingClasses:@[
//                                     NSStringFromClass([self class]),
//                                     ]
//                        logOptions:CJLogDefault|CJLogMethodReturnValue|CJLogMethodTimer|CJLogMethodArgs
//                        logEnabled:YES];
}

+ (void)initialize{
    
    NSString *str = NSStringFromClass(self.class);
    NSArray *array = @[@"UISplitViewController",@"UITableViewController",@"UIViewController",@"UINavigationController",@"UITabBarController",@"UICollectionViewController",@""];
    
    if ([array containsObject:str]) {
        return;
    }
    NSLog(@"这里加载到的类%@",NSStringFromClass(self.class));
    
        [GHOptimizer forwardingClasses:@[
                                         NSStringFromClass(self.class),
                                         ]
                            logOptions:CJLogDefault|CJLogMethodReturnValue|CJLogMethodTimer|CJLogMethodArgs
                            logEnabled:YES];


    
    
    
    ///要过滤的基类名单
    /*
     UISplitViewController
     UITableViewController
     UIViewController
     UINavigationController
     UITabBarController
     
     
     NSLog(@"获取到的类是--%@，一开始的SEL是%@",cls, originSelector);
     NSLog(@"原始类型是---%@",originMethod);
     NSLog(@"原始方法实现是---%@",originIMP);
     NSLog(@"新的SEL是---%@",newSelecotr);
     NSLog(@"给这个类添加的一个新方法有没有成功---%@",addSucess);
     */
}

@end
