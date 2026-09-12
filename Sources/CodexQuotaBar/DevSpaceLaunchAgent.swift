import CodexQuotaBarCore
import Darwin
import Foundation

struct DevSpaceAgentStatus: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case disabled
        case loaded
        case running(pid: Int32?)
    }

    let state: State
    let agentFileExists: Bool

    var isLoaded: Bool {
        switch state {
        case .disabled: false
        case .loaded, .running: true
        }
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }
}

enum DevSpaceAgentError: LocalizedError, Sendable {
    case commandFailed(String)
    case failedToWriteAgent(String)
    case portOccupied(Int)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message):
            message
        case let .failedToWriteAgent(message):
            "无法保存 DevSpace LaunchAgent：\(message)"
        case let .portOccupied(port):
            "端口 \(port) 已被其他进程占用；为避免误杀现有服务，不会自动接管"
        }
    }
}

enum DevSpaceLaunchAgent {
    static let label = "red.ryde.codexquotabar.devspace"

    static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent(label + ".plist")
    }

    static var logDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/CodexQuotaBar", isDirectory: true)
    }

    static func status() async -> DevSpaceAgentStatus {
        await Task.detached(priority: .utility) {
            statusSynchronously()
        }.value
    }

    static func installAndStart(runtime: DevSpaceRuntime) async throws -> DevSpaceAgentStatus {
        try await Task.detached(priority: .utility) {
            try installAndStartSynchronously(runtime: runtime)
        }.value
    }

    static func stopAndRemove() async throws -> DevSpaceAgentStatus {
        try await Task.detached(priority: .utility) {
            try stopAndRemoveSynchronously()
        }.value
    }

    static func bootstrapExistingAgentIfNeeded() async throws -> DevSpaceAgentStatus {
        try await Task.detached(priority: .utility) {
            let current = statusSynchronously()
            guard !current.isLoaded, current.agentFileExists else { return current }

            if portIsOpenSynchronously(7676) {
                throw DevSpaceAgentError.portOccupied(7676)
            }

            let result = runLaunchctl([
                "bootstrap",
                domain,
                agentURL.path
            ])
            guard result.status == 0 else {
                throw DevSpaceAgentError.commandFailed(
                    cleanedError(result) ?? "无法启动已保存的 DevSpace LaunchAgent"
                )
            }
            return statusSynchronously()
        }.value
    }

    static func runtimePathsExist() async -> Bool {
        await Task.detached(priority: .utility) {
            runtimePathsExistSynchronously()
        }.value
    }

    static func isDefaultPortOpen() async -> Bool {
        await Task.detached(priority: .utility) {
            portIsOpenSynchronously(7676)
        }.value
    }

    private static func installAndStartSynchronously(runtime: DevSpaceRuntime) throws -> DevSpaceAgentStatus {
        let fileManager = FileManager.default
        let existing = statusSynchronously()

        if !existing.isLoaded, portIsOpenSynchronously(7676) {
            throw DevSpaceAgentError.portOccupied(7676)
        }

        do {
            try fileManager.createDirectory(
                at: agentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: logDirectoryURL,
                withIntermediateDirectories: true
            )
            try rotateLogIfNeeded(at: logDirectoryURL.appendingPathComponent("devspace.log"))
            try rotateLogIfNeeded(at: logDirectoryURL.appendingPathComponent("devspace-error.log"))
        } catch {
            throw DevSpaceAgentError.failedToWriteAgent(error.localizedDescription)
        }

        let arguments = [runtime.executableURL.path]
            + runtime.argumentPrefix
            + ["serve"]

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": arguments,
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ThrottleInterval": 2,
            "ProcessType": "Background",
            "AbandonProcessGroup": false,
            "WorkingDirectory": FileManager.default.homeDirectoryForCurrentUser.path,
            "StandardOutPath": logDirectoryURL.appendingPathComponent("devspace.log").path,
            "StandardErrorPath": logDirectoryURL.appendingPathComponent("devspace-error.log").path,
            "EnvironmentVariables": [
                "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                "PATH": runtime.pathEnvironment
            ]
        ]

        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: agentURL, options: [.atomic])
        } catch {
            throw DevSpaceAgentError.failedToWriteAgent(error.localizedDescription)
        }

        if existing.isLoaded {
            let bootout = runLaunchctl(["bootout", domain + "/" + label])
            if bootout.status != 0, statusSynchronously().isLoaded {
                throw DevSpaceAgentError.commandFailed(
                    cleanedError(bootout) ?? "无法重新载入 DevSpace LaunchAgent"
                )
            }
        }

        if portIsOpenSynchronously(7676) {
            try? fileManager.removeItem(at: agentURL)
            throw DevSpaceAgentError.portOccupied(7676)
        }

        let bootstrap = runLaunchctl(["bootstrap", domain, agentURL.path])
        guard bootstrap.status == 0 else {
            try? fileManager.removeItem(at: agentURL)
            throw DevSpaceAgentError.commandFailed(
                cleanedError(bootstrap) ?? "无法启动 DevSpace LaunchAgent"
            )
        }

        // RunAtLoad starts the service as part of bootstrap. Do not
        // immediately follow it with kickstart -k: that would kill the process
        // that just started and pay DevSpace's startup cost a second time.
        return try waitUntilReadySynchronously(timeout: 12)
    }

    private static func stopAndRemoveSynchronously() throws -> DevSpaceAgentStatus {
        let current = statusSynchronously()
        if current.isLoaded {
            let result = runLaunchctl(["bootout", domain + "/" + label])
            if result.status != 0, statusSynchronously().isLoaded {
                throw DevSpaceAgentError.commandFailed(
                    cleanedError(result) ?? "无法停止 DevSpace"
                )
            }
        }

        if FileManager.default.fileExists(atPath: agentURL.path) {
            do {
                try FileManager.default.removeItem(at: agentURL)
            } catch {
                throw DevSpaceAgentError.failedToWriteAgent(error.localizedDescription)
            }
        }

        return try waitUntilStoppedSynchronously(timeout: 5)
    }

    private static func waitUntilReadySynchronously(
        timeout: TimeInterval
    ) throws -> DevSpaceAgentStatus {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let status = statusSynchronously()

            if status.isRunning, portIsOpenSynchronously(7676) {
                return status
            }

            if !status.isLoaded {
                throw DevSpaceAgentError.commandFailed(
                    "DevSpace 在启动完成前退出，请检查 ~/Library/Logs/CodexQuotaBar/devspace-error.log"
                )
            }

            usleep(100_000)
        }

        throw DevSpaceAgentError.commandFailed(
            "DevSpace 启动超时（等待 127.0.0.1:7676）"
        )
    }

    private static func waitUntilStoppedSynchronously(
        timeout: TimeInterval
    ) throws -> DevSpaceAgentStatus {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let status = statusSynchronously()
            let portOpen = portIsOpenSynchronously(7676)

            if !status.isLoaded, !portOpen {
                return DevSpaceAgentStatus(
                    state: .disabled,
                    agentFileExists: false
                )
            }

            usleep(100_000)
        }

        throw DevSpaceAgentError.commandFailed(
            "DevSpace 关闭超时"
        )
    }

    private static func runtimePathsExistSynchronously() -> Bool {
        guard let data = try? Data(contentsOf: agentURL),
              let object = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ),
              let plist = object as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String],
              let executable = arguments.first,
              FileManager.default.isExecutableFile(atPath: executable) else {
            return false
        }

        if arguments.count > 1, arguments[1].hasPrefix("/") {
            return FileManager.default.fileExists(atPath: arguments[1])
        }
        return true
    }

    private static func rotateLogIfNeeded(at url: URL) throws {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.int64Value > 5 * 1024 * 1024 else {
            return
        }

        let backup = url.appendingPathExtension("1")
        if fileManager.fileExists(atPath: backup.path) {
            try fileManager.removeItem(at: backup)
        }
        try fileManager.moveItem(at: url, to: backup)
    }

    private static func portIsOpenSynchronously(_ port: Int) -> Bool {
        let result = runCommand(
            executable: URL(fileURLWithPath: "/usr/bin/nc"),
            arguments: ["-z", "-w", "1", "127.0.0.1", String(port)],
            timeout: 2
        )
        return result.status == 0
    }

    private static func statusSynchronously() -> DevSpaceAgentStatus {
        let result = runLaunchctl(["print", domain + "/" + label])
        let exists = FileManager.default.fileExists(atPath: agentURL.path)

        guard result.status == 0 else {
            return DevSpaceAgentStatus(state: .disabled, agentFileExists: exists)
        }

        let text = result.output + "\n" + result.error
        let isRunning = text.range(
            of: #"state\s*=\s*running"#,
            options: .regularExpression
        ) != nil

        let pid: Int32? = {
            guard let range = text.range(
                of: #"pid\s*=\s*([0-9]+)"#,
                options: .regularExpression
            ) else {
                return nil
            }
            let match = String(text[range])
            guard let value = match.split(separator: "=").last?
                .trimmingCharacters(in: .whitespacesAndNewlines) else {
                return nil
            }
            return Int32(value)
        }()

        return DevSpaceAgentStatus(
            state: isRunning ? .running(pid: pid) : .loaded,
            agentFileExists: exists
        )
    }

    private static var domain: String {
        "gui/\(getuid())"
    }

    private static func runLaunchctl(_ arguments: [String]) -> CommandResult {
        runCommand(
            executable: URL(fileURLWithPath: "/bin/launchctl"),
            arguments: arguments,
            timeout: 8
        )
    }

    private static func runCommand(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) -> CommandResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let exited = DispatchSemaphore(value: 0)

        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, output: "", error: error.localizedDescription)
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = exited.wait(timeout: .now() + 0.5)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            return CommandResult(status: -1, output: "", error: "launchctl 操作超时")
        }

        let output = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let error = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        return CommandResult(
            status: process.terminationStatus,
            output: output,
            error: error
        )
    }

    private static func cleanedError(_ result: CommandResult) -> String? {
        let message = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? nil : message
    }

    private struct CommandResult {
        let status: Int32
        let output: String
        let error: String
    }
}
