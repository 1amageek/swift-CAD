import Foundation
import CADCore

public enum SurfaceContinuityLevel: Int, Codable, Sendable, Hashable, Comparable, CaseIterable {
    case positional = 0
    case tangentPlane = 1
    case curvature = 2

    public static func < (lhs: SurfaceContinuityLevel, rhs: SurfaceContinuityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum SurfaceFrameOrientation: String, Codable, Sendable, Hashable {
    case forward
    case reversed
}

public struct SurfaceContinuityTolerances: Codable, Sendable, Hashable {
    public var positionDistance: Double
    public var normalAngle: Double
    public var principalCurvature: Double

    public init(positionDistance: Double, normalAngle: Double, principalCurvature: Double) {
        self.positionDistance = positionDistance
        self.normalAngle = normalAngle
        self.principalCurvature = principalCurvature
    }

    public static func standard(
        modelingTolerance: ModelingTolerance
    ) -> SurfaceContinuityTolerances {
        SurfaceContinuityTolerances(
            positionDistance: modelingTolerance.distance,
            normalAngle: modelingTolerance.angle,
            principalCurvature: 1.0e-6
        )
    }

    public func validate() throws {
        guard positionDistance.isFinite,
              positionDistance > 0.0,
              normalAngle.isFinite,
              normalAngle > 0.0,
              principalCurvature.isFinite,
              principalCurvature > 0.0 else {
            throw GeometryError.invalidTolerance(distance: positionDistance, angle: normalAngle)
        }
    }
}

public struct SurfaceContinuityFrame: Codable, Sendable, Hashable {
    public var u: Double
    public var v: Double
    public var position: Point3D
    public var normal: Vector3D
    public var minimumPrincipalCurvature: Double
    public var maximumPrincipalCurvature: Double
    public var minimumPrincipalDirection: Vector3D
    public var maximumPrincipalDirection: Vector3D

    public init(
        u: Double,
        v: Double,
        position: Point3D,
        normal: Vector3D,
        minimumPrincipalCurvature: Double,
        maximumPrincipalCurvature: Double,
        minimumPrincipalDirection: Vector3D,
        maximumPrincipalDirection: Vector3D
    ) {
        self.u = u
        self.v = v
        self.position = position
        self.normal = normal
        self.minimumPrincipalCurvature = minimumPrincipalCurvature
        self.maximumPrincipalCurvature = maximumPrincipalCurvature
        self.minimumPrincipalDirection = minimumPrincipalDirection
        self.maximumPrincipalDirection = maximumPrincipalDirection
    }
}

public struct SurfaceContinuityTarget: Codable, Sendable, Hashable {
    public var surface: Surface3D
    public var u: Double
    public var v: Double
    public var orientation: SurfaceFrameOrientation

    public init(
        surface: Surface3D,
        u: Double,
        v: Double,
        orientation: SurfaceFrameOrientation = .forward
    ) {
        self.surface = surface
        self.u = u
        self.v = v
        self.orientation = orientation
    }

    public func frame(tolerance: ModelingTolerance) throws -> SurfaceContinuityFrame {
        let geometry = try surface.differentialGeometry(atU: u, v: v, tolerance: tolerance)
        switch orientation {
        case .forward:
            return SurfaceContinuityFrame(
                u: u,
                v: v,
                position: geometry.position,
                normal: geometry.normal,
                minimumPrincipalCurvature: geometry.minimumPrincipalCurvature,
                maximumPrincipalCurvature: geometry.maximumPrincipalCurvature,
                minimumPrincipalDirection: geometry.minimumPrincipalDirection,
                maximumPrincipalDirection: geometry.maximumPrincipalDirection
            )
        case .reversed:
            return SurfaceContinuityFrame(
                u: u,
                v: v,
                position: geometry.position,
                normal: -geometry.normal,
                minimumPrincipalCurvature: -geometry.maximumPrincipalCurvature,
                maximumPrincipalCurvature: -geometry.minimumPrincipalCurvature,
                minimumPrincipalDirection: geometry.maximumPrincipalDirection,
                maximumPrincipalDirection: geometry.minimumPrincipalDirection
            )
        }
    }
}

public struct SurfaceContinuitySamplePair: Codable, Sendable, Hashable {
    public var first: SurfaceContinuityTarget
    public var second: SurfaceContinuityTarget

    public init(first: SurfaceContinuityTarget, second: SurfaceContinuityTarget) {
        self.first = first
        self.second = second
    }
}

public struct SurfaceContinuityRequest: Codable, Sendable, Hashable {
    public var samplePairs: [SurfaceContinuitySamplePair]
    public var requiredLevel: SurfaceContinuityLevel
    public var tolerances: SurfaceContinuityTolerances

    public init(
        samplePairs: [SurfaceContinuitySamplePair],
        requiredLevel: SurfaceContinuityLevel,
        tolerances: SurfaceContinuityTolerances
    ) {
        self.samplePairs = samplePairs
        self.requiredLevel = requiredLevel
        self.tolerances = tolerances
    }
}

public struct SurfaceContinuityDeviation: Codable, Sendable, Hashable {
    public var maximumPositionDistance: Double
    public var maximumNormalAngle: Double
    public var maximumPrincipalCurvatureDistance: Double
    public var sampleCount: Int

    public init(
        maximumPositionDistance: Double,
        maximumNormalAngle: Double,
        maximumPrincipalCurvatureDistance: Double,
        sampleCount: Int
    ) {
        self.maximumPositionDistance = maximumPositionDistance
        self.maximumNormalAngle = maximumNormalAngle
        self.maximumPrincipalCurvatureDistance = maximumPrincipalCurvatureDistance
        self.sampleCount = sampleCount
    }
}

public struct SurfaceContinuityResult: Codable, Sendable, Hashable {
    public var requiredLevel: SurfaceContinuityLevel
    public var achievedLevel: SurfaceContinuityLevel?
    public var deviation: SurfaceContinuityDeviation

    public init(
        requiredLevel: SurfaceContinuityLevel,
        achievedLevel: SurfaceContinuityLevel?,
        deviation: SurfaceContinuityDeviation
    ) {
        self.requiredLevel = requiredLevel
        self.achievedLevel = achievedLevel
        self.deviation = deviation
    }

    public var isSatisfied: Bool {
        guard let achievedLevel else {
            return false
        }
        return achievedLevel >= requiredLevel
    }
}

public struct SurfaceContinuityEvaluator: Sendable {
    private let modelingTolerance: ModelingTolerance

    public init(modelingTolerance: ModelingTolerance) {
        self.modelingTolerance = modelingTolerance
    }

    public func evaluate(_ request: SurfaceContinuityRequest) throws -> SurfaceContinuityResult {
        try modelingTolerance.validate()
        try request.tolerances.validate()
        guard !request.samplePairs.isEmpty else {
            throw GeometryError.invalidDistance(0.0)
        }
        var maximumPositionDistance = 0.0
        var maximumNormalAngle = 0.0
        var maximumPrincipalCurvatureDistance = 0.0
        for pair in request.samplePairs {
            let firstFrame = try pair.first.frame(tolerance: modelingTolerance)
            let secondFrame = try pair.second.frame(tolerance: modelingTolerance)
            maximumPositionDistance = max(
                maximumPositionDistance,
                (firstFrame.position - secondFrame.position).length
            )
            let normalDot = min(max(firstFrame.normal.dot(secondFrame.normal), -1.0), 1.0)
            maximumNormalAngle = max(maximumNormalAngle, acos(normalDot))
            maximumPrincipalCurvatureDistance = max(
                maximumPrincipalCurvatureDistance,
                try shapeOperatorDistance(firstFrame, secondFrame)
            )
        }
        let deviation = SurfaceContinuityDeviation(
            maximumPositionDistance: maximumPositionDistance,
            maximumNormalAngle: maximumNormalAngle,
            maximumPrincipalCurvatureDistance: maximumPrincipalCurvatureDistance,
            sampleCount: request.samplePairs.count
        )
        return SurfaceContinuityResult(
            requiredLevel: request.requiredLevel,
            achievedLevel: achievedLevel(for: deviation, tolerances: request.tolerances),
            deviation: deviation
        )
    }

    private func shapeOperatorDistance(
        _ firstFrame: SurfaceContinuityFrame,
        _ secondFrame: SurfaceContinuityFrame
    ) throws -> Double {
        let firstMinimumDirection = try firstFrame.minimumPrincipalDirection.normalized(
            tolerance: modelingTolerance.distance
        )
        let firstMaximumDirection = try firstFrame.maximumPrincipalDirection.normalized(
            tolerance: modelingTolerance.distance
        )
        let secondMinimumDirection = try secondFrame.minimumPrincipalDirection.normalized(
            tolerance: modelingTolerance.distance
        )
        let secondMaximumDirection = try secondFrame.maximumPrincipalDirection.normalized(
            tolerance: modelingTolerance.distance
        )
        let firstMinimumAction = firstMinimumDirection
            * firstFrame.minimumPrincipalCurvature
        let firstMaximumAction = firstMaximumDirection
            * firstFrame.maximumPrincipalCurvature
        let secondActionOnFirstMinimum = secondMinimumDirection
                * (
                    secondFrame.minimumPrincipalCurvature
                        * secondMinimumDirection.dot(firstMinimumDirection)
                )
            + secondMaximumDirection
                * (
                    secondFrame.maximumPrincipalCurvature
                        * secondMaximumDirection.dot(firstMinimumDirection)
                )
        let secondActionOnFirstMaximum = secondMinimumDirection
                * (
                    secondFrame.minimumPrincipalCurvature
                        * secondMinimumDirection.dot(firstMaximumDirection)
                )
            + secondMaximumDirection
                * (
                    secondFrame.maximumPrincipalCurvature
                        * secondMaximumDirection.dot(firstMaximumDirection)
                )
        return max(
            (firstMinimumAction - secondActionOnFirstMinimum).length,
            (firstMaximumAction - secondActionOnFirstMaximum).length
        )
    }

    private func achievedLevel(
        for deviation: SurfaceContinuityDeviation,
        tolerances: SurfaceContinuityTolerances
    ) -> SurfaceContinuityLevel? {
        guard deviation.maximumPositionDistance <= tolerances.positionDistance else {
            return nil
        }
        guard deviation.maximumNormalAngle <= tolerances.normalAngle else {
            return .positional
        }
        guard deviation.maximumPrincipalCurvatureDistance <= tolerances.principalCurvature else {
            return .tangentPlane
        }
        return .curvature
    }
}
