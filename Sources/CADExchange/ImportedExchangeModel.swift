import CADCore
import CADIR
import CADTopology

public struct ImportedExchangeModel: Sendable {
    public var format: ExchangeFileFormat
    public var document: CADDocument?
    public var brep: BRepModel?
    public var meshes: [BodyID: Mesh]
    public var units: UnitSystem

    public init(
        format: ExchangeFileFormat,
        document: CADDocument? = nil,
        brep: BRepModel? = nil,
        meshes: [BodyID: Mesh] = [:],
        units: UnitSystem = .meters
    ) {
        self.format = format
        self.document = document
        self.brep = brep
        self.meshes = meshes
        self.units = units
    }
}
