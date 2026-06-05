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
}
