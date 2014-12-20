import XCTest
import Nimble

class BeIdenticalToTest: XCTestCase {
    func testBeIdenticalToPositive() {
        expect(NSNumber(integer:1)).to(beIdenticalTo(NSNumber(integer:1)))
    }

    func testBeIdenticalToNegative() {
        expect(NSNumber(integer:1)).toNot(beIdenticalTo("yo"))
        expect([1]).toNot(beIdenticalTo([1]))
    }

    func testBeIdenticalToPositiveMessage() {
        let num1 = NSNumber(integer:1)
        let num2 = NSNumber(integer:2)
        let message = NSString(format: "expected to be identical to <%p>, got <%p>", num2, num1)
        failsWithErrorMessage(message) {
            expect(num1).to(beIdenticalTo(num2))
        }
    }

    func testBeIdenticalToNegativeMessage() {
        let value1 = NSArray(array: [])
        let value2 = NSArray(array: [])
        let message = NSString(format: "expected to not be identical to <%p>, got <%p>", value2, value1)
        failsWithErrorMessage(message) {
            expect(value1).toNot(beIdenticalTo(value2))
        }
    }
    
    func testOperators() {
        expect(NSNumber(integer:1)) === NSNumber(integer:1)
        expect(NSNumber(integer:1)) !== NSNumber(integer:2)
    }
}
