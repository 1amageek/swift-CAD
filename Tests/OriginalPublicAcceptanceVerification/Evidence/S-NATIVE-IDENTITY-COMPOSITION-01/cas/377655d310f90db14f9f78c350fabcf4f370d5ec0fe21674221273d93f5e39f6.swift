/// Cumulative source traversal costs, including admitted canonical scratch values.
public struct PortableSourceEncodingMeasurement: Sendable, Equatable {
    public let consumedBytes: Int
    public let consumedWork: Int

    init(consumedBytes: Int, consumedWork: Int) {
        self.consumedBytes = consumedBytes
        self.consumedWork = consumedWork
    }
}
