@testable import CarthageKit
import Foundation
import Nimble
import Quick
import ReactiveSwift
import Result

final class InputFilesInferrerSpec: QuickSpec {
    override func spec() {
        describe("inferring") {
            var sut: InputFilesInferrer!
            
            let executableResolver: (URL) -> URL? = { $0.appendingPathComponent($0.deletingPathExtension().lastPathComponent) }

            describe("framework dependecies resolving") {
                context("when framework is not listed anywhere") {
                    beforeEach {
                        sut = InputFilesInferrer(
                            builtFrameworks: .empty,
                            linkedFrameworksResolver: { url -> Result<[String], CarthageError> in
                                return .success(["A", "B"])
                            }
                        )
                        sut.executableResolver = executableResolver
                    }
                    
                    it("should ignore it") {
                        let result = sut.inputFiles(for: URL(fileURLWithPath: "/Root"), userInputFiles: .empty)
                            .collect()
                            .single()
                        
                        expect(result?.value).to(haveCount(0))
                    }
                }
                
                context("when framework is listed by frameworks enumerator") {
                    beforeEach {
                        sut = InputFilesInferrer(
                            builtFrameworks: SignalProducer([URL(fileURLWithPath: "/Frameworks/A.framework")]),
                            linkedFrameworksResolver: { url -> Result<[String], CarthageError> in
                                switch url.lastPathComponent {
                                case "Root":
                                    return .success(["A"])
                                    
                                case "A":
                                    return .success([])
                                    
                                default:
                                    return .success([])
                                }
                            }
                        )
                        sut.executableResolver = executableResolver
                    }

                    it("should resolve dependncies at a enumerator's path") {
                        let result = sut.inputFiles(for: URL(fileURLWithPath: "/Root"), userInputFiles: .empty)
                            .collect()
                            .single()

                        expect(result?.value).to(equal([URL(fileURLWithPath: "/Frameworks/A.framework")]))
                    }
                }
                
                context("when framework is listed by user input files") {
                    beforeEach {
                        sut = InputFilesInferrer(
                            builtFrameworks: SignalProducer([URL(fileURLWithPath: "/Frameworks/B.framework")]),
                            linkedFrameworksResolver: { url -> Result<[String], CarthageError> in
                                switch url.lastPathComponent {
                                case "Root":
                                    return .success(["A"])
                                    
                                case "A":
                                    return .success(["B"])
                                    
                                case "B":
                                    return .success([])
                                    
                                default:
                                    return .success([])
                                }
                            }
                        )
                        sut.executableResolver = executableResolver
                    }

                    it("should resolve dependencies using user input files") {
                        let result = sut.inputFiles(
                                for: URL(fileURLWithPath: "/Root"),
                                userInputFiles: SignalProducer([URL(fileURLWithPath: "/User-Frameworks/A.framework")])
                            )
                            .collect()
                            .single()
                        
                        expect(result?.value).to(equal([URL(fileURLWithPath: "/Frameworks/B.framework")]))
                    }
                    
                    it("should not include user input files") {
                        let result = sut.inputFiles(
                            for: URL(fileURLWithPath: "/Root"),
                            userInputFiles: SignalProducer([URL(fileURLWithPath: "/User-Frameworks/A.framework")])
                        )
                        .collect()
                        .single()
                        
                        expect(result?.value).toNot(contain(URL(fileURLWithPath: "/User-Frameworks/A.framework")))
                    }
                }

                context("when framework is listed by user input files and frameworks enumerator") {
                    beforeEach {
                        sut = InputFilesInferrer(
                            builtFrameworks: SignalProducer([URL(fileURLWithPath: "/Frameworks/B.framework")]),
                            linkedFrameworksResolver: { url -> Result<[String], CarthageError> in
                                switch url.lastPathComponent {
                                case "Root":
                                    return .success(["A"])
                                    
                                case "A":
                                    return .success(["B"])
                                    
                                case "B":
                                    return .success([])
                                    
                                default:
                                    return .success([])
                                }
                            }
                        )
                        sut.executableResolver = executableResolver
                    }

                    it("should resolve dependncies at user input file's path") {
                        let result = sut.inputFiles(
                                for: URL(fileURLWithPath: "/Root"),
                                userInputFiles: SignalProducer([URL(fileURLWithPath: "/User-Frameworks/A.framework")])
                            )
                            .collect()
                            .single()

                        expect(result?.value).to(equal([URL(fileURLWithPath: "/Frameworks/B.framework")]))
                    }
                }
                
                context("when has nested dependencies") {
                    beforeEach {
                        sut = InputFilesInferrer(
                            builtFrameworks: SignalProducer([
                                URL(fileURLWithPath: "/Frameworks/RootFramework.framework"),
                                URL(fileURLWithPath: "/Frameworks/NestedFrameworkA.framework"),
                                URL(fileURLWithPath: "/Frameworks/NestedFrameworkB.framework"),
                                URL(fileURLWithPath: "/Frameworks/NestedFrameworkC.framework"),
                                URL(fileURLWithPath: "/Frameworks/NestedFrameworkD.framework"),
                            ]),
                            linkedFrameworksResolver: { url -> Result<[String], CarthageError> in
                                switch url.lastPathComponent {
                                case "Root":
                                    return .success(["RootFramework", "System"])
                                    
                                case "RootFramework":
                                    return .success(["NestedFrameworkA", "NestedFrameworkB"])
                                    
                                case "NestedFrameworkA":
                                    return .success(["NestedFrameworkC"])
                                    
                                case "NestedFrameworkB":
                                    return .success([])
                                    
                                case "NestedFrameworkC" where url.pathComponents[1] == "Frameworks":
                                    return .success([])
                                    
                                case "NestedFrameworkC" where url.pathComponents[1] == "User-Frameworks":
                                    return .success(["NestedFrameworkD"])
                                    
                                case "NestedFrameworkD":
                                    return .success(["NestedFrameworkE"])
                                    
                                default:
                                    return .success([])
                                }
                            }
                        )
                        sut.executableResolver = executableResolver
                    }
                    
                    it("should resolve nested dependecies") {
                        let result = sut.inputFiles(
                                for: URL(fileURLWithPath: "/Root"),
                                userInputFiles: SignalProducer([
                                    URL(fileURLWithPath: "/User-Frameworks/NestedFrameworkC.framework")
                                ])
                            )
                            .collect()
                            .single()
                        
                        let expectedURLs: [URL] = [
                            URL(fileURLWithPath: "/Frameworks/RootFramework.framework"),
                            URL(fileURLWithPath: "/Frameworks/NestedFrameworkA.framework"),
                            URL(fileURLWithPath: "/Frameworks/NestedFrameworkB.framework"),
                            URL(fileURLWithPath: "/Frameworks/NestedFrameworkD.framework")
                        ]
                        
                        expect(result?.value).to(contain(expectedURLs))
                        expect(result?.value).to(haveCount(expectedURLs.count))
                    }
                }
                
                context("when dependencies have cycle") {
                    beforeEach {
                        sut = InputFilesInferrer(
                            builtFrameworks: SignalProducer([
                                URL(fileURLWithPath: "/Frameworks/A.framework"),
                                URL(fileURLWithPath: "/Frameworks/B.framework"),
                                URL(fileURLWithPath: "/Frameworks/C.framework")
                            ]),
                            linkedFrameworksResolver: { url -> Result<[String], CarthageError> in
                                switch url.lastPathComponent {
                                case "Root":
                                    return .success(["A"])
                                    
                                case "A":
                                    return .success(["B", "C"])
                                    
                                case "B":
                                    return .success(["A", "C"])
                                    
                                default:
                                    return .success([])
                                }
                            }
                        )
                        sut.executableResolver = executableResolver
                    }
                    
                    it("should ignore already resolved dependecies") {
                        let result = sut.inputFiles(for: URL(fileURLWithPath: "/Root"), userInputFiles: .empty)
                            .collect()
                            .single()
                        
                        let expectedURLs: [URL] = [
                            URL(fileURLWithPath: "/Frameworks/A.framework"),
                            URL(fileURLWithPath: "/Frameworks/B.framework"),
                            URL(fileURLWithPath: "/Frameworks/C.framework")
                        ]
                        
                        expect(result?.value).to(contain(expectedURLs))
                        expect(result?.value).to(haveCount(expectedURLs.count))
                    }
                }
            }
        }
        
        describe("linked frameworks") {
            let input = """
RootFramework:
    @rpath/RootFramework.framework/RootFramework (compatibility version 0.0.0, current version 0.0.0)
    @rpath/Framework_with_underscore.framework/Framework_with_underscore (compatibility version 0.0.0, current version 0.0.0)
    @rpath/Framework.with.dot.framework/Framework.with.dot (compatibility version 0.0.0, current version 0.0.0)
    @rpath/Dependency.framework/Dependency (compatibility version 1.0.0, current version 0.0.0)
    /System/Library/Frameworks/CoreGraphics.framework/CoreGraphics (compatibility version 64.0.0, current version 1245.9.2)
    /usr/lib/libobjc.A.dylib (compatibility version 1.0.0, current version 228.0.0)
"""
            it("should return framework IDs") {
                let result = linkedFrameworks(from: input)
                expect(result).to(contain(["RootFramework", "Framework_with_underscore", "Framework.with.dot", "Dependency", "CoreGraphics"]))
                expect(result).to(haveCount(5))
            }
            
            it("should not include dylibs") {
                let result = linkedFrameworks(from: input)
                expect(result).toNot(contain(["libobjc.A"]))
            }
        }
    }
}
