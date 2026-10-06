import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DocumentObjectTarget`.
extension CADIR.DocumentObjectTarget: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case .document:
            try encoder.enumeration("CADIR.DocumentObjectTarget", caseName: "document", values: 0)
        case let .feature(value0):
            try encoder.enumeration("CADIR.DocumentObjectTarget", caseName: "feature", values: 1)
            try encoder.field("_0", value0)
        case let .parameter(value0):
            try encoder.enumeration("CADIR.DocumentObjectTarget", caseName: "parameter", values: 1)
            try encoder.field("_0", value0)
        case let .attribute(value0):
            try encoder.enumeration("CADIR.DocumentObjectTarget", caseName: "attribute", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
