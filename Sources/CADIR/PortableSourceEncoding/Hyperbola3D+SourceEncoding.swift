import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.Hyperbola3D`.
extension CADGeometry.Hyperbola3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.Hyperbola3D", fields: 5, using: &admission)
        try encoder.field("center", center, using: &admission)
        try encoder.field("conjugateRadius", conjugateRadius, using: &admission)
        try encoder.field("normal", normal, using: &admission)
        try encoder.field("transverseAxis", transverseAxis, using: &admission)
        try encoder.field("transverseRadius", transverseRadius, using: &admission)
    }
}
