import CADCore
import CADGeometry

/// Resolves an exact chart-preserving representation that official exchange
/// schemas can encode without changing any face-local pcurve coordinates.
struct ExactExchangeSurfaceRepresentationResolver: Sendable {
    func resolve(
        _ surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Surface3D {
        switch surface {
        case .plane, .cylinder, .analytic, .bSpline:
            return surface
        // FIXME(INCOMPLETE_IMPLEMENTATION): Exact STEP/IGES writers reach this
        // branch for native blends. A certified exchange representation and
        // round-trip geometry verification are required before export succeeds.
        case .procedural(.rollingBall):
            throw exchangeError(
                .unsupportedCapability, tolerance: tolerance,
                "General rolling-ball surfaces have no exact exchange representation."
            )
        // FIXME(INCOMPLETE_IMPLEMENTATION): Exact STEP/IGES publication of original revolutions
        // still needs a standard generator carrier retaining normalized traversal and finite U-domain.
        // The explicit certified policy uses the original native source and publishes its guarantee.
        case .procedural(.originalRevolution), .procedural(.originalCoons), .procedural(.originalAffineWord):
            throw exchangeError(.unsupportedCapability, tolerance: tolerance,
                "Original procedural traversal needs chart-preserving standard transport or explicit certified conversion.")
        // FIXME(INCOMPLETE_IMPLEMENTATION): Exact STEP/IGES has no faithful chart-preserving carrier for these source laws.
        // Production writers must refuse until original surface and pcurve round-trip fidelity are proved.
        case .procedural(.originalAngularTransport), .procedural(.originalBoundaryCorrected),
             .procedural(.originalPlaneDerivative), .procedural(.originalDrafted):
            throw exchangeError(.unsupportedCapability, tolerance: tolerance,
                "This original procedural surface has no chart-preserving standard exchange representation.")
        case let .procedural(.ruled(ruled)):
            let patch = try ExactRectangularBSplineSurfacePatchBuilder().build(
                surface: .procedural(.ruled(ruled)),
                lowerU: 0.0,
                upperU: 1.0,
                lowerV: 0.0,
                upperV: 1.0,
                tolerance: tolerance
            )
            guard patch.uMapping.preservesSourceParameter,
                  patch.vMapping.preservesSourceParameter else {
                throw exchangeError(
                    .topologyFailure,
                    tolerance: tolerance,
                    "A procedural ruled exchange representation changed its face parameterization."
                )
            }
            return .bSpline(patch.surface)
        case .procedural(.offset), .procedural(.originalImage):
            // STEP OFFSET_SURFACE and IGES Type 140 preserve the source UV
            // chart and signed normal distance without materialization.
            return surface
        }
    }

    private func exchangeError(
        _ code: KernelErrorCode,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: .exchange,
            code: code,
            tolerance: tolerance,
            message: message
        )
    }
}
