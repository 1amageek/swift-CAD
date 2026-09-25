import CADCore
import CADGeometry
import Foundation

public struct SurfaceBoundaryContinuityEvaluator: Sendable {
    public struct Certificate: Sendable {
        public let level: SurfaceContinuityLevel
        public let maximumPositionDistance: Double
        public let maximumNormalAngle: Double?
        public let maximumShapeOperatorDistance: Double?
        public let inspectedIntervals: Int
    }

    private let modelingTolerance: ModelingTolerance

    public init(modelingTolerance: ModelingTolerance) {
        self.modelingTolerance = modelingTolerance
    }

    public func certify(
        first: SurfaceContinuitySamplingSide, second: SurfaceContinuitySamplingSide,
        requiredLevel: SurfaceContinuityLevel, tolerances: SurfaceContinuityTolerances,
        maximumIntervals: Int, maximumDepth: Int
    ) throws -> Certificate {
        try tolerances.validate()
        func side(_ value: SurfaceContinuitySamplingSide) -> SurfaceBoundaryCertifier.Side {
            .init(lift: SurfaceLiftCurve3D(surface: value.surface, parameterCurve: value.parameterCurve),
                  reversedParameter: value.parameterDirection == .reversed,
                  reversedNormal: value.frameOrientation == .reversed)
        }
        let chordLimit: Double?
        if requiredLevel >= .tangentPlane {
            chordLimit = tolerances.normalAngle >= .pi ? 2 : (2 * sin(tolerances.normalAngle * 0.5)).nextDown
        } else { chordLimit = nil }
        let result = try SurfaceBoundaryCertifier.certify(first: side(first), second: side(second),
            positionTolerance: tolerances.positionDistance, normalChordTolerance: chordLimit,
            shapeOperatorTolerance: requiredLevel >= .curvature ? tolerances.principalCurvature : nil,
            maximumCells: maximumIntervals, maximumDepth: maximumDepth, tolerance: modelingTolerance)
        return Certificate(level: requiredLevel, maximumPositionDistance: result.position,
            maximumNormalAngle: result.normalChord.map { min(.pi, (2 * asin(min(1, $0 * 0.5))).nextUp) },
            maximumShapeOperatorDistance: result.shapeOperator, inspectedIntervals: result.inspectedCells)
    }
}
