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
public actor Execution {
    var effectuationIDStack = [String]()
    var _logger: Logger
    var processID: String?
    var applicationName: String
    var itemInfo: String? = nil
    var _worseMessageType: MessageType = .Debug
    
    var logger: Logger {
        get { _logger }
    }
    
    let debug: Bool
    let showSteps: Bool
    
    public init (logger: Logger, processID: String? = nil, applicationName: String, itemInfo: String? = nil, showSteps: Bool = false, debug: Bool = false) {
        self._logger = logger
        self.processID = processID
        self.applicationName = applicationName
        self.itemInfo = itemInfo
        self.debug = debug
        self.showSteps = showSteps
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
    fileprivate func execute(force: Bool, work: () async -> ()) async {
        forceValues.append(force)
        await work()
        forceValues.removeLast()
    }
    
    /// Force all contained work to be executed, even if already executed before.
    fileprivate func execute(force: Bool, work: () -> ()) {
        forceValues.append(force)
        work()
        forceValues.removeLast()
    }
    
    public func force(work: () -> ()) {
        execute(force: true, work: work)
    }
    
    public func force(work: () async -> ()) async {
        await execute(force: true, work: work)
    }
    
    private func effectuateTest(_ executionDatabase: ExecutionDatabase, _ effectuationID: String) -> Bool {
        if stopped {
            self.log(executionMessages.skippingStep, effectuationID, effectuationID)
        }
        else if !executionDatabase.started(effectuationID) || forceValues.last == true {
            effectuationIDStack.append(effectuationID)
            if showSteps {
                _logger.log(LoggingEvent(
                    type: .Progress,
                    processID: processID,
                    applicationName: applicationName,
                    fact: [.en: ">> STEP \(effectuationID)"],
                    effectuationIDStack: effectuationIDStack
                ))
            }
            executionDatabase.notifyStarting(effectuationID)
            return true
        } else if debug {
            self.log(executionMessages.skippingStep, effectuationID, effectuationID)
        }
        return false
    }
    
    private func afterStep(_ effectuationID: String) {
        if showSteps {
            _logger.log(LoggingEvent(
                type: .Progress,
                processID: processID,
                applicationName: applicationName,
                fact: [.en: stopped ? "<< ABORDED \(effectuationID)" : "<< DONE \(effectuationID)" ],
                effectuationIDStack: effectuationIDStack
            ))
        }
        effectuationIDStack.removeLast()
    }
    
    /// Executes only if the step did not execute before.
    public func effectuate(_ executionDatabase: ExecutionDatabase, _ effectuationID: String, work: () async -> ()) async {
        if effectuateTest(executionDatabase, effectuationID) {
            await execute(force: false, work: work)
            afterStep(effectuationID)
        }
    }
    
    /// Executes only if the step did not execute before.
    public func effectuate(_ executionDatabase: ExecutionDatabase, _ effectuationID: String, work: () -> ()) {
        if effectuateTest(executionDatabase, effectuationID) {
            execute(force: false, work: work)
            afterStep(effectuationID)
        }
    }
    
    /// Log a `Message` instance. A full `LoggingEvent` instance will be created
    /// that contains the message.
    public func log(
        message: Message,
        itemPositionInfo: String? = nil,
        arguments: [String]?
    ) -> () {
        log(event: LoggingEvent(
            messageID: message.id,
            type: message.type,
            processID: processID,
            applicationName: applicationName,
            fact: fillLocalizingMessage(message: message.fact, with: arguments),
            solution: fillLocalizingMessage(optionalMessage: message.solution, with: arguments),
            itemInfo: itemInfo,
            itemPositionInfo: itemPositionInfo,
            effectuationIDStack: effectuationIDStack
        ))
    }
    
    public func log(collected: [SimpleLoggingEvent]) async {
        collected.forEach { simpleEvent in
            log(message: simpleEvent.message, itemPositionInfo: simpleEvent.itemPositionInfo, arguments: simpleEvent.arguments)
        }
    }
    
    /// Log a `Message` instance. A full `LoggingEvent` instance will be created
    /// that contains the message.
    public func log(
        _ message: Message,
        itemPositionInfo: String? = nil,
        _ arguments: String...
    ) -> () {
        log(message: message, itemPositionInfo: itemPositionInfo, arguments: arguments)
    }
    
    /// Log a full `LoggingEvent` instance.
    public func log(event: LoggingEvent) -> () {
        updateWorstMessageType(with: event.type)
        self._logger.log(event)
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

// An error with a description.
public struct DescribingError: LocalizedError {
    
    private let message: String

    public init(_ message: String) {
        self.message = message
    }
    
    public var errorDescription: String? {
        return message
    }
}

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
    
    /// Warnings from the processing.
    case Warning
    
    /// Information about the execution for a work item, e.g. starting.
    case Iteration
    
    /// Errors from the processing.
    case Error
    
    /// A fatal error, the execution (for the data item being processed) is
    /// then abandoned.
    case Fatal
    
    /// A deadly erropr, i.e. not only the processing for one work item
    /// has to be abandoned, but the whole processing cannot continue.
    case Deadly

    /// The description for the message type, which will be used
    /// when logging an event.
    public var description : String {
      switch self {
      case .Debug: return "Debug"
      case .Progress: return "Progress"
      case .Info: return "Info"
      case .Warning: return "Warning"
      case .Iteration: return "Iteration"
      case .Error: return "Error"
      case .Fatal: return "Fatal"
      case .Deadly: return "Deadly"
      }
    }
}

// The message type to be used as argukentthat informs about the severity a message.
public enum MessageTypeArgument: String, ExpressibleByArgument {
    case debug
    case progress
    case info
    case warning
    case iteration
    case error
    case fatal
    case deadly
    
    public var messageType: MessageType {
        switch self {
        case .debug: return MessageType.Debug
        case .progress: return MessageType.Progress
        case .info: return MessageType.Info
        case .warning: return MessageType.Warning
        case .iteration: return MessageType.Iteration
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
