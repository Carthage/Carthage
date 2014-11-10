#import <XCTest/XCTest.h>

/**
 Runs an XCTestSuite instance containing only the given XCTestCase subclass.
 Use this to run QuickSpec subclasses from within a set of unit tests.

 Due to implicit dependencies in _XCTFailureHandler, this function raises an
 exception when used in Swift to run a failing test case.

 @param specClass The class of the spec to be run.
 @return An XCTestRun instance that contains information such as the number of failures, etc.
 */
extern XCTestRun *qck_runSpec(Class specClass);

/**
 Runs an XCTestSuite instance containing the given XCTestCase subclasses, in the order provided.
 See the documentation for `qck_runSpec` for more details.

 @param specClasses An array of QuickSpec classes, in the order they should be run.
 @return An XCTestRun instance that contains information such as the number of failures, etc.
 */
extern XCTestRun *qck_runSpecs(NSArray *specClasses);
