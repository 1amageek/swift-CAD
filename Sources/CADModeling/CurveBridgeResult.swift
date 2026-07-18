import CADGeometry
import CADIR

/// The exact bridge curve and independently verified endpoint continuity.
public struct CurveBridgeResult: Codable, Sendable, Hashable {
    public var curve: BSplineCurve3D
    public var startContinuity: CurveContinuityResult
    public var endContinuity: CurveContinuityResult

    public init(
        curve: BSplineCurve3D,
        startContinuity: CurveContinuityResult,
        endContinuity: CurveContinuityResult
    ) {
        self.curve = curve
        self.startContinuity = startContinuity
        self.endContinuity = endContinuity
    }
}
