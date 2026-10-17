import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductValidationProperty.Value`.
extension CADIR.ProductValidationProperty.Value: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .area(value0):
            try encoder.enumeration("CADIR.ProductValidationProperty.Value", caseName: "area", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .volume(value0):
            try encoder.enumeration("CADIR.ProductValidationProperty.Value", caseName: "volume", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .centroid(value0):
            try encoder.enumeration("CADIR.ProductValidationProperty.Value", caseName: "centroid", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .length(value0):
            try encoder.enumeration("CADIR.ProductValidationProperty.Value", caseName: "length", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
