import Quick
import Nimble

var dinosaursExtinct = false
var mankindExtinct = false

class FunctionalSharedExamples: QuickConfiguration {
    override class func configure(configuration: Configuration) {
        sharedExamples("something living after dinosaurs are extinct") {
            it("no longer deals with dinosaurs") {
                expect(dinosaursExtinct).to(beTruthy())
            }
        }

        sharedExamples("an optimistic person") { (sharedExampleContext: SharedExampleContext) in
            var person: Person!
            beforeEach {
                person = sharedExampleContext()["person"] as Person
            }

            it("is happy") {
                expect(person.isHappy).to(beTruthy())
            }

            it("is a dreamer") {
                expect(person.hopes).to(contain("winning the lottery"))
            }
        }
    }
}

class PersonSpec: QuickSpec {
    override func spec() {
        describe("Person") {
            var person: Person! = nil

            beforeSuite {
                assert(!dinosaursExtinct, "nothing goes extinct twice")
                dinosaursExtinct = true
            }

            afterSuite {
                assert(!mankindExtinct, "tests shouldn't run after the apocalypse")
                mankindExtinct = true
            }

            beforeEach { person = Person() }
            afterEach  { person = nil }

            it("gets hungry") {
                person!.eatChineseFood()
                expect{person.isHungry}.toEventually(beTruthy())
            }

            it("will never be satisfied") {
                expect{person.isSatisfied}.toEventuallyNot(beTruthy())
            }

            it("🔥🔥それでも俺たちは🔥🔥") {
                expect{person.isSatisfied}.toEventuallyNot(beTruthy())
            }

            pending("but one day") {
                it("will never want for anything") {
                    expect{person.isSatisfied}.toEventually(beTruthy())
                }
            }

            it("does not live with dinosaurs") {
                expect(dinosaursExtinct).to(beTruthy())
                expect(mankindExtinct).notTo(beTruthy())
            }

            describe("greeting") {
                context("when the person is unhappy") {
                    beforeEach { person.isHappy = false }
                    it("is lukewarm") {
                        expect(person.greeting).to(equal("Oh, hi."))
                        expect(person.greeting).notTo(equal("Hello!"))
                    }
                }

                context("when the person is happy") {
                    beforeEach { person!.isHappy = true }
                    it("is enthusiastic") {
                        expect(person.greeting).to(equal("Hello!"))
                        expect(person.greeting).notTo(equal("Oh, hi."))
                    }
                }
            }
            
            xdescribe("smalltalk") {
                context("when the person is unhappy") {
                    beforeEach { person.isHappy = false }
                    it("is lukewarm") {
                        expect{person.smalltalk}.to(equal("Weather's nice."))
                        expect{person.smalltalk}.notTo(equal("How are you!?"))
                    }
                }
                
                context("when the person is happy") {
                    beforeEach { person.isHappy = true }
                    it("is enthusiastic") {
                        expect{person.smalltalk}.to(equal("How are you!?"))
                        expect{person.smalltalk}.notTo(equal("Weather's nice."))
                    }
                }
            }
            
            describe("valediction") {
                xcontext("when the person is unhappy") {
                    beforeEach { person.isHappy = false }
                    it("is lukewarm") {
                        expect{person.valediction}.to(equal("Bye then."))
                        expect{person.valediction}.notTo(equal("I'll miss you!"))
                    }
                }
                
                context("when the person is happy") {
                    beforeEach { person.isHappy = true }
                    xit("is enthusiastic") {
                        expect{person.valediction}.to(equal("I'll miss you!"))
                        expect{person.valediction}.notTo(equal("Bye then."))
                    }
                }
            }
        }
    }
}

class PoetSpec: QuickSpec {
    override func spec() {
        describe("Poet") {
            // FIXME: Radar worthy? `var poet: Poet?` results in build error:
            //        "Could not find member 'greeting'"
            var poet: Person! = nil
            beforeEach { poet = Poet() }

            describe("greeting") {
                context("when the poet is unhappy") {
                    beforeEach { poet.isHappy = false }
                    it("is dramatic") {
                        expect(poet.greeting).to(equal("Woe is me!"))
                    }
                }

                context("when the poet is happy") {
                    beforeEach { poet.isHappy = true }
                    it("is joyous") {
                        expect(poet.greeting).to(equal("Oh, joyous day!"))
                    }
                }
            }
        }
    }
}
