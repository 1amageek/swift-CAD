@main
struct A2DocumentTransactionSmoke {
    static func main() async throws {
        try await DocumentTransactionProof.run()
        print("A2_DOCUMENT_TRANSACTION_OK source attributes parameters references dependencies geometry identity history batch rollback stale foreign concurrency resource cancellation")
    }
}
