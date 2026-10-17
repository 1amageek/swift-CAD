import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedIntersectionCurve3D`.
extension CADGeometry.CertifiedIntersectionCurve3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .sphereCone(value0):
            try encoder.enumeration("CADGeometry.CertifiedIntersectionCurve3D", caseName: "sphereCone", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .coneCone(value0):
            try encoder.enumeration("CADGeometry.CertifiedIntersectionCurve3D", caseName: "coneCone", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .coneCylinder(value0):
            try encoder.enumeration("CADGeometry.CertifiedIntersectionCurve3D", caseName: "coneCylinder", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .coneTorus(value0):
            try encoder.enumeration("CADGeometry.CertifiedIntersectionCurve3D", caseName: "coneTorus", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .parallelTorusTorus(value0):
            try encoder.enumeration("CADGeometry.CertifiedIntersectionCurve3D", caseName: "parallelTorusTorus", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
