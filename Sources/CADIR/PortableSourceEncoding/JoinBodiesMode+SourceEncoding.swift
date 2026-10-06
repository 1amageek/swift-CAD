import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.JoinBodiesMode`.
extension CADIR.JoinBodiesMode: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.JoinBodiesMode", caseName: rawValue, values: 0)
    }
}
