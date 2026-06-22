import Foundation
import CADCore

public struct BSplineSurface3D: Codable, Sendable, Hashable {
    public struct DifferentialGeometry: Codable, Sendable, Hashable {
        public var position: Point3D
        public var tangentU: Vector3D
        public var tangentV: Vector3D
        public var secondDerivativeUU: Vector3D
        public var secondDerivativeUV: Vector3D
        public var secondDerivativeVV: Vector3D
        public var normal: Vector3D
        public var normalCurvatureU: Double
        public var normalCurvatureV: Double
        public var meanCurvature: Double
        public var gaussianCurvature: Double
        public var minimumPrincipalCurvature: Double
        public var maximumPrincipalCurvature: Double
        public var minimumPrincipalDirection: Vector3D
        public var maximumPrincipalDirection: Vector3D

        public init(
            position: Point3D,
            tangentU: Vector3D,
            tangentV: Vector3D,
            secondDerivativeUU: Vector3D,
            secondDerivativeUV: Vector3D,
            secondDerivativeVV: Vector3D,
            normal: Vector3D,
            normalCurvatureU: Double,
            normalCurvatureV: Double,
            meanCurvature: Double,
            gaussianCurvature: Double,
            minimumPrincipalCurvature: Double,
            maximumPrincipalCurvature: Double,
            minimumPrincipalDirection: Vector3D,
            maximumPrincipalDirection: Vector3D
        ) {
            self.position = position
            self.tangentU = tangentU
            self.tangentV = tangentV
            self.secondDerivativeUU = secondDerivativeUU
            self.secondDerivativeUV = secondDerivativeUV
            self.secondDerivativeVV = secondDerivativeVV
            self.normal = normal
            self.normalCurvatureU = normalCurvatureU
            self.normalCurvatureV = normalCurvatureV
            self.meanCurvature = meanCurvature
            self.gaussianCurvature = gaussianCurvature
            self.minimumPrincipalCurvature = minimumPrincipalCurvature
            self.maximumPrincipalCurvature = maximumPrincipalCurvature
            self.minimumPrincipalDirection = minimumPrincipalDirection
            self.maximumPrincipalDirection = maximumPrincipalDirection
        }
    }

    public var uDegree: Int
    public var vDegree: Int
    public var uKnots: [Double]
    public var vKnots: [Double]
    public var controlPoints: [[Point3D]]

    public init(
        uDegree: Int,
        vDegree: Int,
        uKnots: [Double],
        vKnots: [Double],
        controlPoints: [[Point3D]]
    ) {
        self.uDegree = uDegree
        self.vDegree = vDegree
        self.uKnots = uKnots
        self.vKnots = vKnots
        self.controlPoints = controlPoints
    }

    public var uControlPointCount: Int {
        controlPoints.first?.count ?? 0
    }

    public var vControlPointCount: Int {
        controlPoints.count
    }

    public var uDomain: ParameterDomain {
        guard uKnots.count > uDegree + 1 else {
            return .closed(0.0, 0.0)
        }
        return .closed(uKnots[uDegree], uKnots[uKnots.count - uDegree - 1])
    }

    public var vDomain: ParameterDomain {
        guard vKnots.count > vDegree + 1 else {
            return .closed(0.0, 0.0)
        }
        return .closed(vKnots[vDegree], vKnots[vKnots.count - vDegree - 1])
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        try validateControlPoints()
        try validateKnots(uKnots, degree: uDegree, controlPointCount: uControlPointCount)
        try validateKnots(vKnots, degree: vDegree, controlPointCount: vControlPointCount)
        try uDomain.validate(tolerance: tolerance)
        try vDomain.validate(tolerance: tolerance)
    }

    public func point(u: Double, v: Double, tolerance: ModelingTolerance = .standard) throws -> Point3D {
        try validate(tolerance: tolerance)
        guard try uDomain.contains(u, tolerance: tolerance),
              try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let clampedU = clampedParameter(u, knots: uKnots, degree: uDegree)
        let clampedV = clampedParameter(v, knots: vKnots, degree: vDegree)
        let uBasis = basisValues(parameter: clampedU, degree: uDegree, knots: uKnots, count: uControlPointCount)
        let vBasis = basisValues(parameter: clampedV, degree: vDegree, knots: vKnots, count: vControlPointCount)
        var result = Vector3D.zero
        for vIndex in 0..<vControlPointCount {
            for uIndex in 0..<uControlPointCount {
                let weight = uBasis[uIndex] * vBasis[vIndex]
                guard weight != 0.0 else {
                    continue
                }
                result = result + vector(from: controlPoints[vIndex][uIndex]) * weight
            }
        }
        return Point3D(x: result.x, y: result.y, z: result.z)
    }

    public func normal(u: Double, v: Double, tolerance: ModelingTolerance = .standard) throws -> Vector3D {
        try differentialGeometry(atU: u, v: v, tolerance: tolerance).normal
    }

    public func differentialGeometry(
        atU u: Double,
        v: Double,
        tolerance: ModelingTolerance = .standard
    ) throws -> DifferentialGeometry {
        try validate(tolerance: tolerance)
        guard try uDomain.contains(u, tolerance: tolerance),
              try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let clampedU = clampedParameter(u, knots: uKnots, degree: uDegree)
        let clampedV = clampedParameter(v, knots: vKnots, degree: vDegree)
        let uBasis = basisValues(parameter: clampedU, degree: uDegree, knots: uKnots, count: uControlPointCount)
        let vBasis = basisValues(parameter: clampedV, degree: vDegree, knots: vKnots, count: vControlPointCount)
        let uFirstDerivative = basisDerivativeValues(
            parameter: clampedU,
            degree: uDegree,
            derivativeOrder: 1,
            knots: uKnots,
            count: uControlPointCount
        )
        let vFirstDerivative = basisDerivativeValues(
            parameter: clampedV,
            degree: vDegree,
            derivativeOrder: 1,
            knots: vKnots,
            count: vControlPointCount
        )
        let uSecondDerivative = basisDerivativeValues(
            parameter: clampedU,
            degree: uDegree,
            derivativeOrder: 2,
            knots: uKnots,
            count: uControlPointCount
        )
        let vSecondDerivative = basisDerivativeValues(
            parameter: clampedV,
            degree: vDegree,
            derivativeOrder: 2,
            knots: vKnots,
            count: vControlPointCount
        )

        let positionVector = evaluateSurfaceVector(uBasis: uBasis, vBasis: vBasis)
        let tangentU = evaluateSurfaceVector(uBasis: uFirstDerivative, vBasis: vBasis)
        let tangentV = evaluateSurfaceVector(uBasis: uBasis, vBasis: vFirstDerivative)
        let secondDerivativeUU = evaluateSurfaceVector(uBasis: uSecondDerivative, vBasis: vBasis)
        let secondDerivativeUV = evaluateSurfaceVector(uBasis: uFirstDerivative, vBasis: vFirstDerivative)
        let secondDerivativeVV = evaluateSurfaceVector(uBasis: uBasis, vBasis: vSecondDerivative)
        let normal = try tangentU.cross(tangentV).normalized(tolerance: tolerance.distance)
        let firstE = tangentU.dot(tangentU)
        let firstF = tangentU.dot(tangentV)
        let firstG = tangentV.dot(tangentV)
        let firstDeterminant = firstE * firstG - firstF * firstF
        let metricTolerance = max(tolerance.distance * tolerance.distance, Double.ulpOfOne)
        guard firstE > metricTolerance,
              firstG > metricTolerance,
              firstDeterminant > metricTolerance else {
            throw GeometryError.invalidVectorLength(0.0)
        }
        let secondL = secondDerivativeUU.dot(normal)
        let secondM = secondDerivativeUV.dot(normal)
        let secondN = secondDerivativeVV.dot(normal)
        let meanCurvature = (
            firstE * secondN - 2.0 * firstF * secondM + firstG * secondL
        ) / (2.0 * firstDeterminant)
        let gaussianCurvature = (
            secondL * secondN - secondM * secondM
        ) / firstDeterminant
        let discriminant = max(meanCurvature * meanCurvature - gaussianCurvature, 0.0)
        let root = sqrt(discriminant)
        let firstPrincipal = meanCurvature - root
        let secondPrincipal = meanCurvature + root
        let principalDirections = try principalDirections(
            minimumCurvature: min(firstPrincipal, secondPrincipal),
            maximumCurvature: max(firstPrincipal, secondPrincipal),
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
        return DifferentialGeometry(
            position: Point3D(x: positionVector.x, y: positionVector.y, z: positionVector.z),
            tangentU: tangentU,
            tangentV: tangentV,
            secondDerivativeUU: secondDerivativeUU,
            secondDerivativeUV: secondDerivativeUV,
            secondDerivativeVV: secondDerivativeVV,
            normal: normal,
            normalCurvatureU: secondL / firstE,
            normalCurvatureV: secondN / firstG,
            meanCurvature: meanCurvature,
            gaussianCurvature: gaussianCurvature,
            minimumPrincipalCurvature: min(firstPrincipal, secondPrincipal),
            maximumPrincipalCurvature: max(firstPrincipal, secondPrincipal),
            minimumPrincipalDirection: principalDirections.minimum,
            maximumPrincipalDirection: principalDirections.maximum
        )
    }

    public static func cubicBezierPatch(
        bottomLeft: Point3D,
        bottomRight: Point3D,
        topRight: Point3D,
        topLeft: Point3D
    ) -> BSplineSurface3D {
        var rows: [[Point3D]] = []
        for vIndex in 0..<4 {
            let v = Double(vIndex) / 3.0
            var row: [Point3D] = []
            for uIndex in 0..<4 {
                let u = Double(uIndex) / 3.0
                row.append(
                    bilinearPoint(
                        bottomLeft: bottomLeft,
                        bottomRight: bottomRight,
                        topRight: topRight,
                        topLeft: topLeft,
                        u: u,
                        v: v
                    )
                )
            }
            rows.append(row)
        }
        return BSplineSurface3D(
            uDegree: 3,
            vDegree: 3,
            uKnots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: rows
        )
    }

    private func validateControlPoints() throws {
        guard uDegree >= 1,
              vDegree >= 1,
              controlPoints.count >= vDegree + 1,
              let firstRow = controlPoints.first,
              firstRow.count >= uDegree + 1 else {
            throw GeometryError.invalidDistance(0.0)
        }
        for row in controlPoints {
            guard row.count == firstRow.count else {
                throw GeometryError.invalidDistance(0.0)
            }
            for point in row {
                try point.validate()
            }
        }
    }

    private func validateKnots(_ knots: [Double], degree: Int, controlPointCount: Int) throws {
        guard knots.count == controlPointCount + degree + 1 else {
            throw GeometryError.invalidDistance(Double(knots.count))
        }
        for knot in knots {
            guard knot.isFinite else {
                throw GeometryError.invalidCoordinate(knot)
            }
        }
        for index in 1..<knots.count {
            guard knots[index] >= knots[index - 1] else {
                throw GeometryError.invalidDistance(knots[index] - knots[index - 1])
            }
        }
        let lowerBound = knots[degree]
        let upperBound = knots[knots.count - degree - 1]
        guard upperBound > lowerBound else {
            throw GeometryError.invalidDistance(upperBound - lowerBound)
        }
    }

    private func basisValues(parameter: Double, degree: Int, knots: [Double], count: Int) -> [Double] {
        var values = Array(repeating: 0.0, count: count)
        let upperDomain = knots[knots.count - degree - 1]
        for index in 0..<count {
            if parameter == upperDomain {
                if index == upperEndpointBasisIndex(upperDomain: upperDomain, knots: knots, count: count) {
                    values[index] = 1.0
                }
            } else if parameter >= knots[index] && parameter < knots[index + 1] {
                values[index] = 1.0
            }
        }
        guard degree > 0 else {
            return values
        }
        for currentDegree in 1...degree {
            var next = Array(repeating: 0.0, count: count)
            for index in 0..<count {
                let leftDenominator = knots[index + currentDegree] - knots[index]
                let rightDenominator = knots[index + currentDegree + 1] - knots[index + 1]
                let left = leftDenominator > 0.0
                    ? ((parameter - knots[index]) / leftDenominator) * values[index]
                    : 0.0
                let right = (index + 1 < count && rightDenominator > 0.0)
                    ? ((knots[index + currentDegree + 1] - parameter) / rightDenominator) * values[index + 1]
                    : 0.0
                next[index] = left + right
            }
            values = next
        }
        return values
    }

    private func upperEndpointBasisIndex(upperDomain: Double, knots: [Double], count: Int) -> Int {
        for index in stride(from: count - 1, through: 0, by: -1) {
            guard index + 1 < knots.count else {
                continue
            }
            if knots[index] < upperDomain && knots[index + 1] == upperDomain {
                return index
            }
        }
        return max(count - 1, 0)
    }

    private func basisDerivativeValues(
        parameter: Double,
        degree: Int,
        derivativeOrder: Int,
        knots: [Double],
        count: Int
    ) -> [Double] {
        guard derivativeOrder > 0 else {
            return basisValues(parameter: parameter, degree: degree, knots: knots, count: count)
        }
        guard degree > 0, derivativeOrder <= degree else {
            return Array(repeating: 0.0, count: count)
        }
        let lowerDerivative = basisDerivativeValues(
            parameter: parameter,
            degree: degree - 1,
            derivativeOrder: derivativeOrder - 1,
            knots: knots,
            count: count + 1
        )
        var values = Array(repeating: 0.0, count: count)
        for index in 0..<count {
            let leftDenominator = knots[index + degree] - knots[index]
            let rightDenominator = knots[index + degree + 1] - knots[index + 1]
            let left = leftDenominator > 0.0
                ? Double(degree) * lowerDerivative[index] / leftDenominator
                : 0.0
            let right = rightDenominator > 0.0
                ? Double(degree) * lowerDerivative[index + 1] / rightDenominator
                : 0.0
            values[index] = left - right
        }
        return values
    }

    private func evaluateSurfaceVector(
        uBasis: [Double],
        vBasis: [Double]
    ) -> Vector3D {
        var result = Vector3D.zero
        for vIndex in 0..<vControlPointCount {
            for uIndex in 0..<uControlPointCount {
                let weight = uBasis[uIndex] * vBasis[vIndex]
                guard weight != 0.0 else {
                    continue
                }
                result = result + vector(from: controlPoints[vIndex][uIndex]) * weight
            }
        }
        return result
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
        let curvatureGap = abs(maximumCurvature - minimumCurvature)
        let curvatureTolerance = max(tolerance.distance, tolerance.angle, Double.ulpOfOne.squareRoot())
        guard curvatureGap > curvatureTolerance else {
            return try orthonormalTangentDirections(
                tangentU: tangentU,
                tangentV: tangentV,
                normal: normal,
                tolerance: tolerance
            )
        }

        let fallbackDirections = try orthonormalTangentDirections(
            tangentU: tangentU,
            tangentV: tangentV,
            normal: normal,
            tolerance: tolerance
        )
        guard let minimumDirection = try principalDirection(
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
        let maximumDirection = try principalDirection(
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
            return fallbackDirections
        }
        return (minimumDirection, maximumDirection)
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
    ) throws -> Vector3D? {
        let firstRowU = secondL - curvature * firstE
        let firstRowV = secondM - curvature * firstF
        let secondRowV = secondN - curvature * firstG
        let firstCandidate = tangentU * firstRowV - tangentV * firstRowU
        let secondCandidate = tangentU * secondRowV - tangentV * firstRowV
        let candidate = firstCandidate.length >= secondCandidate.length ? firstCandidate : secondCandidate
        guard candidate.length > tolerance.distance else {
            return nil
        }
        return try candidate.normalized(tolerance: tolerance.distance)
    }

    private func orthonormalTangentDirections(
        tangentU: Vector3D,
        tangentV: Vector3D,
        normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> (minimum: Vector3D, maximum: Vector3D) {
        let first = try tangentU.normalized(tolerance: tolerance.distance)
        let projectedSecond = tangentV - first * tangentV.dot(first)
        if projectedSecond.length > tolerance.distance {
            return (first, try projectedSecond.normalized(tolerance: tolerance.distance))
        }
        let fallbackSecond = normal.cross(first)
        return (first, try fallbackSecond.normalized(tolerance: tolerance.distance))
    }

    private func clampedParameter(_ parameter: Double, knots: [Double], degree: Int) -> Double {
        let lowerBound = knots[degree]
        let upperBound = knots[knots.count - degree - 1]
        return min(max(parameter, lowerBound), upperBound)
    }

    private func vector(from point: Point3D) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }

    private static func bilinearPoint(
        bottomLeft: Point3D,
        bottomRight: Point3D,
        topRight: Point3D,
        topLeft: Point3D,
        u: Double,
        v: Double
    ) -> Point3D {
        let bottom = vector(from: bottomLeft) * (1.0 - u) + vector(from: bottomRight) * u
        let top = vector(from: topLeft) * (1.0 - u) + vector(from: topRight) * u
        let point = bottom * (1.0 - v) + top * v
        return Point3D(x: point.x, y: point.y, z: point.z)
    }

    private static func vector(from point: Point3D) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }
}
