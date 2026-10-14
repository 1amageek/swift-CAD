import CADCore

/// Encodes original source fields owned by `CADGeometry.CertifiedSphereConeIntersectionCurve.ComponentKind`.
extension CADGeometry.CertifiedSphereConeIntersectionCurve.ComponentKind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADGeometry.CertifiedSphereConeIntersectionCurve.ComponentKind", caseName: rawValue, values: 0)
    }
}
