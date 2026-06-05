import Foundation
import CADUSD

public struct USDZMeshImporter: Sendable {
    private let reader: USDZPackageReader
    private let sceneImporter: SceneImporter

    public init(reader: USDZPackageReader = USDZPackageReader(), sceneImporter: SceneImporter = SceneImporter()) {
        self.reader = reader
        self.sceneImporter = sceneImporter
    }

    public func importMeshes(from data: Data, named sourceName: String = "USDZ") throws -> ImportResult {
        let scene = try reader.read(from: data)
        return try sceneImporter.importScene(scene, named: sourceName)
    }

    public func importMeshes(
        from data: Data,
        rootLayerPath: String,
        named sourceName: String = "USDZ"
    ) throws -> ImportResult {
        let scene = try reader.read(from: data, rootLayerPath: rootLayerPath)
        return try sceneImporter.importScene(scene, named: sourceName)
    }

    @available(*, deprecated, message: "Use importMeshes(from:named:) instead.")
    public func `import`(_ data: Data, named sourceName: String = "USDZ") throws -> ImportResult {
        try importMeshes(from: data, named: sourceName)
    }

    @available(*, deprecated, message: "Use importMeshes(from:rootLayerPath:named:) instead.")
    public func `import`(
        _ data: Data,
        rootLayerPath: String,
        named sourceName: String = "USDZ"
    ) throws -> ImportResult {
        try importMeshes(from: data, rootLayerPath: rootLayerPath, named: sourceName)
    }

    @available(*, deprecated, message: "Use importMeshes(from:named:) instead.")
    public func `import`(_ data: Data, sourceName: String) throws -> ImportResult {
        try importMeshes(from: data, named: sourceName)
    }

    @available(*, deprecated, message: "Use importMeshes(from:rootLayerPath:named:) instead.")
    public func `import`(
        _ data: Data,
        rootLayerPath: String,
        sourceName: String
    ) throws -> ImportResult {
        try importMeshes(from: data, rootLayerPath: rootLayerPath, named: sourceName)
    }

    @available(*, deprecated, message: "Use importMeshes(from:named:) instead.")
    public func `import`(from data: Data, sourceName: String = "USDZ") throws -> ImportResult {
        try importMeshes(from: data, named: sourceName)
    }

    @available(*, deprecated, message: "Use importMeshes(from:rootLayerPath:named:) instead.")
    public func `import`(from data: Data, at rootPath: String, sourceName: String = "USDZ") throws -> ImportResult {
        try importMeshes(from: data, rootLayerPath: rootPath, named: sourceName)
    }
}

@available(*, deprecated, renamed: "USDZMeshImporter")
public typealias MeshImporter = USDZMeshImporter

@available(*, deprecated, renamed: "USDZMeshImporter")
public typealias USDZImporter = USDZMeshImporter
