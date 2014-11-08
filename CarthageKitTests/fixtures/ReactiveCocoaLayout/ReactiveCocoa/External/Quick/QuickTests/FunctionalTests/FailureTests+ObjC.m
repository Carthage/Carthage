#import <XCTest/XCTest.h>

#import <Quick/Quick.h>
#import <Nimble/Nimble.h>

#import "QCKSpecRunner.h"

static BOOL isRunningFunctionalTests = NO;

#pragma mark - Spec

QuickSpecBegin(FunctionalTests_FailureSpec)

describe(@"a group of failing examples", ^{
    it(@"passes", ^{
        expect(@YES).to(beTruthy());
    });

    it(@"fails (but only when running the functional tests)", ^{
        expect(@(isRunningFunctionalTests)).to(beFalsy());
    });

    it(@"fails again (but only when running the functional tests)", ^{
        expect(@(isRunningFunctionalTests)).to(beFalsy());
    });
});

QuickSpecEnd

#pragma mark - Test Helpers

/**
 Run the functional tests within a context that causes two test failures
 and return the result.
 */
static XCTestRun *qck_runFailureSpec(void) {
    isRunningFunctionalTests = YES;
    XCTestRun *result = qck_runSpec([FunctionalTests_FailureSpec class]);
    isRunningFunctionalTests = NO;

    return result;
}

#pragma mark - Tests

@interface FailureTests : XCTestCase; @end

@implementation FailureTests

- (void)testFailureSpecHasSucceededIsFalse {
    XCTestRun *result = qck_runFailureSpec();
    XCTAssertFalse(result.hasSucceeded);
}

- (void)testFailureSpecExecutedAllExamples {
    XCTestRun *result = qck_runFailureSpec();
    XCTAssertEqual(result.executionCount, 3);
}

- (void)testFailureSpecFailureCountIsEqualToTheNumberOfFailingExamples {
    XCTestRun *result = qck_runFailureSpec();
    XCTAssertEqual(result.failureCount, 2);
}

@end
