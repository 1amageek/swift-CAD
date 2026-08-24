import CADCore
import CADGeometry

/// Resolves an exact same-parameter representation that official exchange
/// schemas can encode without changing any face-local pcurve coordinates.
struct ExactExchangeSurfaceRepresentationResolver: Sendable {
    func resolve(
        _ surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Surface3D {
        switch surface {
        case .plane, .cylinder, .analytic, .bSpline:
            return surface
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
        case .procedural(.offset):
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
