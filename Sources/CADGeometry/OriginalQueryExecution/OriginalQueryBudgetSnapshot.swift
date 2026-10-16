/// Internally observed cumulative admission, distinct from an external ledger.
public struct OriginalQueryBudgetSnapshot: Sendable {
    public let work: Int
    public let storageBytes: Int
    public let cellVisits: Int
    public let records: Int
    public let sourceTextBytes: Int

    init(work: Int, storageBytes: Int, cellVisits: Int, records: Int, sourceTextBytes: Int = 0) {
        self.work = work; self.storageBytes = storageBytes; self.cellVisits = cellVisits
        self.records = records; self.sourceTextBytes = sourceTextBytes
    }
}
