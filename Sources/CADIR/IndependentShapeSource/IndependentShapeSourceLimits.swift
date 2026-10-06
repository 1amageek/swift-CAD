/// Source graph ceilings; standard exchange callers forward their remaining ceilings.
public struct IndependentShapeSourceLimits: Equatable, Sendable {
    public let maximumRecords: Int
    public let maximumTextBytes: Int
    public let maximumDepth: Int
    public let maximumAlgebraicDepth: Int
    public let maximumCurveSubdivisionDepth: Int
    public let maximumWork: Int
    public init(maximumRecords: Int = 1_000_000, maximumTextBytes: Int = 64 * 1024 * 1024, maximumDepth: Int = 256, maximumWork: Int = 10_000_000, maximumCurveSubdivisionDepth: Int = 32, maximumAlgebraicDepth: Int = 32) {
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
        self.maximumCurveSubdivisionDepth = maximumCurveSubdivisionDepth
        self.maximumRecords = maximumRecords; self.maximumTextBytes = maximumTextBytes
        self.maximumDepth = maximumDepth; self.maximumWork = maximumWork
    }
    public static let standard = Self()
    public func validate() throws {
        guard maximumRecords > 0, maximumTextBytes >= 0, maximumDepth > 0, maximumWork > 0, maximumCurveSubdivisionDepth >= 0, maximumCurveSubdivisionDepth <= 32, maximumAlgebraicDepth >= 0, maximumAlgebraicDepth <= 32 else {
            throw IndependentShapeSourceError.invalidSource("Independent source limits must have positive records/source depth/work, nonnegative text bytes, and a curve subdivision ceiling in 0...32.")
        }
    }
}

#if !hasFeature(Embedded)
extension IndependentShapeSourceLimits: Codable {}
#endif
