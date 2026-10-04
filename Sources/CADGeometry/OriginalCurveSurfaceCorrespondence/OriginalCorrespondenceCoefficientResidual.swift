import CADCore
import Foundation

/// Preserves correlation only when original native coefficient laws prove it.
struct OriginalCorrespondenceCoefficientResidual {
    func upperBound(curve: BSplineCurve3D, start: Double, end: Double,
                    surface: Surface3D, parameterCurve: SurfaceParameterCurve,
                    budget: inout OriginalCorrespondenceBudget) throws -> Double? {
        if case let .plane(plane) = surface, case let .bSpline(parameter) = parameterCurve,
           curve.degree == parameter.degree, curve.knots == parameter.knots,
           curve.weights == parameter.weights,
           start == curve.knots[curve.degree], end == curve.knots[curve.controlPointCount],
           curve.controlPointCount == parameter.controlPointCount {
            let basis = try plane.parameterBasis(tolerance: budget.tolerance)
            var maximum = 0.0
            for index in curve.controlPoints.indices {
                try CurrentTaskCancellationChecker().checkCancellation()
                let p = parameter.controlPoints[index]
                let lifted = [
                    OriginalCorrespondenceScalarJet.constant(plane.origin.x)
                        + .constant(basis.u.x) * .constant(p.x) + .constant(basis.v.x) * .constant(p.y),
                    OriginalCorrespondenceScalarJet.constant(plane.origin.y)
                        + .constant(basis.u.y) * .constant(p.x) + .constant(basis.v.y) * .constant(p.y),
                    OriginalCorrespondenceScalarJet.constant(plane.origin.z)
                        + .constant(basis.u.z) * .constant(p.x) + .constant(basis.v.z) * .constant(p.y)]
                let original = curve.controlPoints[index]
                let values = [original.x, original.y, original.z]
                var squared = OutwardScalarInterval.exact(0)
                for axis in 0..<3 {
                    let value = lifted[axis].value
                    // Exact identical represented coefficients have an exact zero difference.
                    let difference = value.lower == values[axis] && value.upper == values[axis]
                        ? OutwardScalarInterval.exact(0) : .exact(values[axis]) - value
                    let magnitude = OutwardScalarInterval.exact(difference.absoluteUpperBound)
                    squared = squared + magnitude * magnitude
                }
                let bound = sqrt(max(0, squared.upper)).nextUp
                guard bound.isFinite else {
                    throw OriginalCorrespondenceBudget.failure(.resourceLimitExceeded, budget.tolerance,
                        "Original planar coefficient residual exceeded finite arithmetic.")
                }
                maximum = max(maximum, bound)
            }
            return maximum
        }
        if case let .bSpline(support) = surface,
           case let .constantV(v, uStart, uEnd) = parameterCurve,
           curve.degree == support.uDegree, curve.knots == support.uKnots,
           start == uStart, end == uEnd {
            let row: Int
            if v == support.vKnots[1] { row = 0 }
            else if v == support.vKnots[2] { row = 1 }
            else { return nil }
            try CurrentTaskCancellationChecker().checkCancellation()
            guard curve.controlPoints == support.controlPoints[row], curve.weights == support.weights[row] else { return nil }
            return 0
        }
        return nil
    }
}
