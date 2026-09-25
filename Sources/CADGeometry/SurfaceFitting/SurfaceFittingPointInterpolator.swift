import CADCore
import Foundation

package enum SurfaceFittingPointInterpolator {
    package struct Constraint: Sendable {
        package let u: Double
        package let v: Double
        package let point: Point3D

        package init(u: Double, v: Double, point: Point3D) {
            self.u = u
            self.v = v
            self.point = point
        }
    }

    /// Constructs a candidate only; topology and continuous regularity have separate owners.
    package static func interpolate(
        template: BSplineSurface3D, constraints: [Constraint],
        referenceWeight: Double, controlNetFairnessWeight: Double,
        positionTolerance: Double, relativeRankTolerance: Double,
        maximumElements: Int, tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        let nu = template.uControlPointCount
        let nv = template.vControlPointCount
        guard template.uDegree >= 1, template.uDegree < nu,
              template.vDegree >= 1, template.vDegree < nv,
              template.uKnots.count - template.uDegree - 1 == nu,
              template.vKnots.count - template.vDegree - 1 == nv,
              !constraints.isEmpty,
              referenceWeight.isFinite, referenceWeight > 0,
              controlNetFairnessWeight.isFinite, controlNetFairnessWeight >= 0,
              positionTolerance.isFinite, positionTolerance > 0,
              relativeRankTolerance.isFinite, relativeRankTolerance > 0,
              relativeRankTolerance < 1 else {
            throw failure(.invalidInput, "Point interpolation requires a valid basis, constraints and positive tolerances.")
        }
        let count = nu.multipliedReportingOverflow(by: nv)
        guard maximumElements > 0, !count.overflow, count.partialValue <= maximumElements else {
            throw failure(.resourceLimitExceeded, "Point interpolation exceeded its control-net budget.")
        }
        let columns = count.partialValue
        guard columns <= maximumElements / columns else {
            throw failure(.resourceLimitExceeded, "Point interpolation exceeded its dense objective budget.")
        }
        var remaining = maximumElements
        func charge(_ rows: Int, _ columns: Int) throws {
            guard rows == 0 || columns <= remaining / rows else {
                throw failure(.resourceLimitExceeded, "Point interpolation exceeded its matrix element budget.")
            }
            remaining -= rows * columns
        }
        let fairnessRows = controlNetFairnessWeight > 0 ? (nu - 2) * nv + (nv - 2) * nu : 0
        let rows = columns.addingReportingOverflow(fairnessRows)
        guard !rows.overflow else {
            throw failure(.resourceLimitExceeded, "Point interpolation row count exceeded its numeric range.")
        }
        try charge(rows.partialValue, columns)
        try charge(constraints.count, columns)
        try charge(rows.partialValue, 3)
        try charge(constraints.count, 3)
        try charge(columns, 3)
        try template.validate(tolerance: tolerance)
        for constraint in constraints {
            guard constraint.u.isFinite, constraint.v.isFinite, constraint.point.isFinite,
                  constraint.u >= template.uKnots[template.uDegree], constraint.u <= template.uKnots[nu],
                  constraint.v >= template.vKnots[template.vDegree], constraint.v <= template.vKnots[nv] else {
                throw failure(.invalidInput, "Point interpolation requires finite in-domain constraints.")
            }
        }

        let anchor = template.controlPoints[0][0]
        let weightScale = sqrt(max(referenceWeight, controlNetFairnessWeight))
        let referenceScale = sqrt(referenceWeight) / weightScale
        let fairnessScale = sqrt(controlNetFairnessWeight) / weightScale
        var objective = Array(repeating: 0.0, count: rows.partialValue * columns)
        var targets = Array(repeating: Array(repeating: 0.0, count: rows.partialValue), count: 3)
        for v in 0..<nv {
            for u in 0..<nu {
                let index = v * nu + u
                objective[index * columns + index] = referenceScale
                let delta = template.controlPoints[v][u] - anchor
                targets[0][index] = delta.x * referenceScale
                targets[1][index] = delta.y * referenceScale
                targets[2][index] = delta.z * referenceScale
            }
        }
        var row = columns
        if controlNetFairnessWeight > 0 {
            for v in 0..<nv {
                for u in 0..<(nu - 2) {
                    let index = v * nu + u
                    objective[row * columns + index] = fairnessScale
                    objective[row * columns + index + 1] = -2 * fairnessScale
                    objective[row * columns + index + 2] = fairnessScale
                    row += 1
                }
            }
            for v in 0..<(nv - 2) {
                for u in 0..<nu {
                    let index = v * nu + u
                    objective[row * columns + index] = fairnessScale
                    objective[row * columns + index + nu] = -2 * fairnessScale
                    objective[row * columns + index + 2 * nu] = fairnessScale
                    row += 1
                }
            }
        }
        let maximumWeight = template.weights.reduce(0.0) { value, row in
            max(value, row.max() ?? 0)
        }
        var equality = Array(repeating: 0.0, count: constraints.count * columns)
        var values = Array(repeating: Array(repeating: 0.0, count: constraints.count), count: 3)
        for (index, constraint) in constraints.enumerated() {
            let ub = BSplineBasis.nonzeroValues(parameter: constraint.u, degree: template.uDegree,
                knots: template.uKnots, count: nu)
            let vb = BSplineBasis.nonzeroValues(parameter: constraint.v, degree: template.vDegree,
                knots: template.vKnots, count: nv)
            var denominator = 0.0
            for v in vb.values.indices {
                for u in ub.values.indices {
                    let ui = ub.startIndex + u
                    let vi = vb.startIndex + v
                    let coefficient = ub.values[u] * vb.values[v] * (template.weights[vi][ui] / maximumWeight)
                    equality[index * columns + vi * nu + ui] = coefficient
                    denominator += coefficient
                }
            }
            guard denominator.isFinite, denominator > 0 else {
                throw failure(.resourceLimitExceeded, "Point interpolation cannot normalize its rational basis.")
            }
            for column in 0..<columns { equality[index * columns + column] /= denominator }
            let delta = constraint.point - anchor
            values[0][index] = delta.x
            values[1][index] = delta.y
            values[2][index] = delta.z
        }
        let coordinates = try SurfaceFittingLeastSquares.solve(
            objective: objective, targets: targets, constraints: equality, values: values,
            columns: columns, relativeRankTolerance: relativeRankTolerance,
            constraintTolerance: positionTolerance / sqrt(3), maximumElements: maximumElements)
        var result = template
        for v in 0..<nv {
            for u in 0..<nu {
                let index = v * nu + u
                result.controlPoints[v][u] = anchor + Vector3D(
                    x: coordinates[0][index], y: coordinates[1][index], z: coordinates[2][index])
            }
        }
        try result.validate(tolerance: tolerance)
        for constraint in constraints {
            let point = try result.pointAssumingValid(u: constraint.u, v: constraint.v, tolerance: tolerance)
            let residual = (point - constraint.point).length
            guard residual.isFinite, residual <= positionTolerance else {
                throw failure(.conflictingConstraints, "The fitted surface does not satisfy its positional tolerance.")
            }
        }
        return result
    }

    private static func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: nil, message: message)
    }
}
