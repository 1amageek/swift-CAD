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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BSplineCurve3D {
        let rows = source.controlPointCount - (source.isPeriodic ? source.degree : 0)
        let columns = rows - 1
        guard columns > 0, source.isPeriodic || columns > source.degree else {
            throw BSplineKnotRemovalError.invalidInput("Removing this knot would eliminate the valid B-spline basis.")
        }
        let matrixCount = try KnotRemovalAllocation.product(rows, columns)
        try KnotRemovalAllocation.charge(scalars: KnotRemovalAllocation.product(matrixCount, 4),
            work: KnotRemovalAllocation.product(10, KnotRemovalAllocation.product(matrixCount, columns)), using: &execution)
        try KnotRemovalAllocation.charge(scalars: KnotRemovalAllocation.product(rows + columns, 32), using: &execution)
        let template: BSplineCurve3D
        do { template = try reducedTemplate(source, knot: knot, columns: columns, tolerance: tolerance, using: &execution) }
        catch { try KnotRemovalAllocation.rethrowAdmission(error); throw BSplineKnotRemovalError.numericalFailure("The reduced knot chart is not finite or representable.") }
        if source.isPeriodic {
            let parameter: Double
            let plan: PeriodicBSplineEditPlan
            do {
                parameter = try template.basisParameter(knot, tolerance: tolerance)
                plan = try PeriodicBSplineEditPlan.refinement(degree: source.degree,
                controlPointCount: template.controlPointCount, periodic: true,
                isSeam: parameter == template.knots[template.degree], tolerance: tolerance)
            } catch { try KnotRemovalAllocation.rethrowAdmission(error); throw BSplineKnotRemovalError.numericalFailure("Cyclic refinement has no finite representable plan.") }
            try KnotRemovalAllocation.charge(scalars: KnotRemovalAllocation.product(32,
                KnotRemovalAllocation.product(plan.workspaceControlPointCount, columns)),
                work: KnotRemovalAllocation.product(16,
                    KnotRemovalAllocation.product(plan.knotInsertionWork, columns)), using: &execution)
            // Every translated insertion generates fresh homogeneous/control buffers.
            // The cumulative allocation contract charges each processed control.
            try KnotRemovalAllocation.charge(scalars: KnotRemovalAllocation.product(32,
                KnotRemovalAllocation.product(plan.knotInsertionWork, columns)), using: &execution)
        } else {
            try KnotRemovalAllocation.charge(scalars: KnotRemovalAllocation.product(matrixCount, 12),
                work: KnotRemovalAllocation.product(matrixCount, 16), using: &execution)
        }
        try execution.retainStorage(count: matrixCount, stride: MemoryLayout<Double>.stride)
        var matrix = Array(repeating: 0.0, count: matrixCount)
        for column in 0..<columns {
            try execution.consumeWork(1)
            try execution.retainStorage(count: template.controlPoints.count, stride: MemoryLayout<Point3D>.stride)
            var unit = template
            for index in unit.controlPoints.indices {
                try execution.consumeWork(1)
                unit.controlPoints[index] = Point3D(x: index % columns == column ? 1 : 0, y: 0, z: 0)
            }
            let refined: BSplineCurve3D
            do {
                if source.isPeriodic {
                    refined = try unit.insertingKnot(knot,
                        expansionOptions: .init(maximumControlPointCount: Int.max,
                            maximumKnotInsertionWork: Int.max), tolerance: tolerance, using: &execution)
                } else {
                    var multiplicity = 0
                    for value in unit.knots {
                        try execution.consumeWork(1)
                        if value == knot { multiplicity += 1 }
                    }
                    refined = try unit.insertingInteriorKnot(knot,
                        multiplicity: multiplicity, tolerance: tolerance, using: &execution)
                }
            } catch {
                try KnotRemovalAllocation.rethrowAdmission(error)
                throw BSplineKnotRemovalError.numericalFailure("Inverse refinement could not construct a finite basis map.")
            }
            let rotation: Int
            if source.isPeriodic {
                let representative = try refined.basisParameter(source.knots[source.degree], tolerance: tolerance)
                try execution.retainStorage(count: refined.controlPointCount - refined.degree, stride: MemoryLayout<Double>.stride)
                let cycle = Array(refined.knots[refined.degree..<refined.controlPointCount])
                guard let closest = cycle.indices.min(by: { abs(cycle[$0] - representative) < abs(cycle[$1] - representative) }),
                      abs(cycle[closest] - representative) <= max(1, abs(representative)) * Double.ulpOfOne * 128 else {
                    throw BSplineKnotRemovalError.numericalFailure("Refinement could not align the original periodic chart.")
                }
                rotation = closest
            } else { rotation = 0 }
            for row in 0..<rows {
                try execution.consumeWork(1)
                matrix[row * columns + column] = refined.controlPoints[(row + rotation) % rows].x
            }
        }
        let origin = source.controlPoints[0]
        try execution.retainStorage(count: 4, stride: MemoryLayout<[Double]>.stride)
        try execution.retainStorage(count: KnotRemovalAllocation.product(rows, 4), stride: MemoryLayout<Double>.stride)
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
                relativeRankTolerance: Double.ulpOfOne * 128, maximumElements: matrixCount, using: &execution)
            try execution.retainStorage(count: coordinates.count, stride: MemoryLayout<[Double]>.stride)
            solution = try coordinates.map { try qr.solveFullRankLeastSquares($0, using: &execution) }
        } catch {
            try KnotRemovalAllocation.rethrowAdmission(error)
            throw BSplineKnotRemovalError.numericalFailure("Inverse refinement has insufficient numerical rank or finite range.")
        }
        let polynomial = source.weights.allSatisfy { $0 == 1 }
        if polynomial { try execution.retainStorage(count: columns, stride: MemoryLayout<Double>.stride) }
        let weights = polynomial ? Array(repeating: 1.0, count: columns) : solution[3]
        guard weights.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw BSplineKnotRemovalError.numericalFailure("Reduced rational controls do not have positive finite weights.")
        }
        try execution.retainStorage(count: columns, stride: MemoryLayout<Point3D>.stride)
        let points = try (0..<columns).map { index in
            try execution.consumeWork(1)
            return Point3D(x: origin.x + solution[0][index] / weights[index],
                y: origin.y + solution[1][index] / weights[index],
                z: origin.z + solution[2][index] / weights[index])
        }
        var result: BSplineCurve3D
        if source.isPeriodic {
            try execution.retainStorage(count: template.controlPointCount - template.degree + 1, stride: MemoryLayout<Double>.stride)
            do {
                result = try BSplineCurve3D.periodic(degree: source.degree,
                    cycleKnots: Array(template.knots[template.degree...template.controlPointCount]),
                    controlPoints: points, weights: weights, tolerance: tolerance, using: &execution)
            } catch { try KnotRemovalAllocation.rethrowAdmission(error); throw BSplineKnotRemovalError.numericalFailure("Reduced cyclic homogeneous controls are not finite.") }
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
        do { try result.validate(tolerance: tolerance, using: &execution) }
        catch { try KnotRemovalAllocation.rethrowAdmission(error); throw BSplineKnotRemovalError.numericalFailure("Reduction did not produce a valid finite B-spline.") }
        return result
    }

    private static func reducedTemplate(_ source: BSplineCurve3D, knot: Double, columns: Int,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BSplineCurve3D {
        if source.isPeriodic {
            try execution.retainStorage(count: source.controlPointCount - source.degree + 1, stride: MemoryLayout<Double>.stride)
            try execution.retainStorage(count: columns, stride: MemoryLayout<Point3D>.stride)
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
                controlPoints: Array(repeating: .origin, count: columns), tolerance: tolerance, using: &execution)
        }
        try execution.retainStorage(count: source.knots.count, stride: MemoryLayout<Double>.stride)
        try execution.retainStorage(count: columns, stride: MemoryLayout<Point3D>.stride)
        var knots = source.knots
        guard let index = knots.firstIndex(of: knot) else {
            throw BSplineKnotRemovalError.invalidInput("The knot no longer exists.")
        }
        knots.remove(at: index)
        return BSplineCurve3D(degree: source.degree, knots: knots,
            controlPoints: Array(repeating: .origin, count: columns))
    }
}
