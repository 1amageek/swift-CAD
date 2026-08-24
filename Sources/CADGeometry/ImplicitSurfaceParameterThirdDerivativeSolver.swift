import CADCore

struct ImplicitSurfaceParameterThirdDerivativeSolver {
    enum SolvedCoordinate: Sendable {
        case u
        case v
    }

    func solve(
        surface: SurfaceParameterThirdOrderDerivatives,
        firstParameterDerivative first: Point2D,
        secondParameterDerivative second: Point2D,
        knownThirdParameterDerivative knownThird: Point2D,
        solvedCoordinate: SolvedCoordinate,
        implicitGradient: Vector3D,
        implicitHessian: (Vector3D, Vector3D) -> Double,
        implicitThirdDifferential: (Vector3D, Vector3D, Vector3D) -> Double,
        tolerance: ModelingTolerance,
        diagnosticContext: String
    ) throws -> Point2D {
        let solvedTangent: Vector3D
        switch solvedCoordinate {
        case .u:
            solvedTangent = surface.tangentU
        case .v:
            solvedTangent = surface.tangentV
        }
        let denominator = implicitGradient.dot(solvedTangent)
        let scale = max(
            implicitGradient.length * solvedTangent.length,
            Double.leastNonzeroMagnitude
        )
        let denominatorFloor = max(
            tolerance.relative,
            Double.ulpOfOne * 1_024.0
        ) * scale
        guard denominator.isFinite, abs(denominator) > denominatorFloor else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: abs(denominator) / scale,
                tolerance: tolerance,
                message: "\(diagnosticContext) third derivative reached an implicit-coordinate singularity."
            )
        }

        let spatialFirst = SurfaceParameterThirdOrderChainRule.firstDerivative(
            surface: surface,
            parameter: first
        )
        let spatialSecond = SurfaceParameterThirdOrderChainRule.secondDerivative(
            surface: surface,
            firstParameterDerivative: first,
            secondParameterDerivative: second
        )
        let knownSpatialThird = SurfaceParameterThirdOrderChainRule.thirdDerivative(
            surface: surface,
            firstParameterDerivative: first,
            secondParameterDerivative: second,
            thirdParameterDerivative: knownThird
        )
        let knownImplicitThird = implicitGradient.dot(knownSpatialThird)
            + 3.0 * implicitHessian(spatialSecond, spatialFirst)
            + implicitThirdDifferential(
                spatialFirst,
                spatialFirst,
                spatialFirst
            )
        let solvedValue = -knownImplicitThird / denominator
        var result = knownThird
        switch solvedCoordinate {
        case .u:
            result = Point2D(x: solvedValue, y: knownThird.y)
        case .v:
            result = Point2D(x: knownThird.x, y: solvedValue)
        }
        let residual = knownImplicitThird + denominator * solvedValue
        let residualScale = max(abs(knownImplicitThird), abs(denominator * solvedValue), 1.0)
        guard solvedValue.isFinite,
              residual.isFinite,
              abs(residual) <= tolerance.relative * residualScale else {
            throw KernelError(
                phase: .geometry,
                code: solvedValue.isFinite
                    ? .intersectionFailure
                    : .resourceLimitExceeded,
                residual: residual.isFinite ? abs(residual) / residualScale : nil,
                tolerance: tolerance,
                message: "\(diagnosticContext) failed implicit third-derivative reconstruction."
            )
        }
        return result
    }
}
