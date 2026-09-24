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
        if hasLinearConnectorParameterization(uMinimumBoundary),
           hasLinearConnectorParameterization(uMaximumBoundary) {
            let surface = try ruledBuilder.build(
                startBoundary: vMinimumBoundary,
                endBoundary: vMaximumBoundary,
                tolerance: tolerance
            )
            try BSplineSurfaceRegularityValidator().validate(surface,
                uDomain: surface.uDomain, vDomain: surface.vDomain, tolerance: tolerance)
            try BSplineSurfaceEmbeddingValidator().validate(surface,
                uDomain: surface.uDomain, vDomain: surface.vDomain, tolerance: tolerance)
            return surface
        }

        return try transfiniteBuilder.build(
            vMinimumBoundary: vMinimumBoundary,
            vMaximumBoundary: vMaximumBoundary,
            uMinimumBoundary: uMinimumBoundary,
            uMaximumBoundary: uMaximumBoundary,
            tolerance: tolerance
        )
    }

    private func hasLinearConnectorParameterization(_ curve: BSplineCurve3D) -> Bool {
        curve.degree == 1
            && curve.controlPointCount == 2
            && curve.weights.allSatisfy { $0 == 1.0 }
    }
}
