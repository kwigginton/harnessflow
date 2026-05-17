import Foundation

public struct AgentRunRequest: Equatable, Sendable {
    public var ticketID: UUID
    public var phase: TicketPhase
    public var prompt: String
    public var promptAddendum: String
    public var model: String
    public var workingDirectory: String

    public init(
        ticketID: UUID,
        phase: TicketPhase,
        prompt: String,
        promptAddendum: String = "",
        model: String,
        workingDirectory: String
    ) {
        self.ticketID = ticketID
        self.phase = phase
        self.prompt = prompt
        self.promptAddendum = promptAddendum
        self.model = model
        self.workingDirectory = workingDirectory
    }
}

public struct AgentRunResult: Equatable, Sendable {
    public var output: String
    public var errorOutput: String
    public var startedAt: Date
    public var completedAt: Date
    public var exitCode: Int32

    public var success: Bool {
        exitCode == 0
    }

    public init(
        output: String,
        errorOutput: String,
        startedAt: Date,
        completedAt: Date,
        exitCode: Int32
    ) {
        self.output = output
        self.errorOutput = errorOutput
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.exitCode = exitCode
    }
}

public enum AgentOutputChannel: String, Equatable, Sendable {
    case standardOutput
    case standardError
}

public struct AgentOutputChunk: Equatable, Sendable {
    public var channel: AgentOutputChannel
    public var text: String

    public init(channel: AgentOutputChannel, text: String) {
        self.channel = channel
        self.text = text
    }
}

public enum AgentProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claude

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .codex:
            "Codex"
        case .claude:
            "Claude"
        }
    }
}

struct CodexCLIInvocation: Equatable, Sendable {
    var arguments: [String]
    var environment: [String: String]
}

struct ClaudeCLIInvocation: Equatable, Sendable {
    var arguments: [String]
    var environment: [String: String]
    var currentDirectory: String
}

enum AgentProviderEnvironment {
    private static let fallbackPathComponents = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    static func normalized(
        baseEnvironment: [String: String],
        overrides: [String: String]
    ) -> [String: String] {
        var environment = baseEnvironment.merging(overrides) { _, override in override }
        environment["PATH"] = normalizedPath(environment["PATH"])
        return environment
    }

    private static func normalizedPath(_ path: String?) -> String {
        var seen = Set<String>()
        let pathComponents = (path ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { $0.isEmpty == false }

        return (pathComponents + fallbackPathComponents)
            .filter { seen.insert($0).inserted }
            .joined(separator: ":")
    }
}

public protocol AgentProvider: Sendable {
    func run(
        request: AgentRunRequest,
        onStart: (@Sendable (Int32) -> Void)?,
        onOutput: (@Sendable (AgentOutputChunk) -> Void)?
    ) async throws -> AgentRunResult
}

public extension AgentProvider {
    func run(request: AgentRunRequest) async throws -> AgentRunResult {
        try await run(request: request, onStart: nil, onOutput: nil)
    }
}

public enum AgentProviderError: LocalizedError, Equatable, Sendable {
    case executableNotFound(String)
    case invalidWorkingDirectory(String)
    case launchFailure(String)

    public var errorDescription: String? {
        switch self {
        case let .executableNotFound(path):
            "Agent provider executable was not found or is not executable at \(path)."
        case let .invalidWorkingDirectory(path):
            "Working directory does not exist: \(path)."
        case let .launchFailure(message):
            "Failed to launch agent provider: \(message)"
        }
    }
}

public struct ClaudeCLIProvider: AgentProvider {
    public var executablePath: String
    public var extraArguments: [String]
    public var environmentOverrides: [String: String]

    public init(
        executablePath: String = "/opt/homebrew/bin/claude",
        extraArguments: [String] = [],
        environmentOverrides: [String: String] = [:]
    ) {
        self.executablePath = executablePath
        self.extraArguments = extraArguments
        self.environmentOverrides = environmentOverrides
    }

    public func run(
        request: AgentRunRequest,
        onStart: (@Sendable (Int32) -> Void)? = nil,
        onOutput: (@Sendable (AgentOutputChunk) -> Void)? = nil
    ) async throws -> AgentRunResult {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: executablePath) else {
            throw AgentProviderError.executableNotFound(executablePath)
        }

        let workingDirectory = request.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: workingDirectory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AgentProviderError.invalidWorkingDirectory(workingDirectory)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdinPipe = Pipe()
            let capture = ProcessOutputCapture()
            let startedAt = Date()
            let invocation = makeInvocation(for: request)

            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = invocation.arguments
            process.environment = invocation.environment
            process.currentDirectoryURL = URL(fileURLWithPath: invocation.currentDirectory)
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = stdinPipe

            process.terminationHandler = { process in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                capture.append(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), channel: .standardOutput)
                capture.append(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), channel: .standardError)

                continuation.resume(
                    returning: AgentRunResult(
                        output: capture.output(for: .standardOutput),
                        errorOutput: capture.output(for: .standardError),
                        startedAt: startedAt,
                        completedAt: Date(),
                        exitCode: process.terminationStatus
                    )
                )
            }

            do {
                try process.run()
                stdoutPipe.fileHandleForReading.readabilityHandler = makeReadabilityHandler(
                    for: stdoutPipe.fileHandleForReading,
                    channel: .standardOutput,
                    capture: capture,
                    onOutput: onOutput
                )
                stderrPipe.fileHandleForReading.readabilityHandler = makeReadabilityHandler(
                    for: stderrPipe.fileHandleForReading,
                    channel: .standardError,
                    capture: capture,
                    onOutput: onOutput
                )
                onStart?(process.processIdentifier)
                if let promptData = request.prompt.data(using: .utf8) {
                    stdinPipe.fileHandleForWriting.write(promptData)
                }
                stdinPipe.fileHandleForWriting.closeFile()
            } catch {
                continuation.resume(
                    throwing: AgentProviderError.launchFailure(error.localizedDescription)
                )
            }
        }
    }

    func makeInvocation(
        for request: AgentRunRequest,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ClaudeCLIInvocation {
        ClaudeCLIInvocation(
            arguments: [
                "-p",
                "--model", request.model,
                "--permission-mode", "bypassPermissions",
            ] + extraArguments,
            environment: AgentProviderEnvironment.normalized(
                baseEnvironment: baseEnvironment,
                overrides: environmentOverrides
            ),
            currentDirectory: request.workingDirectory
        )
    }

    private func makeReadabilityHandler(
        for handle: FileHandle,
        channel: AgentOutputChannel,
        capture: ProcessOutputCapture,
        onOutput: (@Sendable (AgentOutputChunk) -> Void)?
    ) -> @Sendable (FileHandle) -> Void {
        { readableHandle in
            let data = readableHandle.availableData
            guard data.isEmpty == false else {
                readableHandle.readabilityHandler = nil
                return
            }

            capture.append(data: data, channel: channel)

            let text = String(decoding: data, as: UTF8.self)
            guard text.isEmpty == false else {
                return
            }
            onOutput?(AgentOutputChunk(channel: channel, text: text))
        }
    }
}

public struct CodexCLIProvider: AgentProvider {
    public var executablePath: String
    public var extraArguments: [String]
    public var environmentOverrides: [String: String]

    public init(
        executablePath: String = "/opt/homebrew/bin/codex",
        extraArguments: [String] = [],
        environmentOverrides: [String: String] = [:]
    ) {
        self.executablePath = executablePath
        self.extraArguments = extraArguments
        self.environmentOverrides = environmentOverrides
    }

    public func run(
        request: AgentRunRequest,
        onStart: (@Sendable (Int32) -> Void)? = nil,
        onOutput: (@Sendable (AgentOutputChunk) -> Void)? = nil
    ) async throws -> AgentRunResult {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: executablePath) else {
            throw AgentProviderError.executableNotFound(executablePath)
        }

        let workingDirectory = request.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fileManager.fileExists(atPath: workingDirectory) else {
            throw AgentProviderError.invalidWorkingDirectory(workingDirectory)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdinPipe = Pipe()
            let capture = ProcessOutputCapture()
            let startedAt = Date()
            let invocation = makeInvocation(for: request)

            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = invocation.arguments
            process.environment = invocation.environment
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = stdinPipe

            process.terminationHandler = { process in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                capture.append(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), channel: .standardOutput)
                capture.append(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), channel: .standardError)

                continuation.resume(
                    returning: AgentRunResult(
                        output: capture.output(for: .standardOutput),
                        errorOutput: capture.output(for: .standardError),
                        startedAt: startedAt,
                        completedAt: Date(),
                        exitCode: process.terminationStatus
                    )
                )
            }

            do {
                try process.run()
                stdoutPipe.fileHandleForReading.readabilityHandler = makeReadabilityHandler(
                    for: stdoutPipe.fileHandleForReading,
                    channel: .standardOutput,
                    capture: capture,
                    onOutput: onOutput
                )
                stderrPipe.fileHandleForReading.readabilityHandler = makeReadabilityHandler(
                    for: stderrPipe.fileHandleForReading,
                    channel: .standardError,
                    capture: capture,
                    onOutput: onOutput
                )
                onStart?(process.processIdentifier)
                if let promptData = request.prompt.data(using: .utf8) {
                    stdinPipe.fileHandleForWriting.write(promptData)
                }
                stdinPipe.fileHandleForWriting.closeFile()
            } catch {
                continuation.resume(
                    throwing: AgentProviderError.launchFailure(error.localizedDescription)
                )
            }
        }
    }

    public func readLoginStatus() -> CodexLoginStatus {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: executablePath) else {
            return .unavailable(AgentProviderError.executableNotFound(executablePath).localizedDescription)
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let parser = CodexLoginStatusParser()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["login", "status"]
        process.environment = AgentProviderEnvironment.normalized(
            baseEnvironment: ProcessInfo.processInfo.environment,
            overrides: environmentOverrides
        )
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: outputData, as: UTF8.self)
            let errorOutput = String(decoding: errorData, as: UTF8.self)
            let combined = [output, errorOutput]
                .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
                .joined(separator: "\n")

            let parsed = parser.parse(combined)
            switch parsed {
            case .unknown where process.terminationStatus != 0:
                let message = combined.trimmingCharacters(in: .whitespacesAndNewlines)
                return .unavailable(
                    message.isEmpty
                        ? "Codex login status failed with exit code \(process.terminationStatus)."
                        : message
                )
            default:
                return parsed
            }
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func makeInvocation(
        for request: AgentRunRequest,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CodexCLIInvocation {
        CodexCLIInvocation(
            arguments: [
                "exec",
                "-m", request.model,
                "-C", request.workingDirectory,
                "--skip-git-repo-check",
                "--dangerously-bypass-approvals-and-sandbox",
                "-",
            ] + extraArguments,
            environment: AgentProviderEnvironment.normalized(
                baseEnvironment: baseEnvironment,
                overrides: environmentOverrides
            )
        )
    }

    private func makeReadabilityHandler(
        for handle: FileHandle,
        channel: AgentOutputChannel,
        capture: ProcessOutputCapture,
        onOutput: (@Sendable (AgentOutputChunk) -> Void)?
    ) -> @Sendable (FileHandle) -> Void {
        { readableHandle in
            let data = readableHandle.availableData
            guard data.isEmpty == false else {
                readableHandle.readabilityHandler = nil
                return
            }

            capture.append(data: data, channel: channel)

            let text = String(decoding: data, as: UTF8.self)
            guard text.isEmpty == false else {
                return
            }
            onOutput?(AgentOutputChunk(channel: channel, text: text))
        }
    }
}

private final class ProcessOutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var standardOutput = ""
    private var standardError = ""

    func append(data: Data, channel: AgentOutputChannel) {
        guard data.isEmpty == false else {
            return
        }

        let text = String(decoding: data, as: UTF8.self)
        guard text.isEmpty == false else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        switch channel {
        case .standardOutput:
            standardOutput.append(text)
        case .standardError:
            standardError.append(text)
        }
    }

    func output(for channel: AgentOutputChannel) -> String {
        lock.lock()
        defer { lock.unlock() }

        switch channel {
        case .standardOutput:
            return standardOutput
        case .standardError:
            return standardError
        }
    }
}
