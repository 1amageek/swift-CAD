import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DocumentObjectTarget`.
extension CADIR.DocumentObjectTarget: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case .document:
            try encoder.enumeration("CADIR.DocumentObjectTarget", caseName: "document", values: 0, using: &admission)
        case let .feature(value0):
            try encoder.enumeration("CADIR.DocumentObjectTarget", caseName: "feature", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .parameter(value0):
            try encoder.enumeration("CADIR.DocumentObjectTarget", caseName: "parameter", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .attribute(value0):
            try encoder.enumeration("CADIR.DocumentObjectTarget", caseName: "attribute", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
