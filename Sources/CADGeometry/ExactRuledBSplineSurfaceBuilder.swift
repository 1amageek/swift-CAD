import CADCore

public struct ExactRuledBSplineSurfaceBuilder: RuledBSplineSurfaceBuilding {
    private let basisResolver: any BSplineCurveCommonBasisResolving

    public init(
        basisResolver: any BSplineCurveCommonBasisResolving = DefaultBSplineCurveCommonBasisResolver()
    ) {
        self.basisResolver = basisResolver
    }

    public func build(
        startBoundary: BSplineCurve3D,
        endBoundary: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        let common = try basisResolver.resolve(
            first: startBoundary,
            second: endBoundary,
            tolerance: tolerance
        )
        let surface = BSplineSurface3D(
            uDegree: common.first.degree,
            vDegree: 1,
            uKnots: common.first.knots,
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                common.first.controlPoints,
                common.second.controlPoints,
            ],
            weights: [
                common.first.weights,
                common.second.weights,
            ]
        )
        try surface.validate(tolerance: tolerance)
        return surface
    }
}
