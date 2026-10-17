import CADCore

/// Evaluation source authority, independent of document display identity and timestamps.
struct PortableDocumentSourcePayload: PortableSourceEncodable {
    let document: CADDocument

    static var defaultLimits: PortableSourceEncodingLimits {
        // The historical convenience API had no source encoding allowance. Do not
        // reinterpret a metadata-text limit as a cap on original geometry bytes.
        PortableSourceEncodingLimits(maximumBytes: Int.max,
            maximumWork: Int.max, maximumDepth: Int.max)
    }

    func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.EvaluationSource.BinaryV1", fields: 9, using: &admission)
        try encoder.field("assembly", document.assembly, using: &admission)
        try encoder.field("designGraph", document.designGraph, using: &admission)
        try encoder.field("documentFoundation", document.documentFoundation, using: &admission)
        try encoder.field("independentShapes", document.independentShapes, using: &admission)
        try encoder.field("parameters", document.parameters, using: &admission)
        try encoder.field("productAttributes", document.productAttributes, using: &admission)
        try encoder.field("schemaVersion", document.schemaVersion, using: &admission)
        let dimensions = try encoder.canonicalOrder(document.selectionDimensions, using: &admission)
        try encoder.field("selectionDimensions", dimensions, using: &admission)
        try encoder.field("units", document.units, using: &admission)
    }
}
