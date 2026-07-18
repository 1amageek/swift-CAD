import CADCore
import CADIR

public protocol DocumentEditing: Sendable {
    func apply(
        _ command: CADCommand,
        to document: CADDocument,
        tolerance: ModelingTolerance
    ) throws -> CADDocument
}
