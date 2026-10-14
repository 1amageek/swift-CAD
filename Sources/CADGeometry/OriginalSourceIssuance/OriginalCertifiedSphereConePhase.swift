import CADCore

/// Source-owned auxiliary phase for the exact plane-contact preimage.
public struct OriginalCertifiedSphereConePhase: OriginalAnalyticCoordinateReading {
    public let original: CertifiedSphereConeIntersectionCurve
    let end: ExactRationalCoefficient
    public var coordinateKind: OriginalAnalyticCoordinateKind { .circle }
    public var firstMagnitude: Double { 1 }
    public var secondMagnitude: Double { 1 }
    public var coneHalfAngle: Double { 0 }
    public func center(in axis: Int) -> Double { 0 }
    public func frame(row: Int, column: Int) -> Double {
        if column == 0 { return row == 1 ? 1 : 0 }
        if column == 1 { return row == 0 ? -1 : 0 }
        return row == 2 ? 1 : 0
    }
    public func angularMap(axis: Int) -> OriginalSourceAngularMap {
        original.componentKind == .boundedAngularInterval
            ? .physicalRadianArc(start: .zero, end: .zero, additionalTurns: 1)
            : .physicalRadianArc(start: .zero, end: end, additionalTurns: 0)
    }
    public func finiteLowerBound(axis: Int) -> Double? { axis == 0 ? 0 : nil }
    public func finiteUpperBound(axis: Int) -> Double? { axis == 0 ? 1 : nil }
    init(original: CertifiedSphereConeIntersectionCurve, end: ExactRationalCoefficient) {
        self.original = original; self.end = end
    }
}
