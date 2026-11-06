import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Prefer a file representation so a very large/iCloud photo is not materialized as Data on main.
struct BackgroundPhoto: Transferable, Sendable {
    let file: URL
    private static var staging: URL { FileManager.default.temporaryDirectory.appendingPathComponent("LinYuBackgroundImports", isDirectory: true) }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let source = received.file
            let copy = Task.detached(priority: .utility) {
                try Task.checkCancellation()
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                let destination = staging.appendingPathComponent(UUID().uuidString + ".import")
                do {
                    try FileManager.default.copyItem(at: source, to: destination)
                    try Task.checkCancellation()
                    return BackgroundPhoto(file: destination)
                } catch {
                    removeStaged(destination)
                    throw error
                }
            }
            return try await withTaskCancellationHandler {
                let photo = try await copy.value
                guard !Task.isCancelled else { removeStaged(photo.file); throw CancellationError() }
                return photo
            } onCancel: { copy.cancel() }
        }
    }

    static func removeStaged(_ file: URL) {
        guard file.standardizedFileURL.deletingLastPathComponent() == staging.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: file)
    }
}
