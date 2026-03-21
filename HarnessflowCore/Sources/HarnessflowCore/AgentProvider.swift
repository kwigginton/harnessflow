import Foundation

public struct AgentRunRequest: Equatable, Sendable {
    public var ticketID: UUID
    public var phase: TicketPhase
    public var prompt: String
    public var model: String
    public var workingDirectory: String

    public init(
        ticketID: UUID,
        phase: TicketPhase,
        prompt: String,
        model: String,
        workingDirectory: String
    ) {
        self.ticketID = ticketID
        self.phase = phase
        self.prompt = prompt
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

    public init(
        executablePath: String = "/opt/homebrew/bin/codex",
        extraArguments: [String] = []
    ) {
        self.executablePath = executablePath
        self.extraArguments = extraArguments
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

            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = [
                "exec",
                "-m", request.model,
                "-C", workingDirectory,
                "--skip-git-repo-check",
                "--dangerously-bypass-approvals-and-sandbox",
                "-",
            ] + extraArguments
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
}

