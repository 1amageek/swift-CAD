import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.Hyperbola3D`.
extension CADGeometry.Hyperbola3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.Hyperbola3D", fields: 5)
        try encoder.field("center", center)
        try encoder.field("conjugateRadius", conjugateRadius)
        try encoder.field("normal", normal)
        try encoder.field("transverseAxis", transverseAxis)
        try encoder.field("transverseRadius", transverseRadius)
    }
}
