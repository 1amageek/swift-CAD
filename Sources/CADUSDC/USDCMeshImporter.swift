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

    @available(*, deprecated, message: "Use importMeshes(from:named:) instead.")
    public func `import`(_ data: Data, named sourceName: String = "USDC") throws -> ImportResult {
        try importMeshes(from: data, named: sourceName)
    }

    @available(*, deprecated, message: "Use importMeshes(from:named:) instead.")
    public func `import`(_ data: Data, sourceName: String) throws -> ImportResult {
        try importMeshes(from: data, named: sourceName)
    }

    @available(*, deprecated, message: "Use importMeshes(from:named:) instead.")
    public func `import`(from data: Data, sourceName: String = "USDC") throws -> ImportResult {
        try importMeshes(from: data, named: sourceName)
    }
}

@available(*, deprecated, renamed: "USDCMeshImporter")
public typealias MeshImporter = USDCMeshImporter

@available(*, deprecated, renamed: "USDCMeshImporter")
public typealias USDCImporter = USDCMeshImporter
