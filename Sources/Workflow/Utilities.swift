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
    
    @available(macOS 10.15, *)
    func removeAsTemp(applicationName: String, logger: Logger) async {
        do {
            if self.isDirectory {
                var empty = true
                try await FileManager.default.contentsOfDirectory(atPath: self.path).forEachAsync { file in
                    logger.log(
                        applicationName: applicationName,
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
                    logger.log(
                        applicationName: applicationName,
                        .Warning,
                        [
                            .en: "temporary directory [\(self.osPath)] is not empty after processing"
                        ]
                    )
                }
            }
        }
        catch {
            logger.log(
                applicationName: applicationName,
                .Warning,
                [
                    .en: "error when deleting temporary directory [\(self.osPath)]: \(error.localizedDescription)"
                ]
            )
        }
    }
    
}
