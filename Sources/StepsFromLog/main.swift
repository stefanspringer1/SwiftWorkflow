import Foundation

var level = -1
var lastLevelPrint = 0

extension String {
    var pretty: String {
        self
            .replacing(/([a-z])([A-Z])(?=[a-z])/) { match in
                "\(match.output.1) \(match.output.2.lowercased())"
            }
            .replacing(/([A-Z0-9])([A-Z0-9])(?=[a-z])/) { match in
                "\(match.output.1) \(match.output.2.lowercased())"
            }
            .replacing(/([a-z])([A-Z])(?=[A-Z])/) { match in
                "\(match.output.1) \(match.output.2)"
            }
            .replacing(/^([a-z]+)(?=[0-9])/) { match in
                "\(match.output.1.uppercased())"
            }
    }
}

var stepStack = [String]()

var newline = false
for logEntry in try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
   .split(separator: "\n")
   .filter({ $0.contains("{Progress}") }) {
    if let range = logEntry.firstRange(of: ">> STEP ") {
        level += 1
        var logEntry = logEntry[range.lowerBound...].dropFirst(8)
        if let range = logEntry.firstRange(of: "(") { logEntry = logEntry[..<range.upperBound].dropLast() }
        stepStack.append(String(logEntry))
        if logEntry.hasSuffix("_step") { logEntry = logEntry.dropLast(5) }
        if level > lastLevelPrint { print(":", terminator: "") }
        if newline { print() } else { newline = true }
        print("\(String(repeating: " ", count: level * 4))\(String(logEntry).pretty)", terminator: "")
        lastLevelPrint = level
    } else if let range = logEntry.firstRange(of: "<< DONE STEP ") {
        var logEntry = logEntry[range.lowerBound...].dropFirst(13)
        if let range = logEntry.firstRange(of: "(") { logEntry = logEntry[..<range.upperBound].dropLast() }
        if stepStack.isEmpty {
            print(" ❌ mismatch: leaving step \"\(logEntry)\" without any open step", terminator: "")
        } else if let last = stepStack.popLast(), last != String(logEntry) {
            print(" ❌ mismatch: leaving step \"\(logEntry)\" does not does not correspond to the open step \"\(last)\"", terminator: "")
        }
        level -= 1
    }
}
print()
