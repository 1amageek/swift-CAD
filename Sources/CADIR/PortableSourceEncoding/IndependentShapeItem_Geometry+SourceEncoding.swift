import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeItem.Geometry`.
extension CADIR.IndependentShapeItem.Geometry: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .curve(value0, value1):
            try encoder.enumeration("CADIR.IndependentShapeItem.Geometry", caseName: "curve", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        case let .surface(value0):
            try encoder.enumeration("CADIR.IndependentShapeItem.Geometry", caseName: "surface", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
