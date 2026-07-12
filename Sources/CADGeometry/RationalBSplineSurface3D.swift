import Foundation
import CADCore

/// A tensor-product rational B-spline surface with exact homogeneous evaluation.
public struct RationalBSplineSurface3D: Codable, Equatable, Hashable, Sendable {
    public struct DifferentialGeometry: Codable, Equatable, Hashable, Sendable {
        public let position: Point3D
        public let tangentU: Vector3D
        public let tangentV: Vector3D
        public let secondDerivativeUU: Vector3D
        public let secondDerivativeUV: Vector3D
        public let secondDerivativeVV: Vector3D
        public let normal: Vector3D
        public let normalCurvatureU: Double
        public let normalCurvatureV: Double
        public let meanCurvature: Double
        public let gaussianCurvature: Double
        public let minimumPrincipalCurvature: Double
        public let maximumPrincipalCurvature: Double
        public let minimumPrincipalDirection: Vector3D
        public let maximumPrincipalDirection: Vector3D

        public init(
            position: Point3D,
            tangentU: Vector3D,
            tangentV: Vector3D,
            normal: Vector3D,
            secondDerivativeUU: Vector3D = .zero,
            secondDerivativeUV: Vector3D = .zero,
            secondDerivativeVV: Vector3D = .zero,
            normalCurvatureU: Double = 0.0,
            normalCurvatureV: Double = 0.0,
            meanCurvature: Double = 0.0,
            gaussianCurvature: Double = 0.0,
            minimumPrincipalCurvature: Double = 0.0,
            maximumPrincipalCurvature: Double = 0.0,
            minimumPrincipalDirection: Vector3D = .zero,
            maximumPrincipalDirection: Vector3D = .zero
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

    public let controlPoints: [[Point3D]]
    public let weights: [[Double]]
    public let knotsU: [Double]
    public let knotsV: [Double]
    public let degreeU: Int
    public let degreeV: Int

    public init(
        controlPoints: [[Point3D]],
        weights: [[Double]]? = nil,
        knotsU: [Double],
        knotsV: [Double],
        degreeU: Int,
        degreeV: Int
    ) {
        self.controlPoints = controlPoints
        self.weights = weights ?? controlPoints.map { Array(repeating: 1.0, count: $0.count) }
        self.knotsU = knotsU
        self.knotsV = knotsV
        self.degreeU = degreeU
        self.degreeV = degreeV
    }

    public var uDomain: SurfaceParameterDomain {
        guard degreeU >= 0, degreeU < knotsU.count else { return .bounded(lower: 0.0, upper: 0.0) }
        return .bounded(lower: knotsU[degreeU], upper: knotsU[knotsU.count - degreeU - 1])
    }

    public var vDomain: SurfaceParameterDomain {
        guard degreeV >= 0, degreeV < knotsV.count else { return .bounded(lower: 0.0, upper: 0.0) }
        return .bounded(lower: knotsV[degreeV], upper: knotsV[knotsV.count - degreeV - 1])
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        guard controlPoints.count >= 2,
              controlPoints.allSatisfy({ $0.count >= 2 }),
              controlPoints.dropFirst().allSatisfy({ $0.count == controlPoints[0].count }),
              degreeU >= 1,
              degreeV >= 1,
              degreeU < controlPoints.count,
              degreeV < controlPoints[0].count else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "Invalid B-spline surface control net or degree.")
        }
        guard weights.count == controlPoints.count,
              weights.allSatisfy({ $0.count == controlPoints[0].count }),
              knotsU.count == controlPoints.count + degreeU + 1,
              knotsV.count == controlPoints[0].count + degreeV + 1,
              knotsU.allSatisfy(\.isFinite),
              knotsV.allSatisfy(\.isFinite),
              zip(knotsU.dropFirst(), knotsU).allSatisfy({ $0 >= $1 }),
              zip(knotsV.dropFirst(), knotsV).allSatisfy({ $0 >= $1 }) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "Invalid B-spline surface knots, weights, or dimensions.")
        }
        guard weights.allSatisfy({ $0.allSatisfy { $0.isFinite && $0 > tolerance.distance } }) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "B-spline surface weights must be finite and positive.")
        }
        try controlPoints.flatMap { $0 }.forEach { try $0.validate() }
        try uDomain.validate()
        try vDomain.validate()
    }

    public func differentialGeometry(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance = .standard
    ) throws -> DifferentialGeometry {
        try validate(tolerance: tolerance)
        guard uDomain.contains(u, tolerance: tolerance.distance),
              vDomain.contains(v, tolerance: tolerance.distance) else {
            throw GeometryError.invalidDistance(u)
        }
        let h00 = homogeneous(u: u, v: v, du: 0, dv: 0)
        let h10 = homogeneous(u: u, v: v, du: 1, dv: 0)
        let h01 = homogeneous(u: u, v: v, du: 0, dv: 1)
        let h20 = homogeneous(u: u, v: v, du: 2, dv: 0)
        let h11 = homogeneous(u: u, v: v, du: 1, dv: 1)
        let h02 = homogeneous(u: u, v: v, du: 0, dv: 2)
        guard abs(h00.w) > tolerance.distance else {
            throw KernelError(phase: .geometry, code: .invalidInput, residual: abs(h00.w), tolerance: tolerance, message: "B-spline surface homogeneous denominator is degenerate.")
        }
        let position = Point3D(x: h00.x / h00.w, y: h00.y / h00.w, z: h00.z / h00.w)
        let tangentU = rationalDerivative(h00, h10)
        let tangentV = rationalDerivative(h00, h01)
        let normal = try tangentU.cross(tangentV).normalized(tolerance: tolerance.distance)
        let secondDerivativeUU = rationalSecondDerivative(
            value: h00,
            first: h10,
            otherFirst: h10,
            second: h20,
            position: position,
            tangent: tangentU
        )
        let secondDerivativeUV = rationalMixedDerivative(
            value: h00,
            firstU: h10,
            firstV: h01,
            mixed: h11,
            position: position,
            tangentU: tangentU,
            tangentV: tangentV
        )
        let secondDerivativeVV = rationalSecondDerivative(
            value: h00,
            first: h01,
            otherFirst: h01,
            second: h02,
            position: position,
            tangent: tangentV
        )
        try secondDerivativeUU.validate()
        try secondDerivativeUV.validate()
        try secondDerivativeVV.validate()
        return try makeDifferential(
            position: position,
            tangentU: tangentU,
            tangentV: tangentV,
            secondDerivativeUU: secondDerivativeUU,
            secondDerivativeUV: secondDerivativeUV,
            secondDerivativeVV: secondDerivativeVV,
            normal: normal,
            tolerance: tolerance
        )
    }

    public func point(u: Double, v: Double, tolerance: ModelingTolerance = .standard) throws -> Point3D {
        try differentialGeometry(u: u, v: v, tolerance: tolerance).position
    }

    public func uvnFrame(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance = .standard
    ) throws -> UVNFrame {
        let differential = try differentialGeometry(u: u, v: v, tolerance: tolerance)
        let tangentU = try differential.tangentU.normalized(tolerance: tolerance.distance)
        let normal = try differential.normal.normalized(tolerance: tolerance.distance)
        let tangentV = try normal.cross(tangentU).normalized(tolerance: tolerance.distance)
        return try UVNFrame(
            position: differential.position,
            u: tangentU,
            v: tangentV,
            normal: normal,
            tolerance: tolerance
        )
    }

    private func homogeneous(u: Double, v: Double, du: Int, dv: Int) -> (x: Double, y: Double, z: Double, w: Double) {
        var value = (x: 0.0, y: 0.0, z: 0.0, w: 0.0)
        for row in controlPoints.indices {
            let bu = RationalBSplineSupport.basis(index: row, degree: degreeU, parameter: u, knots: knotsU, derivative: du)
            for column in controlPoints[row].indices {
                let basis = bu * RationalBSplineSupport.basis(index: column, degree: degreeV, parameter: v, knots: knotsV, derivative: dv)
                let weight = weights[row][column]
                let point = controlPoints[row][column]
                value.x += point.x * weight * basis
                value.y += point.y * weight * basis
                value.z += point.z * weight * basis
                value.w += weight * basis
            }
        }
        return value
    }

    private func rationalDerivative(
        _ value: (x: Double, y: Double, z: Double, w: Double),
        _ derivative: (x: Double, y: Double, z: Double, w: Double)
    ) -> Vector3D {
        Vector3D(
            x: (derivative.x * value.w - value.x * derivative.w) / (value.w * value.w),
            y: (derivative.y * value.w - value.y * derivative.w) / (value.w * value.w),
            z: (derivative.z * value.w - value.z * derivative.w) / (value.w * value.w)
        )
    }

    private func rationalSecondDerivative(
        value: (x: Double, y: Double, z: Double, w: Double),
        first: (x: Double, y: Double, z: Double, w: Double),
        otherFirst: (x: Double, y: Double, z: Double, w: Double),
        second: (x: Double, y: Double, z: Double, w: Double),
        position: Point3D,
        tangent: Vector3D
    ) -> Vector3D {
        let denominator = value.w
        let term = Vector3D(
            x: second.x - position.x * second.w - 2.0 * tangent.x * otherFirst.w,
            y: second.y - position.y * second.w - 2.0 * tangent.y * otherFirst.w,
            z: second.z - position.z * second.w - 2.0 * tangent.z * otherFirst.w
        )
        return term / denominator
    }

    private func rationalMixedDerivative(
        value: (x: Double, y: Double, z: Double, w: Double),
        firstU: (x: Double, y: Double, z: Double, w: Double),
        firstV: (x: Double, y: Double, z: Double, w: Double),
        mixed: (x: Double, y: Double, z: Double, w: Double),
        position: Point3D,
        tangentU: Vector3D,
        tangentV: Vector3D
    ) -> Vector3D {
        let term = Vector3D(
            x: mixed.x - position.x * mixed.w - tangentU.x * firstV.w - tangentV.x * firstU.w,
            y: mixed.y - position.y * mixed.w - tangentU.y * firstV.w - tangentV.y * firstU.w,
            z: mixed.z - position.z * mixed.w - tangentU.z * firstV.w - tangentV.z * firstU.w
        )
        return term / value.w
    }

    private func makeDifferential(
        position: Point3D,
        tangentU: Vector3D,
        tangentV: Vector3D,
        secondDerivativeUU: Vector3D,
        secondDerivativeUV: Vector3D,
        secondDerivativeVV: Vector3D,
        normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        let e = normal.dot(secondDerivativeUU)
        let f = normal.dot(secondDerivativeUV)
        let g = normal.dot(secondDerivativeVV)
        let firstE = tangentU.dot(tangentU)
        let firstF = tangentU.dot(tangentV)
        let firstG = tangentV.dot(tangentV)
        let determinant = firstE * firstG - firstF * firstF
        let mean: Double
        let gaussian: Double
        if determinant > tolerance.distance * tolerance.distance {
            mean = (e * firstG - 2.0 * f * firstF + g * firstE) / (2.0 * determinant)
            gaussian = (e * g - f * f) / determinant
        } else {
            mean = 0.0
            gaussian = 0.0
        }
        let root = sqrt(max(0.0, mean * mean - gaussian))
        let directionU = try tangentU.normalized(tolerance: tolerance.distance)
        let orthogonalV = tangentV - directionU * tangentV.dot(directionU)
        let directionV = try orthogonalV.normalized(tolerance: tolerance.distance)
        let (minimumDirection, maximumDirection) = principalDirections(
            tangentU: directionU,
            tangentV: directionV,
            firstFundamentalE: firstE,
            firstFundamentalF: firstF,
            firstFundamentalG: firstG,
            secondFundamentalE: e,
            secondFundamentalF: f,
            secondFundamentalG: g,
            tolerance: tolerance
        )
        return DifferentialGeometry(
            position: position,
            tangentU: tangentU,
            tangentV: tangentV,
            normal: normal,
            secondDerivativeUU: secondDerivativeUU,
            secondDerivativeUV: secondDerivativeUV,
            secondDerivativeVV: secondDerivativeVV,
            normalCurvatureU: firstE > tolerance.distance * tolerance.distance ? e / firstE : 0.0,
            normalCurvatureV: firstG > tolerance.distance * tolerance.distance ? g / firstG : 0.0,
            meanCurvature: mean,
            gaussianCurvature: gaussian,
            minimumPrincipalCurvature: mean - root,
            maximumPrincipalCurvature: mean + root,
            minimumPrincipalDirection: minimumDirection,
            maximumPrincipalDirection: maximumDirection
        )
    }

    private func principalDirections(
        tangentU: Vector3D,
        tangentV: Vector3D,
        firstFundamentalE: Double,
        firstFundamentalF: Double,
        firstFundamentalG: Double,
        secondFundamentalE: Double,
        secondFundamentalF: Double,
        secondFundamentalG: Double,
        tolerance: ModelingTolerance
    ) -> (minimum: Vector3D, maximum: Vector3D) {
        let safeE = max(firstFundamentalE, tolerance.distance * tolerance.distance)
        let uLength = sqrt(safeE)
        let vLengthSquared = firstFundamentalG - firstFundamentalF * firstFundamentalF / safeE
        let vLength = sqrt(max(vLengthSquared, tolerance.distance * tolerance.distance))
        let b11 = secondFundamentalE / (uLength * uLength)
        let b12 = (secondFundamentalF - secondFundamentalE * firstFundamentalF / safeE) / (uLength * vLength)
        let b22 = (
            secondFundamentalG
                - 2.0 * secondFundamentalF * firstFundamentalF / safeE
                + secondFundamentalE * firstFundamentalF * firstFundamentalF / (safeE * safeE)
        ) / (vLength * vLength)
        let angle = 0.5 * atan2(2.0 * b12, b11 - b22)
        let maximum = tangentU * cos(angle) + tangentV * sin(angle)
        let minimum = tangentU * (-sin(angle)) + tangentV * cos(angle)
        return (minimum, maximum)
    }

}
