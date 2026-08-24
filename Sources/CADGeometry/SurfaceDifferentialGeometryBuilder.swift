import CADCore
import Foundation

struct SurfaceDifferentialGeometryBuilder: Sendable {
    func differentialGeometry(
        derivatives: SurfaceParameterDerivatives,
        tolerance: ModelingTolerance
    ) throws -> Surface3D.DifferentialGeometry {
        let tangentU = derivatives.tangentU
        let tangentV = derivatives.tangentV
        let normal = try regularNormal(
            tangentU: tangentU,
            tangentV: tangentV,
            tolerance: tolerance
        )
        let firstE = tangentU.dot(tangentU)
        let firstF = tangentU.dot(tangentV)
        let firstG = tangentV.dot(tangentV)
        let firstDeterminant = firstE * firstG - firstF * firstF
        let normalizedDeterminant = firstE > 0.0 && firstG > 0.0
            ? max(0.0, firstDeterminant / (firstE * firstG))
            : 0.0
        let angularMetricTolerance = max(
            sin(min(tolerance.angle, Double.pi * 0.5))
                * sin(min(tolerance.angle, Double.pi * 0.5)),
            tolerance.relative * tolerance.relative,
            Double.ulpOfOne * 512.0
        )
        guard firstDeterminant.isFinite,
              normalizedDeterminant > angularMetricTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: normalizedDeterminant,
                tolerance: tolerance,
                message: "Procedural surface differential geometry is singular at the requested parameter."
            )
        }

        let secondL = derivatives.secondDerivativeUU.dot(normal)
        let secondM = derivatives.secondDerivativeUV.dot(normal)
        let secondN = derivatives.secondDerivativeVV.dot(normal)
        let meanCurvature = (
            firstE * secondN - 2.0 * firstF * secondM + firstG * secondL
        ) / (2.0 * firstDeterminant)
        let gaussianCurvature = (
            secondL * secondN - secondM * secondM
        ) / firstDeterminant
        let normalCurvatureU = secondL / firstE
        let normalCurvatureV = secondN / firstG
        guard meanCurvature.isFinite,
              gaussianCurvature.isFinite,
              normalCurvatureU.isFinite,
              normalCurvatureV.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Procedural surface curvature exceeded the finite numeric range."
            )
        }
        let discriminant = max(
            meanCurvature * meanCurvature - gaussianCurvature,
            0.0
        )
        let root = sqrt(discriminant)
        let minimumCurvature = meanCurvature - root
        let maximumCurvature = meanCurvature + root
        let directions = try principalDirections(
            minimumCurvature: minimumCurvature,
            maximumCurvature: maximumCurvature,
            firstE: firstE,
            firstF: firstF,
            firstG: firstG,
            secondL: secondL,
            secondM: secondM,
            secondN: secondN,
            tangentU: tangentU,
            tangentV: tangentV,
            normal: normal,
            tolerance: tolerance
        )
        return Surface3D.DifferentialGeometry(
            position: derivatives.position,
            tangentU: tangentU,
            tangentV: tangentV,
            secondDerivativeUU: derivatives.secondDerivativeUU,
            secondDerivativeUV: derivatives.secondDerivativeUV,
            secondDerivativeVV: derivatives.secondDerivativeVV,
            normal: normal,
            normalCurvatureU: normalCurvatureU,
            normalCurvatureV: normalCurvatureV,
            meanCurvature: meanCurvature,
            gaussianCurvature: gaussianCurvature,
            minimumPrincipalCurvature: minimumCurvature,
            maximumPrincipalCurvature: maximumCurvature,
            minimumPrincipalDirection: directions.minimum,
            maximumPrincipalDirection: directions.maximum
        )
    }

    private func regularNormal(
        tangentU: Vector3D,
        tangentV: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        let tangentULength = tangentU.length
        let tangentVLength = tangentV.length
        guard tangentULength.isFinite,
              tangentVLength.isFinite,
              tangentULength > tolerance.distance,
              tangentVLength > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: min(tangentULength, tangentVLength),
                tolerance: tolerance,
                message: "Procedural surface tangents are singular at the requested parameter."
            )
        }
        let cross = (tangentU / tangentULength).cross(tangentV / tangentVLength)
        let sine = cross.length
        let angularTolerance = max(
            sin(min(tolerance.angle, Double.pi * 0.5)),
            tolerance.relative,
            Double.ulpOfOne * 256.0
        )
        guard sine.isFinite, sine > angularTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: sine,
                tolerance: tolerance,
                message: "Procedural surface tangent directions are linearly dependent."
            )
        }
        return cross / sine
    }

    private func principalDirections(
        minimumCurvature: Double,
        maximumCurvature: Double,
        firstE: Double,
        firstF: Double,
        firstG: Double,
        secondL: Double,
        secondM: Double,
        secondN: Double,
        tangentU: Vector3D,
        tangentV: Vector3D,
        normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> (minimum: Vector3D, maximum: Vector3D) {
        let curvatureScale = max(
            1.0,
            abs(minimumCurvature),
            abs(maximumCurvature)
        )
        let curvatureTolerance = max(
            tolerance.relative * curvatureScale * 64.0,
            Double.ulpOfOne * curvatureScale * 512.0
        )
        if abs(maximumCurvature - minimumCurvature) <= curvatureTolerance {
            let first = try tangentU.normalized(tolerance: tolerance.distance)
            return (
                first,
                try normal.cross(first).normalized(
                    tolerance: tolerance.distance
                )
            )
        }
        guard let minimum = principalDirection(
            curvature: minimumCurvature,
            firstE: firstE,
            firstF: firstF,
            firstG: firstG,
            secondL: secondL,
            secondM: secondM,
            secondN: secondN,
            tangentU: tangentU,
            tangentV: tangentV,
            tolerance: tolerance
        ),
        let maximum = principalDirection(
            curvature: maximumCurvature,
            firstE: firstE,
            firstF: firstF,
            firstG: firstG,
            secondL: secondL,
            secondM: secondM,
            secondN: secondN,
            tangentU: tangentU,
            tangentV: tangentV,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: abs(maximumCurvature - minimumCurvature),
                tolerance: tolerance,
                message: "Procedural surface principal directions could not be resolved."
            )
        }
        return (minimum, maximum)
    }

    private func principalDirection(
        curvature: Double,
        firstE: Double,
        firstF: Double,
        firstG: Double,
        secondL: Double,
        secondM: Double,
        secondN: Double,
        tangentU: Vector3D,
        tangentV: Vector3D,
        tolerance: ModelingTolerance
    ) -> Vector3D? {
        let rowU = secondL - curvature * firstE
        let rowV = secondM - curvature * firstF
        let secondRowV = secondN - curvature * firstG
        let firstCandidate = tangentU * rowV - tangentV * rowU
        let secondCandidate = tangentU * secondRowV - tangentV * rowV
        let candidate = firstCandidate.length >= secondCandidate.length
            ? firstCandidate
            : secondCandidate
        let scale = max(
            1.0,
            abs(rowU),
            abs(rowV),
            abs(secondRowV)
        ) * max(1.0, tangentU.length, tangentV.length)
        let resolution = max(
            tolerance.relative * scale * 64.0,
            Double.ulpOfOne * scale * 512.0
        )
        guard candidate.length.isFinite, candidate.length > resolution else {
            return nil
        }
        return candidate / candidate.length
    }
}
