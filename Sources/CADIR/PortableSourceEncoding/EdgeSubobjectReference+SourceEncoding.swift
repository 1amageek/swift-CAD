import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.EdgeSubobjectReference`.
extension CADIR.EdgeSubobjectReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .whole(value0):
            try encoder.enumeration("CADIR.EdgeSubobjectReference", caseName: "whole", values: 1)
            try encoder.field("_0", value0)
        case let .parameter(value0):
            try encoder.enumeration("CADIR.EdgeSubobjectReference", caseName: "parameter", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
