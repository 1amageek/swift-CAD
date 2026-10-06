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

/// Shared preflight for exact line edits. Callers first validate the source axis.
struct PeriodicBSplineEditPlan {
    let firstCycle: Double
    let cycleCount: Int
    let reservedControlPoints: Int
    let workspaceControlPointCount: Int
    let knotInsertionWork: Int

    static func restriction(
        degree: Int, knots: [Double], controlPointCount: Int, periodic: Bool,
        lower: Double, upper: Double, tolerance: ModelingTolerance
    ) throws -> Self {
        guard lower.isFinite, upper.isFinite, upper > lower else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "An exact restriction requires a finite increasing interval.")
        }
        let insertions = try product(2, degree, tolerance)
        guard periodic else {
            guard lower >= knots[degree], upper <= knots[controlPointCount] else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "An open-axis restriction must lie in its natural interval.")
            }
            return try make(firstCycle: 0, cycles: 0, initialCount: controlPointCount,
                insertions: insertions, tolerance: tolerance)
        }
        let count = controlPointCount - degree
        let origin = knots[degree]
        let period = knots[controlPointCount] - origin
        let first = floor((lower - origin) / period) - 1
        let last = ceil((upper - origin) / period) + 1
        guard first.isFinite, last.isFinite, let cycles = Int(exactly: last - first), cycles > 0 else {
            throw failure(tolerance)
        }
        let initial = try sum(product(cycles, count, tolerance), degree, tolerance)
        return try make(firstCycle: first, cycles: cycles, initialCount: initial,
            insertions: insertions, tolerance: tolerance)
    }

    static func refinement(
        degree: Int, controlPointCount: Int, periodic: Bool, isSeam: Bool,
        tolerance: ModelingTolerance
    ) throws -> Self {
        guard periodic else {
            return try make(firstCycle: 0, cycles: 0, initialCount: controlPointCount,
                insertions: 1, tolerance: tolerance)
        }
        let count = controlPointCount - degree
        let padding = try sum((degree - 1) / count, 3, tolerance)
        let cycles = try sum(product(2, padding, tolerance), 1, tolerance)
        let initial = try sum(product(cycles, count, tolerance), degree, tolerance)
        return try make(firstCycle: -Double(padding), cycles: cycles, initialCount: initial,
            insertions: cycles - (isSeam ? 1 : 0), tolerance: tolerance)
    }

    func admit(_ options: PeriodicBSplineExpansionOptions, tolerance: ModelingTolerance) throws {
        try options.validate(tolerance: tolerance)
        guard workspaceControlPointCount <= options.maximumControlPointCount,
              knotInsertionWork <= options.maximumKnotInsertionWork else {
            throw Self.failure(tolerance)
        }
    }

    static func sum(_ a: Int, _ b: Int, _ tolerance: ModelingTolerance) throws -> Int {
        let (value, overflow) = a.addingReportingOverflow(b)
        guard !overflow else { throw failure(tolerance) }
        return value
    }

    static func product(_ a: Int, _ b: Int, _ tolerance: ModelingTolerance) throws -> Int {
        let (value, overflow) = a.multipliedReportingOverflow(by: b)
        guard !overflow else { throw failure(tolerance) }
        return value
    }

    static func failure(_ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "The exact edit exceeds its control-storage or homogeneous insertion-work budget.")
    }

    private static func make(
        firstCycle: Double, cycles: Int, initialCount: Int, insertions: Int,
        tolerance: ModelingTolerance
    ) throws -> Self {
        let workspace = try sum(initialCount, insertions, tolerance)
        let rectangular = try product(insertions, initialCount, tolerance)
        let triangular = try product(insertions, insertions - 1, tolerance) / 2
        return Self(firstCycle: firstCycle, cycleCount: cycles,
            reservedControlPoints: insertions, workspaceControlPointCount: workspace,
            knotInsertionWork: try sum(rectangular, triangular, tolerance))
    }
}
