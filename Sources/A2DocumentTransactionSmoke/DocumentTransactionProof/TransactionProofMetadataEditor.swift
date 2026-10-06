import SwiftCAD

struct TransactionProofMetadataEditor: DocumentEditing {
    func apply(_ command: CADCommand, to document: CADDocument, tolerance: ModelingTolerance) throws -> CADDocument {
        var result = try DocumentEditor().apply(command, to: document, tolerance: tolerance)
        result.metadata.name = (result.metadata.name ?? "") + ".edited"
        return result
    }
}
