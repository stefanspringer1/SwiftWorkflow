/// This small collection of types and functions is at the
/// heart of the Workflow framework.
///
/// As explained in the package documentation, the Workflow framework
/// is in large part based on conventions.

import Foundation
import Utilities
import ArgumentParser

public struct StepID: Hashable, CustomStringConvertible, Sendable {
    
    public let crossModuleFileDesignation: String
    public let functionSignature: String
    
    public init(crossModuleFileDesignation: String, functionSignature: String) {
        self.crossModuleFileDesignation = crossModuleFileDesignation
        self.functionSignature = functionSignature
    }
    
    public var description: String { "\(functionSignature)@\(crossModuleFileDesignation)" }
}

public let stepPrefix = "step "
public let dispensablePartPrefix = "dispensable part "
public let optionalPartPrefix = "optional part "
public let describedPartPrefix = "doing "

public enum Effectuation: CustomStringConvertible, Sendable {
    
    case step(step: StepID)
    case dispensablePart(name: String)
    case optionalPart(name: String)
    case describedPart(description: String)
    
    enum PostTypeCodingError: Error {
        case decoding(String)
    }
    
    public var description: String {
        switch self {
        case .step(step: let step):
            return "\(stepPrefix)\(step.description)"
        case .dispensablePart(name: let id):
            return "\(dispensablePartPrefix)\"\(id)\""
        case .optionalPart(name: let id):
            return "\(optionalPartPrefix)\"\(id)\""
        case .describedPart(description: let description):
            return "\(describedPartPrefix)\"\(description)\""
        }
    }
    
}

extension Effectuation: Codable {
    
    enum CodingKeys: CodingKey {
        case effectuation
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(description, forKey: .effectuation)
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let description = try values.decode(String.self, forKey: .effectuation)
        if description.hasPrefix(stepPrefix) {
            let stepDescription = description.dropFirst(stepPrefix.count)
            if let atSign = stepDescription.firstIndex(of: "@") {
                self = .step(step: StepID(crossModuleFileDesignation: String(stepDescription[..<atSign]), functionSignature: String(stepDescription[atSign...].dropFirst())))
                return
            }
        } else if description.hasPrefix(optionalPartPrefix) {
            self = .optionalPart(name: String(description.dropFirst(optionalPartPrefix.count+1).dropLast()))
            return
        } else if description.hasPrefix(dispensablePartPrefix) {
            self = .dispensablePart(name: String(description.dropFirst(dispensablePartPrefix.count+1).dropLast()))
            return
        }
        throw PostTypeCodingError.decoding("Could not decode Effectuation form \(dump(values))")
   }

}

public typealias OperationCount = Int
public typealias AugmentOperationCount = Bool

open class WorstMessageTypeHolder {
    
    private var _worstMessageType: MessageType = .Info
    
    private let queue: DispatchQueue
    
    public init() {
        self.queue = DispatchQueue(label: "WorstMessageTypeHolder", qos: .default)
    }
    
    public func updateWorstMessageType(with messageType: MessageType) {
        self.queue.async {
            self._worstMessageType = max(self._worstMessageType, messageType)
        }
    }
    
    var worstMessageType: MessageType {
        var result: MessageType = .Info
        self.queue.sync {
            result = _worstMessageType
        }
        return result
    }
    
}

/// Manages the execution of steps. In particular
/// - prevents double execution of steps
/// - keeps global information for logging
public class Execution {
    
    public var applicationName: String
    
    private var executedSteps = Set<StepID>()
    
    var _effectuationStack: [Effectuation]
    
    public var effectuationStack: [Effectuation] {
        _effectuationStack
    }
    
    public var logger: Logger
    
    public var crashLogger: Logger?
    
    public var logFileInfo: URL? = nil // URL for log file, just as an info
    
    public func setting(
        logger: Logger? = nil,
        crashLogger: Logger? = nil,
        applicationName: String? = nil,
        waitNotPausedFunction: (() -> ())? = nil
    ) -> Self {
        if let applicationName {
            self.applicationName = applicationName
        }
        if let logger {
            self.logger = logger
        }
        if let crashLogger {
            self.crashLogger = crashLogger
        }
        if let waitNotPausedFunction {
            self.waitNotPausedFunction = waitNotPausedFunction
        }
        return self
    }
    
    var processID: String?
    var itemInfo: String? = nil
    
    let alwaysAddCrashInfo: Bool
    let debug: Bool
    
    let dispensedWith: Set<String>?
    let activatedOptions: Set<String>?
    
    var _beforeStepOperation: ((OperationCount,StepID) -> AugmentOperationCount)?
    
    public var beforeStepOperation: ((OperationCount,StepID) -> AugmentOperationCount)? {
        get {
            _beforeStepOperation
        }
        set {
            _beforeStepOperation = newValue
        }
    }
    
    var _afterStepOperation: ((OperationCount,StepID) -> AugmentOperationCount)?
    
    public var afterStepOperation: ((OperationCount,StepID) -> AugmentOperationCount)? {
        get {
            _afterStepOperation
        }
        set {
            _afterStepOperation = newValue
        }
    }
    
    var operationCount = 0
    
    var _attached: Attachments? = nil
    public var attached: Attachments { _attached ?? { _attached = Attachments(); return _attached! }() }
    
    var _async: AsyncEffectuation!
    
    public var async: AsyncEffectuation { _async }
    
    public func closeLoggers() throws {
        try logger.close()
    }
    
    public var parallel: Execution {
        Execution(
            processID: processID,
            applicationName: applicationName,
            logger: logger,
            worstMessageTypeHolder: worstMessageTypeHolder,
            crashLogger: crashLogger,
            itemInfo: itemInfo,
            alwaysAddCrashInfo: alwaysAddCrashInfo,
            debug: debug,
            effectuationStack: _effectuationStack,
            waitNotPausedFunction: waitNotPausedFunction
        )
    }
    
    public var waitNotPausedFunction: (() -> ())?
    
    public init(
        processID: String? = nil,
        applicationName: String = "(unkown application)",
        logger: Logger = PrintLogger(),
        worstMessageTypeHolder: WorstMessageTypeHolder? = nil,
        crashLogger: Logger? = nil,
        itemInfo: String? = nil,
        showSteps: Bool = false,
        alwaysAddCrashInfo: Bool = false,
        debug: Bool = false,
        effectuationStack: [Effectuation] = [Effectuation](),
        beforeStepOperation: ((OperationCount,StepID) -> AugmentOperationCount)? = nil,
        afterStepOperation: ((OperationCount,StepID?) -> AugmentOperationCount)? = nil,
        withOptions activatedOptions: Set<String>? = nil,
        dispensingWith dispensedWith: Set<String>? = nil,
        waitNotPausedFunction: (() -> ())? = nil,
        logFileInfo: URL? = nil
    ) {
        self._effectuationStack = effectuationStack
        self.logger = logger
        self.worstMessageTypeHolder = worstMessageTypeHolder ?? WorstMessageTypeHolder()
        self.crashLogger = crashLogger
        self.processID = processID
        self.applicationName = applicationName
        self.itemInfo = itemInfo
        self.alwaysAddCrashInfo = alwaysAddCrashInfo
        self.debug = debug
        self._beforeStepOperation = beforeStepOperation
        self._afterStepOperation = afterStepOperation
        self.activatedOptions = activatedOptions
        self.dispensedWith = dispensedWith
        self.waitNotPausedFunction = waitNotPausedFunction
        self.logFileInfo = logFileInfo
        _async = AsyncEffectuation(execution: self)
    }
    
    private var force = false
    
    private let worstMessageTypeHolder: WorstMessageTypeHolder
    
    public var stopped: Bool { worstMessageTypeHolder.worstMessageType >= .Fatal }
    
    public var worstMessageType: MessageType { worstMessageTypeHolder.worstMessageType }
    
    public func updateWorstMessageType(with messageType: MessageType) {
        worstMessageTypeHolder.updateWorstMessageType(with: min(appeaseTypes.last ?? .Deadly, messageType))
    }
    
    var forceValues = [Bool]()
    var appeaseTypes = [MessageType]()
    
    // only use when the program has only one execution!
    let semaphoreForPause = DispatchSemaphore(value: 1)
    
    /// Pausing the execution (without effect for async execution).
    public func pause() {
        semaphoreForPause.wait()
    }
    
    /// Proceeding a paused execution.
    public func proceed() {
        semaphoreForPause.signal()
    }
    
    func waitNotPaused() {
        
        func waitNotPaused() {
            semaphoreForPause.wait(); semaphoreForPause.signal()
        }
        
        (waitNotPausedFunction ?? waitNotPaused)() // wait if the execution is paused
    }
    
    fileprivate func beforeExecution(step: StepID?, force: Bool, appeaseTo appeaseType: MessageType? = nil) {
        waitNotPaused() // wait if the execution is paused
        forceValues.append(force)
        if let appeaseType {
            appeaseTypes.append(appeaseType)
        }
        if !force, let _beforeStepOperation, let step {
            operationCount += 1
            if !_beforeStepOperation(operationCount, step) {
                operationCount -= 1
            }
        }
        if let step {
            _effectuationStack.append(.step(step: step))
        }
    }
    
    fileprivate func afterExecution(step: StepID?, force: Bool, appeaseTo appeaseType: MessageType? = nil) {
        if step != nil {
            _effectuationStack.removeLast()
        }
        if !force, let _afterStepOperation, let step {
            operationCount += 1
            if !_afterStepOperation(operationCount, step) {
                operationCount -= 1
            }
        }
        forceValues.removeLast()
        if appeaseType != nil {
            appeaseTypes.removeLast()
        }
    }
    
    /// Force all contained work to be executed, even if already executed before.
    fileprivate func execute<T>(step: StepID?, force: Bool, appeaseTo appeaseType: MessageType? = nil, work: () throws -> T) rethrows -> T {
        beforeExecution(step: step, force: force, appeaseTo: appeaseType)
        let result = try work()
        afterExecution(step: step, force: force, appeaseTo: appeaseType)
        return result
    }
    
    /// Executes only if the step did not execute before.
    public func enter(step: StepID) -> Bool {
        if effectuateTest(forStep: step) {
            beforeExecution(step: step, force: false, appeaseTo: nil)
            return true
        } else {
            return false
        }
    }
    
    /// Do the ending of a step.
    public func ending(step: StepID, start: DispatchTime) {
        afterExecution(step: step, force: false, appeaseTo: nil)
        after(step: step, secondsElapsed: elapsedSeconds(start: start))
    }
    
    /// Starting to force the execution of steps./
    public func startForced() {
        forceValues.append(true)
    }
    
    /// Ending to force the execution of steps.
    public func endForced() {
        forceValues.removeLast()
    }
    
    /// Executes always.
    public func force<T>(work: () throws -> T) rethrows -> T? {
        try execute(step: nil, force: true, work: work)
    }
    
    /// After execution, disremember what has been executed.
    public func disremember<T>(work: () throws -> T) rethrows -> T? {
        let oldExecutedSteps = executedSteps
        let result = try execute(step: nil, force: false, work: work)
        executedSteps = oldExecutedSteps
        return result
    }
    
    /// Executes always if in a forced context.
    public func inheritForced<T>(work: () throws -> T) rethrows -> T? {
        try execute(step: nil, force: forceValues.last == true, work: work)
    }
    
    /// Something that does not run in the normal case but ca be activated. Should use module name as prefix.
    public func optional<T>(named partName: String, work: () throws -> T) rethrows -> T? {
        let result: T?
        if activatedOptions?.contains(partName) != true || dispensedWith?.contains(partName) == true {
            logger.log(LoggingEvent(
                type: .Progress,
                executionLevel: _effectuationStack.count,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: "OPTIONAL PART \"\(partName)\" NOT ACTIVATED"],
                itemInfo: itemInfo,
                effectuationStack: _effectuationStack
            ))
            result = nil
        } else {
            logger.log(LoggingEvent(
                type: .Progress,
                executionLevel: _effectuationStack.count,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: ">> START OPTIONAL PART \"\(partName)\""],
                itemInfo: itemInfo,
                effectuationStack: _effectuationStack
            ))
            _effectuationStack.append(.optionalPart(name: partName))
            result = try execute(step: nil, force: false, work: work)
            _effectuationStack.removeLast()
            logger.log(LoggingEvent(
                type: .Progress,
                executionLevel: _effectuationStack.count,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: "<< DONE OPTIONAL PART \"\(partName)\""],
                itemInfo: itemInfo,
                effectuationStack: _effectuationStack
            ))
        }
        return result
    }
    
    /// Check for something that runs in the normal case but ca be dispensed with. Should use module name as prefix.
        public func dispensableIsActive(named partName: String) -> Bool {
            if dispensedWith?.contains(partName) == true {
                logger.log(LoggingEvent(
                    type: .Progress,
                    executionLevel: _effectuationStack.count,
                    processID: processID,
                    applicationName: applicationName,
                    fact: [.en: "DISPENSABLE PART \"\(partName)\" DEACTIVATED"],
                    itemInfo: itemInfo,
                    effectuationStack: _effectuationStack
                ))
                return false
            } else {
                logger.log(LoggingEvent(
                    type: .Progress,
                    executionLevel: _effectuationStack.count,
                    processID: processID,
                    applicationName: applicationName,
                    fact: [.en: "DISPENSABLE PART \"\(partName)\" IS ACTIVE"],
                    itemInfo: itemInfo,
                    effectuationStack: _effectuationStack
                ))
                return true
            }
        }
    
    /// Something that runs in the normal case but ca be dispensed with. Should use module name as prefix.
    public func dispensable<T>(named partName: String, work: () throws -> T) rethrows -> T? {
        let result: T?
        if dispensedWith?.contains(partName) == true {
            logger.log(LoggingEvent(
                type: .Progress,
                executionLevel: _effectuationStack.count,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: "DISPENSABLE PART \"\(partName)\" DEACTIVATED"],
                itemInfo: itemInfo,
                effectuationStack: _effectuationStack
            ))
            result = nil
        } else {
            logger.log(LoggingEvent(
                type: .Progress,
                executionLevel: _effectuationStack.count,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: ">> START DISPENSABLE PART \"\(partName)\""],
                itemInfo: itemInfo,
                effectuationStack: _effectuationStack
            ))
            _effectuationStack.append(.dispensablePart(name: partName))
            result = try execute(step: nil, force: false, work: work)
            _effectuationStack.removeLast()
            logger.log(LoggingEvent(
                type: .Progress,
                executionLevel: _effectuationStack.count,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: "<< DONE DISPENSABLE PART \"\(partName)\""],
                itemInfo: itemInfo,
                effectuationStack: _effectuationStack
            ))
        }
        return result
    }
    
    /// Make worse message type than `Error` to type `Error` in contained calls.
    public func appease<T>(to appeaseType: MessageType? = .Error, work: () throws -> T) rethrows -> T? {
        try execute(step: nil, force: false, appeaseTo: appeaseType, work: work)
    }
    
    private func effectuateTest(forStep step: StepID) -> Bool {
        if stopped {
            self.log(executionMessages.skippingStep, step.description)
        }
        else if !executedSteps.contains(step) || forceValues.last == true {
            logger.log(LoggingEvent(
                type: .Progress,
                executionLevel: _effectuationStack.count,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: ">> STEP \(step.description)"],
                itemInfo: itemInfo,
                effectuationStack: _effectuationStack
            ))
            executedSteps.insert(step)
            return true
        } else if debug {
            self.log(executionMessages.skippingStep, step.description, step.description)
        }
        return false
    }
    
    /// Logging some work (that is not a step) as progress.
    public func doing<T>(withID id: String? = nil, _ description: String, work: () throws -> T) rethrows -> T? {
        _effectuationStack.append(.describedPart(description: description))
        self.log(Message(id: id, type: .Progress, fact: [.en: "START DOING \(description)"]))
        let result = try work()
        self.log(Message(id: id, type: .Progress, fact: [.en: "DONE DOING \(description)"]))
        _effectuationStack.removeLast()
        return result
    }
    
    private func after(step: StepID, secondsElapsed: Double) {
        logger.log(LoggingEvent(
            type: .Progress,
            executionLevel: _effectuationStack.count,
            processID: processID,
            applicationName: applicationName,
            fact: [.en: "<< \(stopped ? "ABORDED" : "DONE") STEP \(step) (duration: \(secondsElapsed) seconds)" ],
            itemInfo: itemInfo,
            effectuationStack: _effectuationStack
        ))
    }
    
    /// Executes only if the step did not execute before.
    public func effectuate<T>(checking step: StepID, work: () throws -> T) rethrows -> T? {
        if effectuateTest(forStep: step) {
            let start = DispatchTime.now()
            let result = try execute(step: step, force: false, work: work)
            after(step: step, secondsElapsed: elapsedSeconds(start: start))
            return result
        } else {
            return nil
        }
    }
    
    public actor AsyncEffectuation {
        
        private weak var execution: Execution!
        
        init(execution: Execution) {
            self.execution = execution
        }
        
        /// Force all contained work to be executed, even if already executed before.
        fileprivate func execute<T>(step: StepID?, force: Bool, appeaseTo appeaseType: MessageType? = nil, work: () async throws -> T) async rethrows -> T {
            // (no waiting in a paused execution for async execution)
            execution.forceValues.append(force)
            if let appeaseType {
                execution.appeaseTypes.append(appeaseType)
            }
            if !force, let _beforeStepOperation = execution._beforeStepOperation, let step {
                execution.operationCount += 1
                if !_beforeStepOperation(execution.operationCount, step) {
                    execution.operationCount -= 1
                }
            }
            if let step {
                execution._effectuationStack.append(.step(step: step))
            }
            let result = try await work()
            if step != nil {
                execution._effectuationStack.removeLast()
            }
            if !force, let _afterStepOperation = execution._afterStepOperation, let step {
                execution.operationCount += 1
                if !_afterStepOperation(execution.operationCount, step) {
                    execution.operationCount -= 1
                }
            }
            execution.forceValues.removeLast()
            if appeaseType != nil {
                execution.appeaseTypes.removeLast()
            }
            return result
        }
        
        /// Executes only if the step did not execute before.
        public func effectuate<T>(checking step: StepID, sendable work: () async throws -> T) async rethrows -> T? {
            if execution.effectuateTest(forStep: step) {
                let start = DispatchTime.now()
                let result = try await execute(step: step, force: false, work: work)
                execution.after(step: step, secondsElapsed: elapsedSeconds(start: start))
                return result
            } else {
                return nil
            }
        }
        
        /// Executes always.
        public func force<T>(work: () async throws -> T) async rethrows -> T? {
            try await execute(step: nil, force: true, work: work)
        }
        
        /// After execution, disremember what has been executed.
        public func disremember<T>(work: () throws -> T) async rethrows -> T? {
            let oldExecutedSteps = execution.executedSteps
            let result = try await execute(step: nil, force: false, work: work)
            execution.executedSteps = oldExecutedSteps
            return result
        }
        
        /// Executes always if in a forced context.
        public func inheritForced<T>(work: () throws -> T) async rethrows -> T? {
            try await execute(step: nil, force: execution.forceValues.last == true, work: work)
        }
        
        /// Something that does not run in the normal case but ca be activated. Should use module name as prefix.
        public func optional<T>(named partName: String, work: () async throws -> T) async rethrows -> T? {
            
            let result: T?
            if execution.activatedOptions?.contains(partName) != true || execution.dispensedWith?.contains(partName) == true {
                execution.logger.log(LoggingEvent(
                    type: .Progress,
                    executionLevel: execution._effectuationStack.count,
                    processID: execution.processID,
                    applicationName: execution.applicationName,
                    fact: [.en: "OPTIONAL PART \"\(partName)\" NOT ACTIVATED"],
                    itemInfo: execution.itemInfo,
                    effectuationStack: execution._effectuationStack
                ))
                result = nil
            } else {
                execution.logger.log(LoggingEvent(
                    type: .Progress,
                    executionLevel: execution._effectuationStack.count,
                    processID: execution.processID,
                    applicationName: execution.applicationName,
                    fact: [.en: ">> START OPTIONAL PART \"\(partName)\""],
                    itemInfo: execution.itemInfo,
                    effectuationStack: execution._effectuationStack
                ))
                execution._effectuationStack.append(.optionalPart(name: partName))
                result = try await execute(step: nil, force: false, work: work)
                execution._effectuationStack.removeLast()
                execution.logger.log(LoggingEvent(
                    type: .Progress,
                    executionLevel: execution._effectuationStack.count,
                    processID: execution.processID,
                    applicationName: execution.applicationName,
                    fact: [.en: "<< DONE OPTIONAL PART \"\(partName)\""],
                    itemInfo: execution.itemInfo,
                    effectuationStack: execution._effectuationStack
                ))
            }
            return result
        }
        
        /// Something that runs in the normal case but ca be dispensed with. Should use module name as prefix.
        public func dispensable<T>(named partName: String, work: () async throws -> T) async rethrows -> T? {
            let result: T?
            if execution.dispensedWith?.contains(partName) == true {
                execution.logger.log(LoggingEvent(
                    type: .Progress,
                    executionLevel: execution._effectuationStack.count,
                    processID: execution.processID,
                    applicationName: execution.applicationName,
                    fact: [.en: "DISPENSABLE PART \"\(partName)\" DEACTIVATED"],
                    itemInfo: execution.itemInfo,
                    effectuationStack: execution._effectuationStack
                ))
                result = nil
            } else {
                execution.logger.log(LoggingEvent(
                    type: .Progress,
                    executionLevel: execution._effectuationStack.count,
                    processID: execution.processID,
                    applicationName: execution.applicationName,
                    fact: [.en: ">> START DISPENSABLE PART \"\(partName)\""],
                    itemInfo: execution.itemInfo,
                    effectuationStack: execution._effectuationStack
                ))
                execution._effectuationStack.append(.dispensablePart(name: partName))
                result = try await execute(step: nil, force: false, work: work)
                execution._effectuationStack.removeLast()
                execution.logger.log(LoggingEvent(
                    type: .Progress,
                    executionLevel: execution._effectuationStack.count,
                    processID: execution.processID,
                    applicationName: execution.applicationName,
                    fact: [.en: "<< DONE DISPENSABLE PART \"\(partName)\""],
                    itemInfo: execution.itemInfo,
                    effectuationStack: execution._effectuationStack
                ))
            }
            return result
        }
        
        /// Make worse message type than `Error` to type `Error` in contained calls.
        public func appease<T>(to appeaseType: MessageType? = .Error, work: () throws -> T) async rethrows -> T? {
            try await execute(step: nil, force: false, appeaseTo: appeaseType, work: work)
        }
    }
    
    /// Log a `Message` instance. A full `LoggingEvent` instance will be created
    /// that contains the message.
    public func log(
        _ message: Message,
        itemPositionInfo: String? = nil,
        addCrashInfo: Bool = false,
        withArguments arguments: [String]?
    ) {
        log(
            event: LoggingEvent(
                messageID: message.id,
                type: message.type,
                executionLevel: _effectuationStack.count,
                processID: processID,
                applicationName: applicationName,
                fact: message.fact.filling(withArguments: arguments),
                solution: message.solution?.filling(withArguments: arguments),
                itemInfo: itemInfo,
                itemPositionInfo: itemPositionInfo,
                effectuationStack: _effectuationStack
            ),
            addCrashInfo: addCrashInfo
        )
    }
    
    /// Log a `Message` instance. A full `LoggingEvent` instance will be created
    /// that contains the message. Return a simple, English based textual presentation.
    public func logAndUseInfo(
        _ message: Message,
        itemPositionInfo: String? = nil,
        addCrashInfo: Bool = false,
        withArguments arguments: [String]?
    ) -> String {
        let fact = message.fact.filling(withArguments: arguments)
        let solution = message.solution?.filling(withArguments: arguments)
        log(
            event: LoggingEvent(
                messageID: message.id,
                type: message.type,
                executionLevel: _effectuationStack.count,
                processID: processID,
                applicationName: applicationName,
                fact: fact,
                solution: solution,
                itemInfo: itemInfo,
                itemPositionInfo: itemPositionInfo,
                effectuationStack: _effectuationStack
            ),
            addCrashInfo: addCrashInfo
        )
        return fact[.en]?.appending(solution?[.en]?.prepending(" → ")) ?? "(missing English text)"
    }
    
    public func log(collected: [SimpleLoggingEvent], addCrashInfo: Bool = false) async {
        collected.forEach { simpleEvent in
            log(
                simpleEvent.message,
                itemPositionInfo: simpleEvent.itemPositionInfo,
                addCrashInfo: addCrashInfo,
                withArguments: simpleEvent.arguments
            )
        }
    }
    
    /// Log a `Message` instance. A full `LoggingEvent` instance will be created
    /// that contains the message.
    public func log(
        _ message: Message,
        itemPositionInfo: String? = nil,
        addCrashInfo: Bool = false,
        _ arguments: String...
    ) -> () {
        log(message, itemPositionInfo: itemPositionInfo, addCrashInfo: addCrashInfo, withArguments: arguments)
    }
    
    /// Log a full `LoggingEvent` instance.
    public func log(event: LoggingEvent, addCrashInfo: Bool = false) -> () {
        var event = event
        event.executionLevel = _effectuationStack.count
        if addCrashInfo || alwaysAddCrashInfo {
            self.crashLogger?.log(event)
        }
        if let appeaseType = appeaseTypes.last, event.type > appeaseType {
            self.logger.log(event.withType(appeaseType))
        }
        else {
            self.logger.log(event)
        }
        updateWorstMessageType(with: event.type)
    }
}

/// Standard messages informing about the execution.
struct ExecutionMessages: MessagesHolder {
    
    /// A standard message informing aboout the skipping of a step.
    let skippingStep = Message(id: "skipping step", type: .Debug, fact: [
        .en: "Skipping step $1 since it ran already, function: $2.",
        .fr: "L'étape $1 est ignorée car elle a déjà été exécutée, fonction $2.",
        .de: "Schritt $1 wird übersprungen, da er bereits gelaufen ist, Funktion $2.",
    ])
}

// An instance of `ExecutionMessages`.
let executionMessages = ExecutionMessages()

// The message type that informs about the severity a message.
//
// It conforms to `Comparable` so there is an order of severity.
public enum MessageType: Comparable, Codable, Sendable {
    
    /// Debugging information.
    case Debug
    
    /// Information about the progress (e.g. the steps being executed).
    case Progress
    
    /// Information from the processing.
    case Info
    
    /// Information about the execution for a work item, e.g. starting.
    case Iteration
    
    /// Warnings from the processing.
    case Warning
    
    /// Errors from the processing.
    case Error
    
    /// A fatal error, the execution (for the data item being processed) is
    /// then abandoned.
    case Fatal
    
    /// The program or process that has been startet to be in charge for
    /// the whole processing of a work item is lost (crashed or hanging).
    case Loss
    
    /// A deadly error, i.e. not only the processing for one work item
    /// has to be abandoned, but the whole processing cannot continue.
    case Deadly

}

// The message type to be used as argument that informs about the severity a message.
public enum MessageTypeArgument: String, ExpressibleByArgument, CaseIterable {
    case debug
    case progress
    case info
    case iteration
    case warning
    case error
    case fatal
    case loss
    case deadly
    
    public var messageType: MessageType {
        switch self {
        case .debug: MessageType.Debug
        case .progress: MessageType.Progress
        case .info: MessageType.Info
        case .iteration: MessageType.Iteration
        case .warning: MessageType.Warning
        case .error: MessageType.Error
        case .fatal: MessageType.Fatal
        case .loss: MessageType.Loss
        case .deadly: MessageType.Deadly
        }
    }
}

/// A message ID is just a text.
public typealias MessageID = String

/// The language identifier.
// TODO: if Swift >= 5.7: replace by Locale.Language (cf. https://developer.apple.com/documentation/foundation/locale/language)
public enum Language: Comparable, CodingKey {
    case de
    case en
    case fr
    
    public static var languageList: [Language] { [.en, .de, .fr] }
    
    public var description : String {
      switch self {
          case .de: "de"
          case .en: "en"
          case .fr: "fr"
        }
    }
}

// A message text is just a text.
public typealias MessageText = String

/// A localizing message is just a map from language identifiers
/// to a text, so there can be different translations of the
/// message text.
public typealias LocalizingMessage = [Language:MessageText]

public extension LocalizingMessage {
    
    /// Replaces the placeholders in all message texts of an instance of
    /// `LocalizingMessage` by the accordings arguments.
     func filling(withArguments arguments: [String]?) -> LocalizingMessage {
        guard let arguments = arguments else {
            return self
        }
        var newMessage = [Language:String]()
        self.forEach{ language, text in
            newMessage[language] = text.filling(withArguments: arguments)
        }
        return newMessage
    }
    
    /// Replaces the placeholders in all message texts of an instance of
    /// `LocalizingMessage` by the accordings arguments.
    func filling(withArguments arguments: String...) -> LocalizingMessage {
        filling(withArguments: arguments)
    }
}

public extension String {
    
    /// A message text can have placeholders $1, $2, ... which are
    /// replaced by the additional textual arguments of the `log`
    /// method. This function replaces the placeholders by those
    /// arguments.
    func filling(withArguments arguments: [String]) -> String {
        var i = 0
        var s = self
        arguments.forEach { argument in
            s = s.replacingOccurrences(of: "$\(i)", with: argument)
            i += 1
        }
        return s
    }
    
    /// A message text can have placeholders $1, $2, ... which are
    /// replaced by the additional textual arguments of the `log`
    /// method. This function replaces the placeholders by those
    /// arguments.
    func filling(withArguments arguments: String...) -> String {
        filling(withArguments: arguments)
    }
    
}
