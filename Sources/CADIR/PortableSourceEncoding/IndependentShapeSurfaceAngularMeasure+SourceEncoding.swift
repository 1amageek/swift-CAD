import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeSurfaceAngularMeasure`.
extension CADIR.IndependentShapeSurfaceAngularMeasure: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .coneSemiAngle(value0):
            try encoder.enumeration("CADIR.IndependentShapeSurfaceAngularMeasure", caseName: "coneSemiAngle", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
