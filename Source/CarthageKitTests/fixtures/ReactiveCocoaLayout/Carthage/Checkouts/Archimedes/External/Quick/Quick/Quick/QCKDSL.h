//
//  QCKDSL.h
//  Quick
//
//  Created by Brian Ivan Gesiak on 6/11/14.
//  Copyright (c) 2014 Brian Ivan Gesiak. All rights reserved.
//

#import <Foundation/Foundation.h>

#define QuickSharedExampleGroupsBegin(name) \
    @interface name : QuickSharedExampleGroups; @end \
    @implementation name \
    + (void)sharedExampleGroups { \


#define QuickSharedExampleGroupsEnd \
    } \
    @end \


#define QuickSpecBegin(name) \
    @interface name : QuickSpec; @end \
    @implementation name \
    - (void)spec { \


#define QuickSpecEnd \
    } \
    @end \


#define qck_beforeSuite(...) [QCKDSL beforeSuite:__VA_ARGS__]
#define qck_afterSuite(...) [QCKDSL afterSuite:__VA_ARGS__]
#define qck_sharedExamples(name, ...) [QCKDSL sharedExamples:name closure:__VA_ARGS__]
#define qck_describe(description, ...) [QCKDSL describe:description closure:__VA_ARGS__]
#define qck_context(description, ...) [QCKDSL context:description closure:__VA_ARGS__]
#define qck_beforeEach(...) [QCKDSL beforeEach:__VA_ARGS__]
#define qck_afterEach(...) [QCKDSL afterEach:__VA_ARGS__]
#define qck_it(description, ...) [QCKDSL it:description file:@(__FILE__) line:__LINE__ closure:__VA_ARGS__]
#define qck_itBehavesLike(name, ...) [QCKDSL itBehavesLike:name context:__VA_ARGS__ file:@(__FILE__) line:__LINE__]
#define qck_pending(description, ...) [QCKDSL pending:description closure:__VA_ARGS__]
#define qck_xdescribe(description, ...) [QCKDSL xdescribe:description closure:__VA_ARGS__]
#define qck_xcontext(description, ...) [QCKDSL xcontext:description closure:__VA_ARGS__]
#define qck_xit(description, ...) [QCKDSL xit:description closure:__VA_ARGS__]

#ifndef QUICK_DISABLE_SHORT_SYNTAX
#define beforeSuite(...) qck_beforeSuite(__VA_ARGS__)
#define afterSuite(...) qck_afterSuite(__VA_ARGS__)
#define sharedExamples(name, ...) qck_sharedExamples(name, __VA_ARGS__)
#define describe(description, ...) qck_describe(description, __VA_ARGS__)
#define context(description, ...) qck_context(description, __VA_ARGS__)
#define beforeEach(...) qck_beforeEach(__VA_ARGS__)
#define afterEach(...) qck_afterEach(__VA_ARGS__)
#define it(description, ...) qck_it(description, __VA_ARGS__)
#define itBehavesLike(name, ...) qck_itBehavesLike(name, __VA_ARGS__)
#define pending(description, ...) qck_pending(description, __VA_ARGS__)
#define xdescribe(description, ...) qck_xdescribe(description, __VA_ARGS__)
#define xcontext(description, ...) qck_xcontext(description, __VA_ARGS__)
#define xit(description, ...) qck_xit(description, __VA_ARGS__)
#endif

typedef NSDictionary *(^QCKDSLSharedExampleContext)(void);
typedef void (^QCKDSLSharedExampleBlock)(QCKDSLSharedExampleContext);

@interface QCKDSL : NSObject

+ (void)beforeSuite:(void(^)(void))closure;
+ (void)afterSuite:(void(^)(void))closure;
+ (void)sharedExamples:(NSString *)name closure:(QCKDSLSharedExampleBlock)closure;
+ (void)describe:(NSString *)description closure:(void(^)(void))closure;
+ (void)context:(NSString *)description closure:(void(^)(void))closure;
+ (void)beforeEach:(void(^)(void))closure;
+ (void)afterEach:(void(^)(void))closure;
+ (void)it:(NSString *)description file:(NSString *)file line:(NSUInteger)line closure:(void(^)(void))closure;
+ (void)itBehavesLike:(NSString *)name context:(QCKDSLSharedExampleContext)context file:(NSString *)file line:(NSUInteger)line;
+ (void)pending:(NSString *)description closure:(void(^)(void)) __unused closure;
+ (void)xdescribe:(NSString *)description closure:(void(^)(void)) __unused closure;
+ (void)xcontext:(NSString *)description closure:(void(^)(void)) __unused closure;
+ (void)xit:(NSString *)description closure:(void(^)(void)) __unused closure;

@end
