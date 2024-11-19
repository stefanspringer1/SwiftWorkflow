import XCTest
@testable import Workflow

final class WorkflowTests: XCTestCase {
    
    func testExample() throws {
        
        let success = Message(
            id: "error",
            type: .Error,
            fact: [
                .en: "thsi is an error",
            ]
        )
        
        let logger = PrintLogger()
        let execution = Execution(applicationName: "test", logger: logger)
        execution.log(success)
        print(execution.worstMessageType)
    }
    
    func testEffectuationCodable() throws {
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        // step:
        do {
            let effectuation: Effectuation = .step(step: StepID(crossModuleFileDesignation: "script1", functionSignature: "function1"))
            
            let stepEffectuationEncoded = try encoder.encode(effectuation)
            XCTAssertEqual(#"{"effectuation":"step function1@script1"}"#, String(decoding: stepEffectuationEncoded, as: UTF8.self))
            
            let stepEffectuationDecoded = try decoder.decode(Effectuation.self, from: stepEffectuationEncoded)
            XCTAssertEqual(stepEffectuationDecoded.description, "step script1@function1")
        }
        
        // optional part:
        do {
            let effectuation: Effectuation = .optionalPart(name: "optional part 1")
            
            let stepEffectuationEncoded = try encoder.encode(effectuation)
            XCTAssertEqual(#"{"effectuation":"optional part \"optional part 1\""}"#, String(decoding: stepEffectuationEncoded, as: UTF8.self))
            
            let stepEffectuationDecoded = try decoder.decode(Effectuation.self, from: stepEffectuationEncoded)
            XCTAssertEqual(stepEffectuationDecoded.description, #"optional part "optional part 1""#)
        }
        
        // dispensable part:
        do {
            let effectuation: Effectuation = .dispensablePart(name: "dispensable part 1")
            
            let stepEffectuationEncoded = try encoder.encode(effectuation)
            XCTAssertEqual(#"{"effectuation":"dispensable part \"dispensable part 1\""}"#, String(decoding: stepEffectuationEncoded, as: UTF8.self))
            
            let stepEffectuationDecoded = try decoder.decode(Effectuation.self, from: stepEffectuationEncoded)
            XCTAssertEqual(stepEffectuationDecoded.description, #"dispensable part "dispensable part 1""#)
        }
        
    }
}
