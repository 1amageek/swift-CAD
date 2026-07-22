import Foundation
import CADCore

struct BSplineSurfaceTangencyRefiner {
    static let maximumInitialAngularResidual = 0.25

    enum Classification: Sendable {
        case isolated
        case branching
        case contactCurve
        case degenerate
    }

    struct Contact: Sendable {
        let normalizedParameters: [Double]
        let actualParameters: [Double]
        let firstPoint: Point3D
        let secondPoint: Point3D
        let normalResidual: Double
        let classification: Classification
        let contactTangent: [Double]?
        let branchTangents: [[Double]]
    }

    private struct Gauge {
        let origin: [Double]
        let tangent: [Double]
    }

    private struct State {
        let normalizedParameters: [Double]
        let actualParameters: [Double]
        let firstGeometry: BSplineSurface3D.DifferentialGeometry
        let secondGeometry: BSplineSurface3D.DifferentialGeometry
        let positionResidual: Vector3D
        let normalResidual: Vector3D
        let positionColumns: [Vector3D]
        let normalColumns: [Vector3D]

        var distanceResidual: Double {
            positionResidual.length
        }

        var angularResidual: Double {
            firstGeometry.normal.cross(secondGeometry.normal).length
        }
    }

    func refinedContact(
        near normalizedSeed: [Double],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domainLowerBounds: [Double],
        domainSpans: [Double],
        maximumIterations: Int,
        tolerance: ModelingTolerance,
        gaugeOrigin: [Double]? = nil,
        gaugeTangent: [Double]? = nil
    ) throws -> Contact? {
        guard normalizedSeed.count == 4,
              domainLowerBounds.count == 4,
              domainSpans.count == 4,
              gaugeOrigin?.count == gaugeTangent?.count,
              gaugeOrigin?.count == nil || gaugeOrigin?.count == 4 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline surface tangency refinement requires four surface parameters."
            )
        }

        let gauge: Gauge?
        if let gaugeOrigin, let gaugeTangent {
            guard let normalizedTangent = normalized(gaugeTangent) else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "B-spline contact continuation requires a nonzero gauge tangent."
                )
            }
            gauge = Gauge(origin: gaugeOrigin, tangent: normalizedTangent)
        } else {
            gauge = nil
        }

        var parameters = normalizedSeed.map { min(max($0, 0.0), 1.0) }
        let initial = try state(
            normalizedParameters: parameters,
            orientationSign: nil,
            first: first,
            second: second,
            domainLowerBounds: domainLowerBounds,
            domainSpans: domainSpans,
            tolerance: tolerance
        )
        let orientationSign = initial.firstGeometry.normal.dot(initial.secondGeometry.normal) >= 0.0
            ? 1.0
            : -1.0
        guard initial.angularResidual <= Self.maximumInitialAngularResidual else {
            return nil
        }
        let characteristicLength = max(
            initial.positionColumns.map(\.length).max() ?? 0.0,
            tolerance.distance * 16.0
        )
        let curvatureScale = try maximumRelativeCurvature(
            state: initial,
            tolerance: tolerance
        )
        let searchThreshold = max(
            tolerance.angle * 64.0,
            min(
                Self.maximumInitialAngularResidual,
                sqrt(max(curvatureScale, tolerance.relative / characteristicLength) * tolerance.distance) * 8.0
            )
        )
        guard initial.angularResidual <= searchThreshold else {
            return nil
        }

        var current = try state(
            normalizedParameters: parameters,
            orientationSign: orientationSign,
            first: first,
            second: second,
            domainLowerBounds: domainLowerBounds,
            domainSpans: domainSpans,
            tolerance: tolerance
        )
        var damping = max(
            maximumNormalEquationDiagonal(
                state: current,
                characteristicLength: characteristicLength
            ) * 1.0e-10,
            1.0e-14
        )

        for _ in 0..<maximumIterations {
            if current.distanceResidual <= tolerance.distance * 0.1,
               current.angularResidual <= tolerance.angle * 0.1,
               abs(gaugeResidual(state: current, gauge: gauge)) <= 1.0e-11 {
                break
            }
            let currentObjective = objective(
                state: current,
                characteristicLength: characteristicLength,
                gauge: gauge
            )
            var acceptedState: State?
            var acceptedStep = Double.infinity
            for _ in 0..<10 {
                guard let delta = normalEquationStep(
                    state: current,
                    characteristicLength: characteristicLength,
                    damping: damping,
                    gauge: gauge
                ) else {
                    damping *= 16.0
                    continue
                }
                let candidateParameters = zip(parameters, delta).map {
                    min(max($0.0 + $0.1, 0.0), 1.0)
                }
                let candidate = try state(
                    normalizedParameters: candidateParameters,
                    orientationSign: orientationSign,
                    first: first,
                    second: second,
                    domainLowerBounds: domainLowerBounds,
                    domainSpans: domainSpans,
                    tolerance: tolerance
                )
                if objective(
                    state: candidate,
                    characteristicLength: characteristicLength,
                    gauge: gauge
                ) < currentObjective {
                    acceptedState = candidate
                    acceptedStep = zip(candidateParameters, parameters).map {
                        abs($0.0 - $0.1)
                    }.max() ?? 0.0
                    parameters = candidateParameters
                    damping = max(damping * 0.25, 1.0e-16)
                    break
                }
                damping *= 16.0
            }
            guard let acceptedState else { break }
            current = acceptedState
            if acceptedStep <= 1.0e-14 { break }
        }

        guard current.distanceResidual <= tolerance.distance,
              current.angularResidual <= tolerance.angle,
              abs(gaugeResidual(state: current, gauge: gauge)) <= 1.0e-9 else {
            return nil
        }
        let classification = try classification(
            state: current,
            characteristicLength: characteristicLength,
            domainSpans: domainSpans,
            tolerance: tolerance
        )
        return Contact(
            normalizedParameters: current.normalizedParameters,
            actualParameters: current.actualParameters,
            firstPoint: current.firstGeometry.position,
            secondPoint: current.secondGeometry.position,
            normalResidual: current.angularResidual,
            classification: classification.kind,
            contactTangent: classification.kind == .contactCurve
                ? classification.tangents.first
                : nil,
            branchTangents: classification.kind == .branching
                ? classification.tangents
                : []
        )
    }

    private func state(
        normalizedParameters: [Double],
        orientationSign: Double?,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domainLowerBounds: [Double],
        domainSpans: [Double],
        tolerance: ModelingTolerance
    ) throws -> State {
        let actualParameters = normalizedParameters.indices.map {
            domainLowerBounds[$0] + normalizedParameters[$0] * domainSpans[$0]
        }
        let firstGeometry = try first.differentialGeometry(
            atU: actualParameters[0],
            v: actualParameters[1],
            tolerance: tolerance
        )
        let secondGeometry = try second.differentialGeometry(
            atU: actualParameters[2],
            v: actualParameters[3],
            tolerance: tolerance
        )
        let sign = orientationSign
            ?? (firstGeometry.normal.dot(secondGeometry.normal) >= 0.0 ? 1.0 : -1.0)
        let firstNormalDerivatives = normalDerivatives(firstGeometry)
        let secondNormalDerivatives = normalDerivatives(secondGeometry)
        return State(
            normalizedParameters: normalizedParameters,
            actualParameters: actualParameters,
            firstGeometry: firstGeometry,
            secondGeometry: secondGeometry,
            positionResidual: firstGeometry.position - secondGeometry.position,
            normalResidual: firstGeometry.normal - secondGeometry.normal * sign,
            positionColumns: [
                firstGeometry.tangentU * domainSpans[0],
                firstGeometry.tangentV * domainSpans[1],
                secondGeometry.tangentU * -domainSpans[2],
                secondGeometry.tangentV * -domainSpans[3],
            ],
            normalColumns: [
                firstNormalDerivatives.u * domainSpans[0],
                firstNormalDerivatives.v * domainSpans[1],
                secondNormalDerivatives.u * (-sign * domainSpans[2]),
                secondNormalDerivatives.v * (-sign * domainSpans[3]),
            ]
        )
    }

    private func normalDerivatives(
        _ geometry: BSplineSurface3D.DifferentialGeometry
    ) -> (u: Vector3D, v: Vector3D) {
        let areaVector = geometry.tangentU.cross(geometry.tangentV)
        let area = areaVector.length
        let derivativeU = geometry.secondDerivativeUU.cross(geometry.tangentV)
            + geometry.tangentU.cross(geometry.secondDerivativeUV)
        let derivativeV = geometry.secondDerivativeUV.cross(geometry.tangentV)
            + geometry.tangentU.cross(geometry.secondDerivativeVV)
        return (
            projectedNormalDerivative(
                derivativeU,
                normal: geometry.normal,
                area: area
            ),
            projectedNormalDerivative(
                derivativeV,
                normal: geometry.normal,
                area: area
            )
        )
    }

    private func projectedNormalDerivative(
        _ derivative: Vector3D,
        normal: Vector3D,
        area: Double
    ) -> Vector3D {
        (derivative - normal * derivative.dot(normal)) / area
    }

    private func normalEquationStep(
        state: State,
        characteristicLength: Double,
        damping: Double,
        gauge: Gauge?
    ) -> [Double]? {
        var residual = components(state.positionResidual)
            + components(state.normalResidual * characteristicLength)
        var columns = state.positionColumns.indices.map { index in
            components(state.positionColumns[index])
                + components(state.normalColumns[index] * characteristicLength)
        }
        if let gauge {
            residual.append(gaugeResidual(state: state, gauge: gauge) * characteristicLength)
            for index in columns.indices {
                columns[index].append(gauge.tangent[index] * characteristicLength)
            }
        }
        var matrix = Array(repeating: Array(repeating: 0.0, count: 4), count: 4)
        var rightHandSide = Array(repeating: 0.0, count: 4)
        for row in 0..<4 {
            rightHandSide[row] = -dot(columns[row], residual)
            for column in 0..<4 {
                matrix[row][column] = dot(columns[row], columns[column])
            }
            matrix[row][row] += damping
        }
        return SmallLinearSystem4.solve(matrix: matrix, rightHandSide: rightHandSide)
    }

    private func maximumNormalEquationDiagonal(
        state: State,
        characteristicLength: Double
    ) -> Double {
        state.positionColumns.indices.map { index in
            let position = state.positionColumns[index]
            let normal = state.normalColumns[index] * characteristicLength
            return position.dot(position) + normal.dot(normal)
        }.max() ?? 1.0
    }

    private func objective(
        state: State,
        characteristicLength: Double,
        gauge: Gauge?
    ) -> Double {
        let normal = state.normalResidual * characteristicLength
        let scaledGauge = gaugeResidual(state: state, gauge: gauge) * characteristicLength
        return state.positionResidual.dot(state.positionResidual)
            + normal.dot(normal)
            + scaledGauge * scaledGauge
    }

    private func classification(
        state: State,
        characteristicLength: Double,
        domainSpans: [Double],
        tolerance: ModelingTolerance
    ) throws -> (kind: Classification, tangents: [[Double]]) {
        let hessian = try relativeHessian(state: state, tolerance: tolerance)
        let halfDifference = (hessian.xx - hessian.yy) * 0.5
        let radius = sqrt(halfDifference * halfDifference + hessian.xy * hessian.xy)
        let center = (hessian.xx + hessian.yy) * 0.5
        let firstEigenvalue = center - radius
        let secondEigenvalue = center + radius
        let curvatureScale = max(
            max(abs(firstEigenvalue), abs(secondEigenvalue)),
            1.0 / characteristicLength
        )
        let curvatureTolerance = max(
            max(
                curvatureScale * tolerance.relative * 64.0,
                tolerance.angle / characteristicLength * 16.0
            ),
            Double.ulpOfOne * curvatureScale * 256.0
        )
        let firstIsSignificant = abs(firstEigenvalue) > curvatureTolerance
        let secondIsSignificant = abs(secondEigenvalue) > curvatureTolerance
        if firstIsSignificant && secondIsSignificant {
            if firstEigenvalue.sign == secondEigenvalue.sign {
                return (.isolated, [])
            }
            let firstEigenvector = nullEigenvector(
                hessian: hessian,
                eigenvalue: firstEigenvalue
            )
            let secondEigenvector = Point2D(
                x: -firstEigenvector.y,
                y: firstEigenvector.x
            )
            let negativeScale = sqrt(abs(firstEigenvalue))
            let positiveScale = sqrt(abs(secondEigenvalue))
            let localDirections = [1.0, -1.0].map { sign in
                Point2D(
                    x: firstEigenvector.x * positiveScale
                        + secondEigenvector.x * negativeScale * sign,
                    y: firstEigenvector.y * positiveScale
                        + secondEigenvector.y * negativeScale * sign
                )
            }
            let tangents = try localDirections.map {
                try parameterTangent(
                    localDirection: $0,
                    state: state,
                    domainSpans: domainSpans,
                    tolerance: tolerance
                )
            }.sorted(by: lexicographicallyPrecedes)
            return (.branching, tangents)
        }
        guard firstIsSignificant != secondIsSignificant else {
            return (.degenerate, [])
        }
        let zeroEigenvalue = firstIsSignificant ? secondEigenvalue : firstEigenvalue
        let localDirection = nullEigenvector(
            hessian: hessian,
            eigenvalue: zeroEigenvalue
        )
        let tangent = try parameterTangent(
            localDirection: localDirection,
            state: state,
            domainSpans: domainSpans,
            tolerance: tolerance
        )
        return (.contactCurve, [tangent])
    }

    private func parameterTangent(
        localDirection: Point2D,
        state: State,
        domainSpans: [Double],
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let firstBasis = try state.firstGeometry.tangentU.normalized(
            tolerance: tolerance.distance
        )
        let secondBasis = try state.firstGeometry.normal.cross(firstBasis).normalized(
            tolerance: tolerance.distance
        )
        let rawWorldDirection = firstBasis * localDirection.x
            + secondBasis * localDirection.y
        let worldDirection = canonicalDirection(rawWorldDirection)
        let firstParameters = try parameterCoefficients(
            direction: worldDirection,
            geometry: state.firstGeometry,
            tolerance: tolerance
        )
        let secondParameters = try parameterCoefficients(
            direction: worldDirection,
            geometry: state.secondGeometry,
            tolerance: tolerance
        )
        guard let tangent = normalized([
            firstParameters.u / domainSpans[0],
            firstParameters.v / domainSpans[1],
            secondParameters.u / domainSpans[2],
            secondParameters.v / domainSpans[3],
        ]) else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                tolerance: tolerance,
                message: "B-spline tangency classification produced a singular continuation tangent."
            )
        }
        return tangent
    }

    private func nullEigenvector(
        hessian: (xx: Double, xy: Double, yy: Double),
        eigenvalue: Double
    ) -> Point2D {
        let first = Point2D(x: hessian.xy, y: eigenvalue - hessian.xx)
        let second = Point2D(x: eigenvalue - hessian.yy, y: hessian.xy)
        let firstSquaredLength = first.x * first.x + first.y * first.y
        let secondSquaredLength = second.x * second.x + second.y * second.y
        let selected = firstSquaredLength >= secondSquaredLength ? first : second
        let length = sqrt(max(firstSquaredLength, secondSquaredLength))
        return Point2D(x: selected.x / length, y: selected.y / length)
    }

    private func canonicalDirection(_ direction: Vector3D) -> Vector3D {
        for component in [direction.x, direction.y, direction.z] where component != 0.0 {
            return component > 0.0 ? direction : direction * -1.0
        }
        return direction
    }

    private func gaugeResidual(state: State, gauge: Gauge?) -> Double {
        guard let gauge else { return 0.0 }
        return dot(
            zip(state.normalizedParameters, gauge.origin).map { $0.0 - $0.1 },
            gauge.tangent
        )
    }

    private func maximumRelativeCurvature(
        state: State,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let hessian = try relativeHessian(state: state, tolerance: tolerance)
        return max(max(abs(hessian.xx), abs(hessian.xy)), abs(hessian.yy))
    }

    private func relativeHessian(
        state: State,
        tolerance: ModelingTolerance
    ) throws -> (xx: Double, xy: Double, yy: Double) {
        let normal = state.firstGeometry.normal
        let firstBasis = try state.firstGeometry.tangentU.normalized(
            tolerance: tolerance.distance
        )
        let secondBasis = try normal.cross(firstBasis).normalized(
            tolerance: tolerance.distance
        )
        let firstX = try parameterCoefficients(
            direction: firstBasis,
            geometry: state.firstGeometry,
            tolerance: tolerance
        )
        let firstY = try parameterCoefficients(
            direction: secondBasis,
            geometry: state.firstGeometry,
            tolerance: tolerance
        )
        let secondX = try parameterCoefficients(
            direction: firstBasis,
            geometry: state.secondGeometry,
            tolerance: tolerance
        )
        let secondY = try parameterCoefficients(
            direction: secondBasis,
            geometry: state.secondGeometry,
            tolerance: tolerance
        )
        return (
            normalAcceleration(
                firstX,
                firstX,
                geometry: state.firstGeometry,
                normal: normal
            ) - normalAcceleration(
                secondX,
                secondX,
                geometry: state.secondGeometry,
                normal: normal
            ),
            normalAcceleration(
                firstX,
                firstY,
                geometry: state.firstGeometry,
                normal: normal
            ) - normalAcceleration(
                secondX,
                secondY,
                geometry: state.secondGeometry,
                normal: normal
            ),
            normalAcceleration(
                firstY,
                firstY,
                geometry: state.firstGeometry,
                normal: normal
            ) - normalAcceleration(
                secondY,
                secondY,
                geometry: state.secondGeometry,
                normal: normal
            )
        )
    }

    private func parameterCoefficients(
        direction: Vector3D,
        geometry: BSplineSurface3D.DifferentialGeometry,
        tolerance: ModelingTolerance
    ) throws -> (u: Double, v: Double) {
        let e = geometry.tangentU.dot(geometry.tangentU)
        let f = geometry.tangentU.dot(geometry.tangentV)
        let g = geometry.tangentV.dot(geometry.tangentV)
        let determinant = e * g - f * f
        guard determinant > max(tolerance.relative * e * g, Double.ulpOfOne) else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: determinant,
                tolerance: tolerance,
                message: "B-spline tangency classification encountered a singular surface metric."
            )
        }
        let rightU = geometry.tangentU.dot(direction)
        let rightV = geometry.tangentV.dot(direction)
        return (
            (rightU * g - rightV * f) / determinant,
            (rightV * e - rightU * f) / determinant
        )
    }

    private func normalAcceleration(
        _ first: (u: Double, v: Double),
        _ second: (u: Double, v: Double),
        geometry: BSplineSurface3D.DifferentialGeometry,
        normal: Vector3D
    ) -> Double {
        let acceleration = geometry.secondDerivativeUU * (first.u * second.u)
            + geometry.secondDerivativeUV * (first.u * second.v + first.v * second.u)
            + geometry.secondDerivativeVV * (first.v * second.v)
        return normal.dot(acceleration)
    }

    private func components(_ vector: Vector3D) -> [Double] {
        [vector.x, vector.y, vector.z]
    }

    private func dot(_ first: [Double], _ second: [Double]) -> Double {
        zip(first, second).reduce(0.0) { $0 + $1.0 * $1.1 }
    }

    private func normalized(_ values: [Double]) -> [Double]? {
        let length = sqrt(dot(values, values))
        guard length.isFinite, length > 1.0e-12 else { return nil }
        return values.map { $0 / length }
    }

    private func lexicographicallyPrecedes(_ first: [Double], _ second: [Double]) -> Bool {
        for index in first.indices where first[index] != second[index] {
            return first[index] < second[index]
        }
        return false
    }
}
