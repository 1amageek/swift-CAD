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

    func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.EvaluationSource.BinaryV1", fields: 9)
        try encoder.field("assembly", document.assembly)
        try encoder.field("designGraph", document.designGraph)
        try encoder.field("documentFoundation", document.documentFoundation)
        try encoder.field("independentShapes", document.independentShapes)
        try encoder.field("parameters", document.parameters)
        try encoder.field("productAttributes", document.productAttributes)
        try encoder.field("schemaVersion", document.schemaVersion)
        let dimensions = try encoder.canonicalOrder(document.selectionDimensions)
        try encoder.field("selectionDimensions", dimensions)
        try encoder.field("units", document.units)
    }
}
