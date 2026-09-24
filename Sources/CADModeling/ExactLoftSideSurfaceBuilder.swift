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
