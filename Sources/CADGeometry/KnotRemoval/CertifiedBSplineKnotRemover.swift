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

public struct CertifiedBSplineKnotRemover: BSplineKnotRemoving {
    public init() {}

    public func reducingMultiplicity(of source: BSplineCurve3D, at knot: Double, to target: Int,
        maximumDeviation: Double, options: BSplineKnotRemovalOptions = .init(),
        tolerance: ModelingTolerance) throws -> BSplineKnotRemovalResult<BSplineCurve3D> {
        try ordinary { execution in
            try reducingMultiplicity(of: source, at: knot, to: target,
                maximumDeviation: maximumDeviation, options: options, tolerance: tolerance, using: &execution)
        }
    }

    public func reducingMultiplicity(of source: BSplineCurve2D, at knot: Double, to target: Int,
        maximumDeviation: Double, options: BSplineKnotRemovalOptions = .init(),
        tolerance: ModelingTolerance) throws -> BSplineKnotRemovalResult<BSplineCurve2D> {
        try ordinary { execution in
            try reducingMultiplicity(of: source, at: knot, to: target,
                maximumDeviation: maximumDeviation, options: options, tolerance: tolerance, using: &execution)
        }
    }

    public func reducingMultiplicity(of source: BSplineSurface3D, direction: SurfaceParameterDirection, at knot: Double, to target: Int,
        maximumDeviation: Double, options: BSplineKnotRemovalOptions = .init(),
        tolerance: ModelingTolerance) throws -> BSplineKnotRemovalResult<BSplineSurface3D> {
        try ordinary { execution in
            try reducingMultiplicity(of: source, direction: direction, at: knot, to: target,
                maximumDeviation: maximumDeviation, options: options, tolerance: tolerance, using: &execution)
        }
    }

    package func reducingMultiplicity(of source: BSplineCurve3D, at knot: Double, to target: Int,
        maximumDeviation: Double, options: BSplineKnotRemovalOptions = .init(),
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BSplineKnotRemovalResult<BSplineCurve3D> {
        return try selected(options, using: &execution) { execution in
            try admit(maximumDeviation, tolerance)
            try admitScan(source.controlPointCount, source.knots.count, source.weights.count, using: &execution)
            try validate(source, tolerance, using: &execution)
            let parameter = try request(source, knot, target, tolerance, using: &execution)
            let multiplicity = try currentMultiplicity(source, parameter, using: &execution)
            var result = source
            for _ in target..<multiplicity {
                result = try KnotRemovalConstruction.removeOne(result, at: parameter,
                    tolerance: tolerance, using: &execution)
            }
            let bound = try KnotRemovalCertificate.bound(source: [source], candidate: [result], using: &execution)
            try accept(bound, maximumDeviation)
            return .init(geometry: result, removedMultiplicity: multiplicity - target,
                certifiedMaximumDeviation: bound)
                
        }
    }

    package func reducingMultiplicity(of source: BSplineCurve2D, at knot: Double, to target: Int,
        maximumDeviation: Double, options: BSplineKnotRemovalOptions = .init(),
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BSplineKnotRemovalResult<BSplineCurve2D> {
        return try selected(options, using: &execution) { execution in
            try admitScan(source.controlPointCount, source.knots.count, source.weights.count, using: &execution)
            try KnotRemovalAllocation.charge(scalars: KnotRemovalAllocation.product(source.controlPointCount, 3), using: &execution)
            try execution.retainStorage(count: source.controlPointCount, stride: MemoryLayout<Point3D>.stride)
            let lifted = BSplineCurve3D(degree: source.degree, knots: source.knots,
                controlPoints: source.controlPoints.map { Point3D(x: $0.x, y: $0.y, z: 0) }, weights: source.weights)
            try admit(maximumDeviation, tolerance)
            try validate(lifted, tolerance, using: &execution)
            let parameter = try request(lifted, knot, target, tolerance, using: &execution)
            let multiplicity = try currentMultiplicity(lifted, parameter, using: &execution)
            var result = lifted
            for _ in target..<multiplicity {
                result = try KnotRemovalConstruction.removeOne(result, at: parameter,
                    tolerance: tolerance, using: &execution)
            }
            let bound = try KnotRemovalCertificate.bound(source: [lifted], candidate: [result], using: &execution)
            try accept(bound, maximumDeviation)
            try KnotRemovalAllocation.charge(scalars: KnotRemovalAllocation.product(result.controlPointCount, 2), using: &execution)
            try execution.retainStorage(count: result.controlPointCount, stride: MemoryLayout<Point2D>.stride)
            return .init(geometry: BSplineCurve2D(degree: result.degree, knots: result.knots,
                controlPoints: result.controlPoints.map { Point2D(x: $0.x, y: $0.y) }, weights: result.weights),
                removedMultiplicity: multiplicity - target, certifiedMaximumDeviation: bound)
                
        }
    }

    package func reducingMultiplicity(of source: BSplineSurface3D, direction: SurfaceParameterDirection,
        at knot: Double, to target: Int, maximumDeviation: Double,
        options: BSplineKnotRemovalOptions = .init(),
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BSplineKnotRemovalResult<BSplineSurface3D> {
        return try selected(options, using: &execution) { execution in
            try admit(maximumDeviation, tolerance)
            try KnotRemovalAllocation.charge(work: source.controlPoints.count, using: &execution)
            for row in source.controlPoints { try KnotRemovalAllocation.charge(work: KnotRemovalAllocation.product(row.count, 200), using: &execution) }
            try KnotRemovalAllocation.charge(work: source.weights.count, using: &execution)
            for row in source.weights { try KnotRemovalAllocation.charge(work: KnotRemovalAllocation.product(row.count, 20), using: &execution) }
            try KnotRemovalAllocation.charge(work: KnotRemovalAllocation.product(source.uKnots.count, 20), using: &execution)
            try KnotRemovalAllocation.charge(work: KnotRemovalAllocation.product(source.vKnots.count, 20), using: &execution)
            do { try source.validate(tolerance: tolerance, using: &execution) }
            catch { try KnotRemovalAllocation.rethrowAdmission(error); throw BSplineKnotRemovalError.invalidInput("Knot removal requires a valid tensor surface.") }
            let perpendicular = direction == .u ? source.vControlPointCount : source.uControlPointCount
            let axisCount = direction == .u ? source.uControlPointCount : source.vControlPointCount
            // Retained original/final line buffers and assembled output net are all admitted first.
            try KnotRemovalAllocation.charge(scalars: KnotRemovalAllocation.product(12,
                KnotRemovalAllocation.product(perpendicular, axisCount)), using: &execution)
            try execution.retainStorage(count: perpendicular, stride: MemoryLayout<BSplineCurve3D>.stride)
            let original = try (0..<perpendicular).map { try line(source, direction, $0, using: &execution) }
            let parameter = try request(original[0], knot, target, tolerance, using: &execution)
            let multiplicity = try currentMultiplicity(original[0], parameter, using: &execution)
            var reduced: [BSplineCurve3D] = []
            try execution.retainStorage(count: perpendicular, stride: MemoryLayout<BSplineCurve3D>.stride)
            reduced.reserveCapacity(perpendicular)
            for initial in original {
                var curve = initial
                for _ in target..<multiplicity {
                    curve = try KnotRemovalConstruction.removeOne(curve, at: parameter,
                        tolerance: tolerance, using: &execution)
                }
                reduced.append(curve)
            }
            let bound = try KnotRemovalCertificate.bound(source: original, candidate: reduced, using: &execution)
            try accept(bound, maximumDeviation)
            let first = reduced[0]
            var points: [[Point3D]]
            var weights: [[Double]]
            try execution.retainStorage(count: direction == .u ? perpendicular : first.controlPointCount, stride: MemoryLayout<[Point3D]>.stride + MemoryLayout<[Double]>.stride)
            if direction == .u {
                points = reduced.map({ $0.controlPoints })
                weights = reduced.map({ $0.weights })
            } else {
                try execution.retainStorage(count: KnotRemovalAllocation.product(first.controlPointCount, reduced.count), stride: MemoryLayout<Point3D>.stride + MemoryLayout<Double>.stride)
                points = (0..<first.controlPointCount).map { index in reduced.map { $0.controlPoints[index] } }
                weights = (0..<first.controlPointCount).map { index in reduced.map { $0.weights[index] } }
            }
            let surface = BSplineSurface3D(uDegree: source.uDegree, vDegree: source.vDegree,
                uKnots: direction == .u ? first.knots : source.uKnots,
                vKnots: direction == .v ? first.knots : source.vKnots,
                controlPoints: points, weights: weights, isUPeriodic: source.isUPeriodic,
                isVPeriodic: source.isVPeriodic, uPeriodicOrigin: source.uPeriodicOrigin,
                vPeriodicOrigin: source.vPeriodicOrigin)
            do { try surface.validate(tolerance: tolerance, using: &execution) }
            catch { try KnotRemovalAllocation.rethrowAdmission(error); throw BSplineKnotRemovalError.numericalFailure("Reduced tensor lines lost the shared axis contract.") }
            return .init(geometry: surface, removedMultiplicity: multiplicity - target,
                certifiedMaximumDeviation: bound)
                
        }
    }

    private func ordinary<Result>(_ body: (inout OriginalQueryExecution) throws -> Result) throws -> Result {
        var execution = try OriginalQueryExecution.independentGeometry()
        do { return try body(&execution) }
        catch let error as ExactScalarFailure {
            switch error {
            case .resourceLimit, .countOverflow: throw BSplineKnotRemovalError.resourceLimitExceeded
            default: throw error
            }
        }
    }

    private func selected<Result>(_ options: BSplineKnotRemovalOptions,
        using execution: inout OriginalQueryExecution,
        _ body: (inout OriginalQueryExecution) throws -> Result) throws -> Result {
        guard options.maximumGeneratedScalarCount > 0, options.maximumWork > 0 else {
            throw BSplineKnotRemovalError.invalidInput("Knot removal requires positive resource budgets.")
        }
        return try execution.withConversionScope(maximumWorkUnits: options.maximumWork,
            maximumScalarCount: options.maximumGeneratedScalarCount,
            maximumCertificationBoxes: Int.max, body)
    }

    private func admitScan(_ controls: Int, _ knots: Int, _ weights: Int,
        using execution: inout OriginalQueryExecution) throws {
        try KnotRemovalAllocation.charge(work: KnotRemovalAllocation.product(controls, 200), using: &execution)
        try KnotRemovalAllocation.charge(work: KnotRemovalAllocation.product(knots, 20), using: &execution)
        try KnotRemovalAllocation.charge(work: KnotRemovalAllocation.product(weights, 20), using: &execution)
    }

    private func admit(_ deviation: Double, _ tolerance: ModelingTolerance) throws {
        guard deviation.isFinite, deviation >= 0 else {
            throw BSplineKnotRemovalError.invalidInput("Knot removal requires a finite nonnegative deviation tolerance.")
        }
        do { try tolerance.validate() }
        catch { try KnotRemovalAllocation.rethrowAdmission(error); throw BSplineKnotRemovalError.invalidInput("Knot removal requires a valid modeling tolerance.") }
    }

    private func validate(_ source: BSplineCurve3D, _ tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        do { try source.validate(tolerance: tolerance, using: &execution) }
        catch { try KnotRemovalAllocation.rethrowAdmission(error); throw BSplineKnotRemovalError.invalidInput("Knot removal requires a structurally valid B-spline.") }
    }

    private func request(_ source: BSplineCurve3D, _ knot: Double, _ target: Int,
        _ tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double {
        guard knot.isFinite, target >= 0 else {
            throw BSplineKnotRemovalError.invalidInput("Knot identity must be finite and target multiplicity nonnegative.")
        }
        let parameter: Double
        do {
            if source.isPeriodic, source.knots[source.degree..<source.controlPointCount].contains(knot) {
                parameter = knot
            } else {
                parameter = try source.basisParameter(knot, tolerance: tolerance)
            }
        }
        catch { try KnotRemovalAllocation.rethrowAdmission(error); throw BSplineKnotRemovalError.invalidInput("Knot parameter has no representable periodic identity.") }
        if !source.isPeriodic {
            guard knot > source.knots[source.degree], knot < source.knots[source.controlPointCount] else {
                throw BSplineKnotRemovalError.invalidInput("Removing an open endpoint or exterior knot would change its domain.")
            }
        }
        guard try currentMultiplicity(source, parameter, using: &execution) > target else {
            throw BSplineKnotRemovalError.invalidInput("The knot must exist and its requested multiplicity must be lower.")
        }
        return parameter
    }

    private func currentMultiplicity(_ source: BSplineCurve3D, _ parameter: Double, using execution: inout OriginalQueryExecution) throws -> Int {
        let range = source.isPeriodic ? source.degree..<source.controlPointCount : 0..<source.knots.count
        var count = 0
        for index in range {
            try execution.consumeWork(1)
            if source.knots[index] == parameter { count += 1 }
        }
        return count
    }

    private func accept(_ bound: Double, _ requested: Double) throws {
        guard bound.isFinite else { throw BSplineKnotRemovalError.numericalFailure("Deviation enclosure exceeded finite arithmetic.") }
        guard bound <= requested else {
            throw BSplineKnotRemovalError.toleranceRejected(certifiedUpperBound: bound, requested: requested)
        }
    }

    private func line(_ surface: BSplineSurface3D, _ direction: SurfaceParameterDirection,
        _ index: Int, using execution: inout OriginalQueryExecution) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        if direction == .v {
            try execution.retainStorage(count: surface.controlPoints.count, stride: MemoryLayout<Point3D>.stride + MemoryLayout<Double>.stride)
        }
        return BSplineCurve3D(degree: direction == .u ? surface.uDegree : surface.vDegree,
            knots: direction == .u ? surface.uKnots : surface.vKnots,
            controlPoints: direction == .u ? surface.controlPoints[index] : surface.controlPoints.map { $0[index] },
            weights: direction == .u ? surface.weights[index] : surface.weights.map { $0[index] },
            isPeriodic: direction == .u ? surface.isUPeriodic : surface.isVPeriodic,
            periodicOrigin: direction == .u ? surface.uPeriodicOrigin : surface.vPeriodicOrigin)
    }
}
