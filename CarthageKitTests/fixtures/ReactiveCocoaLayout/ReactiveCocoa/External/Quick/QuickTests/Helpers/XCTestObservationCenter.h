#import <XCTest/XCTest.h>

/**
 Expose internal XCTest class and methods in order to run isolated XCTestSuite
 instances while the QuickTests test suite is running.

 If an Xcode upgrade causes QuickTests to crash when executing, or for tests to fail
 with the message "Timed out waiting for IDE barrier message to complete", it is
 likely that this internal interface has been changed.
 */
@interface XCTestObservationCenter : NSObject

/**
 Returns the global instance of XCTestObservationCenter.
 */
+ (instancetype)sharedObservationCenter;

/**
 Suspends test suite observation for the duration that the block is executing.
 Any test suites that are executed within the block do not generate any log output.
 Failures are still reported.

 Use this method to run XCTestSuite objects while another XCTestSuite is running.
 Without this method, tests fail with the message: "Timed out waiting for IDE
 barrier message to complete".
 */
- (void)_suspendObservationForBlock:(void (^)(void))block;

@end
