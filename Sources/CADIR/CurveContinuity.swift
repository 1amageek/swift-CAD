import Foundation
import CADCore

public enum CurveContinuityLevel: Int, Codable, Sendable, Hashable, Comparable, CaseIterable {
    case positional = 0
    case tangent = 1
    case curvature = 2
    /// G3: the curvature vector also changes at the same rate along arc length.
    case curvatureVariation = 3

    public static func < (lhs: CurveContinuityLevel, rhs: CurveContinuityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum CurveFrameOrientation: String, Codable, Sendable, Hashable {
    case forward
    case reversed
}

public struct CurveContinuityTolerances: Codable, Sendable, Hashable {
    public var positionDistance: Double
    public var tangentAngle: Double
    public var curvatureVector: Double

    /// G3 compares the arc-length derivatives of the curvature vectors within the curvature
    /// tolerance's value, so stored tolerances need no new field.
    public var curvatureVariation: Double { curvatureVector }

    public init(positionDistance: Double, tangentAngle: Double, curvatureVector: Double) {
        self.positionDistance = positionDistance
        self.tangentAngle = tangentAngle
        self.curvatureVector = curvatureVector
    }

    public static func standard(
        modelingTolerance: ModelingTolerance
    ) -> CurveContinuityTolerances {
        CurveContinuityTolerances(
            positionDistance: modelingTolerance.distance,
            tangentAngle: modelingTolerance.angle,
            curvatureVector: 1.0e-6
        )
    }

    public func validate() throws {
        guard positionDistance.isFinite,
              positionDistance > 0.0,
              tangentAngle.isFinite,
              tangentAngle > 0.0,
              curvatureVector.isFinite,
              curvatureVector > 0.0 else {
            throw GeometryError.invalidTolerance(distance: positionDistance, angle: tangentAngle)
        }
    }
}

public struct CurveContinuityFrame: Codable, Sendable, Hashable {
    public var parameter: Double
    public var position: Point3D
    public var tangent: Vector3D
    public var curvatureVector: Vector3D
    public var curvature: Double
    /// d(κN)/ds along `tangent`, or nil where the curve has no exact third derivative.
    public var curvatureDerivativeVector: Vector3D?

    public init(
        parameter: Double,
        position: Point3D,
        tangent: Vector3D,
        curvatureVector: Vector3D,
        curvature: Double,
        curvatureDerivativeVector: Vector3D? = nil
    ) {
        self.parameter = parameter
        self.position = position
        self.tangent = tangent
        self.curvatureVector = curvatureVector
        self.curvature = curvature
        self.curvatureDerivativeVector = curvatureDerivativeVector
    }
}

public struct CurveContinuityTarget: Codable, Sendable, Hashable {
    public var curve: Curve3D
    public var parameter: Double
    public var orientation: CurveFrameOrientation

    public init(
        curve: Curve3D,
        parameter: Double,
        orientation: CurveFrameOrientation = .forward
    ) {
        self.curve = curve
        self.parameter = parameter
        self.orientation = orientation
    }

    public func frame(tolerance: ModelingTolerance) throws -> CurveContinuityFrame {
        let geometry = try curve.differentialGeometry(at: parameter, tolerance: tolerance)
        let tangent: Vector3D
        switch orientation {
        case .forward:
            tangent = geometry.tangent
        case .reversed:
            tangent = -geometry.tangent
        }
        return CurveContinuityFrame(
            parameter: parameter,
            position: geometry.position,
            tangent: tangent,
            curvatureVector: geometry.curvatureVector,
            curvature: geometry.curvature,
            curvatureDerivativeVector: try curvatureDerivativeVector(geometry, tolerance: tolerance)
        )
    }

    /// d(κN)/ds from C′, C″ and C‴: with S = |C′|², D = C′·C″ and K = (C″S − DC′)/S²,
    /// dK/du = (C‴S + DC″ − (C‴·C′ + |C″|²)C′)/S² − 4D(C″S − DC′)/S³ and d/ds = (1/|C′|) d/du,
    /// negated for a reversed orientation. Nil for a curve whose third derivative is not exact.
    private func curvatureDerivativeVector(
        _ geometry: Curve3D.DifferentialGeometry,
        tolerance: ModelingTolerance
    ) throws -> Vector3D? {
        let third: Vector3D
        do {
            third = try curve.thirdParameterDerivative(at: parameter, tolerance: tolerance)
        } catch let error as KernelError where error.code == .unsupportedCapability {
            return nil
        }
        let first = geometry.firstDerivative, second = geometry.secondDerivative
        let s = first.dot(first)
        guard s > tolerance.distance * tolerance.distance else { return nil }
        let d = first.dot(second)
        let numerator = second * s - first * d
        let numeratorDerivative = third * s + second * d - first * (third.dot(first) + second.dot(second))
        let perParameter = numeratorDerivative / (s * s) - numerator * (4 * d / (s * s * s))
        let perLength = perParameter / s.squareRoot()
        return orientation == .forward ? perLength : -perLength
    }
}

public struct CurveContinuityRequest: Codable, Sendable, Hashable {
    public var first: CurveContinuityTarget
    public var second: CurveContinuityTarget
    public var requiredLevel: CurveContinuityLevel
    public var tolerances: CurveContinuityTolerances

    public init(
        first: CurveContinuityTarget,
        second: CurveContinuityTarget,
        requiredLevel: CurveContinuityLevel,
        tolerances: CurveContinuityTolerances
    ) {
        self.first = first
        self.second = second
        self.requiredLevel = requiredLevel
        self.tolerances = tolerances
    }
}

public struct CurveContinuityDeviation: Codable, Sendable, Hashable {
    public var positionDistance: Double
    public var tangentAngle: Double
    public var curvatureVectorDistance: Double
    /// |Δ d(κN)/ds|, or nil where either frame has no exact third derivative.
    public var curvatureDerivativeDistance: Double?

    public init(
        positionDistance: Double,
        tangentAngle: Double,
        curvatureVectorDistance: Double,
        curvatureDerivativeDistance: Double? = nil
    ) {
        self.positionDistance = positionDistance
        self.tangentAngle = tangentAngle
        self.curvatureVectorDistance = curvatureVectorDistance
        self.curvatureDerivativeDistance = curvatureDerivativeDistance
    }
}

public struct CurveContinuityResult: Codable, Sendable, Hashable {
    public var requiredLevel: CurveContinuityLevel
    public var achievedLevel: CurveContinuityLevel?
    public var firstFrame: CurveContinuityFrame
    public var secondFrame: CurveContinuityFrame
    public var deviation: CurveContinuityDeviation

    public init(
        requiredLevel: CurveContinuityLevel,
        achievedLevel: CurveContinuityLevel?,
        firstFrame: CurveContinuityFrame,
        secondFrame: CurveContinuityFrame,
        deviation: CurveContinuityDeviation
    ) {
        self.requiredLevel = requiredLevel
        self.achievedLevel = achievedLevel
        self.firstFrame = firstFrame
        self.secondFrame = secondFrame
        self.deviation = deviation
    }

    public var isSatisfied: Bool {
        guard let achievedLevel else {
            return false
        }
        return achievedLevel >= requiredLevel
    }
}

public struct CurveContinuityEvaluator: Sendable {
    private let modelingTolerance: ModelingTolerance

    public init(modelingTolerance: ModelingTolerance) {
        self.modelingTolerance = modelingTolerance
    }

    public func evaluate(_ request: CurveContinuityRequest) throws -> CurveContinuityResult {
        try modelingTolerance.validate()
        try request.tolerances.validate()
        let firstFrame = try request.first.frame(tolerance: modelingTolerance)
        let secondFrame = try request.second.frame(tolerance: modelingTolerance)
        let deviation = try deviation(firstFrame: firstFrame, secondFrame: secondFrame)
        return CurveContinuityResult(
            requiredLevel: request.requiredLevel,
            achievedLevel: achievedLevel(for: deviation, tolerances: request.tolerances),
            firstFrame: firstFrame,
            secondFrame: secondFrame,
            deviation: deviation
        )
    }

    private func deviation(
        firstFrame: CurveContinuityFrame,
        secondFrame: CurveContinuityFrame
    ) throws -> CurveContinuityDeviation {
        let positionDistance = (firstFrame.position - secondFrame.position).length
        let tangentDot = min(max(firstFrame.tangent.dot(secondFrame.tangent), -1.0), 1.0)
        let tangentCross = firstFrame.tangent.cross(secondFrame.tangent).length
        let tangentAngle = atan2(tangentCross, tangentDot)
        let curvatureVectorDistance = (firstFrame.curvatureVector - secondFrame.curvatureVector).length
        guard positionDistance.isFinite,
              tangentAngle.isFinite,
              curvatureVectorDistance.isFinite else {
            throw GeometryError.invalidDistance(positionDistance)
        }
        var curvatureDerivativeDistance: Double?
        if let first = firstFrame.curvatureDerivativeVector, let second = secondFrame.curvatureDerivativeVector {
            curvatureDerivativeDistance = (first - second).length
        }
        return CurveContinuityDeviation(
            positionDistance: positionDistance,
            tangentAngle: tangentAngle,
            curvatureVectorDistance: curvatureVectorDistance,
            curvatureDerivativeDistance: curvatureDerivativeDistance
        )
    }

    private func achievedLevel(
        for deviation: CurveContinuityDeviation,
        tolerances: CurveContinuityTolerances
    ) -> CurveContinuityLevel? {
        guard deviation.positionDistance <= tolerances.positionDistance else {
            return nil
        }
        guard deviation.tangentAngle <= tolerances.tangentAngle else {
            return .positional
        }
        guard deviation.curvatureVectorDistance <= tolerances.curvatureVector else {
            return .tangent
        }
        guard let derivativeDistance = deviation.curvatureDerivativeDistance,
              derivativeDistance <= tolerances.curvatureVariation else {
            return .curvature
        }
        return .curvatureVariation
    }
}
