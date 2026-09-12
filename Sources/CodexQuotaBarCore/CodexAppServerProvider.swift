import Darwin
import Foundation

public struct CodexAppServerProvider: Sendable {
    public let executableURL: URL
    public let timeout: TimeInterval

    public init(executableURL: URL, timeout: TimeInterval = 15) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    public func fetch() async throws -> QuotaSnapshot {
        let executableURL = self.executableURL
        let timeout = self.timeout

        return try await Task.detached(priority: .utility) {
            try Self.fetchSynchronously(executableURL: executableURL, timeout: timeout)
        }.value
    }

    private static func fetchSynchronously(
        executableURL: URL,
        timeout: TimeInterval
    ) throws -> QuotaSnapshot {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        process.executableURL = executableURL
        process.arguments = [
            "app-server",
            "--stdio",
            "-c",
            "analytics.enabled=false"
        ]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw QuotaReadError.launchFailed(error.localizedDescription)
        }

        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
            // Bound cleanup too: a child that ignores SIGTERM must not block refreshes.
            if exited.wait(timeout: .now() + 0.5) == .timedOut, process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 0.5)
            }
            try? output.fileHandleForReading.close()
        }

        try send(request: initializeRequest(), through: input)
        try send(request: initializedNotification(), through: input)
        try send(request: rateLimitsRequest(), through: input)

        let fileDescriptor = output.fileHandleForReading.fileDescriptor
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()

        while Date() < deadline {
            var readSet = fd_set()
            set(fileDescriptor, in: &readSet)

            var waitTime = timeval(tv_sec: 0, tv_usec: 250_000)
            let ready = Darwin.select(
                fileDescriptor + 1,
                &readSet,
                nil,
                nil,
                &waitTime
            )

            if ready < 0 {
                if errno == EINTR {
                    continue
                }
                throw QuotaReadError.protocolError("select")
            }

            if ready == 0 {
                if !process.isRunning {
                    break
                }
                continue
            }

            var bytes = [UInt8](repeating: 0, count: 64 * 1024)
            let byteCount = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(fileDescriptor, buffer.baseAddress, buffer.count)
            }
            if byteCount == 0 {
                break
            }
            if byteCount < 0 {
                if errno == EAGAIN || errno == EINTR {
                    continue
                }
                throw QuotaReadError.protocolError("read")
            }
            buffer.append(contentsOf: bytes[0..<byteCount])

            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newlineIndex])
                buffer.removeSubrange(...newlineIndex)

                guard !line.isEmpty else { continue }
                guard responseID(in: line) == 2 else { continue }
                return try RateLimitParser.parseResponse(line)
            }
        }

        if !process.isRunning {
            throw QuotaReadError.processFailed(process.terminationStatus)
        }
        throw QuotaReadError.timedOut
    }

    private static func set(_ fileDescriptor: Int32, in readSet: inout fd_set) {
        Darwin.__darwin_fd_set(fileDescriptor, &readSet)
    }

    private static func send(request: [String: Any], through input: Pipe) throws {
        let data = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
        input.fileHandleForWriting.write(data)
        input.fileHandleForWriting.write(Data([0x0A]))
    }

    private static func initializeRequest() -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "codex-quota-bar",
                    "title": "Codex Quota Bar",
                    "version": "0.1.0"
                ],
                "capabilities": [
                    "experimentalApi": false
                ]
            ]
        ]
    }

    private static func initializedNotification() -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": NSNull()
        ]
    }

    private static func rateLimitsRequest() -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": 2,
            "method": "account/rateLimits/read",
            "params": NSNull()
        ]
    }

    private static func responseID(in data: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }

        if let value = dictionary["id"] as? Int {
            return value
        }
        if let value = dictionary["id"] as? NSNumber {
            return value.intValue
        }
        return nil
    }
}

public enum CodexExecutableLocator {
    public static func locate(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        var candidates: [String] = []

        if let configured = environment["CODEX_EXECUTABLE"], !configured.isEmpty {
            candidates.append(configured)
        }

        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/codex" })
        }

        candidates.append(contentsOf: [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ])

        for candidate in candidates {
            let url = URL(fileURLWithPath: candidate)
            if fileManager.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        return nil
    }
}
