import CADCore

struct SurfaceParameterSecondDerivativeSolver {
    func solve(
        surface: Surface3D.DifferentialGeometry,
        firstParameterDerivative: Point2D,
        spatialSecondDerivative: Vector3D,
        tolerance: ModelingTolerance,
        diagnosticContext: String
    ) throws -> Point2D {
        let tangentU = surface.tangentU
        let tangentV = surface.tangentV
        let metricUU = tangentU.dot(tangentU)
        let metricUV = tangentU.dot(tangentV)
        let metricVV = tangentV.dot(tangentV)
        let determinant = metricUU * metricVV - metricUV * metricUV
        let metricScale = max(metricUU * metricVV, Double.leastNonzeroMagnitude)
        let determinantFloor = max(
            tolerance.relative * tolerance.relative,
            Double.ulpOfOne * 1_024.0
        ) * metricScale
        guard determinant.isFinite, determinant > determinantFloor else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "\(diagnosticContext) second derivative is singular."
            )
        }
        let firstU = firstParameterDerivative.x
        let firstV = firstParameterDerivative.y
        let quadratic = surface.secondDerivativeUU * (firstU * firstU)
            + surface.secondDerivativeUV * (2.0 * firstU * firstV)
            + surface.secondDerivativeVV * (firstV * firstV)
        let right = spatialSecondDerivative - quadratic
        let rightU = tangentU.dot(right)
        let rightV = tangentV.dot(right)
        let secondU = (rightU * metricVV - rightV * metricUV) / determinant
        let secondV = (rightV * metricUU - rightU * metricUV) / determinant
        let reconstructed = tangentU * secondU + tangentV * secondV + quadratic
        let residual = (reconstructed - spatialSecondDerivative).length
        let scale = max(spatialSecondDerivative.length, quadratic.length, 1.0)
        guard residual <= tolerance.relative * scale else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual / scale,
                tolerance: tolerance,
                message: "\(diagnosticContext) failed second-derivative reconstruction."
            )
        }
        return Point2D(x: secondU, y: secondV)
    }
}
