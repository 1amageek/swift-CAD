import CADCore

public protocol NativeCurveCurveContactClassifying: Sendable {
    func contacts(first: BSplineCurve3D, second: BSplineCurve3D,
                  tolerance: ModelingTolerance) throws -> NativeCurveCurveContactClassification
}
