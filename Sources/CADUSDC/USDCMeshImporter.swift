import Foundation
import CADUSD

public struct USDCMeshImporter: Sendable {
    private let reader: USDCSceneReader
    private let sceneImporter: SceneImporter

    public init(reader: USDCSceneReader = USDCSceneReader(), sceneImporter: SceneImporter = SceneImporter()) {
        self.reader = reader
        self.sceneImporter = sceneImporter
    }

    public func importMeshes(from data: Data, named sourceName: String = "USDC") throws -> ImportResult {
        let scene = try reader.read(from: data)
        return try sceneImporter.importScene(scene, named: sourceName)
    }
}
