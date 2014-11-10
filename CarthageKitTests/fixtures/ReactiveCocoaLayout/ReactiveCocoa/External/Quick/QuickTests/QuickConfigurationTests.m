#import <XCTest/XCTest.h>
#import <Quick/Quick.h>

@interface QuickConfigurationTests : XCTestCase; @end

@implementation QuickConfigurationTests

- (void)testInitThrows {
    XCTAssertThrowsSpecificNamed([QuickConfiguration new], NSException, NSInternalInconsistencyException);
}

@end
