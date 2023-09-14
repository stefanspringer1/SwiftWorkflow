/// This small collection of types and functions is at the
/// heart of the Workflow framework.
///
/// As explained in the package documentation, the Workflow framework
/// is in large part based on conventions.

import Foundation
import Utilities
import ArgumentParser

public struct StepID: Hashable, CustomStringConvertible {
    
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

public enum Effectuation: CustomStringConvertible {
    
    case step(step: StepID)
    case dispensablePart(name: String)
    case optionalPart(name: String)
    
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

/// Manages the execution of steps. In particular
/// - prevents double execution of steps
/// - keeps global information for logging
public class Execution {
    
    private var executedSteps = Set<StepID>()
    
    var effectuationStack: [Effectuation]
    
    let logger: Logger
    let crashLogger: Logger?
    var processID: String?
    var applicationName: String
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
        Execution(logger: logger, crashLogger: crashLogger, processID: processID, applicationName: applicationName, itemInfo: itemInfo, alwaysAddCrashInfo: alwaysAddCrashInfo, debug: debug, effectuationStack: effectuationStack)
    }
    
    private init (
        logger: Logger,
        crashLogger: Logger? = nil,
        processID: String? = nil,
        applicationName: String,
        itemInfo: String? = nil,
        showSteps: Bool = false,
        alwaysAddCrashInfo: Bool = false,
        debug: Bool = false,
        effectuationStack: [Effectuation] = [Effectuation](),
        beforeStepOperation: ((OperationCount,StepID) -> AugmentOperationCount)? = nil,
        afterStepOperation: ((OperationCount,StepID?) -> AugmentOperationCount)? = nil,
        withOptions activatedOptions: Set<String>? = nil,
        dispensingWith dispensedWith: Set<String>? = nil
    ) {
        self.effectuationStack = effectuationStack
        self.logger = logger
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
        _async = AsyncEffectuation(execution: self)
    }
    
    public convenience init (
        logger: Logger,
        crashLogger: Logger? = nil,
        processID: String? = nil,
        applicationName: String,
        itemInfo: String? = nil,
        showSteps: Bool = false,
        alwaysAddCrashInfo: Bool = false,
        debug: Bool = false,
        beforeStepOperation: ((OperationCount,StepID) -> AugmentOperationCount)? = nil,
        afterStepOperation: ((OperationCount,StepID?) -> AugmentOperationCount)? = nil,
        withOptions activatedOptions: Set<String>? = nil,
        dispensingWith dispensedWith: Set<String>? = nil
    ) {
        self.init (
            logger: logger,
            crashLogger: crashLogger,
            processID: processID,
            applicationName: applicationName,
            itemInfo: itemInfo,
            showSteps: showSteps,
            alwaysAddCrashInfo: alwaysAddCrashInfo,
            debug: debug,
            effectuationStack: [Effectuation](),
            beforeStepOperation: beforeStepOperation,
            afterStepOperation: afterStepOperation,
            withOptions: activatedOptions,
            dispensingWith: dispensedWith
        )
    }
    
    private var force = false
    
    private var _worstMessageType = MessageType.Info
    
    public var stopped: Bool { _worstMessageType >= .Fatal }
    
    public var worstMessageType: MessageType { _worstMessageType }
    
    public func updateWorstMessageType(with messageType: MessageType) {
        _worstMessageType = max(_worstMessageType, messageType)
    }

    var forceValues = [Bool]()
    var appeaseTypes = [MessageType]()
    
    /// Force all contained work to be executed, even if already executed before.
    fileprivate func execute<T>(step: StepID?, force: Bool, appeaseTo appeaseType: MessageType? = nil, work: () throws -> T) rethrows -> T {
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
        let result = try work()
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
        return result
    }
    
    /// Executes always.
    public func force<T>(work: () throws -> T) rethrows -> T? {
        try execute(step: nil, force: true, work: work)
    }
    
    /// Something that does not run in the normal case but ca be activated. Should use module name as prefix.
    public func optional<T>(named partName: String, work: () throws -> T) rethrows -> T? {
        let result: T?
        effectuationStack.append(.optionalPart(name: partName))
        if activatedOptions?.contains(partName) != true || dispensedWith?.contains(partName) == true {
            logger.log(LoggingEvent(
                type: .Progress,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: "OPTIONAL PART \"\(partName)\" NOT ACTIVATED"],
                effectuationStack: effectuationStack
            ))
            result = nil
        } else {
            logger.log(LoggingEvent(
                type: .Progress,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: ">> OPTIONAL PART \"\(partName)\""],
                effectuationStack: effectuationStack
            ))
            result = try execute(step: nil, force: false, work: work)
            logger.log(LoggingEvent(
                type: .Progress,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: "<< DONE OPTIONAL PART \"\(partName)\""],
                effectuationStack: effectuationStack
            ))
        }
        effectuationStack.removeLast()
        return result
    }
    
    /// Something that runs in the normal case but ca be dispensed with. Should use module name as prefix.
    public func dispensable<T>(named partName: String, work: () throws -> T) rethrows -> T? {
        let result: T?
        effectuationStack.append(.dispensablePart(name: partName))
        if dispensedWith?.contains(partName) == true {
            logger.log(LoggingEvent(
                type: .Progress,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: "DISPENSABLE PART \"\(partName)\" DEACTIVATED"],
                effectuationStack: effectuationStack
            ))
            result = nil
        } else {
            logger.log(LoggingEvent(
                type: .Progress,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: ">> DISPENSABLE PART \"\(partName)\""],
                effectuationStack: effectuationStack
            ))
            result = try execute(step: nil, force: false, work: work)
            logger.log(LoggingEvent(
                type: .Progress,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: "<< DONE DISPENSABLE PART \"\(partName)\""],
                effectuationStack: effectuationStack
            ))
        }
        effectuationStack.removeLast()
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
            effectuationStack.append(.step(step: step))
            logger.log(LoggingEvent(
                type: .Progress,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: ">> STEP \(step.description)"],
                effectuationStack: effectuationStack
            ))
            executedSteps.insert(step)
            return true
        } else if debug {
            self.log(executionMessages.skippingStep, step.description, step.description)
        }
        return false
    }
    
    private func after(step: StepID, secondsElapsed: Double) {
        logger.log(LoggingEvent(
            type: .Progress,
            processID: processID,
            applicationName: applicationName,
            fact: [.en: "<< \(stopped ? "ABORDED" : "DONE") STEP \(step) (duration: \(secondsElapsed) seconds)" ],
            effectuationStack: effectuationStack
        ))
        effectuationStack.removeLast()
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
            let result = try await work()
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
        public func effectuate<T>(checking step: StepID, work: () async throws -> T) async rethrows -> T? {
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
        
        /// Something that does not run in the normal case but ca be activated. Should use module name as prefix.
        public func optional<T>(named partName: String, work: () async throws -> T) async rethrows -> T? {
            execution.effectuationStack.append(.optionalPart(name: partName))
            let result: T?
            if execution.activatedOptions?.contains(partName) != true || execution.dispensedWith?.contains(partName) == true {
                execution.logger.log(LoggingEvent(
                    type: .Progress,
                    processID: execution.processID,
                    applicationName: execution.applicationName,
                    fact: [.en: "OPTIONAL PART \"\(partName)\" NOT ACTIVATED"],
                    effectuationStack: execution.effectuationStack
                ))
                result = nil
            } else {
                execution.logger.log(LoggingEvent(
                    type: .Progress,
                    processID: execution.processID,
                    applicationName: execution.applicationName,
                    fact: [.en: ">> OPTIONAL PART \"\(partName)\""],
                    effectuationStack: execution.effectuationStack
                ))
                result = try await execute(step: nil, force: false, work: work)
                execution.logger.log(LoggingEvent(
                    type: .Progress,
                    processID: execution.processID,
                    applicationName: execution.applicationName,
                    fact: [.en: "<< DONE OPTIONAL PART \"\(partName)\""],
                    effectuationStack: execution.effectuationStack
                ))
            }
            execution.effectuationStack.removeLast()
            return result
        }
        
        /// Something that runs in the normal case but ca be dispensed with. Should use module name as prefix.
        public func dispensable<T>(named partName: String, work: () async throws -> T) async rethrows -> T? {
            let result: T?
            execution.effectuationStack.append(.dispensablePart(name: partName))
            if execution.dispensedWith?.contains(partName) == true {
                execution.logger.log(LoggingEvent(
                    type: .Progress,
                    processID: execution.processID,
                    applicationName: execution.applicationName,
                    fact: [.en: "DISPENSABLE PART \"\(partName)\" DEACTIVATED"],
                    effectuationStack: execution.effectuationStack
                ))
                result = nil
            } else {
                execution.logger.log(LoggingEvent(
                    type: .Progress,
                    processID: execution.processID,
                    applicationName: execution.applicationName,
                    fact: [.en: ">> DISPENSABLE PART \"\(partName)\""],
                    effectuationStack: execution.effectuationStack
                ))
                result = try await execute(step: nil, force: false, work: work)
                execution.logger.log(LoggingEvent(
                    type: .Progress,
                    processID: execution.processID,
                    applicationName: execution.applicationName,
                    fact: [.en: "<< DONE DISPENSABLE PART \"\(partName)\""],
                    effectuationStack: execution.effectuationStack
                ))
            }
            execution.effectuationStack.removeLast()
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
    ) -> () {
        log(
            event: LoggingEvent(
                messageID: message.id,
                type: message.type,
                processID: processID,
                applicationName: applicationName,
                fact: message.fact.filling(withArguments: arguments),
                solution: message.solution?.filling(withArguments: arguments),
                itemInfo: itemInfo,
                itemPositionInfo: itemPositionInfo,
                effectuationStack: effectuationStack
            ),
            addCrashInfo: addCrashInfo
        )
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
public enum MessageType: Comparable, Codable {
    
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
public enum MessageTypeArgument: String, ExpressibleByArgument {
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
        case .debug: return MessageType.Debug
        case .progress: return MessageType.Progress
        case .info: return MessageType.Info
        case .iteration: return MessageType.Iteration
        case .warning: return MessageType.Warning
        case .error: return MessageType.Error
        case .fatal: return MessageType.Fatal
        case .loss: return MessageType.Loss
        case .deadly: return MessageType.Deadly
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
          case .de: return "de"
          case .en: return "en"
          case .fr: return "fr"
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
