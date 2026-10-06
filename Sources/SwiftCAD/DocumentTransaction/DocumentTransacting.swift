import CADIR

/// Atomic source editing and publication of complete exact evaluations.
public protocol DocumentTransacting: Sendable {
    func status() async -> DocumentTransactionStatus
    func snapshot() async -> DocumentTransactionSnapshot
    func begin(expectedEpoch: UInt64) async throws -> DocumentTransactionToken
    func stage(_ commands: [CADCommand], in token: DocumentTransactionToken) async throws -> DocumentTransactionPreview
    func preview(_ token: DocumentTransactionToken) async throws -> DocumentTransactionPreview
    func commit(_ token: DocumentTransactionToken) async throws -> DocumentTransactionSnapshot
    func rollback(_ token: DocumentTransactionToken) async throws
    func undo(expectedEpoch: UInt64) async throws -> DocumentTransactionSnapshot
    func redo(expectedEpoch: UInt64) async throws -> DocumentTransactionSnapshot
}
