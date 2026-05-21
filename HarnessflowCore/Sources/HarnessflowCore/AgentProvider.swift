import Foundation

public enum AgentRunOrigin: Equatable, Sendable {
    case manual
    case continuation
    case autoAdvance(from: TicketPhase)

    public var displayTitle: String {
        switch self {
        case .manual:
            "Manual"
        case .continuation:
            "Continuation"
        case let .autoAdvance(phase):
            "Auto-run from \(phase.title)"
        }
    }
}

public struct AgentRunRequest: Equatable, Sendable {
    public var ticketID: UUID
    public var phase: TicketPhase
    public var prompt: String
    public var promptAddendum: String
    public var model: String
    public var workingDirectory: String
    public var origin: AgentRunOrigin

    public init(
        ticketID: UUID,
        phase: TicketPhase,
        prompt: String,
        promptAddendum: String = "",
        model: String,
        workingDirectory: String,
        origin: AgentRunOrigin = .manual
    ) {
        self.ticketID = ticketID
        self.phase = phase
        self.prompt = prompt
        self.promptAddendum = promptAddendum
        self.model = model
        self.workingDirectory = workingDirectory
        self.origin = origin
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
        overrides: [String: String],
        removals: Set<String> = []
    ) -> [String: String] {
        var environment = baseEnvironment
        removals.forEach { environment.removeValue(forKey: $0) }
        environment.merge(overrides) { _, override in override }
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

struct ClaudeStreamOutputParser {
    private struct ToolUse {
        var id: String
        var name: String
        var input: Any?
    }

    private var bufferedText = ""
    private var finalResult: String?
    private var accumulatedAssistantText = ""
    private var assistantTextByMessageID: [String: String] = [:]
    private var emittedToolUseIDs = Set<String>()

    var output: String {
        (finalResult ?? accumulatedAssistantText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func append(_ text: String) -> [String] {
        guard text.isEmpty == false else {
            return []
        }

        bufferedText.append(text)
        var chunks: [String] = []

        while let newlineIndex = bufferedText.firstIndex(of: "\n") {
            let line = String(bufferedText[..<newlineIndex])
            bufferedText.removeSubrange(bufferedText.startIndex...newlineIndex)
            chunks.append(contentsOf: processLine(line))
        }

        return chunks
    }

    mutating func finish() -> [String] {
        let line = bufferedText
        bufferedText = ""
        return processLine(line)
    }

    private mutating func processLine(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return []
        }

        guard
            let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            accumulatedAssistantText.append(line)
            accumulatedAssistantText.append("\n")
            return [line + "\n"]
        }

        return processEvent(object)
    }

    private mutating func processEvent(_ event: [String: Any]) -> [String] {
        let type = string(event["type"])?.lowercased()

        switch type {
        case "system":
            return processSystemEvent(event)
        case "assistant":
            return processAssistantEvent(event)
        case "result":
            return processResultEvent(event)
        default:
            if isRetryEvent(event) {
                return [statusLine("API retry: \(eventMessage(event))")]
            }
            return []
        }
    }

    private func processSystemEvent(_ event: [String: Any]) -> [String] {
        let subtype = string(event["subtype"])?.lowercased()

        if subtype == "init" {
            var details: [String] = []
            if let model = string(event["model"]), model.isEmpty == false {
                details.append(model)
            }
            if let sessionID = string(event["session_id"]), sessionID.isEmpty == false {
                details.append("session \(shortSessionID(sessionID))")
            }

            let suffix = details.isEmpty ? "" : " (\(details.joined(separator: ", ")))"
            return [statusLine("Session started\(suffix)")]
        }

        if isRetryEvent(event) {
            return [statusLine("API retry: \(eventMessage(event))")]
        }

        return []
    }

    private mutating func processAssistantEvent(_ event: [String: Any]) -> [String] {
        let message = dictionary(event["message"]) ?? event
        let messageID = string(message["id"]) ?? string(event["message_id"]) ?? "_assistant_stream"
        let parsedContent = parseContent(message["content"] ?? event["content"])
        var chunks = parsedContent.tools.compactMap { toolStatusLine(for: $0) }

        if let deltaText = textDelta(in: event), deltaText.isEmpty == false {
            accumulatedAssistantText.append(deltaText)
            chunks.append(deltaText)
            return chunks
        }

        let text = parsedContent.text
        guard text.isEmpty == false else {
            return chunks
        }

        let previousText = assistantTextByMessageID[messageID] ?? ""
        let delta: String
        if text.hasPrefix(previousText) {
            delta = String(text.dropFirst(previousText.count))
        } else if text != previousText {
            delta = text
        } else {
            delta = ""
        }

        assistantTextByMessageID[messageID] = text

        if delta.isEmpty == false {
            accumulatedAssistantText.append(delta)
            chunks.append(delta)
        }

        return chunks
    }

    private mutating func processResultEvent(_ event: [String: Any]) -> [String] {
        if let result = string(event["result"])?.trimmingCharacters(in: .whitespacesAndNewlines), result.isEmpty == false {
            finalResult = result
        }

        if bool(event["is_error"]) == true {
            return [statusLine("Run ended with error: \(eventMessage(event))")]
        }

        return []
    }

    private func parseContent(_ content: Any?) -> (text: String, tools: [ToolUse]) {
        guard let content else {
            return ("", [])
        }

        if let text = content as? String {
            return (text, [])
        }

        if let block = content as? [String: Any] {
            return parseContentBlock(block)
        }

        guard let blocks = content as? [Any] else {
            return ("", [])
        }

        var text = ""
        var tools: [ToolUse] = []
        for block in blocks {
            guard let block = block as? [String: Any] else {
                continue
            }
            let parsed = parseContentBlock(block)
            text.append(parsed.text)
            tools.append(contentsOf: parsed.tools)
        }

        return (text, tools)
    }

    private func parseContentBlock(_ block: [String: Any]) -> (text: String, tools: [ToolUse]) {
        let type = string(block["type"])?.lowercased()

        if type == "text", let text = string(block["text"]) {
            return (text, [])
        }

        if type == "tool_use" {
            let id = string(block["id"]) ?? "\(string(block["name"]) ?? "tool")-\(emittedToolUseIDs.count)"
            let name = string(block["name"]) ?? "Tool"
            return ("", [ToolUse(id: id, name: name, input: block["input"])])
        }

        return ("", [])
    }

    private func textDelta(in event: [String: Any]) -> String? {
        if let delta = dictionary(event["delta"]), let text = string(delta["text"]) {
            return text
        }

        return string(event["text"])
    }

    private mutating func toolStatusLine(for toolUse: ToolUse) -> String? {
        guard emittedToolUseIDs.insert(toolUse.id).inserted else {
            return nil
        }

        let detail = toolDetail(name: toolUse.name, input: toolUse.input)
        return statusLine("Using \(toolUse.name)\(detail)")
    }

    private func toolDetail(name: String, input: Any?) -> String {
        guard let input else {
            return ""
        }

        if let input = input as? [String: Any] {
            let lowercasedName = name.lowercased()
            if lowercasedName == "bash", let command = string(input["command"]) {
                return ": \(clipped(command, limit: 180))"
            }
            if let path = string(input["file_path"]) ?? string(input["path"]) {
                return ": \(clipped(path, limit: 180))"
            }
            if lowercasedName == "grep", let pattern = string(input["pattern"]) {
                return ": \(clipped(pattern, limit: 180))"
            }
        }

        guard let json = compactJSONString(input) else {
            return ""
        }
        return ": \(clipped(json, limit: 180))"
    }

    private func statusLine(_ text: String) -> String {
        let prefix = accumulatedAssistantText.isEmpty || accumulatedAssistantText.hasSuffix("\n") ? "" : "\n"
        return "\(prefix)[Claude] \(text)\n"
    }

    private func isRetryEvent(_ event: [String: Any]) -> Bool {
        let kind = [
            string(event["type"]),
            string(event["subtype"]),
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let message = eventMessage(event).lowercased()

        return kind.contains("retry")
            || message.contains("retry")
            || message.contains("rate limit")
            || message.contains("overloaded")
    }

    private func eventMessage(_ event: [String: Any]) -> String {
        for key in ["message", "error", "reason", "details", "detail"] {
            if let message = string(event[key]), message.isEmpty == false {
                return clipped(message, limit: 240)
            }
            if let nested = dictionary(event[key]) {
                let nestedMessage = eventMessage(nested)
                if nestedMessage.isEmpty == false {
                    return nestedMessage
                }
            }
        }

        let strings = stringValues(in: event)
            .filter { value in
                let lowered = value.lowercased()
                return lowered != "system"
                    && lowered != "assistant"
                    && lowered != "result"
                    && lowered != "init"
            }

        return clipped(strings.first ?? "Claude reported a retryable API event.", limit: 240)
    }

    private func stringValues(in value: Any) -> [String] {
        if let string = value as? String {
            return [string]
        }

        if let dictionary = value as? [String: Any] {
            return dictionary.values.flatMap(stringValues)
        }

        if let array = value as? [Any] {
            return array.flatMap(stringValues)
        }

        return []
    }

    private func shortSessionID(_ sessionID: String) -> String {
        guard sessionID.count > 8 else {
            return sessionID
        }
        return String(sessionID.prefix(8))
    }

    private func clipped(_ text: String, limit: Int) -> String {
        guard text.count > limit else {
            return text
        }
        return String(text.prefix(limit)) + "..."
    }

    private func compactJSONString(_ value: Any) -> String? {
        if let string = value as? String {
            return string
        }

        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return text
    }

    private func string(_ value: Any?) -> String? {
        value as? String
    }

    private func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        if let value = value as? String {
            return Bool(value)
        }
        return nil
    }
}

private final class ClaudeStreamOutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var parser = ClaudeStreamOutputParser()

    func append(data: Data) -> [String] {
        guard data.isEmpty == false else {
            return []
        }

        let text = String(decoding: data, as: UTF8.self)
        guard text.isEmpty == false else {
            return []
        }

        lock.lock()
        defer { lock.unlock() }
        return parser.append(text)
    }

    func finish() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return parser.finish()
    }

    func output() -> String {
        lock.lock()
        defer { lock.unlock() }
        return parser.output
    }
}

public struct ClaudeCLIProvider: AgentProvider {
    public var executablePath: String
    public var extraArguments: [String]
    public var authMode: ClaudeAuthMode
    public var permissionMode: ClaudePermissionMode
    public var environmentOverrides: [String: String]

    public init(
        executablePath: String = "/opt/homebrew/bin/claude",
        extraArguments: [String] = [],
        authMode: ClaudeAuthMode = .subscription,
        permissionMode: ClaudePermissionMode = .bypassPermissions,
        environmentOverrides: [String: String] = [:]
    ) {
        self.executablePath = executablePath
        self.extraArguments = extraArguments
        self.authMode = authMode
        self.permissionMode = permissionMode
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
            let stdoutCapture = ClaudeStreamOutputCapture()
            let stderrCapture = ProcessOutputCapture()
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
                Self.emitClaudeOutput(
                    stdoutCapture.append(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile()),
                    onOutput: onOutput
                )
                Self.emitClaudeOutput(stdoutCapture.finish(), onOutput: onOutput)
                stderrCapture.append(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), channel: .standardError)

                continuation.resume(
                    returning: AgentRunResult(
                        output: stdoutCapture.output(),
                        errorOutput: stderrCapture.output(for: .standardError),
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
                    capture: stdoutCapture,
                    onOutput: onOutput
                )
                stderrPipe.fileHandleForReading.readabilityHandler = makeReadabilityHandler(
                    for: stderrPipe.fileHandleForReading,
                    channel: .standardError,
                    capture: stderrCapture,
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
                "--permission-mode", permissionMode.rawValue,
                "--output-format", "stream-json",
                "--verbose",
                "--include-partial-messages",
            ] + extraArguments,
            environment: AgentProviderEnvironment.normalized(
                baseEnvironment: baseEnvironment,
                overrides: environmentOverrides,
                removals: authMode.environmentRemovals
            ),
            currentDirectory: request.workingDirectory
        )
    }

    private func makeReadabilityHandler(
        for handle: FileHandle,
        capture: ClaudeStreamOutputCapture,
        onOutput: (@Sendable (AgentOutputChunk) -> Void)?
    ) -> @Sendable (FileHandle) -> Void {
        { readableHandle in
            let data = readableHandle.availableData
            guard data.isEmpty == false else {
                readableHandle.readabilityHandler = nil
                return
            }

            Self.emitClaudeOutput(capture.append(data: data), onOutput: onOutput)
        }
    }

    private static func emitClaudeOutput(
        _ chunks: [String],
        onOutput: (@Sendable (AgentOutputChunk) -> Void)?
    ) {
        for chunk in chunks where chunk.isEmpty == false {
            onOutput?(AgentOutputChunk(channel: .standardOutput, text: chunk))
        }
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
