//
//  GHOptimizer.m
//  GHOptimizer
//
//  Created by Guanghui Liao on 5/30/18.
//  Copyright © 2018 liaoworking. All rights reserved.
//

#import "GHOptimizer.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <UIKit/UIKit.h>

static NSString *_CJMethodPrefix = @"cjlMethod_";/*新增方法前缀*/
static NSInteger _CJDeep = -1;/*调用方法层级*/


typedef void (*_VIMP)(id, SEL, ...);
typedef id (*_IMP)(id, SEL, ...);

static NSMutableArray *_hookedClassList = nil;/*保存已被hook的类名*/
static NSMutableDictionary *_hookClassMethodDic = nil;/*记录已被hook的类的方法列表*/
//static CJLogger *_logger;
static BOOL _logEnable = NO;/*是否打印CJMethodLog的log信息*/

#pragma mark - Function Define
BOOL inMainBundle(Class hookClass);/*判断是否为自定义类*/
BOOL haveHookClass(Class hookClass);
BOOL enableHook(Method method);
BOOL inBlackList(NSString *methodName);
BOOL forwardInvocationReplaceMethod(Class cls, SEL originSelector, CJLogOptions options);


/**
 看当前的bundle有没有这个类
 
 @param hookClass 类名
 @return 有木有
 */
BOOL inMainBundle(Class hookClass) {
    NSBundle *currentBundle = [NSBundle bundleForClass:hookClass];
    return [currentBundle.bundlePath hasPrefix:[NSBundle mainBundle].bundlePath];
}


/**
 判断这个类有没有被hook
 
 @param hookClass 类型
 @return 有木有
 */
BOOL haveHookClass(Class hookClass) {
    NSString *className = NSStringFromClass(hookClass);
    return ([_hookedClassList containsObject:className]);
}

BOOL enableHook(Method method) {
    //若在黑名单中则不处理
    NSString *selectorName = NSStringFromSelector(method_getName(method));
    if (inBlackList(selectorName)) return NO;
    
    if ([selectorName rangeOfString:_CJMethodPrefix].location != NSNotFound) return NO;
    
    return YES;
}

BOOL inBlackList(NSString *methodName) {
    static NSArray *defaultBlackList = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaultBlackList = @[/*UIViewController的:*/
                             @".cxx_destruct",
                             @"dealloc",
                             @"_isDeallocating",
                             @"release",
                             @"autorelease",
                             @"retain",
                             @"Retain",
                             @"_tryRetain",
                             @"copy",
                             /*UIView的:*/
                             @"nsis_descriptionOfVariable:",
                             /*NSObject的:*/
                             @"respondsToSelector:",
                             @"class",
                             @"allowsWeakReference",
                             @"retainWeakReference",
                             @"init",
                             @"resolveInstanceMethod:",
                             @"resolveClassMethod:",
//                             @"forwardingTargetForSelector:",
                             @"methodSignatureForSelector:",
                             @"forwardInvocation:",
                             @"doesNotRecognizeSelector:",
                             @"description",
                             @"debugDescription",
                             @"self",
                             @"lockFocus",
                             @"lockFocusIfCanDraw",
                             @"lockFocusIfCanDraw"
                             ];
    });
    return ([defaultBlackList containsObject:methodName]);
}

FOUNDATION_EXPORT SEL createNewSelector(SEL originalSelector) {
    NSString *oldSelectorName = NSStringFromSelector(originalSelector);
    NSString *newSelectorName = [NSString stringWithFormat:@"%@%@",_CJMethodPrefix,oldSelectorName];
    SEL newSelector = NSSelectorFromString(newSelectorName);
    return newSelector;
}

FOUNDATION_EXPORT BOOL isInstanceType(Class cls) {
    return !(cls == [cls class]);
}

FOUNDATION_EXPORT BOOL isStructType(const char *encoding) {
    return encoding[0] == _C_STRUCT_B;
}


BOOL forwardInvocationReplaceMethod(Class cls, SEL originSelector, CJLogOptions options) {
    Method originMethod = class_getInstanceMethod(cls, originSelector);
    if (originMethod == nil) {
        return NO;
    }
    const char *originTypes = method_getTypeEncoding(originMethod);
    
    IMP msgForwardIMP = _objc_msgForward;
#if !defined(__arm64__)
    if (isStructType(originTypes)) {
        //Reference JSPatch:
        //In some cases that returns struct, we should use the '_stret' API:
        //http://sealiesoftware.com/blog/archive/2008/10/30/objc_explain_objc_msgSend_stret.html
        //NSMethodSignature knows the detail but has no API to return, we can only get the info from debugDescription.
        NSMethodSignature *methodSignature = [NSMethodSignature signatureWithObjCTypes:originTypes];
        if ([methodSignature.debugDescription rangeOfString:@"is special struct return? YES"].location != NSNotFound) {
            msgForwardIMP = (IMP)_objc_msgForward_stret;
        }
    }
#endif
    
    IMP originIMP = method_getImplementation(originMethod);
    if (originIMP == nil || originIMP == msgForwardIMP) {
        return NO;
    }
    
    //添加一个新方法，该方法的IMP是原方法的IMP，并且在hook到的forwardInvocation里调用新方法
    SEL newSelecotr = createNewSelector(originSelector);
    BOOL addSucess = class_addMethod(cls, newSelecotr, originIMP, originTypes);
    if (!addSucess) {
        NSString *str = NSStringFromSelector(newSelecotr);
//        CJLNSLog(@"CJMethodLog: Class addMethod fail : %@，%@",cls,str);
        return NO;
    }
    
    //替换当前方法的IMP为msgForwardIMP，从而在调用时候触发消息转发
    class_replaceMethod(cls, originSelector, msgForwardIMP, originTypes);
    
    Method forwardInvocationMethod = class_getInstanceMethod(cls, @selector(forwardInvocation:));
    _VIMP originMethod_IMP = (_VIMP)method_getImplementation(forwardInvocationMethod);
    method_setImplementation(forwardInvocationMethod, imp_implementationWithBlock(^(id target, NSInvocation *invocation){
        
        SEL originSelector = invocation.selector;
        BOOL isInstance = isInstanceType(target);
        Class targetClass = isInstance?[target class]:object_getClass(target);
        if (class_respondsToSelector(targetClass, originSelector)) {
            
            _CJDeep ++;
            NSString *originSelectorStr = NSStringFromSelector(originSelector);
            NSMutableString *methodlog = [[NSMutableString alloc]initWithCapacity:3];
            for (NSInteger deepLevel = 0; deepLevel <= _CJDeep; deepLevel ++) {
                [methodlog appendString:@"-"];
            }
            
            [methodlog appendFormat:@" <%@> ",targetClass];
            
            CFTimeInterval startTimeInterval = 0;
            BOOL beginAndEnd = NO;
            if ((options & CJLogMethodTimer) || (options & CJLogMethodArgs)) {
                [methodlog appendFormat:@" begin: "];
                if (options & CJLogMethodTimer) {
                    startTimeInterval = CACurrentMediaTime();
                }
                beginAndEnd = YES;
            }
            
            if (isInstance) {
                [methodlog appendFormat:@" -%@",originSelectorStr];
            }else{
                [methodlog appendFormat:@" +%@",originSelectorStr];
            }
            
//            if (options & CJLogMethodArgs) {
//                //TODO:调用方法拼接参数处理
//                NSDictionary *methodArguments = CJMethodArguments(invocation);
//                NSArray *argumentArray = methodArguments[_CJMethodArgsListKey];
//                NSMutableString *argStr = [[NSMutableString alloc]initWithCapacity:3];
//
//                for (NSInteger i = 0; i < argumentArray.count; i++) {
//                    id arg = argumentArray[i];
//                    if (i == 0) {
//                        [argStr appendFormat:@" ; args=[ argIndex:%@ argValue:%@",@(i),[arg description]];
//                    }else{
//                        [argStr appendFormat:@", argIndex:%@ argValue:%@",@(i),[arg description]];
//                    }
//                }
//                if (argumentArray.count > 0) {
//                    [argStr appendString:@" ]"];
//                }
//                [methodlog appendString:argStr];
//            }
            
            if (_logEnable) {
                
            }
//            [_logger flushAllocationStack:[NSString stringWithFormat:@"%@\n",methodlog]];
//
            [invocation setSelector:createNewSelector(originSelector)];
            [invocation setTarget:target];
            [invocation invoke];
            
            if (beginAndEnd) {
                [methodlog setString:[methodlog stringByReplacingOccurrencesOfString:@"begin: " withString:@"finish:"]];
                
                if (options & CJLogMethodTimer) {
                    CFTimeInterval endTimeInterval = CACurrentMediaTime();
                    [methodlog appendFormat:@" ; time=%f",(endTimeInterval-startTimeInterval)];
                }
                
//                if (options & CJLogMethodReturnValue) {
//                    id returnValue = getReturnValue(invocation);
//                    [methodlog appendFormat:@" ; return= %@",[returnValue description]];
//                }
                
//                if (_logEnable) {
//                    CJLNSLog(@"%@",methodlog);
//                }
//                [_logger flushAllocationStack:[NSString stringWithFormat:@"%@\n",methodlog]];
            }
            
            _CJDeep --;
            NSLog(@"%@",methodlog);

        }
        //如果target本身已经实现了对无法执行的方法的消息转发(forwardInvocation:)，则这里要还原其本来的实现
        else {
            originMethod_IMP(target,@selector(forwardInvocation:),invocation);
        }
        if (_CJDeep == -1) {
            if (_logEnable) {
//                CJLNSLog(@"\n");
            }
//            [_logger flushAllocationStack:@"\n"];
        }

    }));
    return YES;
}


#pragma mark - CJMethodLog implementation
@implementation GHOptimizer

/**
 基本配置  把要记录的类去保存去记录一个hook操作
 
 @param classNameList 类名组
 @param options 没什么太大的感觉
 @param value 要不要打印
 */
+ (void)forwardingClasses:(NSArray <NSString *>*)classNameList logOptions:(CJLogOptions)options logEnabled:(BOOL)value {
    _logEnable = value;
    [self forwardInvocationCommonInstall:YES];
    for (NSString *className in classNameList) {
        Class hookClass = NSClassFromString(className);
        [self hookClasses:hookClass forwardMsg:YES fromConfig:YES logOptions:options];
    }
}

// 直接hook每一个方法
+ (void)hookClasses:(NSArray <NSString *>*)classNameList logOptions:(CJLogOptions)options logEnabled:(BOOL)value {
    _logEnable = value;
    [self forwardInvocationCommonInstall:NO];
    for (NSString *className in classNameList) {
        Class hookClass = NSClassFromString(className);
        [self hookClasses:hookClass forwardMsg:NO fromConfig:YES logOptions:options];
    }
}


/**
 创建classList数组 和 ClassmethodDic字典
 
 @param forwardInvocation 这个参数没有用
 */
+ (void)forwardInvocationCommonInstall:(BOOL)forwardInvocation {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _hookedClassList = [NSMutableArray array];
        _hookClassMethodDic = [NSMutableDictionary dictionary];
//        if (!_logger) {
//            _logger = [[CJLogger alloc]init];
//        }
    });
    [_hookedClassList removeAllObjects];
    [_hookClassMethodDic removeAllObjects];
}

/**
 hook 指定类方法
 
 @param hookClass  指定类
 @param forwardMsg 是否采用消息转发机制
 @param fromConfig 指定类是否从配置获取
 @param options    记录日志选项
 */
+ (void)hookClasses:(Class)hookClass forwardMsg:(BOOL)forwardMsg fromConfig:(BOOL)fromConfig logOptions:(CJLogOptions)options {
    if (!hookClass) return;
    if (haveHookClass(hookClass)) return;
    
    if (fromConfig) {//有配置的话就选这个
        [self enumerateMethods:hookClass forwardMsg:forwardMsg logOptions:options];
    }else{  // 没有的话就先看当前的bundle里面有没有这个类，有的话再搞
        if (inMainBundle(hookClass)) {
            [self enumerateMethods:hookClass forwardMsg:forwardMsg logOptions:options];
        }
    }
}


/**
 <#Description#>
 
 @param hookClass 要hook的类名
 @param forwardMsg 这里的forwardMsg统一设置成yes
 @param options 打印选项
 */
+ (void)enumerateMethods:(Class)hookClass forwardMsg:(BOOL)forwardMsg logOptions:(CJLogOptions)options {
    ///遍历方法
    [self enumerateClassMethods:hookClass forwardMsg:forwardMsg logOptions:options];
    ///遍历类方法
    [self enumerateMetaClassMethods:hookClass forwardMsg:forwardMsg logOptions:options];
    ///父类的方法
    [self enumerateSuperclassMethods:hookClass forwardMsg:forwardMsg logOptions:options];
}

+ (void)enumerateSuperclassMethods:(Class)hookClass forwardMsg:(BOOL)forwardMsg logOptions:(CJLogOptions)options {
    //    //hook 父类方法
    //    Class superClass = class_getSuperclass(hookClass);
    //    [self hookClasses:superClass forwardMsg:forwardMsg fromConfig:NO logOptions:options];
}

+ (void)enumerateMetaClassMethods:(Class)hookClass forwardMsg:(BOOL)forwardMsg logOptions:(CJLogOptions)options {
    //获取元类，处理类方法。object_getClass获取的isa指针即是元类
    Class metaClass = object_getClass(hookClass);
    [self enumerateClassMethods:metaClass forwardMsg:forwardMsg logOptions:options];
}

+ (void)enumerateClassMethods:(Class)hookClass forwardMsg:(BOOL)forwardMsg logOptions:(CJLogOptions)options {
    
    NSString *hookClassName = NSStringFromClass(hookClass);
    // hookClass中已经被hook过的方法
    NSArray *hookClassMethodList = [_hookClassMethodDic objectForKey:hookClassName];
    NSMutableArray *methodList = [NSMutableArray arrayWithArray:hookClassMethodList];
    
    //属性的 setter 与 getter 方法不hook
    ///属性的settergetter方法都记录进去了
    NSMutableArray *propertyMethodList = [NSMutableArray array];
    unsigned int propertyCount = 0;
    objc_property_t *properties = class_copyPropertyList(hookClass, &propertyCount);
    for (int i = 0; i < propertyCount; i++) {
        objc_property_t property = properties[i];
        // getter 方法
        NSString *propertyName = [[NSString alloc]initWithCString:property_getName(property) encoding:NSUTF8StringEncoding];
        [propertyMethodList addObject:propertyName];
        // setter 方法
        NSString *firstCharacter = [propertyName substringToIndex:1];
        firstCharacter = [firstCharacter uppercaseString];
        NSString *endCharacter = [propertyName substringFromIndex:1];
        NSMutableString *propertySetName = [[NSMutableString alloc]initWithString:@"set"];
        [propertySetName appendString:firstCharacter];
        [propertySetName appendString:endCharacter];
        [propertySetName appendString:@":"];
        [propertyMethodList addObject:propertySetName];
    }
    
    unsigned int outCount;
    Method *methods = class_copyMethodList(hookClass,&outCount);
    for (int i = 0; i < outCount; i ++) {
        Method tempMethod = *(methods + i);
        SEL selector = method_getName(tempMethod);
        
        BOOL needHook = YES;
        for (NSString *selStr in propertyMethodList) {
            SEL propertySel = NSSelectorFromString(selStr);
            if (sel_isEqual(selector, propertySel)) {
                needHook = NO;
                ///这里把所有的setter getter方法过滤掉了
                break;
            }
        }
        
        if (needHook) {
            if (forwardMsg) {
                /*
                 * 方案一：利用消息转发，hook forwardInvocation: 方法
                 */
                BOOL canHook = enableHook(tempMethod);
                if (canHook) {
                    forwardInvocationReplaceMethod(hookClass, selector, options);
                }
            }else{
                //                char *returnType = method_copyReturnType(tempMethod);
                //                /*
                //                 * 方案二：hook每一个方法（未实现）
                //                 */
                //                cjlHookMethod(hookClass, selector, returnType);
                //                free(returnType);
            }
            
            [methodList addObject:NSStringFromSelector(selector)];
        }
        
    }
    free(methods);
    
    [_hookedClassList addObject:hookClassName];
    [_hookClassMethodDic setObject:methodList forKey:hookClassName];
}

@end




