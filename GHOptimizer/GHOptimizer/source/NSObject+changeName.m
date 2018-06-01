//
//  NSObject+changeName.m
//  GHOptimizer
//
//  Created by Guanghui Liao on 5/31/18.
//  Copyright © 2018 liaoworking. All rights reserved.
//

#import "NSObject+changeName.h"
#import <objc/runtime.h>

bool should_intercept_message(Class cls, SEL sel)
{
    return [NSStringFromSelector(sel) hasPrefix:@"__WZQMessageTemporary"];
}

void method_swizzle(Class cls, SEL origSEL, SEL newSEL)
{
    Method origMethod = class_getInstanceMethod(cls, origSEL);
    Method newMethod = class_getInstanceMethod(cls, newSEL);
    
    if (class_addMethod(cls, origSEL, method_getImplementation(newMethod), method_getTypeEncoding(newMethod))) {
        class_replaceMethod(cls, newSEL, method_getImplementation(origMethod), method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, newMethod);
    }
}


#pragma mark - WZQMessageStub
@interface WZQMessageStub : NSObject

- (instancetype)initWithTarget:(id)target selector:(SEL)temporarySEL;

@end

@interface WZQMessageStub()
@property (nonatomic, unsafe_unretained) id target;
@property (nonatomic) SEL selector;
@end

@implementation WZQMessageStub

- (instancetype)initWithTarget:(id)target selector:(SEL)temporarySEL
{
    self = [super init];
    if (self) {
        _target = target;
        
        NSString *finalSELStr = [NSStringFromSelector(temporarySEL) stringByReplacingOccurrencesOfString:@"__WZQMessageTemporary_" withString:@"__WZQMessageFinal_"];
        _selector = NSSelectorFromString(finalSELStr);
    }
    return self;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    Method m = class_getInstanceMethod(object_getClass(self.target), self.selector);
    assert(m);
    return [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    anInvocation.target = self.target;
    anInvocation.selector = self.selector;
    
    if (![NSThread isMainThread]) {
        NSLog(@"===============[libMainThreadChecker.dylib]::%@ should be called within main thread only================\n", NSStringFromSelector(self.selector));
    }
    
    [anInvocation invoke];
}

@end




@implementation NSObject (changeName)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        method_swizzle(self, @selector(forwardingTargetForSelector:), @selector(wzq_forwardingTargetForSelector:));
    });
}

- (id)wzq_forwardingTargetForSelector:(SEL)temporarySEL
{
    if (should_intercept_message(object_getClass(self), temporarySEL) && ![self isKindOfClass:[WZQMessageStub class]]) {
        return [[WZQMessageStub alloc] initWithTarget:self selector:temporarySEL];
    }
    
    return [self wzq_forwardingTargetForSelector:temporarySEL];
}

@end


