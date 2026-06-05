import Foundation
import CADUSD

public struct USDZMeshImporter: Sendable {
    private let reader: USDZPackageReader
    private let sceneImporter: USDSceneImporter

    public init(reader: USDZPackageReader = USDZPackageReader(), sceneImporter: USDSceneImporter = USDSceneImporter()) {
        self.reader = reader
        self.sceneImporter = sceneImporter
    }

    public func `import`(_ data: Data, named sourceName: String = "USDZ") throws -> USDImportResult {
        let scene = try reader.read(from: data)
        return try sceneImporter.import(scene, named: sourceName)
    }

    public func `import`(
        _ data: Data,
        rootLayerPath: String,
        named sourceName: String = "USDZ"
    ) throws -> USDImportResult {
        let scene = try reader.read(from: data, rootLayerPath: rootLayerPath)
        return try sceneImporter.import(scene, named: sourceName)
    }

    @available(*, deprecated, message: "Use import(_:named:) instead.")
    public func `import`(_ data: Data, sourceName: String) throws -> USDImportResult {
        try `import`(data, named: sourceName)
    }

    @available(*, deprecated, message: "Use import(_:rootLayerPath:named:) instead.")
    public func `import`(
        _ data: Data,
        rootLayerPath: String,
        sourceName: String
    ) throws -> USDImportResult {
        try `import`(data, rootLayerPath: rootLayerPath, named: sourceName)
    }

    @available(*, deprecated, message: "Use import(_:named:) instead.")
    public func `import`(from data: Data, sourceName: String = "USDZ") throws -> USDImportResult {
        try `import`(data, named: sourceName)
    }

    @available(*, deprecated, message: "Use import(_:rootLayerPath:named:) instead.")
    public func `import`(from data: Data, at rootPath: String, sourceName: String = "USDZ") throws -> USDImportResult {
        try `import`(data, rootLayerPath: rootPath, named: sourceName)
    }
}

@available(*, deprecated, renamed: "USDZMeshImporter")
public typealias USDZImporter = USDZMeshImporter
