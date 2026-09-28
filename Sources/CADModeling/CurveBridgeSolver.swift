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
        try validate(request.start, owner: "start")
        try validate(request.end, owner: "end")
        let startFrame = try request.start.target.frame(tolerance: modelingTolerance)
        let endFrame = try request.end.target.frame(tolerance: modelingTolerance)
        let chord = endFrame.position - startFrame.position
        let chordLength = chord.length
        guard chordLength.isFinite,
              chordLength > modelingTolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: chordLength,
                tolerance: modelingTolerance,
                message: "Bridge curve endpoints must be separated by more than the modeling distance tolerance."
            )
        }
        // One Bezier whose degree gives each end exactly the control points its continuity
        // fixes: G0 one, G1 two, G2 three, G3 four, so degree = k₁ + k₂ + 1.
        let degree = request.start.requiredLevel.rawValue + request.end.requiredLevel.rawValue + 1
        let startPoints = try leadingControlPoints(request.start, frame: startFrame, degree: degree, chordLength: chordLength, owner: "start")
        // The end is the start of the reversed bridge: its tangent leaves the end backwards, the
        // curvature vector is unchanged and d(κN)/ds changes sign.
        let reversedEndFrame = CurveContinuityFrame(
            parameter: endFrame.parameter,
            position: endFrame.position,
            tangent: -endFrame.tangent,
            curvatureVector: endFrame.curvatureVector,
            curvature: endFrame.curvature,
            curvatureDerivativeVector: endFrame.curvatureDerivativeVector.map { -$0 }
        )
        let endPoints = try leadingControlPoints(request.end, frame: reversedEndFrame, degree: degree, chordLength: chordLength, owner: "end")
        let curve = BSplineCurve3D(
            degree: degree,
            knots: bezierKnots(degree: degree),
            controlPoints: startPoints + endPoints.reversed()
        )
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
        try verify(startContinuity, owner: "start", tolerances: request.continuityTolerances)
        try verify(endContinuity, owner: "end", tolerances: request.continuityTolerances)
        return CurveBridgeResult(
            curve: curve,
            startContinuity: startContinuity,
            endContinuity: endContinuity
        )
    }

    private func validate(
        _ constraint: CurveBridgeEndpointConstraint,
        owner: String
    ) throws {
        if let derivativeMagnitude = constraint.derivativeMagnitude {
            guard constraint.requiredLevel >= .tangent else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    residual: derivativeMagnitude,
                    tolerance: modelingTolerance,
                    message: "Bridge curve \(owner) derivative magnitude requires G1 or higher continuity."
                )
            }
            guard derivativeMagnitude.isFinite,
                  derivativeMagnitude > modelingTolerance.distance else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    residual: derivativeMagnitude,
                    tolerance: modelingTolerance,
                    message: "Bridge curve \(owner) derivative magnitude must exceed the modeling distance tolerance."
                )
            }
        }
        for (name, tension) in [("second", constraint.secondTension), ("third", constraint.thirdTension)] {
            guard tension.isFinite, tension > 0 else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    residual: tension,
                    tolerance: modelingTolerance,
                    message: "Bridge curve \(owner) \(name) tension must be positive and finite."
                )
            }
        }
    }

    private func verify(
        _ result: CurveContinuityResult,
        owner: String,
        tolerances: CurveContinuityTolerances
    ) throws {
        let deviation = result.deviation
        if deviation.positionDistance > tolerances.positionDistance {
            throw continuityError(
                owner: owner,
                quantity: "position",
                residual: deviation.positionDistance,
                limit: tolerances.positionDistance
            )
        }
        if result.requiredLevel >= .tangent,
           deviation.tangentAngle > tolerances.tangentAngle {
            throw continuityError(
                owner: owner,
                quantity: "tangent angle",
                residual: deviation.tangentAngle,
                limit: tolerances.tangentAngle
            )
        }
        if result.requiredLevel >= .curvature,
           deviation.curvatureVectorDistance > tolerances.curvatureVector {
            throw continuityError(
                owner: owner,
                quantity: "curvature vector",
                residual: deviation.curvatureVectorDistance,
                limit: tolerances.curvatureVector
            )
        }
        if result.requiredLevel >= .curvatureVariation {
            guard let derivativeDistance = deviation.curvatureDerivativeDistance else {
                throw KernelError(
                    phase: .geometry,
                    code: .unsupportedCapability,
                    tolerance: modelingTolerance,
                    message: "Bridge curve \(owner) curve has no exact third derivative, so it cannot take G3 continuity."
                )
            }
            if derivativeDistance > tolerances.curvatureVariation {
                throw continuityError(
                    owner: owner,
                    quantity: "curvature variation",
                    residual: derivativeDistance,
                    limit: tolerances.curvatureVariation
                )
            }
        }
    }

    private func continuityError(
        owner: String,
        quantity: String,
        residual: Double,
        limit: Double
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .singularGeometry,
            residual: residual,
            tolerance: modelingTolerance,
            message: "Bridge curve \(owner) \(quantity) residual \(residual) exceeds \(limit)."
        )
    }

    /// The first k + 1 control points of a degree-n Bezier leaving `frame` with continuity
    /// k: B′ = sT with s the end speed, B″ = σ₂T + s²K, B‴ = σ₃T + 3sσ₂K + s³K′, where K is the
    /// curvature vector, K′ its arc-length derivative, σ₂ = (n − 1)(tension₂ − 1)s and
    /// σ₃ = (n − 1)(n − 2)(tension₃ − 1)s — so the second and third tensions slide control
    /// points two and three along the tangent and default to the natural spacing.
    private func leadingControlPoints(
        _ constraint: CurveBridgeEndpointConstraint,
        frame: CurveContinuityFrame,
        degree n: Int,
        chordLength: Double,
        owner: String
    ) throws -> [Point3D] {
        let k = constraint.requiredLevel.rawValue
        var points = [frame.position]
        guard k >= 1 else { return points }
        try frame.tangent.validateUnitLength(tolerance: modelingTolerance)
        let s = try derivativeMagnitude(constraint.derivativeMagnitude, defaultMagnitude: chordLength)
        let degree = Double(n)
        let p1 = frame.position + frame.tangent * (s / degree)
        points.append(p1)
        guard k >= 2 else { return points }
        let sigma2 = (degree - 1) * (constraint.secondTension - 1) * s
        let second = frame.tangent * sigma2 + frame.curvatureVector * (s * s)
        let p2 = point(from: vector(from: p1) * 2 - vector(from: frame.position) + second / (degree * (degree - 1)))
        points.append(p2)
        guard k >= 3 else { return points }
        guard let curvatureDerivative = frame.curvatureDerivativeVector else {
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: modelingTolerance,
                message: "Bridge curve \(owner) curve has no exact third derivative, so it cannot take G3 continuity."
            )
        }
        let sigma3 = (degree - 1) * (degree - 2) * (constraint.thirdTension - 1) * s
        let third = frame.tangent * sigma3 + frame.curvatureVector * (3 * s * sigma2) + curvatureDerivative * (s * s * s)
        let p3 = point(from: vector(from: p2) * 3 - vector(from: p1) * 3 + vector(from: frame.position)
            + third / (degree * (degree - 1) * (degree - 2)))
        points.append(p3)
        return points
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
