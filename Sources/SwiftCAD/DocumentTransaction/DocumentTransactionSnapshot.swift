import CADIR
import CADKernel

/// One committed evaluation and the session status observed in the same actor turn.
public struct DocumentTransactionSnapshot: Sendable {
    public let evaluatedDocument: EvaluatedDocument
    public let status: DocumentTransactionStatus

    public var sourceDocument: CADDocument { evaluatedDocument.document }
}
