import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.UnjoinFacesSelection`.
extension CADIR.UnjoinFacesSelection: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case .everyFace:
            try encoder.enumeration("CADIR.UnjoinFacesSelection", caseName: "everyFace", values: 0, using: &admission)
        case let .faces(value0):
            try encoder.enumeration("CADIR.UnjoinFacesSelection", caseName: "faces", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
