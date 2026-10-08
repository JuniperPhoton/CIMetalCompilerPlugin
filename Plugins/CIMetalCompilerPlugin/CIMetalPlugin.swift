import Foundation
import os
import PackagePlugin

@main
struct CIMetalPlugin: BuildToolPlugin {
    func createBuildCommands(context: PackagePlugin.PluginContext, target: PackagePlugin.Target) async throws -> [PackagePlugin.Command] {
        var paths: [URL] = []
        var headers: [URL] = []
        
        target.directoryURL.walk { path in
            switch path.pathExtension {
            case "metal":
                paths.append(path)
            case "h":
                headers.append(path)
            default:
                break
            }
        }
        
        // Sort to keep the command line stable: a different order changes the task signature,
        // which makes Xcode re-run the command.
        paths.sort { $0.path() < $1.path() }
        headers.sort { $0.path() < $1.path() }
        
        let cache = context.pluginWorkDirectoryURL.appending(path: "cache")
        let output = context.pluginWorkDirectoryURL.appending(path: "default.metallib")
        
        guard !paths.isEmpty else {
            Diagnostics.remark("No .metal files found in target directory, skipping CIMetalCompilerTool execution.")
            return []
        }
        
        Diagnostics.remark("Running...for \(paths)")
        
        return [
            .buildCommand(
                displayName: "CIMetalCompilerTool",
                executable: try context.tool(named: "CIMetalCompilerTool").url,
                arguments: [
                    "--output", output.path(),
                    "--cache", cache.path(),
                ] + headers.flatMap { ["--header", $0.path()] } + paths.map(\.path),
                environment: [:],
                // Headers are declared as inputs so that editing them triggers a rebuild.
                inputFiles: paths + headers,
                outputFiles: [
                    output
                ]
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
            errorHandler: { _,_ in true }
        ) else {
            fatalError()
        }
        
        for url in enumerator {
            guard let url = url as? URL else {
                fatalError()
            }
            visitor(url)
        }
    }
}
