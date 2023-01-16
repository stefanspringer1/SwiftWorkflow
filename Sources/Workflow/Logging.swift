/// This collection of types and functions is used for logging
/// within the Workflow framework.

import Foundation
import Utilities

#if canImport(FoundationNetworking)
    import FoundationNetworking // for URLRequest and URLSession
#endif

extension LoggingEvent {
    
    /// Put a prefix before each message text.
    func prefixed(with prefixText: String) -> LoggingEvent {
        return LoggingEvent(
            messageID: messageID,
            type: type,
            processID: processID,
            applicationName: applicationName,
            fact: fact,
            solution: solution,
            itemInfo: itemInfo,
            itemPositionInfo: itemPositionInfo,
            effectuationIDStack: effectuationIDStack
        )
    }
}

extension LocalizingMessage {
    
    /// Put a prefix before each message text.
    func prefixed(with prefixText: String) -> LocalizingMessage {
        var prefixed = LocalizingMessage()
        self.forEach{ (language,text) in
            prefixed[language] = prefixText + text
        }
        return prefixed
    }
}

public struct SimpleLoggingEvent {
    let message: Message
    let itemPositionInfo: String?
    let arguments: [String]?
}

/// A logging event.
public struct LoggingEvent: CustomStringConvertible, Encodable {
    
    /// The message ID (can be any text).
    public var messageID: MessageID? = nil
    
    /// The message type.
    public let type: MessageType

    /// The process ID for embedding in a complex processing scenario.
    public let processID: String?
    
    /// The application prefix informing about the application being executed.
    public let applicationName: String
    
    /// The description of the fact.
    public let fact: LocalizingMessage
    
    /// Possibly a proposed solution.
    public let solution: LocalizingMessage?
    
    /// The information about the work item.
    public var itemInfo: String? = nil
    
    /// The information about the position in the work item.
    public var itemPositionInfo: String? = nil
    
    /// The hierarchy of the effectuation IDs aka "step IDs"
    /// (i.e. the current one, the ID of the parent effectuation, etc.,
    /// in reversed order i.e. beginning top-level).
    public var effectuationIDStack: [String]? = nil
    
    /// The time of the event.
    public var time: String
    
    public init(
        messageID: MessageID? = nil,
        type: MessageType,
        processID: String? = nil,
        applicationName: String,
        fact: LocalizingMessage,
        solution: LocalizingMessage? = nil,
        itemInfo: String? = nil,
        itemPositionInfo: String? = nil,
        effectuationIDStack: [String]? = nil,
        time: String = formattedTime()
    ) {
        self.messageID = messageID
        self.type = type
        self.processID = processID
        self.applicationName = applicationName
        self.fact = fact
        self.solution = solution
        self.itemInfo = itemInfo
        self.itemPositionInfo = itemPositionInfo
        self.effectuationIDStack = effectuationIDStack
        self.time = time
    }
    
    /// A textual representation of the step stack.
    public var effectuationIDStackDescription: String {
        return self.effectuationIDStack?.joined(separator: " / ") ?? ""
    }
    
    /// A short textual representation of the logging event.
    public var description: String {
        return "\(self.type): \(fact[.en]?.trimming() ?? "?")\(solution != nil ? " – solution: \(solution?[.en]?.trimming() ?? "?")" : "")" + (self.itemPositionInfo != nil ? " @ \(self.itemPositionInfo!)" : "")
    }
    
    /// A longer textual representation of the logging event used in the actual logging.
    public func descriptionForLogging(usingStepIndentation: Bool = false) -> String {
        let messagePart1 = (self.processID != nil ? "{\(processID!)} " : "") + self.applicationName + " (" + self.time + "):" + STEP_INDENTATION + (usingStepIndentation && type <= .Info ? String(repeating: STEP_INDENTATION, count: self.effectuationIDStack?.count ?? 0) : (type < .Warning ? "" : (type == .Warning ? "! " : (type == .Error ? "!! " : (type == .Fatal ? "!!! " : (type == .Deadly ? "\u{1F480}" : "? "))))))
        let messagePart2 = self.description + (self.effectuationIDStack?.isEmpty == false ? " (step path: " + effectuationIDStackDescription + ")" : "")
        return messagePart1 + messagePart2 + (self.itemPositionInfo != nil ? " @ \(self.itemPositionInfo!)" : "") + (self.itemInfo != nil ? " [\(self.itemInfo!)]" : "")
    }
    
    /// The coding keys for supporting e.g. loggig via a REST API.
    enum CodingKeys: String, CodingKey {
        case messageID
        case type
        case processID
        case applicationName
        case fact
        case solution
        case itemInfo
        case itemPositionInfo
        case effectuationIDStack
        case time
    }
    
    /// The encode method for supporting e.g. loggig via a REST API.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messageID, forKey: .messageID)
        try container.encode(type, forKey: .type)
        try container.encode(processID, forKey: .processID)
        try container.encode(applicationName, forKey: .applicationName)
        try container.encode(itemInfo, forKey: .itemInfo)
        try container.encode(itemPositionInfo, forKey: .itemPositionInfo)
        try container.encode(effectuationIDStack, forKey: .effectuationIDStack)
        try container.encode(time, forKey: .time)

        var languageContainerForInfo = container.nestedContainer(keyedBy: Language.self, forKey: .fact)
        try languageContainerForInfo.encode(fact[Language.en], forKey: .en)
        try languageContainerForInfo.encode(fact[Language.fr], forKey: .fr)
        try languageContainerForInfo.encode(fact[Language.de], forKey: .de)
        
        var languageContainerForSolution = container.nestedContainer(keyedBy: Language.self, forKey: .solution)
        try languageContainerForSolution.encode(solution?[Language.en], forKey: .en)
        try languageContainerForSolution.encode(solution?[Language.fr], forKey: .fr)
        try languageContainerForSolution.encode(solution?[Language.de], forKey: .de)

    }
}

/// Decode when getting the values from e.g. via a REST API.
extension LoggingEvent: Decodable {

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.messageID = try values.decode(String?.self, forKey: .messageID)
        self.type = try values.decode(MessageType.self, forKey: .type)
        self.processID = try values.decode(String.self, forKey: .processID)
        self.applicationName = try values.decode(String.self, forKey: .applicationName)
        self.itemInfo = try values.decode(String?.self, forKey: .itemInfo)
        self.itemPositionInfo = try values.decode(String?.self, forKey: .itemPositionInfo)
        self.effectuationIDStack = try values.decode([String]?.self, forKey: .effectuationIDStack)
        self.time = try values.decode(String.self, forKey: .time)
        let fact = try values.nestedContainer(keyedBy: Language.self, forKey: .fact)
        self.fact = [Language.en: try fact.decode(String.self, forKey: .en),
                                 Language.fr: try fact.decode(String.self, forKey: .fr),
                                 Language.de: try fact.decode(String.self, forKey: .de)]
        let solution = try values.nestedContainer(keyedBy: Language.self, forKey: .solution)
        self.solution = [Language.en: try solution.decode(String.self, forKey: .en),
                                 Language.fr: try solution.decode(String.self, forKey: .fr),
                                 Language.de: try solution.decode(String.self, forKey: .de)]
    }
}

/// If configuration, the progress messages about the steps being executed are
/// indented accordings to their related structure. This is the indentation
/// then used (currently not configuratable).
let STEP_INDENTATION  = "  "

/// Get a text into one line so it can be better used for printout when logging.
extension String {
    func lineForLogfile() -> String {
        return self.trimming().replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n")
    }
}

/// A message contains a message ID, a message type, and a `LocalizingMessage`.
public struct Message {
    
    public let id: MessageID?
    public let type: MessageType
    public let fact: LocalizingMessage
    public let solution: LocalizingMessage?
    
    public init(id: MessageID?, type: MessageType, fact: LocalizingMessage, solution: LocalizingMessage? = nil) {
        self.id = id
        self.type = type
        self.fact = fact
        self.solution = solution
    }
    
}

/// A collection of messages as a map from the message ID to the message.
public typealias Messages = [MessageID:Message]

/// A `MessagesHolder` is something that contains a messages.
public protocol MessagesHolder { }

/// Getting all messages of a message holders that have an ID (only non-static members).
public extension MessagesHolder {
    var messages:[String:Message] {
        get {
            var messages = [String:Message]()
            Mirror(reflecting: self).children.forEach { child in
                if let message = child.value as? Message, let id = message.id {
                    messages[id] = message
                }
            }
            return messages
        }
    }
}

/// A step error is an error that occurred while trying to orgnaize / execute the steps.
public struct StepError: LocalizedError {
    
    private let message: String

    public init(_ message: String) {
        self.message = message
    }
    
    public var errorDescription: String? {
        return message
    }
}

/// `StepData` is something that containes messages and a descrition of the step.
public protocol StepData: MessagesHolder {
    var stepDescription: String { get }
}

extension StepData
{
    /// Get all message ID from contained steps (only non-static members).
    func messageIDs() -> [String] {
        return Mirror(reflecting: self).children.compactMap{ $0.label }
    }
}

/// Collects via its methods `collect(from:forStep:)` all messages from `StepData` instances.
///
/// It can then write all messages to an Excel table (CSV).
public class StepDataCollector {
    var allData = [String:(String,[MessageID:Message])]()
    var _languages = Set<Language>()
    public var languages: Set<Language> {
        get {
            return _languages
        }
    }
    
    public init() {}
    
    /// Collects the messages from a `StepData` instance.
    public func collect(from stepData: StepData, forStep stepName: String) {
        let stepMessages = stepData.messages
        allData[stepName] = (stepData.stepDescription,stepMessages)
        stepData.messages.values.forEach { localizingMessage in
            localizingMessage.fact.keys.forEach{ language in
                _languages.insert(language)
            }
            localizingMessage.solution?.keys.forEach{ language in
                _languages.insert(language)
            }
        }
    }
    
    /// Writes all messages to an Excel table (CSV).
    public func writeAll(toFile path: String) {
        let fileManager = FileManager.default
    
        fileManager.createFile(atPath: path,  contents:Data("".utf8), attributes: nil)
        
        if let fileHandle = FileHandle(forWritingAtPath: path) {
            writeAll(toFile: fileHandle)
        }
        else {
            print("ERROR: cannot write to [\(path)]");
        }
    }
    
    /// Prints all messages.
    public func printAll() {
        writeAll(toFile: FileHandle.standardOutput)
    }
    
    /// Writes all messages to an Excel table (CSV).
    public func writeAll(toFile fileHandle: FileHandle) {
        let languageList = Language.languageList //_languages.sorted()
        fileHandle.write("\"Step\";\"Step Description\";\"Message ID\";\"Message Type\"".data(using: .utf8)!)
        languageList.forEach { language in
            fileHandle.write(";\"Info (\(language))\";\"Solution (\(language))\"".data(using: .utf8)!)
        }
        fileHandle.write("\r\n".data(using: .utf8)!)
        allData.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .forEach { stepName in
                let stepNameEscaped = stepName.replacingOccurrences(of: "\"", with: "\"\"")
                if let (stepDescription,messagesForStep) = allData[stepName] {
                    let stepDescriptionEscaped = stepDescription.replacingOccurrences(of: "\"", with: "\"\"")
                    messagesForStep.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                    .forEach { messageID in
                        let messageIDEscaped = messageID.replacingOccurrences(of: "\"", with: "\"\"")
                        if let message = messagesForStep[messageID] {
                            fileHandle.write("\"\(stepNameEscaped)\";\"\(stepDescriptionEscaped)\";\"\(messageIDEscaped)\";\"\(message.type)\"".data(using: .utf8)!)
                            languageList.forEach { language in
                                let infoEscaped = message.fact[language]?.replacingOccurrences(of: "\"", with: "\"\"") ?? ""
                                fileHandle.write(";\"\(infoEscaped)\"".data(using: .utf8)!)
                                let solutionEscaped = message.solution?[language]?.replacingOccurrences(of: "\"", with: "\"\"") ?? ""
                                fileHandle.write(";\"\(solutionEscaped)\"".data(using: .utf8)!)
                            }
                            fileHandle.write("\r\n".data(using: .utf8)!)
                        }
                    }
                }
            }
    }
}
