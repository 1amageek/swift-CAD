import Foundation
import CADCore

public enum CurveContinuityLevel: Int, Codable, Sendable, Hashable, Comparable, CaseIterable {
    case positional = 0
    case tangent = 1
    case curvature = 2

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

    public init(
        parameter: Double,
        position: Point3D,
        tangent: Vector3D,
        curvatureVector: Vector3D,
        curvature: Double
    ) {
        self.parameter = parameter
        self.position = position
        self.tangent = tangent
        self.curvatureVector = curvatureVector
        self.curvature = curvature
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
            curvature: geometry.curvature
        )
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

    public init(
        positionDistance: Double,
        tangentAngle: Double,
        curvatureVectorDistance: Double
    ) {
        self.positionDistance = positionDistance
        self.tangentAngle = tangentAngle
        self.curvatureVectorDistance = curvatureVectorDistance
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
        return CurveContinuityDeviation(
            positionDistance: positionDistance,
            tangentAngle: tangentAngle,
            curvatureVectorDistance: curvatureVectorDistance
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
        return .curvature
    }
}
