import Foundation
import CADUSD

public struct USDCImporter: Sendable {
    private let reader: USDCReader
    private let sceneImporter: USDSceneImporter

    public init(reader: USDCReader = USDCReader(), sceneImporter: USDSceneImporter = USDSceneImporter()) {
        self.reader = reader
        self.sceneImporter = sceneImporter
    }

    public func `import`(_ data: Data, sourceName: String = "USDC") throws -> USDImportResult {
        let scene = try reader.read(from: data)
        return try sceneImporter.import(scene, sourceName: sourceName)
    }

    @available(*, deprecated, message: "Use import(_:sourceName:) instead.")
    public func `import`(from data: Data, sourceName: String = "USDC") throws -> USDImportResult {
        try `import`(data, sourceName: sourceName)
    }
}
