import CodexQuotaBarCore
import Foundation

@MainActor
final class DevSpaceController {
    enum ActualState: Equatable {
        case disabled
        case externalPortOccupied
        case loaded
        case running
        case error(String)
    }

    private(set) var isEnabled = false
    private(set) var actualState: ActualState = .disabled
    private(set) var isBusy = false
    private(set) var runtimeDescription: String?

    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let desiredStateKey = "devspace.desiredEnabled"
    private let runtimeCacheKey = "devspace.runtimeCache"
    private var operationTask: Task<Void, Never>?
    private var cachedRuntime: DevSpaceRuntime?
    private var busyStatusText: String?

    deinit {
        operationTask?.cancel()
    }

    func start() {
        cachedRuntime = loadCachedRuntime()
        reconcile()
    }

    func refresh() {
        guard !isBusy else { return }

        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let self else { return }
            let status = await DevSpaceLaunchAgent.status()
            guard !Task.isCancelled else { return }

            if !status.isLoaded, await DevSpaceLaunchAgent.isDefaultPortOpen() {
                actualState = .externalPortOccupied
                notifyChange()
            } else {
                apply(status: status)
            }
        }
    }

    func toggle() {
        guard !isBusy else { return }
        if isEnabled {
            disable()
        } else {
            enable()
        }
    }

    var statusText: String {
        if isBusy {
            return busyStatusText ?? "处理中…"
        }

        switch actualState {
        case .disabled:
            return "已关闭"
        case .externalPortOccupied:
            return "未接管（7676 已占用）"
        case .loaded:
            return "已启用，等待运行"
        case .running:
            return "运行中"
        case let .error(message):
            return message
        }
    }

    private func reconcile() {
        guard !isBusy else { return }
        isBusy = true
        busyStatusText = "检查中…"
        notifyChange()

        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let self else { return }

            var status = await DevSpaceLaunchAgent.status()
            guard !Task.isCancelled else { return }

            let storedValue = defaults.object(forKey: desiredStateKey) as? Bool
            let desiredEnabled = storedValue
                ?? (status.isLoaded || status.agentFileExists)

            defaults.set(desiredEnabled, forKey: desiredStateKey)
            isEnabled = desiredEnabled

            if !desiredEnabled {
                if status.isLoaded || status.agentFileExists {
                    do {
                        status = try await DevSpaceLaunchAgent.stopAndRemove()
                    } catch {
                        actualState = .error(
                            (error as? LocalizedError)?.errorDescription ?? "关闭失败"
                        )
                        busyStatusText = nil
                        isBusy = false
                        notifyChange()
                        return
                    }
                }

                if await DevSpaceLaunchAgent.isDefaultPortOpen() {
                    actualState = .externalPortOccupied
                } else {
                    actualState = .disabled
                }
                busyStatusText = nil
                isBusy = false
                notifyChange()
                return
            }

            do {
                if status.isLoaded {
                    // Do not disrupt a healthy running service just because nvm's
                    // default version changed. Repair only if the job is currently
                    // unable to run and its recorded absolute paths disappeared.
                    if !status.isRunning,
                       !(await DevSpaceLaunchAgent.runtimePathsExist()) {
                        let runtime = try await DevSpaceRuntimeResolver.resolve()
                        status = try await DevSpaceLaunchAgent.installAndStart(runtime: runtime)
                        runtimeDescription = Self.describe(runtime)
                    }
                } else if status.agentFileExists,
                          await DevSpaceLaunchAgent.runtimePathsExist() {
                    status = try await DevSpaceLaunchAgent.bootstrapExistingAgentIfNeeded()
                } else {
                    // The user still wants DevSpace enabled but either the plist was
                    // removed or an nvm/fnm/asdf upgrade invalidated its paths.
                    let runtime = try await DevSpaceRuntimeResolver.resolve()
                    status = try await DevSpaceLaunchAgent.installAndStart(runtime: runtime)
                    runtimeDescription = Self.describe(runtime)
                }
            } catch {
                actualState = .error(
                    (error as? LocalizedError)?.errorDescription ?? "已启用，但启动失败"
                )
                busyStatusText = nil
                isBusy = false
                notifyChange()
                return
            }

            if status.isLoaded {
                isEnabled = true
                defaults.set(true, forKey: desiredStateKey)
            }

            apply(status: status)
            busyStatusText = nil
            isBusy = false
            notifyChange()
        }
    }

    private func enable() {
        // Reflect the user's requested state immediately. Runtime discovery and
        // launchd work continue asynchronously; failures roll the switch back.
        isBusy = true
        busyStatusText = "正在启动…"
        isEnabled = true
        defaults.set(true, forKey: desiredStateKey)
        actualState = .loaded
        notifyChange()

        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let runtime = try await reusableOrResolvedRuntime()
                guard !Task.isCancelled else { return }

                let status = try await DevSpaceLaunchAgent.installAndStart(runtime: runtime)
                guard !Task.isCancelled else { return }

                cache(runtime)
                runtimeDescription = Self.describe(runtime)
                apply(status: status)
            } catch {
                isEnabled = false
                defaults.set(false, forKey: desiredStateKey)
                actualState = .error(
                    (error as? LocalizedError)?.errorDescription ?? "启动失败"
                )
            }

            busyStatusText = nil
            isBusy = false
            notifyChange()
        }
    }

    private func disable() {
        isBusy = true
        busyStatusText = "正在关闭…"
        notifyChange()

        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let self else { return }

            // Persist intent first. If the app is terminated during shutdown, the
            // next launch will finish reconciling launchd to the requested OFF state.
            defaults.set(false, forKey: desiredStateKey)
            isEnabled = false

            do {
                let status = try await DevSpaceLaunchAgent.stopAndRemove()
                apply(status: status)
                runtimeDescription = nil
            } catch {
                actualState = .error(
                    (error as? LocalizedError)?.errorDescription ?? "关闭失败"
                )
            }

            busyStatusText = nil
            isBusy = false
            notifyChange()
        }
    }

    private func apply(status: DevSpaceAgentStatus) {
        switch status.state {
        case .disabled:
            actualState = .disabled
        case .loaded:
            actualState = .loaded
        case .running:
            actualState = .running
        }
        notifyChange()
    }

    private func reusableOrResolvedRuntime() async throws -> DevSpaceRuntime {
        if let cachedRuntime, Self.runtimePathsExist(cachedRuntime) {
            return cachedRuntime
        }

        if let persisted = loadCachedRuntime(), Self.runtimePathsExist(persisted) {
            cachedRuntime = persisted
            return persisted
        }

        let runtime = try await DevSpaceRuntimeResolver.resolve()
        cache(runtime)
        return runtime
    }

    private func cache(_ runtime: DevSpaceRuntime) {
        cachedRuntime = runtime

        defaults.set(
            [
                "nodePath": runtime.nodeURL.path,
                "devSpacePath": runtime.devSpaceURL.path,
                "executablePath": runtime.executableURL.path,
                "argumentPrefix": runtime.argumentPrefix,
                "nodeVersion": runtime.nodeVersion,
                "devSpaceVersion": runtime.devSpaceVersion,
                "source": runtime.source.rawValue,
                "pathEnvironment": runtime.pathEnvironment
            ],
            forKey: runtimeCacheKey
        )
    }

    private func loadCachedRuntime() -> DevSpaceRuntime? {
        guard let dictionary = defaults.dictionary(forKey: runtimeCacheKey),
              let nodePath = dictionary["nodePath"] as? String,
              let devSpacePath = dictionary["devSpacePath"] as? String,
              let executablePath = dictionary["executablePath"] as? String,
              let argumentPrefix = dictionary["argumentPrefix"] as? [String],
              let nodeVersion = dictionary["nodeVersion"] as? String,
              let devSpaceVersion = dictionary["devSpaceVersion"] as? String,
              let sourceValue = dictionary["source"] as? String,
              let source = DevSpaceRuntime.Source(rawValue: sourceValue),
              let pathEnvironment = dictionary["pathEnvironment"] as? String else {
            return nil
        }

        let runtime = DevSpaceRuntime(
            nodeURL: URL(fileURLWithPath: nodePath),
            devSpaceURL: URL(fileURLWithPath: devSpacePath),
            executableURL: URL(fileURLWithPath: executablePath),
            argumentPrefix: argumentPrefix,
            nodeVersion: nodeVersion,
            devSpaceVersion: devSpaceVersion,
            source: source,
            pathEnvironment: pathEnvironment
        )

        return Self.runtimePathsExist(runtime) ? runtime : nil
    }

    private static func runtimePathsExist(_ runtime: DevSpaceRuntime) -> Bool {
        let fileManager = FileManager.default

        guard fileManager.isExecutableFile(atPath: runtime.nodeURL.path),
              fileManager.fileExists(atPath: runtime.devSpaceURL.path),
              fileManager.isExecutableFile(atPath: runtime.executableURL.path) else {
            return false
        }

        for argument in runtime.argumentPrefix where argument.hasPrefix("/") {
            guard fileManager.fileExists(atPath: argument) else {
                return false
            }
        }

        return true
    }

    private static func describe(_ runtime: DevSpaceRuntime) -> String {
        "DevSpace \(runtime.devSpaceVersion) · Node \(runtime.nodeVersion) · \(runtime.source.rawValue)"
    }

    private func notifyChange() {
        onChange?()
    }
}
