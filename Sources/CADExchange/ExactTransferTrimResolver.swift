import CADCore
import CADGeometry
import CADTopology

struct ExactTransferTrimResolver {
    let tolerance: ModelingTolerance

    func resolve(
        transferCurve: Curve3D,
        transferTrim: CurveTrim,
        exactCurve: Curve3D,
        convention: String
    ) throws -> CurveTrim {
        let transferStartPoint = try transferCurve.point(
            at: transferTrim.startParameter,
            tolerance: tolerance
        )
        let transferEndPoint = try transferCurve.point(
            at: transferTrim.endParameter,
            tolerance: tolerance
        )
        var exactStart = try exactCurve.parameterProjection(
            of: transferStartPoint,
            tolerance: tolerance
        ).parameter
        var exactEnd = try exactCurve.parameterProjection(
            of: transferEndPoint,
            tolerance: tolerance
        ).parameter
        let transferTangent = try transferCurve.differentialGeometry(
            at: transferTrim.startParameter,
            tolerance: tolerance
        ).tangent
        let exactTangent = try exactCurve.differentialGeometry(
            at: exactStart,
            tolerance: tolerance
        ).tangent
        let alignment = transferTangent.dot(exactTangent)
        guard abs(alignment) > tolerance.angle else {
            throw invalid(
                "\(convention) transfer tangent is orthogonal to its exact reconstruction."
            )
        }
        let followsExactCurve = alignment > 0.0

        if case let .periodic(period) = exactCurve.parameterDomain {
            if followsExactCurve {
                while exactEnd <= exactStart + tolerance.angle {
                    exactEnd += period
                }
            } else {
                while exactEnd >= exactStart - tolerance.angle {
                    exactEnd -= period
                }
            }
            guard abs(exactEnd - exactStart) < period - tolerance.angle else {
                throw invalid(
                    "\(convention) periodic exact transfer spans a full or degenerate period."
                )
            }
        } else if case let .implicit(implicitCurve) = exactCurve,
                  implicitCurve.isClosed {
            let seamPoint = try exactCurve.point(at: 0.0, tolerance: tolerance)
            if transferStartPoint.isApproximatelyEqual(
                to: seamPoint,
                tolerance: tolerance.distance
            ) {
                exactStart = followsExactCurve ? 0.0 : 1.0
            }
            if transferEndPoint.isApproximatelyEqual(
                to: seamPoint,
                tolerance: tolerance.distance
            ) {
                exactEnd = followsExactCurve ? 1.0 : 0.0
            }
        }
        guard abs(exactEnd - exactStart) > tolerance.relative,
              (exactEnd > exactStart) == followsExactCurve else {
            throw invalid(
                "\(convention) transfer direction does not map to one exact trim interval."
            )
        }
        return CurveTrim(startParameter: exactStart, endParameter: exactEnd)
    }

    private func invalid(_ message: String) -> ImportError {
        .invalidData(message)
    }
}
