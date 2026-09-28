import CADCore

/// The kernel adapter for the shared polynomial continuation implementation.
public struct CubicBezierChainExtension: Sendable {
    public typealias End = NaturalBezierContinuation.End
    public let tolerance: ModelingTolerance
    public init(tolerance: ModelingTolerance) { self.tolerance = tolerance }

    public func naturalSpan(of controlPoints: [Point2D], at end: End, length: Double) throws -> [Point2D] {
        try NaturalBezierContinuation(tolerance: tolerance).naturalSpan(of: controlPoints, at: end, length: length)
    }

    public func naturalSpan(ofSegment segment: [Point2D], at end: End, length: Double) throws -> [Point2D] {
        try NaturalBezierContinuation(tolerance: tolerance).naturalSpan(ofSegment: segment, at: end, length: length)
    }
}
