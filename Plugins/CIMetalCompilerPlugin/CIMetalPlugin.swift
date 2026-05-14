import Foundation
import os
import PackagePlugin

@main
struct CIMetalPlugin: BuildToolPlugin {
    func createBuildCommands(context: PackagePlugin.PluginContext, target: PackagePlugin.Target) async throws -> [PackagePlugin.Command] {
        var paths: [URL] = []
        
        target.directoryURL.walk { path in
            if path.pathExtension == "metal" {
                paths.append(path)
            }
        }
        
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
                ] + paths.map(\.path),
                environment: [:],
                inputFiles: paths,
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
