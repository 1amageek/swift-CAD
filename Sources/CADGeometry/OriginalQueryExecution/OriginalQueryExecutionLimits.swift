/// Independent query-local ceilings; work and bytes belong to the shared budget.
public struct OriginalQueryExecutionLimits: Equatable, Sendable {
    public let maximumValueDepth: Int
    public let maximumCoefficientDepth: Int
    public let maximumCells: Int
    public let maximumCharts: Int
    public let maximumFamilies: Int
    public let maximumResults: Int
    public let remainingSourceDepth: Int
    public let maximumTransportDepth: Int
    public let maximumSubdivisionDepth: Int
    public let maximumSpans: Int
    public let maximumNativeSpans: Int?
    public let maximumPolynomialDegree: Int
    public var maximumGeometricDepth: Int { maximumSubdivisionDepth }
    public let maximumScalarSlots: Int

    public init(maximumValueDepth: Int, maximumCoefficientDepth: Int,
        maximumCells: Int = Int.max, maximumCharts: Int = Int.max,
        maximumFamilies: Int = Int.max, maximumResults: Int = Int.max,
        remainingSourceDepth: Int = Int.max, maximumTransportDepth: Int = Int.max,
        maximumSubdivisionDepth: Int = Int.max, maximumSpans: Int = Int.max,
        maximumPolynomialDegree: Int = Int.max, maximumScalarSlots: Int = Int.max,
        maximumNativeSpans: Int? = nil) throws(ExactScalarFailure) {
        guard maximumValueDepth >= 0, maximumCoefficientDepth >= 0,
            maximumCells >= 0, maximumCharts >= 0, maximumFamilies >= 0,
            maximumResults >= 0, remainingSourceDepth >= 0, maximumTransportDepth >= 0,
            maximumSubdivisionDepth >= 0, maximumSpans >= 0,
            maximumPolynomialDegree >= 0, maximumScalarSlots >= 0,
            maximumNativeSpans.map({ $0 >= 0 }) ?? true else { throw .invalidSource }
        self.maximumValueDepth = maximumValueDepth
        self.maximumCoefficientDepth = maximumCoefficientDepth
        self.maximumCells = maximumCells; self.maximumCharts = maximumCharts
        self.maximumFamilies = maximumFamilies; self.maximumResults = maximumResults
        self.remainingSourceDepth = remainingSourceDepth
        self.maximumTransportDepth = maximumTransportDepth
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumSpans = maximumSpans; self.maximumNativeSpans = maximumNativeSpans
        self.maximumPolynomialDegree = maximumPolynomialDegree
        self.maximumScalarSlots = maximumScalarSlots
    }
    public func intersecting(_ other: Self) -> Self { Self(intersecting: self, other) }
    private init(intersecting first: Self, _ second: Self) {
        self.maximumValueDepth = min(first.maximumValueDepth, second.maximumValueDepth)
        self.maximumCoefficientDepth = min(first.maximumCoefficientDepth, second.maximumCoefficientDepth)
        self.maximumCells = min(first.maximumCells, second.maximumCells)
        self.maximumCharts = min(first.maximumCharts, second.maximumCharts)
        self.maximumFamilies = min(first.maximumFamilies, second.maximumFamilies)
        self.maximumResults = min(first.maximumResults, second.maximumResults)
        self.remainingSourceDepth = min(first.remainingSourceDepth, second.remainingSourceDepth)
        self.maximumTransportDepth = min(first.maximumTransportDepth, second.maximumTransportDepth)
        self.maximumSubdivisionDepth = min(first.maximumSubdivisionDepth, second.maximumSubdivisionDepth)
        self.maximumSpans = min(first.maximumSpans, second.maximumSpans)
        self.maximumPolynomialDegree = min(first.maximumPolynomialDegree, second.maximumPolynomialDegree)
        self.maximumScalarSlots = min(first.maximumScalarSlots, second.maximumScalarSlots)
        self.maximumNativeSpans = min(first.maximumNativeSpans ?? first.maximumSpans,
            second.maximumNativeSpans ?? second.maximumSpans)
    }
}
