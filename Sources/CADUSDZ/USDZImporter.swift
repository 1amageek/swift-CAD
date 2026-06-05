import Foundation
import CADUSD

public struct USDZImporter: Sendable {
    private let reader: USDZReader
    private let sceneImporter: USDSceneImporter

    public init(reader: USDZReader = USDZReader(), sceneImporter: USDSceneImporter = USDSceneImporter()) {
        self.reader = reader
        self.sceneImporter = sceneImporter
    }

    public func `import`(_ data: Data, sourceName: String = "USDZ") throws -> USDImportResult {
        let scene = try reader.read(from: data)
        return try sceneImporter.import(scene, sourceName: sourceName)
    }

    public func `import`(
        _ data: Data,
        rootLayerPath: String,
        sourceName: String = "USDZ"
    ) throws -> USDImportResult {
        let scene = try reader.read(from: data, rootLayerPath: rootLayerPath)
        return try sceneImporter.import(scene, sourceName: sourceName)
    }

    @available(*, deprecated, message: "Use import(_:sourceName:) instead.")
    public func `import`(from data: Data, sourceName: String = "USDZ") throws -> USDImportResult {
        try `import`(data, sourceName: sourceName)
    }

    @available(*, deprecated, message: "Use import(_:rootLayerPath:sourceName:) instead.")
    public func `import`(from data: Data, at rootPath: String, sourceName: String = "USDZ") throws -> USDImportResult {
        try `import`(data, rootLayerPath: rootPath, sourceName: sourceName)
    }
}
