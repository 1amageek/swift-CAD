import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

/// Numerical candidate construction. The independent interval certifier owns acceptance.
enum KnotRemovalConstruction {
    static func removeOne(_ source: BSplineCurve3D, at knot: Double,
        tolerance: ModelingTolerance, budget: inout KnotRemovalBudget) throws -> BSplineCurve3D {
        let rows = source.controlPointCount - (source.isPeriodic ? source.degree : 0)
        let columns = rows - 1
        guard columns > 0, source.isPeriodic || columns > source.degree else {
            throw BSplineKnotRemovalError.invalidInput("Removing this knot would eliminate the valid B-spline basis.")
        }
        let matrixCount = try KnotRemovalBudget.product(rows, columns)
        try budget.charge(scalars: KnotRemovalBudget.product(matrixCount, 4),
            work: KnotRemovalBudget.product(10, KnotRemovalBudget.product(matrixCount, columns)))
        try budget.charge(scalars: KnotRemovalBudget.product(rows + columns, 32))
        let template: BSplineCurve3D
        do { template = try reducedTemplate(source, knot: knot, columns: columns, tolerance: tolerance) }
        catch { throw BSplineKnotRemovalError.numericalFailure("The reduced knot chart is not finite or representable.") }
        if source.isPeriodic {
            let parameter: Double
            let plan: PeriodicBSplineEditPlan
            do {
                parameter = try template.basisParameter(knot, tolerance: tolerance)
                plan = try PeriodicBSplineEditPlan.refinement(degree: source.degree,
                controlPointCount: template.controlPointCount, periodic: true,
                isSeam: parameter == template.knots[template.degree], tolerance: tolerance)
            } catch { throw BSplineKnotRemovalError.numericalFailure("Cyclic refinement has no finite representable plan.") }
            try budget.charge(scalars: KnotRemovalBudget.product(32,
                KnotRemovalBudget.product(plan.workspaceControlPointCount, columns)),
                work: KnotRemovalBudget.product(16,
                    KnotRemovalBudget.product(plan.knotInsertionWork, columns)))
            // Every translated insertion generates fresh homogeneous/control buffers.
            // The cumulative allocation contract charges each processed control.
            try budget.charge(scalars: KnotRemovalBudget.product(32,
                KnotRemovalBudget.product(plan.knotInsertionWork, columns)))
        } else {
            try budget.charge(scalars: KnotRemovalBudget.product(matrixCount, 12),
                work: KnotRemovalBudget.product(matrixCount, 16))
        }
        var matrix = Array(repeating: 0.0, count: matrixCount)
        for column in 0..<columns {
            var unit = template
            for index in unit.controlPoints.indices {
                unit.controlPoints[index] = Point3D(x: index % columns == column ? 1 : 0, y: 0, z: 0)
            }
            let refined: BSplineCurve3D
            do {
                if source.isPeriodic {
                    refined = try unit.insertingKnot(knot,
                        expansionOptions: .init(maximumControlPointCount: Int.max,
                            maximumKnotInsertionWork: Int.max), tolerance: tolerance)
                } else {
                    refined = try unit.insertingInteriorKnot(knot,
                        multiplicity: unit.knots.filter { $0 == knot }.count, tolerance: tolerance)
                }
            } catch {
                throw BSplineKnotRemovalError.numericalFailure("Inverse refinement could not construct a finite basis map.")
            }
            let rotation: Int
            if source.isPeriodic {
                let representative = try refined.basisParameter(source.knots[source.degree], tolerance: tolerance)
                let cycle = Array(refined.knots[refined.degree..<refined.controlPointCount])
                guard let closest = cycle.indices.min(by: { abs(cycle[$0] - representative) < abs(cycle[$1] - representative) }),
                      abs(cycle[closest] - representative) <= max(1, abs(representative)) * Double.ulpOfOne * 128 else {
                    throw BSplineKnotRemovalError.numericalFailure("Refinement could not align the original periodic chart.")
                }
                rotation = closest
            } else { rotation = 0 }
            for row in 0..<rows { matrix[row * columns + column] = refined.controlPoints[(row + rotation) % rows].x }
        }
        let origin = source.controlPoints[0]
        let coordinates: [[Double]] = [
            (0..<rows).map { (source.controlPoints[$0].x - origin.x) * source.weights[$0] },
            (0..<rows).map { (source.controlPoints[$0].y - origin.y) * source.weights[$0] },
            (0..<rows).map { (source.controlPoints[$0].z - origin.z) * source.weights[$0] },
            Array(source.weights.prefix(rows))
        ]
        guard coordinates.allSatisfy({ $0.allSatisfy({ $0.isFinite }) }) else {
            throw BSplineKnotRemovalError.numericalFailure("Homogeneous coordinates exceed finite arithmetic.")
        }
        let solution: [[Double]]
        do {
            let qr = try SurfaceFittingQR(coefficients: matrix, rows: rows, columns: columns,
                relativeRankTolerance: Double.ulpOfOne * 128, maximumElements: matrixCount)
            solution = try coordinates.map { try qr.solveFullRankLeastSquares($0) }
        } catch {
            throw BSplineKnotRemovalError.numericalFailure("Inverse refinement has insufficient numerical rank or finite range.")
        }
        let polynomial = source.weights.allSatisfy { $0 == 1 }
        let weights = polynomial ? Array(repeating: 1.0, count: columns) : solution[3]
        guard weights.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw BSplineKnotRemovalError.numericalFailure("Reduced rational controls do not have positive finite weights.")
        }
        let points = (0..<columns).map { index in
            Point3D(x: origin.x + solution[0][index] / weights[index],
                y: origin.y + solution[1][index] / weights[index],
                z: origin.z + solution[2][index] / weights[index])
        }
        var result: BSplineCurve3D
        if source.isPeriodic {
            do {
                result = try BSplineCurve3D.periodic(degree: source.degree,
                    cycleKnots: Array(template.knots[template.degree...template.controlPointCount]),
                    controlPoints: points, weights: weights, tolerance: tolerance)
            } catch { throw BSplineKnotRemovalError.numericalFailure("Reduced cyclic homogeneous controls are not finite.") }
            result.periodicOrigin = source.periodicOrigin
            let oldPeriod = source.knots[source.controlPointCount] - source.knots[source.degree]
            let newPeriod = result.knots[result.controlPointCount] - result.knots[result.degree]
            guard oldPeriod == newPeriod else {
                throw BSplineKnotRemovalError.numericalFailure("A rotated periodic chart cannot retain the exact stored period.")
            }
        } else {
            result = BSplineCurve3D(degree: source.degree, knots: template.knots,
                controlPoints: points, weights: weights)
        }
        do { try result.validate(tolerance: tolerance) }
        catch { throw BSplineKnotRemovalError.numericalFailure("Reduction did not produce a valid finite B-spline.") }
        return result
    }

    private static func reducedTemplate(_ source: BSplineCurve3D, knot: Double, columns: Int,
        tolerance: ModelingTolerance) throws -> BSplineCurve3D {
        if source.isPeriodic {
            var independent = Array(source.knots[source.degree..<source.controlPointCount])
            guard let first = independent.firstIndex(of: knot) else {
                throw BSplineKnotRemovalError.invalidInput("The periodic knot no longer exists.")
            }
            // Keep the stored base chart until the final seam copy is removed.
            let removing = first == 0 && independent.count > 1 && independent[1] == knot ? 1 : first
            independent.remove(at: removing)
            let period = source.knots[source.controlPointCount] - source.knots[source.degree]
            independent.append(independent[0] + period)
            return try BSplineCurve3D.periodic(degree: source.degree, cycleKnots: independent,
                controlPoints: Array(repeating: .origin, count: columns), tolerance: tolerance)
        }
        var knots = source.knots
        guard let index = knots.firstIndex(of: knot) else {
            throw BSplineKnotRemovalError.invalidInput("The knot no longer exists.")
        }
        knots.remove(at: index)
        return BSplineCurve3D(degree: source.degree, knots: knots,
            controlPoints: Array(repeating: .origin, count: columns))
    }
}
