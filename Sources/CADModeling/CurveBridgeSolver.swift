import CADCore
import CADGeometry
import CADIR

public struct CurveBridgeSolver: Sendable {
    private let modelingTolerance: ModelingTolerance

    public init(modelingTolerance: ModelingTolerance) {
        self.modelingTolerance = modelingTolerance
    }

    public func solve(_ request: CurveBridgeRequest) throws -> CurveBridgeResult {
        try modelingTolerance.validate()
        try request.continuityTolerances.validate()
        let startFrame = try request.start.target.frame(tolerance: modelingTolerance)
        let endFrame = try request.end.target.frame(tolerance: modelingTolerance)
        let chord = endFrame.position - startFrame.position
        let chordLength = chord.length
        guard chordLength.isFinite,
              chordLength > modelingTolerance.distance else {
            throw GeometryError.invalidDistance(chordLength)
        }
        let degree = degree(for: request)
        let curve: BSplineCurve3D
        switch degree {
        case 1:
            curve = lineBridge(startFrame: startFrame, endFrame: endFrame)
        case 3:
            curve = try cubicBridge(
                request: request,
                startFrame: startFrame,
                endFrame: endFrame,
                chordLength: chordLength
            )
        default:
            curve = try quinticBridge(
                request: request,
                startFrame: startFrame,
                endFrame: endFrame,
                chordLength: chordLength
            )
        }
        try curve.validate(tolerance: modelingTolerance)
        let bridgeCurve = Curve3D.bSpline(curve)
        let evaluator = CurveContinuityEvaluator(modelingTolerance: modelingTolerance)
        let startContinuity = try evaluator.evaluate(CurveContinuityRequest(
            first: request.start.target,
            second: CurveContinuityTarget(curve: bridgeCurve, parameter: 0.0),
            requiredLevel: request.start.requiredLevel,
            tolerances: request.continuityTolerances
        ))
        let endContinuity = try evaluator.evaluate(CurveContinuityRequest(
            first: request.end.target,
            second: CurveContinuityTarget(curve: bridgeCurve, parameter: 1.0),
            requiredLevel: request.end.requiredLevel,
            tolerances: request.continuityTolerances
        ))
        guard startContinuity.isSatisfied,
              endContinuity.isSatisfied else {
            throw GeometryError.invalidDistance(max(
                startContinuity.deviation.positionDistance,
                endContinuity.deviation.positionDistance
            ))
        }
        return CurveBridgeResult(
            curve: curve,
            startContinuity: startContinuity,
            endContinuity: endContinuity
        )
    }

    private func degree(for request: CurveBridgeRequest) -> Int {
        let level = max(request.start.requiredLevel, request.end.requiredLevel)
        switch level {
        case .positional:
            return 1
        case .tangent:
            return 3
        case .curvature:
            return 5
        }
    }

    private func lineBridge(
        startFrame: CurveContinuityFrame,
        endFrame: CurveContinuityFrame
    ) -> BSplineCurve3D {
        BSplineCurve3D(
            degree: 1,
            knots: bezierKnots(degree: 1),
            controlPoints: [startFrame.position, endFrame.position]
        )
    }

    private func cubicBridge(
        request: CurveBridgeRequest,
        startFrame: CurveContinuityFrame,
        endFrame: CurveContinuityFrame,
        chordLength: Double
    ) throws -> BSplineCurve3D {
        let startDerivative = try derivative(
            frame: startFrame,
            requestedMagnitude: request.start.derivativeMagnitude,
            defaultMagnitude: chordLength
        )
        let endDerivative = try derivative(
            frame: endFrame,
            requestedMagnitude: request.end.derivativeMagnitude,
            defaultMagnitude: chordLength
        )
        return BSplineCurve3D(
            degree: 3,
            knots: bezierKnots(degree: 3),
            controlPoints: [
                startFrame.position,
                startFrame.position + startDerivative / 3.0,
                endFrame.position + (-endDerivative / 3.0),
                endFrame.position,
            ]
        )
    }

    private func quinticBridge(
        request: CurveBridgeRequest,
        startFrame: CurveContinuityFrame,
        endFrame: CurveContinuityFrame,
        chordLength: Double
    ) throws -> BSplineCurve3D {
        let startMagnitude = try derivativeMagnitude(
            request.start.derivativeMagnitude,
            defaultMagnitude: chordLength
        )
        let endMagnitude = try derivativeMagnitude(
            request.end.derivativeMagnitude,
            defaultMagnitude: chordLength
        )
        let startDerivative = startFrame.tangent * startMagnitude
        let endDerivative = endFrame.tangent * endMagnitude
        let startSecondDerivative = startFrame.curvatureVector * (startMagnitude * startMagnitude)
        let endSecondDerivative = endFrame.curvatureVector * (endMagnitude * endMagnitude)
        let firstControl = startFrame.position + startDerivative / 5.0
        let secondControl = point(
            from: startSecondDerivative / 20.0 +
                vector(from: firstControl) * 2.0 -
                vector(from: startFrame.position)
        )
        let fourthControl = endFrame.position + (-endDerivative / 5.0)
        let thirdControl = point(
            from: endSecondDerivative / 20.0 -
                vector(from: endFrame.position) +
                vector(from: fourthControl) * 2.0
        )
        return BSplineCurve3D(
            degree: 5,
            knots: bezierKnots(degree: 5),
            controlPoints: [
                startFrame.position,
                firstControl,
                secondControl,
                thirdControl,
                fourthControl,
                endFrame.position,
            ]
        )
    }

    private func derivative(
        frame: CurveContinuityFrame,
        requestedMagnitude: Double?,
        defaultMagnitude: Double
    ) throws -> Vector3D {
        try frame.tangent.validateUnitLength(tolerance: modelingTolerance)
        return try frame.tangent * derivativeMagnitude(requestedMagnitude, defaultMagnitude: defaultMagnitude)
    }

    private func derivativeMagnitude(
        _ requestedMagnitude: Double?,
        defaultMagnitude: Double
    ) throws -> Double {
        let magnitude = requestedMagnitude ?? defaultMagnitude
        guard magnitude.isFinite,
              magnitude > modelingTolerance.distance else {
            throw GeometryError.invalidDistance(magnitude)
        }
        return magnitude
    }

    private func bezierKnots(degree: Int) -> [Double] {
        Array(repeating: 0.0, count: degree + 1) + Array(repeating: 1.0, count: degree + 1)
    }

    private func vector(from point: Point3D) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }

    private func point(from vector: Vector3D) -> Point3D {
        Point3D(x: vector.x, y: vector.y, z: vector.z)
    }
}
