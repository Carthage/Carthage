//
//  FunctionalTests+ObjC.m
//  Quick
//
//  Created by Brian Ivan Gesiak on 6/11/14.
//  Copyright (c) 2014 Brian Ivan Gesiak. All rights reserved.
//

#import <Quick/Quick.h>
#import <Nimble/Nimble.h>


QuickSharedExampleGroupsBegin(FunctionalTestsObjCSharedExampleGroups)

sharedExamples(@"a truthy value", ^(QCKDSLSharedExampleContext sharedExampleContext) {
    __block NSNumber *value = nil;
    beforeEach(^{
        value = sharedExampleContext()[@"value"];
    });

    it(@"is true", ^{
        expect(value).to(beTruthy());
    });
});

QuickSharedExampleGroupsEnd


static BOOL beforeSuiteExecuted_afterSuiteNotYetExecuted = NO;


QuickSpecBegin(FunctionalTestsObjC)

beforeSuite(^{
    beforeSuiteExecuted_afterSuiteNotYetExecuted = YES;
});

afterSuite(^{
    beforeSuiteExecuted_afterSuiteNotYetExecuted = NO;
});

describe(@"a describe block", ^{
    it(@"contains an it block", ^{
        expect(@(beforeSuiteExecuted_afterSuiteNotYetExecuted)).to(beTruthy());
    });

    itBehavesLike(@"a truthy value", ^{ return @{ @"value": @YES }; });

    pending(@"a pending block", ^{
        it(@"contains a failing it block", ^{
            expect(@NO).to(beTruthy());
        });
    });
    
    xdescribe(@"a pending (shorthand) describe block", ^{
        it(@"contains a failing it block", ^{
            expect(@NO).to(beTruthy());
        });
    });
    
    xcontext(@"a pending (shorthand) context block", ^{
        it(@"contains a failing it block", ^{
            expect(@NO).to(beTruthy());
        });
    });
    
    xit(@"contains a pending (shorthand) it block", ^{
        expect(@NO).to(beTruthy());
    });
});

QuickSpecEnd
