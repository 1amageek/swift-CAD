import CADCore

struct SurfaceParameterThirdDerivativeSolver {
    func solve(
        surface: SurfaceParameterThirdOrderDerivatives,
        firstParameterDerivative: Point2D,
        secondParameterDerivative: Point2D,
        spatialThirdDerivative: Vector3D,
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
                message: "\(diagnosticContext) third derivative is singular."
            )
        }

        let knownTerms = SurfaceParameterThirdOrderChainRule.thirdDerivative(
            surface: surface,
            firstParameterDerivative: firstParameterDerivative,
            secondParameterDerivative: secondParameterDerivative,
            thirdParameterDerivative: Point2D(x: 0.0, y: 0.0)
        )
        let right = spatialThirdDerivative - knownTerms
        let rightU = tangentU.dot(right)
        let rightV = tangentV.dot(right)
        let thirdU = (rightU * metricVV - rightV * metricUV) / determinant
        let thirdV = (rightV * metricUU - rightU * metricUV) / determinant
        let reconstructed = tangentU * thirdU
            + tangentV * thirdV
            + knownTerms
        let residual = (reconstructed - spatialThirdDerivative).length
        let scale = max(spatialThirdDerivative.length, knownTerms.length, 1.0)
        guard thirdU.isFinite,
              thirdV.isFinite,
              residual <= tolerance.relative * scale else {
            throw KernelError(
                phase: .geometry,
                code: thirdU.isFinite && thirdV.isFinite
                    ? .intersectionFailure
                    : .resourceLimitExceeded,
                residual: residual.isFinite ? residual / scale : nil,
                tolerance: tolerance,
                message: "\(diagnosticContext) failed third-derivative reconstruction."
            )
        }
        return Point2D(x: thirdU, y: thirdV)
    }
}
