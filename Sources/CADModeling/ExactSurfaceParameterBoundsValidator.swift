import CADCore
import CADGeometry

package struct ExactSurfaceParameterBoundsValidator {
    package init() {}

    package func validate(
        _ bounds: RectangularSurfaceParameterBounds,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try surface.validate(tolerance: tolerance)
        let scale = max(
            abs(bounds.lowerU),
            abs(bounds.upperU),
            abs(bounds.lowerV),
            abs(bounds.upperV),
            1.0
        )
        let parameterTolerance = max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 256.0
        )
        guard bounds.lowerU.isFinite,
              bounds.upperU.isFinite,
              bounds.lowerV.isFinite,
              bounds.upperV.isFinite,
              bounds.upperU - bounds.lowerU > parameterTolerance,
              bounds.upperV - bounds.lowerV > parameterTolerance,
              try surface.uDomain.containsSpan(
                  from: bounds.lowerU,
                  to: bounds.upperU,
                  tolerance: tolerance
              ),
              try surface.vDomain.containsSpan(
                  from: bounds.lowerV,
                  to: bounds.upperV,
                  tolerance: tolerance
              ) else {
            throw KernelError(
                phase: .evaluation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Surface parameter bounds must be finite, non-degenerate, and contained in the exact surface domain."
            )
        }
        try validatePeriodicSpan(
            bounds.upperU - bounds.lowerU,
            domain: surface.uDomain,
            tolerance: tolerance
        )
        try validatePeriodicSpan(
            bounds.upperV - bounds.lowerV,
            domain: surface.vDomain,
            tolerance: tolerance
        )
        switch surface {
        case let .bSpline(spline):
            try BSplineSurfaceRegularityValidator().validate(
                spline,
                uDomain: .closed(bounds.lowerU, bounds.upperU),
                vDomain: .closed(bounds.lowerV, bounds.upperV),
                tolerance: tolerance
            )
            try BSplineSurfaceEmbeddingValidator().validate(
                spline,
                uDomain: .closed(bounds.lowerU, bounds.upperU),
                vDomain: .closed(bounds.lowerV, bounds.upperV),
                tolerance: tolerance
            )
        case .analytic(.sphere):
            let pole = Double.pi * 0.5
            guard bounds.lowerV > -pole + tolerance.angle,
                  bounds.upperV < pole - tolerance.angle else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularGeometry,
                    tolerance: tolerance,
                    message: "A rectangular surface domain must not include a spherical parameter pole."
                )
            }
        case .analytic(.cone):
            guard bounds.lowerV > tolerance.distance
                    || bounds.upperV < -tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularGeometry,
                    tolerance: tolerance,
                    message: "A rectangular surface domain must not include the cone apex."
                )
            }
        case .plane,
             .cylinder,
             .analytic(.plane),
             .analytic(.cylinder),
             .analytic(.torus):
            break
        case .procedural:
            try DefaultSurfaceRegularityValidator().validate(
                surface,
                over: SurfaceParameterBox(
                    u: try ScalarInterval(
                        lower: bounds.lowerU,
                        upper: bounds.upperU
                    ),
                    v: try ScalarInterval(
                        lower: bounds.lowerV,
                        upper: bounds.upperV
                    )
                ),
                tolerance: tolerance
            )
        }
    }

    private func validatePeriodicSpan(
        _ span: Double,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws {
        guard case let .periodic(period) = domain else { return }
        guard span < period - max(
            tolerance.angle,
            tolerance.relative * period
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                tolerance: tolerance,
                message: "A rectangular surface boundary must not collapse across a complete periodic domain."
            )
        }
    }
}
