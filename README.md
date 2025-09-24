# CIMetalCompilerPlugin

A Swift Package plugin to compile and link Core Image Metal Shaders to a single Metal Library that can be use in code. 

This repo significantly changed some implementations of this [original repo](https://github.com/schwa/MetalCompilerPlugin).

More details and insights about creating a Swift Package plugin can be [read here](https://juniperphoton.substack.com/p/creating-core-image-metal-shader).

# Background

Why do you need this Swift Package Plugin?

1. Compiling and linking Core Image Metal Shaders (not pure Metal Shaders) requires specifying certain flags (`-fcikernel` and `-cikernel`) in the Xcode Build Settings.
2. Swift Package Manager doesn't support setting user-defined flags for compiling and linking Metal Shaders.
3. Therefore, you have to put your Core Image Metal Shaders inside a Framework to prebuild, or inside a target to build.
4. If you have Swift code that resides in a Swift Package and reads the Metal library, the code and the shader code can't be in the same package.
5. Putting shader code inside targets to build increases the app bundle size, as the built artifacts will exist in every target that uses the shader code.

> Note: Swift Package can build pure Metal Shader out of the box. Separating your Core Image Metal Shader and pure Metal Shader should be a good start.

# Usage 

Add this package as a dependency to your Swift Package:

```swift
dependencies: [
    .package(url: "https://github.com/JuniperPhoton/CIMetalCompilerPlugin", from: "0.11.0")
]
```

Specify the plugin to use for your target.

```swift
targets: [
    .target(
        name: "MyPackage",
        exclude: [
            "Shaders/"
        ],
        plugins: [
            .plugin(name: "CIMetalCompilerPlugin", package: "CIMetalCompilerPlugin")
        ]
    )
]
```

Note:

1. You should put all your Core Image Metal Shaders in a folder like `Shaders`, as shown above, including any C headers that are included in the shaders.
2. You also need to explicitly exclude the entire `Shaders` folder, as the Swift Package build system will still try to build the shaders and will fail.

After the Swift Packgage being built, the `default.metallib` will reside in the Package's Bundle. Get this file using `Bundle.module` in your Swift Package's code:

```swift
let url = Bundle.module.url(forResource: "default", withExtension: "metallib")
```

# How does it work under the hood

It internally iterates over the directory to find all files that end with "metal".

Then it uses the equivalent command to create the intermediate files:

```shell
xcrun metal -c -fcikernel MyKernel.metal -o MyKernel.air "-fmodules=none" 
```

> Clang enables Modules for Metal by default. Enabling Modules will cause the build to fail when running on Xcode Cloud, as it may not have permissions to write the files to the system default cache dir. Thus, disabling Modules by specifying `-fmodules=none` or specifying the dir in the plugin sandbox dir `-fmodules-cache-path=xxxx` will do the trick.

For each intermediate file:

```shell
xcrun metallib --cikernel MyKernel.air -o MyKernel.metallib
```

Those `metallib` can be already used directly in code:

```swift
let resource = "your_metallib_name"

guard let url = Bundle.module.url(forResource: resource, withExtension: "metallib") else {
    return nil
}

guard let data = try? Data(contentsOf: url) else {
    return nil
}

let kernel = try? CIKernel(functionName: functionName, fromMetalLibraryData: data)
```

They can be then merged into one `default.metallib`:

```shell
xcrun metal -fcikernel -o default.metallib MyKernel1.metallib MyKernel2.metallib ...
```

# Useful Links

The original repo: 

https://github.com/schwa/MetalCompilerPlugin

Building a Shader Library by Precompiling Source Files:

https://developer.apple.com/documentation/metal/building-a-shader-library-by-precompiling-source-files

Xcrun:

https://keith.github.io/xcode-man-pages/xcrun.1.html

Clang Modules:

https://clang.llvm.org/docs/Modules.html#problems-with-the-current-model

# License

BSD 3-clause. See [LICENSE.md](./LICENSE.md).
