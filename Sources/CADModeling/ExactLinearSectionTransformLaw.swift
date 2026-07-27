import CADCore

package struct ExactLinearSectionTransformLaw: Sendable, Hashable {
    private enum Interpolation: Sendable, Hashable {
        case identity
        case linear(direction: Vector3D, pathLength: Double)
    }

    package let pathStart: Point3D
    package let pathEnd: Point3D
    package let endTransform: ExactSectionTransform2D
    private let interpolation: Interpolation

    package init(
        pathSpans: [ExactBSplineCurveSpan],
        endTransform: ExactSectionTransform2D,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard endTransform.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                featureID: featureID,
                tolerance: tolerance,
                message: "Exact linear section transform must contain finite coefficients."
            )
        }
        try Self.validatePositiveDeterminant(
            endTransform: endTransform,
            featureID: featureID,
            tolerance: tolerance
        )
        guard let pathStart = pathSpans.first?.startPoint,
              let pathEnd = pathSpans.last?.endPoint else {
            throw FeatureEvaluationError.emptyResult(
                "Exact linear section Sweep path has no bounded span."
            )
        }
        self.pathStart = pathStart
        self.pathEnd = pathEnd
        self.endTransform = endTransform
        guard endTransform != .identity else {
            interpolation = .identity
            return
        }
        let chord = pathEnd - pathStart
        let pathLength = chord.length
        guard pathLength > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(pathLength)
        }
        let direction = try chord.normalized(
            tolerance: tolerance.distance
        )
        for span in pathSpans {
            for point in span.curve.controlPoints {
                let offset = point - pathStart
                let perpendicular = offset - direction * offset.dot(direction)
                guard perpendicular.length <= tolerance.distance else {
                    throw KernelError(
                        phase: .geometry,
                        code: .sweepScalePathUnavailable,
                        featureID: featureID,
                        residual: perpendicular.length,
                        tolerance: tolerance,
                        message: "Exact linear section Sweep requires every rational path control point to lie on one straight axis."
                    )
                }
            }
        }
        interpolation = .linear(
            direction: direction,
            pathLength: pathLength
        )
    }

    package func transform(
        at point: Point3D
    ) -> ExactSectionTransform2D {
        switch interpolation {
        case .identity:
            return .identity
        case .linear(let direction, let pathLength):
            let ratio = (point - pathStart).dot(direction) / pathLength
            return endTransform.interpolated(ratio: ratio)
        }
    }

    private static func validatePositiveDeterminant(
        endTransform: ExactSectionTransform2D,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws {
        let a = endTransform.m11 - 1.0
        let b = endTransform.m12
        let c = endTransform.m21
        let d = endTransform.m22 - 1.0
        let linear = a + d
        let quadratic = a * d - b * c
        var candidates = [
            1.0,
            endTransform.determinant,
        ]
        if abs(quadratic) > tolerance.relative {
            let stationary = -linear / (2.0 * quadratic)
            if stationary > 0.0, stationary < 1.0 {
                candidates.append(
                    1.0 + linear * stationary
                        + quadratic * stationary * stationary
                )
            }
        }
        guard let minimum = candidates.min(),
              minimum > tolerance.relative * tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .sweepGuideTransformCollapse,
                featureID: featureID,
                residual: candidates.min(),
                tolerance: tolerance,
                message: "Exact linear section transform collapses or reverses orientation along the Sweep path."
            )
        }
    }
}
