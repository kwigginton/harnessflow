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

struct CodexCLIInvocation: Equatable, Sendable {
    var arguments: [String]
    var environment: [String: String]
}

public protocol AgentProvider: Sendable {
    func run(request: AgentRunRequest) async throws -> AgentRunResult
}

public enum AgentProviderError: LocalizedError, Equatable, Sendable {
    case executableNotFound(String)
    case invalidWorkingDirectory(String)
    case launchFailure(String)

    public var errorDescription: String? {
        switch self {
        case let .executableNotFound(path):
            "Codex executable was not found or is not executable at \(path)."
        case let .invalidWorkingDirectory(path):
            "Working directory does not exist: \(path)."
        case let .launchFailure(message):
            "Failed to launch agent provider: \(message)"
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

    public func run(request: AgentRunRequest) async throws -> AgentRunResult {
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
            let startedAt = Date()
            let invocation = makeInvocation(for: request)

            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = invocation.arguments
            process.environment = invocation.environment
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = stdinPipe

            process.terminationHandler = { process in
                let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: outputData, as: UTF8.self)
                let errorOutput = String(decoding: errorData, as: UTF8.self)

                continuation.resume(
                    returning: AgentRunResult(
                        output: output,
                        errorOutput: errorOutput,
                        startedAt: startedAt,
                        completedAt: Date(),
                        exitCode: process.terminationStatus
                    )
                )
            }

            do {
                try process.run()
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
            environment: baseEnvironment.merging(environmentOverrides) { _, override in override }
        )
    }
}
