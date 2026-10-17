import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeTrimmingSource.Selector`.
extension CADIR.IndependentShapeTrimmingSource.Selector: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .parameter(value0):
            try encoder.enumeration("CADIR.IndependentShapeTrimmingSource.Selector", caseName: "parameter", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .point(value0):
            try encoder.enumeration("CADIR.IndependentShapeTrimmingSource.Selector", caseName: "point", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
