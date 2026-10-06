import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductValidationProperty.Value`.
extension CADIR.ProductValidationProperty.Value: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .area(value0):
            try encoder.enumeration("CADIR.ProductValidationProperty.Value", caseName: "area", values: 1)
            try encoder.field("_0", value0)
        case let .volume(value0):
            try encoder.enumeration("CADIR.ProductValidationProperty.Value", caseName: "volume", values: 1)
            try encoder.field("_0", value0)
        case let .centroid(value0):
            try encoder.enumeration("CADIR.ProductValidationProperty.Value", caseName: "centroid", values: 1)
            try encoder.field("_0", value0)
        case let .length(value0):
            try encoder.enumeration("CADIR.ProductValidationProperty.Value", caseName: "length", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
