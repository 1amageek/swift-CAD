import CADCore

/// Encodes original source fields owned by `CADGeometry.CertifiedSphereCylinderIntersectionCurve.ComponentKind`.
extension CADGeometry.CertifiedSphereCylinderIntersectionCurve.ComponentKind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADGeometry.CertifiedSphereCylinderIntersectionCurve.ComponentKind", caseName: rawValue, values: 0)
    }
}
