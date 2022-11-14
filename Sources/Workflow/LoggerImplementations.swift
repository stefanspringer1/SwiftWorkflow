import Foundation
import Utilities

#if !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    import FoundationNetworking // for URLRequest and URLSession
#endif

/// This is a logger that can be used to "merge" several other loggers,
/// i.e. all logging events are being distributed to all loggers.
public class MultiLogger: Logger {

    public var loggers: [Logger]
    
    public init(_ loggers: Logger?...) {
        self.loggers = loggers.compactMap{$0}
    }
    
    public init(withLoggers loggers: [Logger?]) {
        self.loggers = loggers.compactMap{$0}
    }
    
    public func log(_ event: LoggingEvent) {
        loggers.forEach { logger in
            logger.log(event)
        }
    }
    
    public func close() throws {
        try loggers.forEach { logger in
            try logger.close()
        }
    }
}

/// A logger just collecting all logging events.
public class CollectingLogger: ConcurrentLogger {
    
    private var loggingEvents: [LoggingEvent]! = [LoggingEvent]()
    
    public override init(loggingLevel: MessageType = .Debug) {
        super.init(loggingLevel: loggingLevel)
        loggingAction = { event in
            self.loggingEvents.append(event)
        }
    }
    
    /// Get all collected message events.
    public func getLoggingEvents() throws -> [LoggingEvent] {
        return loggingEvents
    }
}

/// A logger that just prints.
///
/// It print top standard output if the message type is Info or better.
///
/// It prints to standard error if the message type is Error or worse.
///
/// If `errorsToStandard` is `true`, then all message are printed to standard output.
///
/// If `minEventType` defines the best message type that is to be printed
/// (default value is `Info`).
public class PrintLogger: ConcurrentLogger {
    
    var stepIndentation: Bool
    let errorsToStandard: Bool
    
    public init(
        loggingLevel: MessageType = .Debug,
        stepIndentation: Bool = true,
        errorsToStandard: Bool = false
    ) {
        self.stepIndentation = stepIndentation
        self.errorsToStandard = errorsToStandard
        super.init(loggingLevel: loggingLevel)
        loggingAction = { event in
            let message = event.descriptionForLogging(usingStepIndentation: stepIndentation)
            switch event.type {
            case .Error, .Fatal, .Deadly:
                if errorsToStandard {
                    print(message)
                }
                else {
                    print(message, to: &StandardError.instance)
                }
            default:
                print(message)
            }
        }
    }
    
}

/// A logger writing into a file.
public class FileLogger: ConcurrentLogger {
    
    public let path: String
    var writableFile: WritableFile
    
    let stepIndentation: Bool
    var messages = Set<String>()
    
    public init(
        usingFile path: String,
        stepIndentation: Bool = false,
        loggingLevel: MessageType = MessageType.Info,
        append: Bool = false,
        blocking: Bool = true
    ) throws {
        self.path = path
        writableFile = try WritableFile(path: path, append: append, blocking: blocking)
        self.stepIndentation = stepIndentation
        super.init(loggingLevel: loggingLevel)
        loggingAction = { event in
            do {
                try self.writableFile.reopen()
                try self.writableFile.write(event.descriptionForLogging(usingStepIndentation: stepIndentation).lineForLogfile())
                if !self.writableFile.blocking {
                    try self.writableFile.close()
                }
            }
            catch {
                print("could not log to \(path)", to: &StandardError.instance)
            }
        }
        closeAction = {
            do {
                try self.writableFile.close()
            }
            catch {
                print("could not log to \(path)", to: &StandardError.instance)
            }
        }
    }
}

/// A logger writing immediately into a file.
public class FileCrashLogger: ConcurrentCrashLogger {
    
    public let path: String
    var writableFile: WritableFile
    
    let stepIndentation: Bool
    var messages = Set<String>()
    
    public init(
        usingFile path: String,
        stepIndentation: Bool,
        loggingLevel: MessageType = MessageType.Info,
        append: Bool = true
    ) throws {
        self.path = path
        writableFile = try WritableFile(path: path, append: append)
        self.stepIndentation = stepIndentation
        super.init(loggingLevel: loggingLevel)
        loggingAction = { event in
            do {
                try self.writableFile.write(event.descriptionForLogging(usingStepIndentation: stepIndentation).lineForLogfile())
                try self.writableFile.flush()
            }
            catch {
                print("could not log to \(path)", to: &StandardError.instance)
            }
        }
        closeAction = {
            do {
                try self.writableFile.close()
            }
            catch {
                print("could not log to \(path)", to: &StandardError.instance)
            }
        }
    }
}

/// A logger using a REST API to store the information.
public class RESTLogger: ConcurrentLogger {
    
    public override init(loggingLevel: MessageType = MessageType.Info) {
        super.init(loggingLevel: loggingLevel)
        loggingAction = { event in
            let sem = DispatchSemaphore.init(value: 0)
            let encoder = JSONEncoder()
            let jsonData = try! encoder.encode(event)

            //https://stackoverflow.com/a/38952964/2640045
            //https://stackoverflow.com/a/60440711/2640045
            let url = URL(string: "http://127.0.0.1:8080/logEvent")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("\(String(describing: jsonData.count))", forHTTPHeaderField: "Content-Length")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // insert json data to the request
            request.httpBody = jsonData

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                defer { sem.signal() }
                guard let data = data, error == nil else {
                    print(error?.localizedDescription ?? "No data")
                    return
                }
                let responseJSON = try? JSONSerialization.jsonObject(with: data, options: [])
                if let responseJSON = responseJSON as? [String: Any] {
                    print(responseJSON) //Code after successful POST request
                }
            }

            task.resume()
            sem.wait()
        }
    }
}

/// A logger that adds a prefix to all message texts
/// before forwarding it to the contained logger.
/// The referenced loggers are being closed when the
/// PrefixedLogger is being closed.
public class PrefixedLogger: Logger {
    
    let prefix: String
    let logger: Logger
    
    public init(prefix: String, logger: Logger) {
        self.prefix = prefix
        self.logger = logger
    }
    
    public func log(_ event: LoggingEvent) {
        logger.log(event.prefixed(with: prefix))
    }
    
    public func close() throws {
        try logger.close()
    }
}
