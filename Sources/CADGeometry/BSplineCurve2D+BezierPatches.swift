import CADCore

public extension BSplineCurve2D {
    func rationalBezierPatches(
        tolerance: ModelingTolerance
    ) throws -> [RationalBezierCurvePatch2D] {
        let lifted = BSplineCurve3D(
            degree: degree,
            knots: knots,
            controlPoints: controlPoints.map {
                Point3D(x: $0.x, y: $0.y, z: 0.0)
            },
            weights: weights
        )
        return try BSplineCurveBezierDecomposer().curvePatches(
            curve: lifted,
            tolerance: tolerance
        ).map { patch in
            RationalBezierCurvePatch2D(
                controlPoints: patch.controlPoints.map {
                    Point2D(x: $0.x, y: $0.y)
                },
                weights: patch.weights,
                lower: patch.lower,
                upper: patch.upper
            )
        }
    }
}
