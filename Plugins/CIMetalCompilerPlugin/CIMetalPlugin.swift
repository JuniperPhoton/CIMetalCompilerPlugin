import Foundation
import PackagePlugin

@main
struct CIMetalPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PackagePlugin.PluginContext,
        target: PackagePlugin.Target
    ) async throws -> [PackagePlugin.Command] {
        var paths: [URL] = []

        target.directoryURL.walk { path in
            if path.pathExtension == "metal" {
                paths.append(path)
            }
        }

        guard !paths.isEmpty else {
            Diagnostics.remark("No .metal files found in target directory, skipping CIMetalCompilerPlugin execution.")
            return []
        }

        Diagnostics.remark("Running CIMetalCompilerPlugin for \(paths.count) shader(s)")

        let workDir = context.pluginWorkDirectoryURL
        // Keep cache inside work dir but separate from the output dir so only
        // default.metallib ends up as a bundle resource.
        let cacheDir = workDir.appending(path: "cache")
        let outputDir = workDir.appending(path: "output")
        let output = outputDir.appending(path: "default.metallib")

        // Sort for deterministic ordering across invocations.
        let sortedPaths = paths.sorted { $0.path < $1.path }

        var lines = [
            "#!/bin/sh",
            "set -e",
            "mkdir -p '\(cacheDir.path())'",
            "mkdir -p '\(outputDir.path())'",
        ]

        var airFiles: [String] = []
        for metalPath in sortedPaths {
            let name = metalPath.deletingPathExtension().lastPathComponent
            let airPath = cacheDir.appending(path: "\(name).air").path()
            airFiles.append(airPath)
            lines.append("/usr/bin/xcrun metal -c -fcikernel '\(metalPath.path())' -o '\(airPath)' -fmodules=none")
        }

        let airArgs = airFiles.map { "'\($0)'" }.joined(separator: " ")
        lines.append("/usr/bin/xcrun metal -fcikernel -o '\(output.path())' \(airArgs)")

        let script = lines.joined(separator: "\n")
        let scriptPath = workDir.appending(path: "compile_metal.sh")
        try script.write(toFile: scriptPath.path(), atomically: true, encoding: .utf8)

        return [
            .prebuildCommand(
                displayName: "CIMetalCompilerPlugin",
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: [scriptPath.path()],
                environment: [:],
                outputFilesDirectory: outputDir
            )
        ]
    }
}

extension URL {
    func walk(_ visitor: (URL) -> Void) {
        guard let enumerator = FileManager().enumerator(
            at: self,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return
        }

        for case let url as URL in enumerator {
            visitor(url)
        }
    }
}
