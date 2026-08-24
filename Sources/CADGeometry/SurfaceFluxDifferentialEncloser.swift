import CADCore

/// A certified enclosure of the divergence-theorem surface-flux integrand.
package struct SurfaceFluxDifferentialEnclosure: Sendable, Hashable {
    package let value: ScalarInterval
    package let firstDerivativeU: ScalarInterval
    package let firstDerivativeV: ScalarInterval
    package let secondDerivativeUU: ScalarInterval
    package let secondDerivativeUV: ScalarInterval
    package let secondDerivativeVV: ScalarInterval
}

/// Keeps differential geometry certification inside CADGeometry while callers
/// retain ownership of trim integration and face orientation.
package struct SurfaceFluxDifferentialEncloser: Sendable {
    package init() {}

    package func enclosure(
        of surface: Surface3D,
        over parameters: SurfaceParameterBox,
        relativeTo reference: Point3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceFluxDifferentialEnclosure {
        let surfaceJet = try DefaultSurfaceDifferentialEncloser().intervalJet(
            of: surface,
            over: parameters,
            tolerance: tolerance
        )
        let relativePosition = surfaceJet
            + (-SurfaceIntervalVectorJet.constant(reference))
        let tangentU = surfaceJet.differentiatedUThroughSecondOrder()
        let tangentV = surfaceJet.differentiatedVThroughSecondOrder()
        let flux = relativePosition.dot(tangentU.cross(tangentV))
            * .constant(1.0 / 3.0)
        return SurfaceFluxDifferentialEnclosure(
            value: try scalarInterval(
                flux.value,
                tolerance: tolerance
            ),
            firstDerivativeU: try scalarInterval(
                flux.derivativeU,
                tolerance: tolerance
            ),
            firstDerivativeV: try scalarInterval(
                flux.derivativeV,
                tolerance: tolerance
            ),
            secondDerivativeUU: try scalarInterval(
                flux.secondDerivativeUU,
                tolerance: tolerance
            ),
            secondDerivativeUV: try scalarInterval(
                flux.secondDerivativeUV,
                tolerance: tolerance
            ),
            secondDerivativeVV: try scalarInterval(
                flux.secondDerivativeVV,
                tolerance: tolerance
            )
        )
    }

    private func scalarInterval(
        _ interval: OutwardScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        guard interval.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Surface-flux differential certification exceeded finite interval arithmetic."
            )
        }
        return try ScalarInterval(
            lower: interval.lower,
            upper: interval.upper
        )
    }
}
