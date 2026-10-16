/// Root-owned secondary admission for actual numeric allocations.
public enum OriginalQueryAllocationPolicy: Sendable {
    case none
    /// Each rounded UInt32 payload word debits both work and source records.
    case uint32Words
    /// Each UInt32 payload word debits work without source records.
    case uint32WordWork
    /// Each payload byte also debits work.
    case bytes
}
