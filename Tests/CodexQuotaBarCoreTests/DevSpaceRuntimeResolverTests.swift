import Foundation
import Testing
@testable import CodexQuotaBarCore

@Suite("DevSpace runtime resolver")
struct DevSpaceRuntimeResolverTests {
    @Test("Uses explicitly configured Node and DevSpace executables")
    func explicitExecutables() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bin = directory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let node = bin.appendingPathComponent("node")
        let devSpace = bin.appendingPathComponent("devspace")
        try writeExecutable(
            "#!/bin/sh\necho v24.17.0\n",
            to: node
        )
        try writeExecutable(
            "#!/bin/sh\necho 1.2.3\n",
            to: devSpace
        )

        let runtime = try await DevSpaceRuntimeResolver.resolve(
            environment: [
                "HOME": directory.path,
                "PATH": "/usr/bin:/bin",
                "SHELL": "/bin/false",
                "DEVSPACE_NODE_EXECUTABLE": node.path,
                "DEVSPACE_EXECUTABLE": devSpace.path
            ],
            homeDirectory: directory
        )

        #expect(runtime.source == .environment)
        #expect(runtime.nodeURL.path == node.path)
        #expect(runtime.devSpaceURL.path == devSpace.path)
        #expect(runtime.executableURL.path == devSpace.path)
        #expect(runtime.argumentPrefix.isEmpty)
        #expect(runtime.nodeVersion == "24.17.0")
        #expect(runtime.devSpaceVersion == "1.2.3")
    }

    @Test("Rejects an unsupported Node version")
    func rejectsUnsupportedNode() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bin = directory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let node = bin.appendingPathComponent("node")
        let devSpace = bin.appendingPathComponent("devspace")
        try writeExecutable(
            "#!/bin/sh\necho v20.18.0\n",
            to: node
        )
        try writeExecutable(
            "#!/bin/sh\necho 1.2.3\n",
            to: devSpace
        )

        await #expect(throws: DevSpaceRuntimeError.self) {
            _ = try await DevSpaceRuntimeResolver.resolve(
                environment: [
                    "HOME": directory.path,
                    "PATH": "/usr/bin:/bin",
                    "SHELL": "/bin/false",
                    "DEVSPACE_NODE_EXECUTABLE": node.path,
                    "DEVSPACE_EXECUTABLE": devSpace.path
                ],
                homeDirectory: directory
            )
        }
    }

    @Test("Finds nvm installs and bypasses env node for JavaScript CLI symlinks")
    func nvmJavaScriptSymlink() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let version = directory
            .appendingPathComponent(".nvm/versions/node/v24.17.0", isDirectory: true)
        let bin = version.appendingPathComponent("bin", isDirectory: true)
        let dist = version
            .appendingPathComponent("lib/node_modules/@waishnav/devspace/dist", isDirectory: true)

        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dist, withIntermediateDirectories: true)

        let node = bin.appendingPathComponent("node")
        try writeExecutable(
            """
            #!/bin/sh
            if [ "$1" = "--version" ]; then
              echo v24.17.0
            else
              echo 9.9.9
            fi
            """,
            to: node
        )

        let cli = dist.appendingPathComponent("cli.js")
        try "#!/usr/bin/env node\n".write(to: cli, atomically: true, encoding: .utf8)

        let devSpace = bin.appendingPathComponent("devspace")
        try FileManager.default.createSymbolicLink(
            at: devSpace,
            withDestinationURL: URL(
                fileURLWithPath: "../lib/node_modules/@waishnav/devspace/dist/cli.js",
                relativeTo: bin
            )
        )

        let runtime = try await DevSpaceRuntimeResolver.resolve(
            environment: [
                "HOME": directory.path,
                "PATH": "/usr/bin:/bin",
                "SHELL": "/bin/false"
            ],
            homeDirectory: directory
        )

        #expect(runtime.source == .nvm)
        #expect(
            runtime.nodeURL.resolvingSymlinksInPath().path
                == node.resolvingSymlinksInPath().path
        )
        #expect(
            runtime.devSpaceURL.standardizedFileURL.path
                == devSpace.standardizedFileURL.path
        )
        #expect(
            runtime.executableURL.resolvingSymlinksInPath().path
                == node.resolvingSymlinksInPath().path
        )
        #expect(runtime.argumentPrefix == [cli.path])
        #expect(runtime.nodeVersion == "24.17.0")
        #expect(runtime.devSpaceVersion == "9.9.9")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeExecutable(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
    }
}
