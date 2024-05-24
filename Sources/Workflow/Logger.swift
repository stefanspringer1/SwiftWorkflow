import Foundation

/// A logger, logging instances of `LoggingEvent`.
public protocol Logger {
    func log(_ event: LoggingEvent)
    func close() throws
}

public protocol WithLoggingFilter {
    var loggingLevel: MessageType { get set }
    var logProgress: Bool { get set }
}

public extension WithLoggingFilter {
    
    func filter(event: LoggingEvent) -> LoggingEvent? {
        if event.type == .Progress {
            if logProgress {
                return event
            }
        } else if event.type >= loggingLevel {
            return event
        }
        return nil
    }
    
}

open class ConcurrentLogger: Logger, WithLoggingFilter {
    
    public var loggingLevel: MessageType
    public var logProgress: Bool

    internal let group: DispatchGroup
    internal let queue: DispatchQueue
    
    public var loggingAction: ((LoggingEvent) -> ())? = nil
    public var closeAction: (() -> ())? = nil
    
    public init(loggingLevel: MessageType = .Debug, logProgress: Bool = true) {
        self.loggingLevel = loggingLevel
        self.logProgress = logProgress
        self.group = DispatchGroup()
        self.queue = DispatchQueue(label: "AyncLogger", qos: .background)
    }
    
    private var closed = false
    
    public func log(_ event: LoggingEvent) {
        if let event = filter(event: event) {
            group.enter()
            self.queue.async {
                if !self.closed {
                    self.loggingAction?(event)
                }
                self.group.leave()
            }
        }
    }
    
    public func close() throws {
        group.enter()
        self.queue.sync {
            if !self.closed {
                self.closeAction?()
                self.closed = true
                self.closeAction = nil
                self.group.leave()
            }
        }
    }
    
}

open class ConcurrentCrashLogger: Logger, WithLoggingFilter {
    
    public var loggingLevel: MessageType
    public var logProgress: Bool

    private let queue: DispatchQueue
    
    public var loggingAction: ((LoggingEvent) -> ())? = nil
    public var closeAction: (() -> ())? = nil
    
    public init(loggingLevel: MessageType = .Debug, logProgress: Bool = true) {
        self.loggingLevel = loggingLevel
        self.logProgress = logProgress
        self.queue = DispatchQueue(label: "AyncLogger", qos: .background)
    }
    
    private var closed = false
    
    public func log(_ event: LoggingEvent) {
        if let event = filter(event: event) {
            self.queue.sync {
                self.loggingAction?(event)
            }
        }
    }
    
    public func close() {
        self.queue.sync {
            if !closed {
                closeAction?()
                closed = true
                closeAction = nil
            }
        }
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
        itemInfo: String? = nil,
        itemPositionInfo: String? = nil,
        messageID: MessageID? = nil,
        effectuationStack: [Effectuation]? = nil
    ) {
        log(LoggingEvent(
            messageID: messageID,
            type: type,
            processID: processID,
            applicationName: applicationName,
            fact: fact,
            solution: solution,
            itemInfo: itemInfo,
            itemPositionInfo: itemPositionInfo,
            effectuationStack: effectuationStack
        ))
    }
}
