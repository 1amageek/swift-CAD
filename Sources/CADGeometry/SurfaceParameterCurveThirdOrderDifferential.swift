import CADCore

struct SurfaceParameterCurveThirdOrderDifferential: Sendable {
    let parameter: SurfaceParameter
    let firstDerivative: Point2D
    let secondDerivative: Point2D
    let thirdDerivative: Point2D
}
