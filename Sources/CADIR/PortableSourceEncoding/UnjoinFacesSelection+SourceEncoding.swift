import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.UnjoinFacesSelection`.
extension CADIR.UnjoinFacesSelection: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case .everyFace:
            try encoder.enumeration("CADIR.UnjoinFacesSelection", caseName: "everyFace", values: 0)
        case let .faces(value0):
            try encoder.enumeration("CADIR.UnjoinFacesSelection", caseName: "faces", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
