/// This small collection of types and functions is at the
/// heart of the Workflow framework.
///
/// As explained in the package documentation, the Workflow framework
/// is in large part based on conventions.

import Foundation
import Utilities
import ArgumentParser

/// A store to keep track of the steps already run.
///
/// The signatures of the step function are used as unique
/// identifier within package (use the `#function` compiler directive
/// to get the fnction name within the function). To be unique,
/// step functions should be top-level functions.
///
/// When calling steps from another package, another
/// `ExecutionDatabase` instance should be used. See
/// the package documentation.
public class ExecutionDatabase {
    
    private var functionsExecuted = Set<String>()
    
    public init() {}
    
    /// Notify the databases that a certain step is about
    /// to be executed.
    func notifyStarting(_ functionName: String) {
        functionsExecuted.insert(functionName)
    }
    
    /// Check if the excution of a step has
    /// been started).
    func started(_ functionName: String) -> Bool {
        return functionsExecuted.contains(functionName)
    }
}

/// Manages the execution of steps. In particular
/// - prevents double execution of steps
/// - keeps global information for logging
public class Execution {
    
    var stepCount = 0
    var effectuationIDStack: [String]
    let logger: Logger
    let crashLogger: Logger?
    var processID: String?
    var applicationName: String
    var itemInfo: String? = nil
    
    let alwaysAddCrashInfo: Bool
    let debug: Bool
    
    let beforeStepOperation: ((Int,String) -> ())?
    let afterStepOperation: ((Int,String) -> ())?
    
    var _attached: [String:Any]? = nil
    
    public var attached: [String:Any] { _attached ?? { _attached = [String:Any](); return _attached! }() }
    
    var _async: AsyncEffectuation? = nil
    
    public var async: AsyncEffectuation { _async! }
    
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
        beforeStepOperation: ((Int,String) -> ())? = nil,
        afterStepOperation: ((Int,String) -> ())? = nil
    ) {
        self.effectuationIDStack = effectuationIDStack
        self.logger = logger
        self.crashLogger = crashLogger
        self.processID = processID
        self.applicationName = applicationName
        self.itemInfo = itemInfo
        self.alwaysAddCrashInfo = alwaysAddCrashInfo
        self.debug = debug
        self.beforeStepOperation = beforeStepOperation
        self.afterStepOperation = afterStepOperation
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
    
    /// Force all contained work to be executed, even if already executed before.
    fileprivate func execute(force: Bool, work: () -> ()) {
        forceValues.append(force)
        stepCount += 1
        beforeStepOperation?(stepCount, effectuationIDStack.last ?? "")
        work()
        afterStepOperation?(stepCount, effectuationIDStack.last ?? "")
        forceValues.removeLast()
    }
    
    /// Executes always.
    public func force(work: () -> ()) {
        execute(force: true, work: work)
    }
    
    private func effectuateTest(_ executionDatabase: ExecutionDatabase, _ effectuationID: String) -> Bool {
        if stopped {
            self.log(executionMessages.skippingStep, effectuationID, effectuationID)
        }
        else if !executionDatabase.started(effectuationID) || forceValues.last == true {
            effectuationIDStack.append(effectuationID)
            logger.log(LoggingEvent(
                type: .Progress,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: ">> STEP \(effectuationID)"],
                effectuationIDStack: effectuationIDStack
            ))
            executionDatabase.notifyStarting(effectuationID)
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
            fact: [.en: "<< \(stopped ? "ABORDED" : "DONE") \(effectuationID) (duration: \(secondsElapsed) seconds)" ],
            effectuationIDStack: effectuationIDStack
        ))
        effectuationIDStack.removeLast()
    }
    
    /// Executes only if the step did not execute before.
    public func effectuate(_ executionDatabase: ExecutionDatabase, _ effectuationID: String, work: () -> ()) {
        if effectuateTest(executionDatabase, effectuationID) {
            let start = DispatchTime.now()
            execute(force: false, work: work)
            afterStep(effectuationID, secondsElapsed: elapsedSeconds(start: start))
        }
    }
    
    public actor AsyncEffectuation {
        
        private let execution: Execution
        
        init(execution: Execution) {
            self.execution = execution
        }
        
        /// Force all contained work to be executed, even if already executed before.
        fileprivate func execute(force: Bool, work: () async -> ()) async {
            execution.forceValues.append(force)
            execution.stepCount += 1
            execution.beforeStepOperation?(execution.stepCount, execution.effectuationIDStack.last ?? "")
            await work()
            execution.afterStepOperation?(execution.stepCount, execution.effectuationIDStack.last ?? "")
            execution.forceValues.removeLast()
        }
        
        /// Executes only if the step did not execute before.
        public func effectuate(_ executionDatabase: ExecutionDatabase, _ effectuationID: String, work: () async -> ()) async {
            if execution.effectuateTest(executionDatabase, effectuationID) {
                let start = DispatchTime.now()
                await execute(force: false, work: work)
                execution.afterStep(effectuationID, secondsElapsed: elapsedSeconds(start: start))
            }
        }
        
        /// Executes always.
        public func force(work: () async -> ()) async {
            await execute(force: true, work: work)
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
        self.logger.log(event)
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
