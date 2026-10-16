#if !hasFeature(Embedded)
/// One atomic view of the decoder root's common admission counters.
public struct NativeRationalSourceDecodingSnapshot: Equatable, Sendable {
    public let maximumWork: Int
    public let maximumCells: Int
    public let maximumStorage: Int
    public let maximumDepth: Int
    public let work: Int
    public let cells: Int
    public let storage: Int
    public var remainingWork: Int { maximumWork - work }
    public var remainingCells: Int { maximumCells - cells }
    public var remainingStorage: Int { maximumStorage - storage }
}
#endif
