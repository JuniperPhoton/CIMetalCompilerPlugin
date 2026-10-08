import ArgumentParser
import CryptoKit
import Foundation
import os

#if !targetEnvironment(macCatalyst)
/// Useful links:
/// https://clang.llvm.org/docs/Modules.html#problems-with-the-current-model
/// https://keith.github.io/xcode-man-pages/xcrun.1.html
/// https://developer.apple.com/documentation/metal/building-a-shader-library-by-precompiling-source-files
@main
@available(macOS 13.0, *)
struct CIMetalCompilerTool: ParsableCommand {
    @Option(name: .long)
    var output: String

    @Option(name: .long)
    var cache: String

    /// Headers included by the shaders. Their contents are part of every cache key,
    /// so changing a header recompiles all shaders.
    @Option(name: .long)
    var header: [String] = []

    @Argument
    var inputs: [String]

    mutating func run() throws {
        print("=== run MetalCompilerTool ===")

        let start = Date()
        let fileManager = FileManager.default
        let cacheURL = URL(fileURLWithPath: cache)

        try fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)

        // Xcode re-runs this command whenever the build environment changes (switching run destinations,
        // SwiftUI Previews builds, etc.), even if no shader changed. Each .air is cached by the hash of
        // everything that affects its output, so those re-runs only compile what actually changed.
        let baseKey = try makeBaseKey()

        let compileUnits = try inputs.map { input in
            var hasher = SHA256()
            hasher.update(data: baseKey)
            hasher.update(data: Data(input.utf8))
            hasher.update(data: try Data(contentsOf: URL(fileURLWithPath: input)))
            let key = hasher.finalize().hexString
            return CompileUnit(
                input: input,
                airOutput: cacheURL.appending(path: "\(input.nameWithoutExtension)-\(key).air").path()
            )
        }

        let pendingUnits = compileUnits.filter { !fileManager.fileExists(atPath: $0.airOutput) }

        // First compile each input to .air files, in parallel.
        // Equivelent to this command line:
        // xcrun metal -c -fcikernel MyKernel.metal -o MyKernel.air
        let errors = ErrorCollector()
        DispatchQueue.concurrentPerform(iterations: pendingUnits.count) { index in
            let unit = pendingUnits[index]

            // Compile to a temporary file first so an interrupted build never leaves a broken .air in the cache.
            let tempOutput = "\(unit.airOutput).\(UUID().uuidString).tmp"

            do {
                try runXcrun([
                    "metal",
                    "-c",
                    "-fcikernel",
                    unit.input,
                    "-o",
                    tempOutput,
                    "-fmodules=none" // Must disable fmodules to avoid issues when building in Xcode Cloud.
                ], errorMessage: "Failed to compile \(unit.input)")

                try? FileManager.default.removeItem(atPath: unit.airOutput)
                try FileManager.default.moveItem(atPath: tempOutput, toPath: unit.airOutput)
                print("compiled \(unit.input) to \(unit.airOutput)")
            } catch {
                try? FileManager.default.removeItem(atPath: tempOutput)
                errors.append(error)
            }
        }

        if let error = errors.first {
            throw error
        }

        print("reused \(compileUnits.count - pendingUnits.count) cached .air file(s), compiled \(pendingUnits.count)")

        let airOutputs = compileUnits.map(\.airOutput)

        print("merging \(airOutputs) to \(output)")

        // Finally, merge all .air files into one output file.
        // Equivelent to this command line:
        // xcrun metal -fcikernel -o default.metallib MyKernel1.air MyKernel2.air ...
        // NOTE: This command is different from the one that was first introduced in WWDC20:
        // https://developer.apple.com/videos/play/wwdc2020/10021
        // The old command is obsolete and no longer works.
        try runXcrun([
            "metal",
            "-fcikernel",
            "-o",
            output,
        ] + airOutputs, errorMessage: "Failed to merge to \(output)")

        pruneCache(at: cacheURL, keeping: Set(airOutputs))

        print("====CIMetalCompilerTool completed in \(String(format: "%.2f", Date().timeIntervalSince(start)))s!")
    }

    /// Hash of the inputs shared by all shaders: headers and the compile environment.
    private func makeBaseKey() throws -> Data {
        var hasher = SHA256()

        // Bump this when the compile flags above change.
        hasher.update(data: Data("v1 -c -fcikernel -fmodules=none".utf8))

        // xcrun resolves the SDK and toolchain from these, and clang reads *_DEPLOYMENT_TARGET.
        let environment = ProcessInfo.processInfo.environment
        let relevantKeys = environment.keys.filter { key in
            key == "SDKROOT" || key == "DEVELOPER_DIR" || key == "TOOLCHAINS" || key.hasSuffix("_DEPLOYMENT_TARGET")
        }.sorted()
        for key in relevantKeys {
            hasher.update(data: Data("\(key)=\(environment[key] ?? "")\n".utf8))
        }

        for header in header.sorted() {
            hasher.update(data: Data(header.utf8))
            hasher.update(data: try Data(contentsOf: URL(fileURLWithPath: header)))
        }

        return Data(hasher.finalize())
    }

    /// Removes cached files that are not used by this run and haven't been used for a while.
    /// Recently used ones are kept so that switching between platforms (device / simulator) stays fast.
    private func pruneCache(at cacheURL: URL, keeping used: Set<String>) {
        let fileManager = FileManager.default
        let now = Date()
        let maxAge: TimeInterval = 7 * 24 * 60 * 60

        for path in used {
            try? fileManager.setAttributes([.modificationDate: now], ofItemAtPath: path)
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }

        for url in contents where !used.contains(url.path()) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) < maxAge {
                continue
            }
            try? fileManager.removeItem(at: url)
        }
    }
}

private struct CompileUnit {
    let input: String
    let airOutput: String
}

private final class ErrorCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [Error] = []

    var first: Error? {
        lock.withLock { errors.first }
    }

    func append(_ error: Error) {
        lock.withLock { errors.append(error) }
    }
}

private func runXcrun(_ arguments: [String], errorMessage: String) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    p.arguments = arguments

    try p.run()
    p.waitUntilExit()

    let status = p.terminationStatus
    if status != 0 {
        throw CompileError(message: "\(errorMessage) with exit code \(status)")
    }
}

private extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
#else
@main
struct CIMetalCompilerTool: ParsableCommand {
    @Option(name: .long)
    var output: String

    @Option(name: .long)
    var cache: String

    @Option(name: .long)
    var header: [String] = []

    @Argument
    var inputs: [String]

    mutating func run() throws {
        throw CompileError(message: "CIMetalCompilerTool is not supported on macOS Catalyst. But this code won't run anyway.")
    }
}
#endif
