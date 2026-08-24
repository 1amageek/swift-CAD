import CADCore

struct SurfaceParameterFirstDerivativeSolver {
    func solve(
        tangentU: Vector3D,
        tangentV: Vector3D,
        spatialFirstDerivative: Vector3D,
        tolerance: ModelingTolerance,
        diagnosticContext: String
    ) throws -> Point2D {
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
                message: "\(diagnosticContext) first derivative is singular."
            )
        }
        let rightU = tangentU.dot(spatialFirstDerivative)
        let rightV = tangentV.dot(spatialFirstDerivative)
        let derivativeU = (rightU * metricVV - rightV * metricUV) / determinant
        let derivativeV = (rightV * metricUU - rightU * metricUV) / determinant
        let reconstructed = tangentU * derivativeU + tangentV * derivativeV
        let residual = (reconstructed - spatialFirstDerivative).length
        let scale = max(spatialFirstDerivative.length, 1.0)
        guard derivativeU.isFinite,
              derivativeV.isFinite,
              residual <= tolerance.relative * scale else {
            throw KernelError(
                phase: .geometry,
                code: derivativeU.isFinite && derivativeV.isFinite
                    ? .intersectionFailure
                    : .resourceLimitExceeded,
                residual: residual.isFinite ? residual / scale : nil,
                tolerance: tolerance,
                message: "\(diagnosticContext) failed first-derivative reconstruction."
            )
        }
        return Point2D(x: derivativeU, y: derivativeV)
    }
}
