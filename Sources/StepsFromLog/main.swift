import Foundation
import Utilities

// ************************************************************
// first argument:
// path to log file
//
// optional second argument:
// path of directory with Swift file with a step "..._step"
// and the description after "- function:".
// ************************************************************

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

var stepToDescription = [Substring: Substring]()

if CommandLine.arguments.count > 2 {
    let directory = URL(fileURLWithPath: CommandLine.arguments[2])
//    print("Reading step descriptions from \(directory.osPath)...")
    for file in try directory.files(withPattern: #".*\.swift"#, findRecursively: true) {
        let content = try String(contentsOf: file, encoding: .utf8)
        if let stepFunction = content.firstMatch(of: /func ([^(]+)_step\(/), let description = content.firstMatch(of: /\- function: (.*)\n/) {
            let stepFunctionCore = stepFunction.output.1
            let description = description.output.1.replacing("This is a step.", with: "").trimming()
            if !description.isEmpty {
                stepToDescription[stepFunctionCore] = description
            }
        }
    }
//    print("Reading step descriptions done.")
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
        if let description = stepToDescription[logEntry] {
            print(" (\(description))", terminator: "")
        }
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
