import Foundation
import CADUSD

public struct MeshImporter: Sendable {
    private let reader: SceneReader
    private let sceneImporter: SceneImporter

    public init(reader: SceneReader = SceneReader(), sceneImporter: SceneImporter = SceneImporter()) {
        self.reader = reader
        self.sceneImporter = sceneImporter
    }

    public func `import`(_ data: Data, named sourceName: String = "USDC") throws -> ImportResult {
        let scene = try reader.read(from: data)
        return try sceneImporter.import(scene, named: sourceName)
    }

    @available(*, deprecated, message: "Use import(_:named:) instead.")
    public func `import`(_ data: Data, sourceName: String) throws -> ImportResult {
        try `import`(data, named: sourceName)
    }

    @available(*, deprecated, message: "Use import(_:named:) instead.")
    public func `import`(from data: Data, sourceName: String = "USDC") throws -> ImportResult {
        try `import`(data, named: sourceName)
    }
}

@available(*, deprecated, renamed: "MeshImporter")
public typealias USDCMeshImporter = MeshImporter

@available(*, deprecated, renamed: "MeshImporter")
public typealias USDCImporter = MeshImporter
