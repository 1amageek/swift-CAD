import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SectionReference`.
extension CADIR.SectionReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .profile(value0):
            try encoder.enumeration("CADIR.SectionReference", caseName: "profile", values: 1)
            try encoder.field("_0", value0)
        case let .curve(value0):
            try encoder.enumeration("CADIR.SectionReference", caseName: "curve", values: 1)
            try encoder.field("_0", value0)
        case let .face(value0):
            try encoder.enumeration("CADIR.SectionReference", caseName: "face", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
