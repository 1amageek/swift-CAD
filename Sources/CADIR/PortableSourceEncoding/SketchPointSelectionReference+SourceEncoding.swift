import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchPointSelectionReference`.
extension CADIR.SketchPointSelectionReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SketchPointSelectionReference", fields: 2, using: &admission)
        try encoder.field("entityID", entityID, using: &admission)
        try encoder.field("featureID", featureID, using: &admission)
    }
}
