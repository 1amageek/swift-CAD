import CADCore

public protocol BSplineCurveCommonBasisResolving: Sendable {
    func resolve(
        first: BSplineCurve3D,
        second: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurveCommonBasisPair
}
