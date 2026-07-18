import CADCore

public struct EvaluatedCurvePathSegment: Sendable, Hashable {
    public var curve: EvaluatedCurve
    public var isReversed: Bool

    public init(curve: EvaluatedCurve, isReversed: Bool = false) {
        self.curve = curve
        self.isReversed = isReversed
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try curve.validate(tolerance: tolerance)
    }
}
