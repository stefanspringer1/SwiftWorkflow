//
//  File.swift
//  
//
//  Created by Stefan Springer on 02.08.22.
//

import Foundation
import Utilities

extension Sequence {
    
    @available(macOS 10.15, *)
    func forEachAsync (
        _ operation: (Element) async -> Void
    ) async {
        for element in self {
            await operation(element)
        }
    }
    
    @available(macOS 10.15, *)
    func forEachAsync (
        _ operation: (Element) async throws -> Void
    ) async rethrows {
        for element in self {
            try await operation(element)
        }
    }
    
}

public extension URL {
    
    func removeAsTemp(applicationName: String, execution: Execution) {
        do {
            if self.isDirectory {
                var empty = true
                try FileManager.default.contentsOfDirectory(atPath: self.path).forEach { file in
                    execution.log(Message(
                        id: "file in temporary directory after processing", type: .Warning,
                        fact: [
                            .en: "file in temporary directory after processing: [\(file)]",
                        ]
                    ))
                    empty = false
                }
                if empty {
                    try self.removeDirectorySafely()
                } else {
                    execution.log(Message(
                        id: "temporary directory not empty after processing", type: .Warning,
                        fact: [
                            .en: "temporary directory [\(self.osPath)] is not empty after processing",
                        ]
                    ))
                }
            }
        }
        catch {
            execution.log(Message(
                id: "error when deleting temporary directory", type: .Warning,
                fact: [
                    .en: "error when deleting temporary directory [\(self.osPath)]: \(error.localizedDescription)",
                ]
            ))
        }
    }
    
}
