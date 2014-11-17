import Quick
import Nimble

class FunctionalTests_SharedExamplesTests_SharedExamples: QuickConfiguration {
    override class func configure(configuration: Configuration) {
        sharedExamples("a group of three shared examples") {
            it("passes once") { expect(true).to(beTruthy()) }
            it("passes twice") { expect(true).to(beTruthy()) }
            it("passes three times") { expect(true).to(beTruthy()) }
        }

        sharedExamples("shared examples that take a context") { (sharedExampleContext: SharedExampleContext) in
            it("is passed the correct parameters via the context") {
                let callsite = sharedExampleContext()["callsite"] as String
                expect(callsite).to(equal("SharedExamplesSpec"))
            }
        }
    }
}