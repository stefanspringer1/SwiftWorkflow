//
//  File.swift
//  
//
//  Created by Stefan Springer on 02.08.22.
//

import Foundation
import Utilities

extension Sequence {
    
    func forEachAsync (
        _ operation: (Element) async -> Void
    ) async {
        for element in self {
            await operation(element)
        }
    }
    
    func forEachAsyncThrowing (
        _ operation: (Element) async throws -> Void
    ) async rethrows {
        for element in self {
            try await operation(element)
        }
    }
    
}

public extension URL {
    
    func removeAsTemp(applicationPrefix: String, logger: Logger) async {
        do {
            if self.isDirectory {
                var empty = true
                try await FileManager.default.contentsOfDirectory(atPath: self.path).forEachAsync { file in
                    await logger.log(
                        applicationPrefix: applicationPrefix,
                        .Warning,
                        [
                            .en: "file in temporary directory after processing: [\(file)]"
                        ]
                    )
                    empty = false
                }
                if empty {
                    try self.removeDirectorySafely()
                } else {
                    await logger.log(
                        applicationPrefix: applicationPrefix,
                        .Warning,
                        [
                            .en: "temporary directory [\(self.osPath)] is not empty after processing"
                        ]
                    )
                }
            }
        }
        catch {
            await logger.log(
                applicationPrefix: applicationPrefix,
                .Warning,
                [
                    .en: "error when deleting temporary directory [\(self.osPath)]: \(error.localizedDescription)"
                ]
            )
        }
    }
    
}
