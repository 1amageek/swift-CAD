import CADCore
import CADGeometry
import CADTopology

package struct ExactSurfaceParameterBoundsResolver {
    package init() {}

    package func resolve(
        parameterCurves: [SurfaceParameterCurve],
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterBox {
        guard parameterCurves.isEmpty == false else {
            throw failure(
                .topologyFailure,
                tolerance: tolerance,
                message: "An exact face parameter domain requires at least one boundary pcurve."
            )
        }
        var lowerU = Double.infinity
        var upperU = -Double.infinity
        var lowerV = Double.infinity
        var upperV = -Double.infinity
        let encloser = CertifiedSurfaceParameterCurveEncloser()
        for curve in parameterCurves {
            for enclosure in try encloser.enclosures(
                for: curve,
                maximumWidth: 0.25,
                tolerance: tolerance
            ) {
                lowerU = min(lowerU, enclosure.u.lower)
                upperU = max(upperU, enclosure.u.upper)
                lowerV = min(lowerV, enclosure.v.lower)
                upperV = max(upperV, enclosure.v.upper)
            }
        }
        let uBounds = try clippedBounds(
            lower: lowerU,
            upper: upperU,
            domain: surface.uDomain,
            tolerance: tolerance
        )
        let vBounds = try clippedBounds(
            lower: lowerV,
            upper: upperV,
            domain: surface.vDomain,
            tolerance: tolerance
        )
        return SurfaceParameterBox(
            u: try ScalarInterval(lower: uBounds.lower, upper: uBounds.upper),
            v: try ScalarInterval(lower: vBounds.lower, upper: vBounds.upper)
        )
    }

    private func clippedBounds(
        lower: Double,
        upper: Double,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> (lower: Double, upper: Double) {
        var resolvedLower = lower
        var resolvedUpper = upper
        if case let .closed(domainLower, domainUpper) = domain {
            resolvedLower = max(resolvedLower, domainLower)
            resolvedUpper = min(resolvedUpper, domainUpper)
        }
        let scale = max(abs(resolvedLower), abs(resolvedUpper), 1.0)
        guard resolvedLower.isFinite,
              resolvedUpper.isFinite,
              resolvedUpper - resolvedLower > max(
                  tolerance.relative * scale,
                  Double.ulpOfOne * scale * 256.0
              ) else {
            throw failure(
                .singularGeometry,
                tolerance: tolerance,
                message: "The exact face boundary does not certify a finite non-degenerate parameter domain."
            )
        }
        return (resolvedLower, resolvedUpper)
    }

    private func failure(
        _ code: KernelErrorCode,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure ? .topology : .geometry,
            code: code,
            tolerance: tolerance,
            message: message
        )
    }
}
