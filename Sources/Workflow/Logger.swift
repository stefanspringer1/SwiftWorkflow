import Foundation

/// A logger, logging instances of `LoggingEvent`.
public protocol Logger {
    func log(_ event: LoggingEvent)
}

open class ConcurrentLogger: Logger {

    public let loggingLevel: MessageType

    private let group: DispatchGroup
    private let queue: DispatchQueue
    
    public var loggingAction: ((LoggingEvent) -> ())? = nil
    public var closeAction: (() -> ())? = nil
    
    public init(loggingLevel: MessageType = .Debug) {
        self.loggingLevel = loggingLevel
        self.group = DispatchGroup()
        self.queue = DispatchQueue(label: "AyncLogger", qos: .background)
    }
    
    private var closed = false
    
    public func log(_ event: LoggingEvent) {
        if event.type >= loggingLevel {
            group.enter()
            self.queue.async {
                if !self.closed {
                    self.loggingAction?(event)
                }
                self.group.leave()
            }
        }
    }
    
    private func close() {
        group.enter()
        self.queue.async {
            self.closeAction?()
            self.closed = true
            self.closeAction = nil
            self.group.leave()
        }
    }
    
    deinit {
        close()
    }
    
}

open class ConcurrentCrashLogger: Logger {

    public let loggingLevel: MessageType

    private let queue: DispatchQueue
    
    public var loggingAction: ((LoggingEvent) -> ())? = nil
    public var closeAction: (() -> ())? = nil
    
    public init(loggingLevel: MessageType = .Debug) {
        self.loggingLevel = loggingLevel
        self.queue = DispatchQueue(label: "AyncLogger", qos: .background)
    }
    
    private var closed = false
    
    public func log(_ event: LoggingEvent) {
        if event.type >= loggingLevel {
            self.queue.sync {
                self.loggingAction?(event)
            }
        }
    }
    
    private func close() {
        self.queue.sync {
            if !closed {
                closeAction?()
                closed = true
                closeAction = nil
            }
        }
        
    }
    
    deinit {
        close()
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
    ) {
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
