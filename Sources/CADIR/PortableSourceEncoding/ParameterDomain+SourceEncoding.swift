import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.ParameterDomain`.
extension CADGeometry.ParameterDomain: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case .unbounded:
            try encoder.enumeration("CADGeometry.ParameterDomain", caseName: "unbounded", values: 0, using: &admission)
        case let .closed(value0, value1):
            try encoder.enumeration("CADGeometry.ParameterDomain", caseName: "closed", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .periodic(value0):
            try encoder.enumeration("CADGeometry.ParameterDomain", caseName: "periodic", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
