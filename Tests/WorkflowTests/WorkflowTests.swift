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
        let execution = Execution(logger: logger, applicationName: "test")
        execution.log(success)
        print(execution.worstMessageType)
    }
}
