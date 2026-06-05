import CADCore
import CADIR

public struct ImportResult: Sendable {
    public var meshes: [BodyID: Mesh]
    public var units: UnitSystem

    public init(meshes: [BodyID: Mesh], units: UnitSystem) {
        self.meshes = meshes
        self.units = units
    }
}

@available(*, deprecated, renamed: "ImportResult")
public typealias USDImportResult = ImportResult
