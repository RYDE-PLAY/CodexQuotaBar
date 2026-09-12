import Darwin
import Foundation

public struct DevSpaceRuntime: Equatable, Sendable {
    public enum Source: String, Equatable, Sendable {
        case environment
        case nvm
        case shell
        case path
        case fnm
        case volta
        case asdf
        case mise
        case homebrew
        case system
    }

    public let nodeURL: URL
    public let devSpaceURL: URL
    public let executableURL: URL
    public let argumentPrefix: [String]
    public let nodeVersion: String
    public let devSpaceVersion: String
    public let source: Source
    public let pathEnvironment: String

    public init(
        nodeURL: URL,
        devSpaceURL: URL,
        executableURL: URL,
        argumentPrefix: [String],
        nodeVersion: String,
        devSpaceVersion: String,
        source: Source,
        pathEnvironment: String
    ) {
        self.nodeURL = nodeURL
        self.devSpaceURL = devSpaceURL
        self.executableURL = executableURL
        self.argumentPrefix = argumentPrefix
        self.nodeVersion = nodeVersion
        self.devSpaceVersion = devSpaceVersion
        self.source = source
        self.pathEnvironment = pathEnvironment
    }

    public func arguments(appending arguments: [String]) -> [String] {
        argumentPrefix + arguments
    }
}

public enum DevSpaceRuntimeError: LocalizedError, Equatable, Sendable {
    case notFound
    case unusable(String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            "未找到可用的 DevSpace。请先安装 DevSpace，并确认当前 Node 环境可以运行 devspace --version。"
        case let .unusable(message):
            "DevSpace 无法运行：\(message)"
        }
    }
}

public enum DevSpaceRuntimeResolver {
    private struct Candidate: Hashable, Sendable {
        let nodeURL: URL
        let devSpaceURL: URL
        let source: DevSpaceRuntime.Source
    }

    private struct CommandResult: Sendable {
        let status: Int32
        let standardOutput: String
        let standardError: String
    }

    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) async throws -> DevSpaceRuntime {
        try await Task.detached(priority: .utility) {
            try resolveSynchronously(environment: environment, homeDirectory: homeDirectory)
        }.value
    }

    private static func resolveSynchronously(
        environment: [String: String],
        homeDirectory: URL
    ) throws -> DevSpaceRuntime {
        let candidates = cheapCandidates(
            environment: environment,
            homeDirectory: homeDirectory
        )
        var lastFailure: String?

        for candidate in candidates {
            do {
                return try validate(
                    candidate: candidate,
                    environment: environment,
                    homeDirectory: homeDirectory
                )
            } catch {
                lastFailure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }

        // Shell startup can be surprisingly expensive with nvm/oh-my-zsh/etc.
        // Only pay that cost if all cheap absolute-path candidates failed.
        if let nvm = probeNVM(environment: environment, homeDirectory: homeDirectory) {
            let candidate = Candidate(
                nodeURL: URL(fileURLWithPath: nvm.node),
                devSpaceURL: URL(fileURLWithPath: nvm.devSpace),
                source: .nvm
            )
            do {
                return try validate(
                    candidate: candidate,
                    environment: environment,
                    homeDirectory: homeDirectory
                )
            } catch {
                lastFailure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }

        if let shell = probeLoginShell(environment: environment) {
            let candidate = Candidate(
                nodeURL: URL(fileURLWithPath: shell.node),
                devSpaceURL: URL(fileURLWithPath: shell.devSpace),
                source: .shell
            )
            do {
                return try validate(
                    candidate: candidate,
                    environment: environment,
                    homeDirectory: homeDirectory
                )
            } catch {
                lastFailure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }

        if candidates.isEmpty && lastFailure == nil {
            throw DevSpaceRuntimeError.notFound
        }
        throw DevSpaceRuntimeError.unusable(lastFailure ?? "没有候选运行环境通过验证")
    }

    private static func cheapCandidates(
        environment: [String: String],
        homeDirectory: URL
    ) -> [Candidate] {
        var result: [Candidate] = []
        var seen = Set<String>()

        func append(node: String?, devSpace: String?, source: DevSpaceRuntime.Source) {
            guard let node, let devSpace, node.hasPrefix("/"), devSpace.hasPrefix("/") else {
                return
            }
            let key = "\(node)|\(devSpace)"
            guard seen.insert(key).inserted else { return }
            result.append(
                Candidate(
                    nodeURL: URL(fileURLWithPath: node),
                    devSpaceURL: URL(fileURLWithPath: devSpace),
                    source: source
                )
            )
        }

        append(
            node: environment["DEVSPACE_NODE_EXECUTABLE"] ?? environment["NODE_EXECUTABLE"],
            devSpace: environment["DEVSPACE_EXECUTABLE"],
            source: .environment
        )

        if let path = environment["PATH"] {
            append(
                node: executable(named: "node", in: path),
                devSpace: executable(named: "devspace", in: path),
                source: .path
            )
        }

        let nvmRoots = nvmRoots(environment: environment, homeDirectory: homeDirectory)
        for root in nvmRoots {
            for bin in versionedBins(
                under: root.appendingPathComponent("versions/node"),
                suffix: "bin"
            ) {
                append(
                    node: bin.appendingPathComponent("node").path,
                    devSpace: bin.appendingPathComponent("devspace").path,
                    source: .nvm
                )
            }
        }

        let fnmRoots = [
            homeDirectory.appendingPathComponent(".local/share/fnm/node-versions"),
            homeDirectory.appendingPathComponent("Library/Application Support/fnm/node-versions")
        ]
        for root in fnmRoots {
            for version in children(of: root).sorted(by: versionURLDescending) {
                let bin = version.appendingPathComponent("installation/bin")
                append(
                    node: bin.appendingPathComponent("node").path,
                    devSpace: bin.appendingPathComponent("devspace").path,
                    source: .fnm
                )
            }
        }

        let knownBins: [(URL, DevSpaceRuntime.Source)] = [
            (homeDirectory.appendingPathComponent(".volta/bin"), .volta),
            (homeDirectory.appendingPathComponent(".asdf/shims"), .asdf),
            (homeDirectory.appendingPathComponent(".local/share/mise/shims"), .mise),
            (URL(fileURLWithPath: "/opt/homebrew/bin"), .homebrew),
            (URL(fileURLWithPath: "/usr/local/bin"), .homebrew),
            (URL(fileURLWithPath: "/usr/bin"), .system)
        ]

        for (bin, source) in knownBins {
            append(
                node: bin.appendingPathComponent("node").path,
                devSpace: bin.appendingPathComponent("devspace").path,
                source: source
            )
        }

        return result
    }

    private static func validate(
        candidate: Candidate,
        environment: [String: String],
        homeDirectory: URL
    ) throws -> DevSpaceRuntime {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: candidate.nodeURL.path) else {
            throw DevSpaceRuntimeError.unusable("Node 不可执行：\(candidate.nodeURL.path)")
        }
        guard fileManager.fileExists(atPath: candidate.devSpaceURL.path) else {
            throw DevSpaceRuntimeError.unusable("DevSpace 不存在：\(candidate.devSpaceURL.path)")
        }

        let resolvedDevSpace = candidate.devSpaceURL.resolvingSymlinksInPath()
        let pathEnvironment = makePathEnvironment(
            nodeURL: candidate.nodeURL,
            devSpaceURL: candidate.devSpaceURL,
            existingPath: environment["PATH"]
        )

        let commandEnvironment = runtimeEnvironment(
            base: environment,
            homeDirectory: homeDirectory,
            path: pathEnvironment
        )

        let nodeResult = try run(
            executableURL: candidate.nodeURL,
            arguments: ["--version"],
            environment: commandEnvironment,
            timeout: 3
        )
        guard nodeResult.status == 0 else {
            throw DevSpaceRuntimeError.unusable(
                nodeResult.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let nodeVersion = firstNonemptyLine(nodeResult.standardOutput)
            .replacingOccurrences(of: "v", with: "", options: [.anchored])
        guard isSupportedNodeVersion(nodeVersion) else {
            throw DevSpaceRuntimeError.unusable(
                "Node \(nodeVersion) 不满足 DevSpace 要求（>=22.19 <27）"
            )
        }

        let executableURL: URL
        let argumentPrefix: [String]
        if resolvedDevSpace.pathExtension.lowercased() == "js" {
            executableURL = candidate.nodeURL
            argumentPrefix = [resolvedDevSpace.path]
        } else {
            guard fileManager.isExecutableFile(atPath: candidate.devSpaceURL.path) else {
                throw DevSpaceRuntimeError.unusable(
                    "DevSpace 入口不可执行：\(candidate.devSpaceURL.path)"
                )
            }
            executableURL = candidate.devSpaceURL
            argumentPrefix = []
        }

        let devSpaceVersion: String
        if let packageVersion = packageVersion(for: resolvedDevSpace) {
            devSpaceVersion = packageVersion
        } else {
            let devSpaceResult = try run(
                executableURL: executableURL,
                arguments: argumentPrefix + ["--version"],
                environment: commandEnvironment,
                timeout: 5
            )
            guard devSpaceResult.status == 0 else {
                let message = [
                    devSpaceResult.standardError,
                    devSpaceResult.standardOutput
                ]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                throw DevSpaceRuntimeError.unusable(
                    message.isEmpty ? "devspace --version 失败" : message
                )
            }

            devSpaceVersion = firstNonemptyLine(devSpaceResult.standardOutput)
            guard !devSpaceVersion.isEmpty else {
                throw DevSpaceRuntimeError.unusable("devspace --version 没有返回版本号")
            }
        }

        return DevSpaceRuntime(
            nodeURL: candidate.nodeURL,
            devSpaceURL: candidate.devSpaceURL,
            executableURL: executableURL,
            argumentPrefix: argumentPrefix,
            nodeVersion: nodeVersion,
            devSpaceVersion: devSpaceVersion,
            source: candidate.source,
            pathEnvironment: pathEnvironment
        )
    }

    private static func probeNVM(
        environment: [String: String],
        homeDirectory: URL
    ) -> (node: String, devSpace: String)? {
        for root in nvmRoots(environment: environment, homeDirectory: homeDirectory) {
            let script = root.appendingPathComponent("nvm.sh")
            guard FileManager.default.fileExists(atPath: script.path) else { continue }

            var probeEnvironment = environment
            probeEnvironment["NVM_DIR"] = root.path
            probeEnvironment["HOME"] = homeDirectory.path

            let command = """
            . "$NVM_DIR/nvm.sh" >/dev/null 2>&1 || exit 0
            nvm use --silent default >/dev/null 2>&1 || true
            printf '__CQB_NODE__=%s\\n' "$(command -v node 2>/dev/null)"
            printf '__CQB_DEVSPACE__=%s\\n' "$(command -v devspace 2>/dev/null)"
            """

            guard let result = try? run(
                executableURL: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-c", command],
                environment: probeEnvironment,
                timeout: 4
            ) else {
                continue
            }
            if let parsed = parseProbeOutput(result.standardOutput) {
                return parsed
            }
        }
        return nil
    }

    private static func probeLoginShell(
        environment: [String: String]
    ) -> (node: String, devSpace: String)? {
        let shell = environment["SHELL"] ?? "/bin/zsh"
        guard shell.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: shell) else {
            return nil
        }

        let command = """
        printf '__CQB_NODE__=%s\\n' "$(command -v node 2>/dev/null)"
        printf '__CQB_DEVSPACE__=%s\\n' "$(command -v devspace 2>/dev/null)"
        """

        guard let result = try? run(
            executableURL: URL(fileURLWithPath: shell),
            arguments: ["-lic", command],
            environment: environment,
            timeout: 4
        ) else {
            return nil
        }
        return parseProbeOutput(result.standardOutput)
    }

    private static func parseProbeOutput(_ output: String) -> (node: String, devSpace: String)? {
        var node: String?
        var devSpace: String?

        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("__CQB_NODE__=") {
                node = String(line.dropFirst("__CQB_NODE__=".count))
            } else if line.hasPrefix("__CQB_DEVSPACE__=") {
                devSpace = String(line.dropFirst("__CQB_DEVSPACE__=".count))
            }
        }

        guard let node, let devSpace, node.hasPrefix("/"), devSpace.hasPrefix("/") else {
            return nil
        }
        return (node, devSpace)
    }

    private static func nvmRoots(
        environment: [String: String],
        homeDirectory: URL
    ) -> [URL] {
        var roots: [URL] = []
        if let value = environment["NVM_DIR"], !value.isEmpty {
            roots.append(URL(fileURLWithPath: value))
        }
        roots.append(homeDirectory.appendingPathComponent(".nvm"))
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            roots.append(URL(fileURLWithPath: xdg).appendingPathComponent("nvm"))
        } else {
            roots.append(homeDirectory.appendingPathComponent(".config/nvm"))
        }

        var seen = Set<String>()
        return roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func versionedBins(under root: URL, suffix: String) -> [URL] {
        children(of: root)
            .sorted(by: versionURLDescending)
            .map { $0.appendingPathComponent(suffix) }
    }

    private static func children(of root: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func versionURLDescending(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.lastPathComponent.compare(
            rhs.lastPathComponent,
            options: [.numeric, .caseInsensitive]
        ) == .orderedDescending
    }

    private static func executable(named name: String, in path: String) -> String? {
        for component in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(component))
                .appendingPathComponent(name)
                .path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func makePathEnvironment(
        nodeURL: URL,
        devSpaceURL: URL,
        existingPath: String?
    ) -> String {
        var components = [
            nodeURL.deletingLastPathComponent().path,
            devSpaceURL.deletingLastPathComponent().path
        ]
        if let existingPath {
            components.append(contentsOf: existingPath.split(separator: ":").map(String.init))
        }
        components.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ])

        var seen = Set<String>()
        return components
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
    }

    private static func runtimeEnvironment(
        base: [String: String],
        homeDirectory: URL,
        path: String
    ) -> [String: String] {
        var environment = base
        environment["HOME"] = homeDirectory.path
        environment["PATH"] = path
        return environment
    }

    private static func packageVersion(for resolvedDevSpace: URL) -> String? {
        var directory = resolvedDevSpace.deletingLastPathComponent()

        for _ in 0..<5 {
            let packageJSON = directory.appendingPathComponent("package.json")
            if let data = try? Data(contentsOf: packageJSON),
               let object = try? JSONSerialization.jsonObject(with: data),
               let dictionary = object as? [String: Any],
               let name = dictionary["name"] as? String,
               name == "@waishnav/devspace",
               let version = dictionary["version"] as? String,
               !version.isEmpty {
                return version
            }

            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { break }
            directory = parent
        }

        return nil
    }

    private static func firstNonemptyLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func isSupportedNodeVersion(_ version: String) -> Bool {
        let components = version
            .split(separator: ".")
            .prefix(3)
            .compactMap { Int($0) }
        guard components.count >= 2 else { return false }

        let major = components[0]
        let minor = components[1]

        if major == 22 {
            return minor >= 19
        }
        return major > 22 && major < 27
    }

    private static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) throws -> CommandResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        let exited = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            throw DevSpaceRuntimeError.unusable(error.localizedDescription)
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 0.5) == .timedOut, process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 0.5)
            }
            throw DevSpaceRuntimeError.unusable(
                "\(executableURL.lastPathComponent) 响应超时"
            )
        }

        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(
            status: process.terminationStatus,
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData, as: UTF8.self)
        )
    }
}
