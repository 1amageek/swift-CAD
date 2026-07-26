import CADCore

struct VerifiedCurveSurfaceTangentIntersectionResolver:
    CurveSurfaceTangentIntersectionResolving
{
    func intersection(
        curve: Curve3D,
        surface: Surface3D,
        parameter: Double,
        options: CurveSurfaceIntersectionOptions,
        iterations: Int,
        tolerance: ModelingTolerance
    ) throws -> CurveSurfaceIntersection? {
        let curveGeometry = try curve.differentialGeometry(
            at: parameter,
            tolerance: tolerance
        )
        let projection = try surface.parameterProjection(
            of: curveGeometry.position,
            tolerance: tolerance
        )
        let rangeResolver = SurfaceParameterRangeResolver()
        guard let surfaceU = rangeResolver.resolvedParameter(
            projection.u,
            domain: surface.uDomain,
            requestedRange: options.surfaceURange,
            tolerance: tolerance
        ), let surfaceV = rangeResolver.resolvedParameter(
            projection.v,
            domain: surface.vDomain,
            requestedRange: options.surfaceVRange,
            tolerance: tolerance
        ) else {
            return nil
        }
        let surfacePoint = try surface.point(
            u: surfaceU,
            v: surfaceV,
            tolerance: tolerance
        )
        let surfaceGeometry = try surface.differentialGeometry(
            atU: surfaceU,
            v: surfaceV,
            tolerance: tolerance
        )
        let residual = max(
            projection.residual,
            (curveGeometry.position - surfacePoint).length
        )
        guard residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "A stationary curve-surface contact failed geometric residual verification."
            )
        }
        let incidence = abs(
            curveGeometry.tangent.dot(surfaceGeometry.normal)
        )
        guard incidence <= tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: incidence,
                tolerance: tolerance,
                message: "A stationary curve-surface root is not a verified tangent contact."
            )
        }
        return try CurveSurfaceIntersection(
            point: curveGeometry.position,
            curveParameter: parameter,
            surfaceU: surfaceU,
            surfaceV: surfaceV,
            kind: .tangent,
            residual: residual,
            iterations: iterations
        )
    }
}
