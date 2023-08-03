/// This small collection of types and functions is at the
/// heart of the Workflow framework.
///
/// As explained in the package documentation, the Workflow framework
/// is in large part based on conventions.

import Foundation
import Utilities
import ArgumentParser

/// Manages the execution of steps. In particular
/// - prevents double execution of steps
/// - keeps global information for logging
public class Execution {
    
    private var executed = Set<String>()
    
    var effectuationIDStack: [String]
    let logger: Logger
    let crashLogger: Logger?
    var processID: String?
    var applicationName: String
    var itemInfo: String? = nil
    
    let alwaysAddCrashInfo: Bool
    let debug: Bool
    
    var _beforeStepOperation: ((Int,String) -> Bool)?
    
    let dispensedWith: Set<String>?
    let activatedOptions: Set<String>?
    
    public var beforeStepOperation: ((Int,String) -> Bool)? {
        get {
            _beforeStepOperation
        }
        set {
            _beforeStepOperation = newValue
        }
    }
    
    var _afterStepOperation: ((Int,String) -> Bool)?
    
    public var afterStepOperation: ((Int,String) -> Bool)? {
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
        Execution(logger: logger, crashLogger: crashLogger, processID: processID, applicationName: applicationName, itemInfo: itemInfo, alwaysAddCrashInfo: alwaysAddCrashInfo, debug: debug, effectuationIDStack: effectuationIDStack)
    }
    
    public init (
        logger: Logger,
        crashLogger: Logger? = nil,
        processID: String? = nil,
        applicationName: String,
        itemInfo: String? = nil,
        showSteps: Bool = false,
        alwaysAddCrashInfo: Bool = false,
        debug: Bool = false,
        effectuationIDStack: [String] = [String](),
        beforeStepOperation: ((Int,String) -> Bool)? = nil,
        afterStepOperation: ((Int,String) -> Bool)? = nil,
        withOptions activatedOptions: Set<String>? = nil,
        dispensingWith: Set<String>? = nil
    ) {
        self.effectuationIDStack = effectuationIDStack
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
        self.dispensedWith = dispensingWith
        _async = AsyncEffectuation(execution: self)
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
    fileprivate func execute<T>(force: Bool, appeaseTo appeaseType: MessageType? = nil, work: () throws -> T) rethrows -> T {
        forceValues.append(force)
        if let appeaseType {
            appeaseTypes.append(appeaseType)
        }
        if !force, let _beforeStepOperation {
            operationCount += 1
            if !_beforeStepOperation(operationCount, effectuationIDStack.last ?? "") {
                operationCount -= 1
            }
        }
        let result = try work()
        if !force, let _afterStepOperation{
            operationCount += 1
            if !_afterStepOperation(operationCount, effectuationIDStack.last ?? "") {
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
        try execute(force: true, work: work)
    }
    
    /// Something that does not run in the normal case but ca be activated. Should use module name as prefix.
    public func optional<T>(named optionName: String, work: () throws -> T) rethrows -> T? {
        let result: T?
        effectuationIDStack.append("optional part \"\(optionName)\"")
        if activatedOptions?.contains(optionName) != true || dispensedWith?.contains(optionName) == true {
            logger.log(LoggingEvent(
                type: .Progress,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: "OPTIONAL PART \"\(optionName)\" NOT ACTIVATED"],
                effectuationIDStack: effectuationIDStack
            ))
            result = nil
        } else {
            logger.log(LoggingEvent(
                type: .Progress,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: ">> OPTIONAL PART \"\(optionName)\""],
                effectuationIDStack: effectuationIDStack
            ))
            result = try execute(force: false, work: work)
            logger.log(LoggingEvent(
                type: .Progress,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: "<< DONE OPTIONAL PART \"\(optionName)\""],
                effectuationIDStack: effectuationIDStack
            ))
        }
        effectuationIDStack.removeLast()
        return result
    }
    
    /// Something that runs in the normal case but ca be dispensed with. Should use module name as prefix.
    public func dispensable<T>(named optionName: String, work: () throws -> T) rethrows -> T? {
        let result: T?
        effectuationIDStack.append("dispensable part \"\(optionName)\"")
        if dispensedWith?.contains(optionName) == true {
            logger.log(LoggingEvent(
                type: .Progress,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: "DISPENSABLE PART \"\(optionName)\" DEACTIVATED"],
                effectuationIDStack: effectuationIDStack
            ))
            result = nil
        } else {
            logger.log(LoggingEvent(
                type: .Progress,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: ">> DISPENSABLE PART \"\(optionName)\""],
                effectuationIDStack: effectuationIDStack
            ))
            result = try execute(force: false, work: work)
            logger.log(LoggingEvent(
                type: .Progress,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: "<< DONE DISPENSABLE PART \"\(optionName)\""],
                effectuationIDStack: effectuationIDStack
            ))
        }
        effectuationIDStack.removeLast()
        return result
    }
    
    /// Make worse message type than `Error` to type `Error` in contained calls.
    public func appease<T>(to appeaseType: MessageType? = .Error, work: () throws -> T) rethrows -> T? {
        try execute(force: false, appeaseTo: appeaseType, work: work)
    }
    
    private func effectuateTest( _ effectuationID: String) -> Bool {
        if stopped {
            self.log(executionMessages.skippingStep, effectuationID, effectuationID)
        }
        else if !executed.contains(effectuationID) || forceValues.last == true {
            effectuationIDStack.append(effectuationID)
            logger.log(LoggingEvent(
                type: .Progress,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: ">> STEP \(effectuationID)"],
                effectuationIDStack: effectuationIDStack
            ))
            executed.insert(effectuationID)
            return true
        } else if debug {
            self.log(executionMessages.skippingStep, effectuationID, effectuationID)
        }
        return false
    }
    
    private func afterStep(_ effectuationID: String, secondsElapsed: Double) {
        logger.log(LoggingEvent(
            type: .Progress,
            processID: processID,
            applicationName: applicationName,
            fact: [.en: "<< \(stopped ? "ABORDED" : "DONE") STEP \(effectuationID) (duration: \(secondsElapsed) seconds)" ],
            effectuationIDStack: effectuationIDStack
        ))
        effectuationIDStack.removeLast()
    }
    
    /// Executes only if the step did not execute before.
    public func effectuate<T>(_ effectuationID: String, work: () throws -> T) rethrows -> T? {
        if effectuateTest(effectuationID) {
            let start = DispatchTime.now()
            let result = try execute(force: false, work: work)
            afterStep(effectuationID, secondsElapsed: elapsedSeconds(start: start))
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
        fileprivate func execute<T>(force: Bool, appeaseTo appeaseType: MessageType? = nil, work: () async throws -> T) async rethrows -> T {
            execution.forceValues.append(force)
            if let appeaseType {
                execution.appeaseTypes.append(appeaseType)
            }
            if !force, let _beforeStepOperation = execution._beforeStepOperation {
                execution.operationCount += 1
                if !_beforeStepOperation(execution.operationCount, execution.effectuationIDStack.last ?? "") {
                    execution.operationCount -= 1
                }
            }
            let result = try await work()
            if !force, let _afterStepOperation = execution._afterStepOperation {
                execution.operationCount += 1
                if !_afterStepOperation(execution.operationCount, execution.effectuationIDStack.last ?? "") {
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
        public func effectuate<T>(_ effectuationID: String, work: () async throws -> T) async rethrows -> T? {
            if execution.effectuateTest(effectuationID) {
                let start = DispatchTime.now()
                let result = try await execute(force: false, work: work)
                execution.afterStep(effectuationID, secondsElapsed: elapsedSeconds(start: start))
                return result
            } else {
                return nil
            }
        }
        
        /// Executes always.
        public func force<T>(work: () async throws -> T) async rethrows -> T? {
            try await execute(force: true, work: work)
        }
        
        /// Something that does not run in the normal case but ca be activated. Should use module name as prefix.
        public func optional<T>(named optionName: String, work: () async throws -> T) async rethrows -> T? {
            execution.effectuationIDStack.append("optional part \"\(optionName)\"")
            let result: T?
            if execution.activatedOptions?.contains(optionName) != true || execution.dispensedWith?.contains(optionName) == true {
                execution.logger.log(LoggingEvent(
                    type: .Progress,
                    processID: execution.processID,
                    applicationName: execution.applicationName,
                    fact: [.en: "OPTIONAL PART \"\(optionName)\" NOT ACTIVATED"],
                    effectuationIDStack: execution.effectuationIDStack
                ))
                result = nil
            } else {
                execution.logger.log(LoggingEvent(
                    type: .Progress,
                    processID: execution.processID,
                    applicationName: execution.applicationName,
                    fact: [.en: ">> OPTIONAL PART \"\(optionName)\""],
                    effectuationIDStack: execution.effectuationIDStack
                ))
                result = try await execute(force: false, work: work)
                execution.logger.log(LoggingEvent(
                    type: .Progress,
                    processID: execution.processID,
                    applicationName: execution.applicationName,
                    fact: [.en: "<< DONE OPTIONAL PART \"\(optionName)\""],
                    effectuationIDStack: execution.effectuationIDStack
                ))
            }
            execution.effectuationIDStack.removeLast()
            return result
        }
        
        /// Something that runs in the normal case but ca be dispensed with. Should use module name as prefix.
        public func dispensable<T>(named optionName: String, work: () async throws -> T) async rethrows -> T? {
            let result: T?
            execution.effectuationIDStack.append("dispensable part \"\(optionName)\"")
            if execution.dispensedWith?.contains(optionName) == true {
                execution.logger.log(LoggingEvent(
                    type: .Progress,
                    processID: execution.processID,
                    applicationName: execution.applicationName,
                    fact: [.en: "DISPENSABLE PART \"\(optionName)\" DEACTIVATED"],
                    effectuationIDStack: execution.effectuationIDStack
                ))
                result = nil
            } else {
                execution.logger.log(LoggingEvent(
                    type: .Progress,
                    processID: execution.processID,
                    applicationName: execution.applicationName,
                    fact: [.en: ">> DISPENSABLE PART \"\(optionName)\""],
                    effectuationIDStack: execution.effectuationIDStack
                ))
                result = try await execute(force: false, work: work)
                execution.logger.log(LoggingEvent(
                    type: .Progress,
                    processID: execution.processID,
                    applicationName: execution.applicationName,
                    fact: [.en: "<< DONE DISPENSABLE PART \"\(optionName)\""],
                    effectuationIDStack: execution.effectuationIDStack
                ))
            }
            execution.effectuationIDStack.removeLast()
            return result
        }
        
        /// Make worse message type than `Error` to type `Error` in contained calls.
        public func appease<T>(to appeaseType: MessageType? = .Error, work: () throws -> T) async rethrows -> T? {
            try await execute(force: false, appeaseTo: appeaseType, work: work)
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
                fact: fillLocalizingMessage(message: message.fact, with: arguments),
                solution: fillLocalizingMessage(optionalMessage: message.solution, with: arguments),
                itemInfo: itemInfo,
                itemPositionInfo: itemPositionInfo,
                effectuationIDStack: effectuationIDStack
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

/// A message text can have placeholders $1, $2, ... which are
/// replaced by the additional textual arguments of the `log`
/// method. This function replaces the placeholders by those
/// arguments.
func format(_ _s: String, using arguments: [String]) -> String {
    var i = 0
    var s = _s
    arguments.forEach { argument in
        i += 1
        s = s.replacingOccurrences(of: "$\(i)", with: argument)
    }
    return s
}

/// Replaces the placeholders in all message texts of an instance of
/// `LocalizingMessage` by the accordings arguments.
public func fillLocalizingMessage(message: LocalizingMessage, with arguments: [String]?) -> LocalizingMessage {
    guard let arguments = arguments else {
        return message
    }
    var newMessage = [Language:String]()
    message.forEach{ language, text in
        newMessage[language] = format(text, using: arguments)
    }
    return newMessage
}

/// Replaces the placeholders in all message texts of an instance of
/// `LocalizingMessage` by the accordings arguments.
public func fillLocalizingMessage(optionalMessage _message: LocalizingMessage?, with arguments: [String]?) -> LocalizingMessage? {
    guard let message = _message else {
        return nil
    }
    return fillLocalizingMessage(message: message, with: arguments)
}
