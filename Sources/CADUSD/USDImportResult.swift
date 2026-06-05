import CADCore
import CADIR

public struct USDImportResult: Sendable {
    public var meshes: [BodyID: Mesh]
    public var units: UnitSystem

    public init(meshes: [BodyID: Mesh], units: UnitSystem) {
        self.meshes = meshes
        self.units = units
    }
}
