/// This small collection of types and functions is at the
/// heart of the Workflow framework.
///
/// As explained in the package documentation, the Workflow framework
/// is in large part based on conventions.

import Foundation
import Utilities

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

#if !os(macOS)
    import FoundationNetworking // for URLRequest and URLSession
#endif

/// Manages the execution of steps. In particular
/// - prevents double execution of steps
/// - keeps global information for logging
public actor Execution {
    var stepFunctionStack = [String]()
    var stepNameStack = [String]()
    var _logger: Logger
    var applicationPrefix: String
    var itemInfo: String? = nil
    var _worseMessageType: MessageType = .Debug
    
    var logger: Logger {
        get { _logger }
    }
    
    let debug: Bool
    let showSteps: Bool
    
    public init (logger: Logger, applicationPrefix: String, itemInfo: String? = nil, showSteps: Bool = false, debug: Bool = false) {
        self._logger = logger
        self.applicationPrefix = applicationPrefix
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
    
    public func force(work: () async -> ()) async {
        await execute(force: true, work: work)
    }
    
    /// Executes only if the step did not execute before.
    public func effectuate(_ executionDatabase: ExecutionDatabase, _ functionName: String, work: () async -> ()) async {
        let stepName = functionName.until(substring: "(")
        if stopped {
            await self.log(executionMessages.skippingStep, stepName, functionName)
        }
        else if !executionDatabase.started(functionName) || forceValues.last == true {
            stepFunctionStack.append(functionName)
            stepNameStack.append(stepName)
            if showSteps {
                await _logger.log(LoggingEvent(
                    type: .Progress,
                    applicationPrefix: applicationPrefix,
                    localizingMessage: [.en: ">> STEP \(stepName)"],
                    stepStack: stepNameStack
                ))
            }
            executionDatabase.notifyStarting(functionName)
            await execute(force: false, work: work)
            if showSteps {
                await _logger.log(LoggingEvent(
                    type: .Progress,
                    applicationPrefix: applicationPrefix,
                    localizingMessage: [.en: stopped ? "<< ABORDED \(stepName)" : "<< DONE \(stepName)" ],
                    stepStack: stepNameStack
                ))
            }
            stepFunctionStack.removeLast()
            stepNameStack.removeLast()
        } else if debug {
            await self.log(executionMessages.skippingStep, stepName, functionName)
        }
    }
    
    /// Log a `Message` instance. A full `LoggingEvent` instance will be created
    /// that contains the message.
    public func log(
        message: Message,
        itemPositionInfo: String? = nil,
        arguments: [String]?
    ) async -> () {
        await log(event: LoggingEvent(
            messageID: message.id,
            type: message.type,
            applicationPrefix: applicationPrefix,
            localizingMessage: fillLocalizingMessage(message: message.localizingMessage, with: arguments),
            itemInfo: itemInfo,
            itemPositionInfo: itemPositionInfo,
            stepID: stepNameStack.last,
            stepFunction: stepFunctionStack.last,
            stepStack: stepNameStack
        ))
    }
    
    public func log(collected: [SimpleLoggingEvent]) async {
        await collected.forEachAsync { simpleEvent in
            await log(message: simpleEvent.message, itemPositionInfo: simpleEvent.itemPositionInfo, arguments: simpleEvent.arguments)
        }
    }
    
    /// Log a `Message` instance. A full `LoggingEvent` instance will be created
    /// that contains the message.
    public func log(
        _ message: Message,
        itemPositionInfo: String? = nil,
        _ arguments: String...
    ) async -> () {
        await log(message: message, itemPositionInfo: itemPositionInfo, arguments: arguments)
    }
    
    /// Log a full `LoggingEvent` instance.
    public func log(event: LoggingEvent) async -> () {
        updateWorstMessageType(with: event.type)
        await self._logger.log(event)
    }
}

/// Standard messages informing about the execution.
struct ExecutionMessages: MessagesHolder {
    
    /// A standard message informing aboout the skipping of a step.
    let skippingStep = Message(id: "skipping step", type: .Debug, localizingMessage: [
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
    case Execution
    
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
      case .Execution: return "Execution"
      case .Error: return "Error"
      case .Fatal: return "Fatal"
      case .Deadly: return "Deadly"
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
