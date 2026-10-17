import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeSurfaceAngularMeasure`.
extension CADIR.IndependentShapeSurfaceAngularMeasure: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .coneSemiAngle(value0):
            try encoder.enumeration("CADIR.IndependentShapeSurfaceAngularMeasure", caseName: "coneSemiAngle", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
