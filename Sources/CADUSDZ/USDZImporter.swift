import Foundation
import CADUSD

public struct USDZImporter: Sendable {
    private let reader: USDZReader
    private let sceneImporter: USDSceneImporter

    public init(reader: USDZReader = USDZReader(), sceneImporter: USDSceneImporter = USDSceneImporter()) {
        self.reader = reader
        self.sceneImporter = sceneImporter
    }

    public func `import`(from data: Data, sourceName: String = "USDZ") throws -> USDImportResult {
        let scene = try reader.read(from: data)
        return try sceneImporter.import(scene, sourceName: sourceName)
    }

    public func `import`(from data: Data, at rootPath: String, sourceName: String = "USDZ") throws -> USDImportResult {
        let scene = try reader.read(from: data, at: rootPath)
        return try sceneImporter.import(scene, sourceName: sourceName)
    }
}
