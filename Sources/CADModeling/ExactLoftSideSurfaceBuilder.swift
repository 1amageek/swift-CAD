import CADCore
import CADGeometry

package struct ExactLoftSideSurfaceBuilder: Sendable {
    private let ruledBuilder: any RuledBSplineSurfaceBuilding
    private let transfiniteBuilder: any TransfiniteBSplineSurfaceBuilding

    package init(
        ruledBuilder: any RuledBSplineSurfaceBuilding = ExactRuledBSplineSurfaceBuilder(),
        transfiniteBuilder: any TransfiniteBSplineSurfaceBuilding = ExactCoonsBSplineSurfaceBuilder()
    ) {
        self.ruledBuilder = ruledBuilder
        self.transfiniteBuilder = transfiniteBuilder
    }

    package func build(
        vMinimumBoundary: BSplineCurve3D,
        vMaximumBoundary: BSplineCurve3D,
        uMinimumBoundary: BSplineCurve3D,
        uMaximumBoundary: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        try tolerance.validate()
        let surface: BSplineSurface3D
        if hasLinearConnectorParameterization(uMinimumBoundary),
           hasLinearConnectorParameterization(uMaximumBoundary) {
            surface = try ruledBuilder.build(
                startBoundary: vMinimumBoundary,
                endBoundary: vMaximumBoundary,
                tolerance: tolerance
            )
        } else {
            surface = try transfiniteBuilder.build(
                vMinimumBoundary: vMinimumBoundary,
                vMaximumBoundary: vMaximumBoundary,
                uMinimumBoundary: uMinimumBoundary,
                uMaximumBoundary: uMaximumBoundary,
                tolerance: tolerance
            )
        }
        return try validated(surface, tolerance: tolerance)
    }

    /// The Hermite side between two section spans of one basis and one set of weights: in v a
    /// Bézier of `degree` 3 or 5 leaving `start` with the derivative rows `startDerivatives` and
    /// arriving at `end` with `endDerivatives`, one per control point. A quintic's second rows
    /// continue its first, so its second derivative at both ends vanishes.
    package func buildHermite(
        start: BSplineCurve3D,
        startDerivatives: [Vector3D],
        end: BSplineCurve3D,
        endDerivatives: [Vector3D],
        degree: Int,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        try tolerance.validate()
        guard degree == 3 || degree == 5, start.degree == end.degree, start.knots == end.knots,
              start.weights == end.weights, start.controlPoints.count == end.controlPoints.count,
              startDerivatives.count == start.controlPoints.count, endDerivatives.count == end.controlPoints.count else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A Hermite Loft side needs two spans of one basis with a derivative per control point.")
        }
        let steps = degree == 3 ? [0.0, 1.0 / 3] : [0.0, 1.0 / 5, 2.0 / 5]
        let leading = steps.map { step in zip(start.controlPoints, startDerivatives).map { $0 + $1 * step } }
        let trailing = steps.reversed().map { step in zip(end.controlPoints, endDerivatives).map { $0 + $1 * -step } }
        let rows = leading + trailing
        let surface = BSplineSurface3D(
            uDegree: start.degree, vDegree: degree, uKnots: start.knots,
            vKnots: Array(repeating: 0.0, count: degree + 1) + Array(repeating: 1.0, count: degree + 1),
            controlPoints: rows, weights: Array(repeating: start.weights, count: rows.count)
        )
        return try validated(surface, tolerance: tolerance)
    }

    private func validated(_ surface: BSplineSurface3D, tolerance: ModelingTolerance) throws -> BSplineSurface3D {
        // The returned tensor chart is a construction map. The body builder
        // publishes the certified planar support for a collinear corner.
        if try BSplineSurfaceEmbeddingValidator.stationaryPlanarSupport(for: surface, tolerance: tolerance) == nil {
            try BSplineSurfaceRegularityValidator().validate(surface,
                uDomain: surface.uDomain, vDomain: surface.vDomain, tolerance: tolerance,
                allowStationaryBoundaryParameterization: true)
        }
        try BSplineSurfaceEmbeddingValidator().validate(surface,
            uDomain: surface.uDomain, vDomain: surface.vDomain, tolerance: tolerance,
            allowStationaryBoundaryParameterization: true)
        return surface
    }

    private func hasLinearConnectorParameterization(_ curve: BSplineCurve3D) -> Bool {
        curve.degree == 1
            && curve.controlPointCount == 2
            && curve.weights.allSatisfy { $0 == 1.0 }
    }
}
