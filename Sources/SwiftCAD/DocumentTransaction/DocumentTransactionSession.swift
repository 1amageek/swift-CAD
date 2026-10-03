import Foundation
import CADCore
import CADIR
import CADKernel

/// Owns a single draft and bounded complete evaluation history.
public actor DocumentTransactionSession: DocumentTransacting {
    private struct Draft {
        let token: DocumentTransactionToken
        var document: CADDocument
        var commandCount: Int
    }

    private struct HistoryRecord {
        let before: EvaluatedDocument
        let after: EvaluatedDocument
    }

    private let sessionID = UUID()
    private let editor: any DocumentEditing
    private let evaluator: any ExactDocumentEvaluating
    private let tolerance: ModelingTolerance
    private let limits: DocumentTransactionLimits
    private var committed: EvaluatedDocument
    private var epoch: UInt64 = 0
    private var draft: Draft?
    private var undoRecords: [HistoryRecord] = []
    private var redoRecords: [HistoryRecord] = []

    public init(
        document: CADDocument,
        editor: any DocumentEditing = DocumentEditor(),
        evaluator: any ExactDocumentEvaluating,
        limits: DocumentTransactionLimits
    ) throws {
        let tolerance = evaluator.evaluationTolerance
        try tolerance.validate()
        self.committed = try Self.evaluate(document, using: evaluator, tolerance: tolerance)
        self.editor = editor
        self.evaluator = evaluator
        self.tolerance = tolerance
        self.limits = limits
    }

    public func status() -> DocumentTransactionStatus {
        DocumentTransactionStatus(epoch: epoch, undoCount: undoRecords.count, redoCount: redoRecords.count,
            activeTransaction: draft?.token, stagedCommandCount: draft?.commandCount ?? 0)
    }

    public func snapshot() -> DocumentTransactionSnapshot {
        DocumentTransactionSnapshot(evaluatedDocument: committed, status: status())
    }

    public func begin(expectedEpoch: UInt64) throws -> DocumentTransactionToken {
        try Task.checkCancellation()
        try requireEpoch(expectedEpoch)
        guard draft == nil else { throw DocumentTransactionError.transactionAlreadyActive }
        let token = DocumentTransactionToken(sessionID: sessionID, transactionID: UUID(), baseEpoch: epoch)
        draft = Draft(token: token, document: committed.document, commandCount: 0)
        return token
    }

    public func stage(_ commands: [CADCommand], in token: DocumentTransactionToken) throws -> DocumentTransactionPreview {
        try Task.checkCancellation()
        var staged = try requireDraft(token)
        guard !commands.isEmpty else { throw DocumentTransactionError.emptyCommandBatch }
        guard commands.count <= limits.maximumCommandsPerTransaction - staged.commandCount else {
            throw DocumentTransactionError.resourceLimitExceeded("Commands per transaction")
        }
        for command in commands {
            try Task.checkCancellation()
            let next = try editor.apply(command, to: staged.document, tolerance: tolerance)
            guard next.id == committed.document.id else { throw DocumentTransactionError.incompatibleEditorOutput }
            try next.validate(tolerance: tolerance)
            staged.document = next
        }
        try Task.checkCancellation()
        staged.commandCount += commands.count
        draft = staged
        return makePreview(staged)
    }

    public func preview(_ token: DocumentTransactionToken) throws -> DocumentTransactionPreview {
        try Task.checkCancellation()
        return makePreview(try requireDraft(token))
    }

    public func commit(_ token: DocumentTransactionToken) throws -> DocumentTransactionSnapshot {
        try Task.checkCancellation()
        let staged = try requireDraft(token)
        guard staged.commandCount > 0 else { throw DocumentTransactionError.emptyTransaction }
        guard undoRecords.count < limits.maximumHistoryEntries else {
            throw DocumentTransactionError.resourceLimitExceeded("History entries")
        }
        let nextEpoch = try advancedEpoch()
        let evaluated = try Self.evaluate(staged.document, using: evaluator, tolerance: tolerance)
        // Publication has no suspension point; all fallible work precedes these mutations.
        redoRecords.removeAll(keepingCapacity: false)
        undoRecords.append(HistoryRecord(before: committed, after: evaluated))
        committed = evaluated
        epoch = nextEpoch
        draft = nil
        return snapshot()
    }

    public func rollback(_ token: DocumentTransactionToken) throws {
        try Task.checkCancellation()
        _ = try requireDraft(token)
        draft = nil
    }

    public func undo(expectedEpoch: UInt64) throws -> DocumentTransactionSnapshot {
        try Task.checkCancellation()
        try requireHistoryAccess(expectedEpoch)
        guard let record = undoRecords.last else { throw DocumentTransactionError.noUndo }
        let nextEpoch = try advancedEpoch()
        undoRecords.removeLast()
        redoRecords.append(record)
        committed = record.before
        epoch = nextEpoch
        return snapshot()
    }

    public func redo(expectedEpoch: UInt64) throws -> DocumentTransactionSnapshot {
        try Task.checkCancellation()
        try requireHistoryAccess(expectedEpoch)
        guard let record = redoRecords.last else { throw DocumentTransactionError.noRedo }
        let nextEpoch = try advancedEpoch()
        redoRecords.removeLast()
        undoRecords.append(record)
        committed = record.after
        epoch = nextEpoch
        return snapshot()
    }

    private func requireEpoch(_ expected: UInt64) throws {
        guard expected == epoch else { throw DocumentTransactionError.staleEpoch(expected: expected, actual: epoch) }
    }

    private func requireDraft(_ token: DocumentTransactionToken) throws -> Draft {
        guard token.sessionID == sessionID else { throw DocumentTransactionError.foreignToken }
        guard let draft, draft.token == token, token.baseEpoch == epoch else {
            throw DocumentTransactionError.staleTransaction
        }
        return draft
    }

    private func requireHistoryAccess(_ expected: UInt64) throws {
        try requireEpoch(expected)
        guard draft == nil else { throw DocumentTransactionError.activeTransaction }
    }

    private func advancedEpoch() throws -> UInt64 {
        guard epoch < UInt64.max else { throw DocumentTransactionError.resourceLimitExceeded("Session epoch") }
        return epoch + 1
    }

    private func makePreview(_ draft: Draft) -> DocumentTransactionPreview {
        DocumentTransactionPreview(sourceDocument: draft.document, baseEpoch: draft.token.baseEpoch,
            commandCount: draft.commandCount)
    }

    private nonisolated static func evaluate(
        _ document: CADDocument,
        using evaluator: any ExactDocumentEvaluating,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedDocument {
        try Task.checkCancellation()
        try document.validate(tolerance: tolerance)
        let evaluated = try evaluator.evaluateExact(document)
        guard evaluated.document == document, evaluated.configuration.tolerance == tolerance else {
            throw DocumentTransactionError.incompatibleEvaluationOutput
        }
        try Task.checkCancellation()
        return evaluated
    }
}
