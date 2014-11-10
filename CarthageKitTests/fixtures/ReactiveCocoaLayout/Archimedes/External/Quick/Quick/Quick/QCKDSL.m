//
//  QCKDSL.m
//  Quick
//
//  Created by Brian Ivan Gesiak on 6/11/14.
//  Copyright (c) 2014 Brian Ivan Gesiak. All rights reserved.
//

#import "QCKDSL.h"
#import <Quick/Quick-Swift.h>

@implementation QCKDSL

+ (void)beforeSuite:(void (^)(void))closure {
    [DSL beforeSuite:closure];
}

+ (void)afterSuite:(void (^)(void))closure {
    [DSL afterSuite:closure];
}

+ (void)sharedExamples:(NSString *)name closure:(QCKDSLSharedExampleBlock)closure {
    [DSL sharedExamples:name closure:closure];
}

+ (void)describe:(NSString *)description closure:(void(^)(void))closure {
    [DSL describe:description closure:closure];
}

+ (void)context:(NSString *)description closure:(void(^)(void))closure {
    [self describe:description closure:closure];
}

+ (void)beforeEach:(void(^)(void))closure {
    [DSL beforeEach:closure];
}

+ (void)afterEach:(void(^)(void))closure {
    [DSL afterEach:closure];
}

+ (void)it:(NSString *)description file:(NSString *)file line:(NSUInteger)line closure:(void (^)(void))closure {
    [DSL it:description file:file line:line closure:closure];
}

+ (void)itBehavesLike:(NSString *)name context:(QCKDSLSharedExampleContext)context file:(NSString *)file line:(NSUInteger)line {
    [DSL itBehavesLike:name sharedExampleContext:context file:file line:line];
}

+ (void)pending:(NSString *)description closure:(void(^)(void))closure {
    [DSL pending:description closure:closure];
}

+ (void)xdescribe:(NSString *)description closure:(void(^)(void))closure {
    [self pending:description closure:closure];
}

+ (void)xcontext:(NSString *)description closure:(void(^)(void))closure {
    [self pending:description closure:closure];
}

+ (void)xit:(NSString *)description closure:(void(^)(void))closure {
    [self pending:description closure:closure];
}

@end
