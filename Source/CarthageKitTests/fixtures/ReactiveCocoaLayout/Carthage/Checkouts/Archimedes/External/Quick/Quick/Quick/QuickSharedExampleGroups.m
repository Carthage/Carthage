//
//  QuickSharedExampleGroups.m
//  Quick
//
//  Created by Brian Ivan Gesiak on 6/30/14.
//  Copyright (c) 2014 Brian Ivan Gesiak. All rights reserved.
//

#import "QuickSharedExampleGroups.h"
#import <objc/runtime.h>

typedef void (^QCKClassEnumerationBlock)(Class klass);

void qck_enumerateSubclasses(Class klass, QCKClassEnumerationBlock block) {
    Class *classes = NULL;
    int classesCount = objc_getClassList(NULL, 0);

    if (classesCount > 0) {
        classes = (Class *)calloc(sizeof(Class), classesCount);
        classesCount = objc_getClassList(classes, classesCount);

        Class subclass, superclass;
        for(int i = 0; i < classesCount; i++) {
            subclass = classes[i];
            superclass = class_getSuperclass(subclass);
            if (superclass == klass && block) {
                block(subclass);
            }
        }

        free(classes);
    }
}

@implementation QuickSharedExampleGroups

#pragma mark - NSObject Overrides

+ (void)initialize {
    if ([self class] == [QuickSharedExampleGroups class]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            qck_enumerateSubclasses([QuickSharedExampleGroups class], ^(__unsafe_unretained Class klass) {
                [klass sharedExampleGroups];
            });
        });
    }
}

#pragma mark - Public Interface

+ (void)sharedExampleGroups { }

@end
