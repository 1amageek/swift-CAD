import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchPointSelectionReference`.
extension CADIR.SketchPointSelectionReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SketchPointSelectionReference", fields: 2)
        try encoder.field("entityID", entityID)
        try encoder.field("featureID", featureID)
    }
}
