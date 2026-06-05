import Foundation
import CADCore

#if os(macOS)
import Darwin
#endif

public struct SystemUSDConversionToolchain: USDConversionToolchain, USDImportToolchain {
    public init() {}

    public func writeUSDA(fromUSD url: URL, to sink: any ByteSink) throws {
        #if os(macOS)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftCAD-usd-import-\(UUID().uuidString)")
            .appendingPathExtension("usda")
        var primaryError: Error?
        do {
            try runUSDTool(
                named: "usdcat",
                arguments: ["--flatten", "--skipSourceFileComment", url.path, "-o", outputURL.path]
            )
            try runUSDTool(named: "usdchecker", arguments: [outputURL.path])
            try copyFile(at: outputURL, to: sink)
        } catch {
            primaryError = mapSystemUSDImportError(error)
        }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            do {
                try FileManager.default.removeItem(at: outputURL)
            } catch {
                if primaryError == nil {
                    primaryError = ImportError.fileReadFailure(
                        "Failed to remove temporary USD import output: \(error.localizedDescription)"
                    )
                }
            }
        }
        if let primaryError {
            throw primaryError
        }
        #else
        throw ImportError.unsupportedFormat("System USD")
        #endif
    }

    public func writeUSDC(fromUSDA url: URL, to sink: any ByteSink) throws {
        #if os(macOS)
        let outputURL = url.deletingPathExtension().appendingPathExtension("usdc")
        try runUSDTool(named: "usdcat", arguments: [url.path, "-o", outputURL.path])
        try runUSDTool(named: "usdchecker", arguments: [outputURL.path])
        try copyFile(at: outputURL, to: sink)
        try FileManager.default.removeItem(at: outputURL)
        #else
        throw ExportError.externalToolUnavailable("usdcat")
        #endif
    }

    public func writeUSDZ(fromUSDA url: URL, to sink: any ByteSink) throws {
        #if os(macOS)
        let outputURL = url.deletingLastPathComponent().appendingPathComponent("scene.usdz")
        try runUSDTool(named: "usdzip", arguments: [outputURL.path, url.path])
        try runUSDTool(named: "usdchecker", arguments: [outputURL.path])
        try copyFile(at: outputURL, to: sink)
        try FileManager.default.removeItem(at: outputURL)
        #else
        throw ExportError.externalToolUnavailable("usdzip")
        #endif
    }
}

#if os(macOS)
private let usdToolTimeoutSeconds: TimeInterval = 30.0
private let usdToolTerminationGraceSeconds: TimeInterval = 2.0

private func runUSDTool(named name: String, arguments: [String]) throws {
    guard let executableURL = executableURL(named: name) else {
        throw ExportError.externalToolUnavailable(name)
    }
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments

    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "SwiftCAD-\(name)-\(UUID().uuidString).log"
    )
    guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
        throw ExportError.fileWriteFailure("Failed to create USD tool output file.")
    }
    let outputHandle: FileHandle
    do {
        outputHandle = try FileHandle(forWritingTo: outputURL)
    } catch {
        throw ExportError.fileWriteFailure(error.localizedDescription)
    }
    defer {
        outputHandle.closeFile()
    }
    process.standardOutput = outputHandle
    process.standardError = outputHandle
    do {
        try process.run()
    } catch {
        let outputText = usdToolOutputText(from: outputURL)
        let cleanupMessage = removeUSDToolOutputLogMessage(at: outputURL)
        throw ExportError.externalToolFailure(
            tool: name,
            output: usdToolDiagnostic(
                primary: "Failed to launch \(name): \(error.localizedDescription)",
                outputText: outputText,
                cleanupMessage: cleanupMessage
            )
        )
    }
    let deadline = Date().addingTimeInterval(usdToolTimeoutSeconds)
    while process.isRunning {
        if Date() >= deadline {
            let terminationText = terminateUSDTool(process, name: name)
            let outputText = usdToolOutputText(from: outputURL)
            let cleanupMessage = removeUSDToolOutputLogMessage(at: outputURL)
            throw ExportError.externalToolFailure(
                tool: name,
                output: usdToolDiagnostic(
                    primary: terminationText,
                    outputText: outputText,
                    cleanupMessage: cleanupMessage
                )
            )
        }
        Thread.sleep(forTimeInterval: 0.02)
    }
    let outputText = usdToolOutputText(from: outputURL)
    guard process.terminationStatus == 0 else {
        let cleanupMessage = removeUSDToolOutputLogMessage(at: outputURL)
        throw ExportError.externalToolFailure(
            tool: name,
            output: usdToolDiagnostic(
                primary: "\(name) exited with status \(process.terminationStatus).",
                outputText: outputText,
                cleanupMessage: cleanupMessage
            )
        )
    }
    try removeUSDToolOutputLog(at: outputURL)
}

private func copyFile(at url: URL, to sink: any ByteSink) throws {
    let handle: FileHandle
    do {
        handle = try FileHandle(forReadingFrom: url)
    } catch {
        throw ExportError.fileWriteFailure("Failed to read USD tool output: \(error.localizedDescription)")
    }
    defer {
        handle.closeFile()
    }
    while true {
        let data = handle.readData(ofLength: 64 * 1024)
        guard !data.isEmpty else {
            break
        }
        try sink.write(data)
    }
}

private func usdToolOutputText(from url: URL) -> String {
    do {
        return try MappedFileByteSource(url: url).withNoCopyData { output in
            String(data: output, encoding: .utf8) ?? "USD tool output was not valid UTF-8."
        }
    } catch {
        return "Failed to read USD tool output log: \(error.localizedDescription)"
    }
}

private func terminateUSDTool(_ process: Process, name: String) -> String {
    process.terminate()
    let terminationDeadline = Date().addingTimeInterval(usdToolTerminationGraceSeconds)
    if waitForUSDToolExit(process, until: terminationDeadline) {
        return "Timed out after \(usdToolTimeoutSeconds) seconds; \(name) terminated after SIGTERM."
    }
    let killResult = Darwin.kill(process.processIdentifier, SIGKILL)
    let killDeadline = Date().addingTimeInterval(usdToolTerminationGraceSeconds)
    if waitForUSDToolExit(process, until: killDeadline) {
        if killResult == 0 {
            return "Timed out after \(usdToolTimeoutSeconds) seconds; \(name) required SIGKILL."
        }
        return "Timed out after \(usdToolTimeoutSeconds) seconds; \(name) exited after SIGTERM grace elapsed."
    }
    if killResult == 0 {
        return "Timed out after \(usdToolTimeoutSeconds) seconds; \(name) remained running after SIGKILL."
    }
    return "Timed out after \(usdToolTimeoutSeconds) seconds; failed to send SIGKILL to \(name)."
}

private func waitForUSDToolExit(_ process: Process, until deadline: Date) -> Bool {
    while process.isRunning {
        if Date() >= deadline {
            return false
        }
        Thread.sleep(forTimeInterval: 0.02)
    }
    return true
}

private func removeUSDToolOutputLog(at url: URL) throws {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        throw ExportError.fileWriteFailure(
            "Failed to remove USD tool output log: \(error.localizedDescription)"
        )
    }
}

private func removeUSDToolOutputLogMessage(at url: URL) -> String? {
    do {
        try FileManager.default.removeItem(at: url)
        return nil
    } catch {
        return "Failed to remove USD tool output log: \(error.localizedDescription)"
    }
}

private func usdToolDiagnostic(primary: String, outputText: String, cleanupMessage: String?) -> String {
    var lines = [primary, outputText].filter { !$0.isEmpty }
    if let cleanupMessage {
        lines.append(cleanupMessage)
    }
    return lines.joined(separator: "\n")
}

private func executableURL(named name: String) -> URL? {
    let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
    var searchPaths = environmentPath.split(separator: ":").map(String.init)
    searchPaths.append(contentsOf: ["/usr/bin", "/usr/local/bin", "/opt/homebrew/bin"])
    var visited: Set<String> = []
    for path in searchPaths where !visited.contains(path) {
        visited.insert(path)
        let candidate = URL(fileURLWithPath: path).appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
    }
    return nil
}

private func mapSystemUSDImportError(_ error: Error) -> ImportError {
    switch error {
    case let error as ImportError:
        return error
    case let ExportError.externalToolUnavailable(tool):
        return .unsupportedFormat("System USD tool \(tool)")
    case let ExportError.externalToolFailure(tool, output):
        return .invalidData("\(tool) failed while importing USD data: \(output)")
    case let ExportError.fileWriteFailure(message):
        return .fileReadFailure(message)
    case let ByteSinkError.fileOpenFailure(message):
        return .fileReadFailure(message)
    case let ByteSinkError.fileWriteFailure(message):
        return .fileReadFailure(message)
    case let ByteSinkError.fileCloseFailure(message):
        return .fileReadFailure(message)
    case let ByteSinkError.fileReplaceFailure(message):
        return .fileReadFailure(message)
    default:
        return .invalidData(error.localizedDescription)
    }
}
#endif
