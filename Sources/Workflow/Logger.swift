import Foundation

/// A logger, logging instances of `LoggingEvent`.
public protocol Logger {
    func log(_ event: LoggingEvent)
    func close() throws
}

open class AsyncLogger: Logger {

    public let loggingLevel: MessageType

    private let group: DispatchGroup
    private let queue: DispatchQueue
    
    public var loggingAction: ((LoggingEvent) -> ())? = nil
    public var closeAction: (() -> ())? = nil
    
    public init(
        loggingLevel: MessageType = .Debug
    ) {
        self.loggingLevel = loggingLevel
        self.group = DispatchGroup()
        self.queue = DispatchQueue(label: "AyncLogger", qos: .background)
    }
    
    public func log(_ event: LoggingEvent) {
        if event.type >= loggingLevel {
            group.enter()
            self.queue.async {
                self.loggingAction?(event)
                self.group.leave()
            }
        }
    }
    
    public func close() {
        group.wait()
        closeAction?()
        closeAction = nil
    }
    
}

public extension Logger {
    
    /// Logging the data that is to be composed into a `LoggingEvent`.
    func log(
        processID: String? = nil,
        applicationName: String,
        _ type: MessageType,
        _ fact: LocalizingMessage,
        solution: LocalizingMessage? = nil,
        messageID: MessageID? = nil,
        effectuationIDStack: [String]? = nil
    ) async {
        log(LoggingEvent(
            messageID: messageID,
            type: type,
            processID: processID,
            applicationName: applicationName,
            fact: fact,
            solution: solution,
            effectuationIDStack: effectuationIDStack
        ))
    }
}
