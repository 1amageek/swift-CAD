import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeAngularSource.Law`.
extension CADIR.IndependentShapeAngularSource.Law: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .radian(value0):
            try encoder.enumeration("CADIR.IndependentShapeAngularSource.Law", caseName: "radian", values: 1)
            try encoder.field("_0", value0)
        case let .conversion(value0):
            try encoder.enumeration("CADIR.IndependentShapeAngularSource.Law", caseName: "conversion", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
