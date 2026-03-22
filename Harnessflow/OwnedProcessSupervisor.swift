import Foundation
import Darwin
import HarnessflowCore

struct OwnedProcessStatus: Equatable {
    enum Kind: Equatable {
        case attached
        case runningDetached
        case exited
        case mismatchedExecutable
        case mismatchedLaunchTime
        case unavailable
    }

    let kind: Kind
    let summary: String

    var canTerminate: Bool {
        kind == .attached || kind == .runningDetached
    }
}

struct OwnedProcessSupervisor {
    func status(
        for reference: OwnedProcessReference,
        attachedPID: Int32?
    ) -> OwnedProcessStatus {
        guard isAlive(reference.processIdentifier) else {
            return OwnedProcessStatus(kind: .exited, summary: "No process is currently running for PID \(reference.processIdentifier).")
        }

        guard let command = commandLine(for: reference.processIdentifier) else {
            return OwnedProcessStatus(kind: .unavailable, summary: "The app could not inspect PID \(reference.processIdentifier).")
        }

        guard executableMatches(command: command, expectedPath: reference.executablePath) else {
            return OwnedProcessStatus(
                kind: .mismatchedExecutable,
                summary: "PID \(reference.processIdentifier) is alive, but it no longer matches the executable Harnessflow launched."
            )
        }

        guard launchTimeMatches(pid: reference.processIdentifier, expected: reference.launchedAt) else {
            return OwnedProcessStatus(
                kind: .mismatchedLaunchTime,
                summary: "PID \(reference.processIdentifier) was reused by a different process after the original run detached."
            )
        }

        if attachedPID == reference.processIdentifier {
            return OwnedProcessStatus(kind: .attached, summary: "Harnessflow is actively attached to PID \(reference.processIdentifier).")
        }

        return OwnedProcessStatus(kind: .runningDetached, summary: "PID \(reference.processIdentifier) is still running, but this app session is no longer attached to its output stream.")
    }

    func terminate(reference: OwnedProcessReference, force: Bool) -> OwnedProcessStatus {
        let status = status(for: reference, attachedPID: nil)
        guard status.canTerminate else {
            return status
        }

        let signal = force ? SIGKILL : SIGTERM
        let result = Darwin.kill(reference.processIdentifier, signal)
        if result == 0 {
            let verb = force ? "killed" : "sent SIGTERM to"
            return OwnedProcessStatus(kind: .runningDetached, summary: "Harnessflow \(verb) PID \(reference.processIdentifier).")
        }

        return OwnedProcessStatus(
            kind: .unavailable,
            summary: "Failed to terminate PID \(reference.processIdentifier): \(String(cString: strerror(errno)))."
        )
    }

    private func isAlive(_ pid: Int32) -> Bool {
        Darwin.kill(pid, 0) == 0 || errno == EPERM
    }

    private func executableMatches(command: String, expectedPath: String) -> Bool {
        let trimmedExpected = expectedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedExpected.isEmpty == false else {
            return false
        }

        let expectedURL = URL(fileURLWithPath: trimmedExpected)
        let commandPath = command.split(separator: " ").first.map(String.init) ?? command
        let commandURL = URL(fileURLWithPath: commandPath)
        return commandURL.path == expectedURL.path || commandURL.lastPathComponent == expectedURL.lastPathComponent
    }

    private func launchTimeMatches(pid: Int32, expected: Date) -> Bool {
        guard let actual = launchTime(for: pid) else {
            return false
        }

        return abs(actual.timeIntervalSince(expected)) < 2
    }

    private func commandLine(for pid: Int32) -> String? {
        runPS(pid: pid, field: "command=")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func launchTime(for pid: Int32) -> Date? {
        let output = runPS(pid: pid, field: "lstart=")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.isEmpty == false else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter.date(from: output)
    }

    private func runPS(pid: Int32, field: String) -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", "\(pid)", "-o", field]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return ""
        }
    }
}
