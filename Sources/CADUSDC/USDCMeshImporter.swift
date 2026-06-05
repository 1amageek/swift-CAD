import Foundation
import CADUSD

public struct USDCMeshImporter: Sendable {
    private let reader: USDCSceneReader
    private let sceneImporter: USDSceneImporter

    public init(reader: USDCSceneReader = USDCSceneReader(), sceneImporter: USDSceneImporter = USDSceneImporter()) {
        self.reader = reader
        self.sceneImporter = sceneImporter
    }

    public func `import`(_ data: Data, named sourceName: String = "USDC") throws -> USDImportResult {
        let scene = try reader.read(from: data)
        return try sceneImporter.import(scene, named: sourceName)
    }

    @available(*, deprecated, message: "Use import(_:named:) instead.")
    public func `import`(_ data: Data, sourceName: String) throws -> USDImportResult {
        try `import`(data, named: sourceName)
    }

    @available(*, deprecated, message: "Use import(_:named:) instead.")
    public func `import`(from data: Data, sourceName: String = "USDC") throws -> USDImportResult {
        try `import`(data, named: sourceName)
    }
}

@available(*, deprecated, renamed: "USDCMeshImporter")
public typealias USDCImporter = USDCMeshImporter
