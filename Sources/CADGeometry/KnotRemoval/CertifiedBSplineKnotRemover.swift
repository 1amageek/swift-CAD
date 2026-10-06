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
        var budget = try KnotRemovalBudget(options)
        try admit(maximumDeviation, tolerance)
        try admitScan(source.controlPointCount, source.knots.count, source.weights.count, &budget)
        try validate(source, tolerance)
        let parameter = try request(source, knot, target, tolerance)
        let multiplicity = currentMultiplicity(source, parameter)
        var result = source
        for _ in target..<multiplicity {
            result = try KnotRemovalConstruction.removeOne(result, at: parameter,
                tolerance: tolerance, budget: &budget)
        }
        let bound = try KnotRemovalCertificate.bound(source: [source], candidate: [result], budget: &budget)
        try accept(bound, maximumDeviation)
        return .init(geometry: result, removedMultiplicity: multiplicity - target,
            certifiedMaximumDeviation: bound)
    }

    public func reducingMultiplicity(of source: BSplineCurve2D, at knot: Double, to target: Int,
        maximumDeviation: Double, options: BSplineKnotRemovalOptions = .init(),
        tolerance: ModelingTolerance) throws -> BSplineKnotRemovalResult<BSplineCurve2D> {
        var budget = try KnotRemovalBudget(options)
        try admitScan(source.controlPointCount, source.knots.count, source.weights.count, &budget)
        try budget.charge(scalars: KnotRemovalBudget.product(source.controlPointCount, 3))
        let lifted = BSplineCurve3D(degree: source.degree, knots: source.knots,
            controlPoints: source.controlPoints.map { Point3D(x: $0.x, y: $0.y, z: 0) }, weights: source.weights)
        try admit(maximumDeviation, tolerance)
        try validate(lifted, tolerance)
        let parameter = try request(lifted, knot, target, tolerance)
        let multiplicity = currentMultiplicity(lifted, parameter)
        var result = lifted
        for _ in target..<multiplicity {
            result = try KnotRemovalConstruction.removeOne(result, at: parameter,
                tolerance: tolerance, budget: &budget)
        }
        let bound = try KnotRemovalCertificate.bound(source: [lifted], candidate: [result], budget: &budget)
        try accept(bound, maximumDeviation)
        try budget.charge(scalars: KnotRemovalBudget.product(result.controlPointCount, 2))
        return .init(geometry: BSplineCurve2D(degree: result.degree, knots: result.knots,
            controlPoints: result.controlPoints.map { Point2D(x: $0.x, y: $0.y) }, weights: result.weights),
            removedMultiplicity: multiplicity - target, certifiedMaximumDeviation: bound)
    }

    public func reducingMultiplicity(of source: BSplineSurface3D, direction: SurfaceParameterDirection,
        at knot: Double, to target: Int, maximumDeviation: Double,
        options: BSplineKnotRemovalOptions = .init(),
        tolerance: ModelingTolerance) throws -> BSplineKnotRemovalResult<BSplineSurface3D> {
        var budget = try KnotRemovalBudget(options)
        try admit(maximumDeviation, tolerance)
        try budget.charge(work: source.controlPoints.count)
        for row in source.controlPoints { try budget.charge(work: KnotRemovalBudget.product(row.count, 200)) }
        try budget.charge(work: source.weights.count)
        for row in source.weights { try budget.charge(work: KnotRemovalBudget.product(row.count, 20)) }
        try budget.charge(work: KnotRemovalBudget.product(source.uKnots.count, 20))
        try budget.charge(work: KnotRemovalBudget.product(source.vKnots.count, 20))
        do { try source.validate(tolerance: tolerance) }
        catch { throw BSplineKnotRemovalError.invalidInput("Knot removal requires a valid tensor surface.") }
        let perpendicular = direction == .u ? source.vControlPointCount : source.uControlPointCount
        let axisCount = direction == .u ? source.uControlPointCount : source.vControlPointCount
        // Retained original/final line buffers and assembled output net are all admitted first.
        try budget.charge(scalars: KnotRemovalBudget.product(12,
            KnotRemovalBudget.product(perpendicular, axisCount)))
        let original = (0..<perpendicular).map { line(source, direction, $0) }
        let parameter = try request(original[0], knot, target, tolerance)
        let multiplicity = currentMultiplicity(original[0], parameter)
        var reduced: [BSplineCurve3D] = []
        reduced.reserveCapacity(perpendicular)
        for initial in original {
            var curve = initial
            for _ in target..<multiplicity {
                curve = try KnotRemovalConstruction.removeOne(curve, at: parameter,
                    tolerance: tolerance, budget: &budget)
            }
            reduced.append(curve)
        }
        let bound = try KnotRemovalCertificate.bound(source: original, candidate: reduced, budget: &budget)
        try accept(bound, maximumDeviation)
        let first = reduced[0]
        var points: [[Point3D]]
        var weights: [[Double]]
        if direction == .u {
            points = reduced.map({ $0.controlPoints })
            weights = reduced.map({ $0.weights })
        } else {
            points = (0..<first.controlPointCount).map { index in reduced.map { $0.controlPoints[index] } }
            weights = (0..<first.controlPointCount).map { index in reduced.map { $0.weights[index] } }
        }
        let surface = BSplineSurface3D(uDegree: source.uDegree, vDegree: source.vDegree,
            uKnots: direction == .u ? first.knots : source.uKnots,
            vKnots: direction == .v ? first.knots : source.vKnots,
            controlPoints: points, weights: weights, isUPeriodic: source.isUPeriodic,
            isVPeriodic: source.isVPeriodic, uPeriodicOrigin: source.uPeriodicOrigin,
            vPeriodicOrigin: source.vPeriodicOrigin)
        do { try surface.validate(tolerance: tolerance) }
        catch { throw BSplineKnotRemovalError.numericalFailure("Reduced tensor lines lost the shared axis contract.") }
        return .init(geometry: surface, removedMultiplicity: multiplicity - target,
            certifiedMaximumDeviation: bound)
    }

    private func admitScan(_ controls: Int, _ knots: Int, _ weights: Int,
        _ budget: inout KnotRemovalBudget) throws {
        try budget.charge(work: KnotRemovalBudget.product(controls, 200))
        try budget.charge(work: KnotRemovalBudget.product(knots, 20))
        try budget.charge(work: KnotRemovalBudget.product(weights, 20))
    }

    private func admit(_ deviation: Double, _ tolerance: ModelingTolerance) throws {
        guard deviation.isFinite, deviation >= 0 else {
            throw BSplineKnotRemovalError.invalidInput("Knot removal requires a finite nonnegative deviation tolerance.")
        }
        do { try tolerance.validate() }
        catch { throw BSplineKnotRemovalError.invalidInput("Knot removal requires a valid modeling tolerance.") }
    }

    private func validate(_ source: BSplineCurve3D, _ tolerance: ModelingTolerance) throws {
        do { try source.validate(tolerance: tolerance) }
        catch { throw BSplineKnotRemovalError.invalidInput("Knot removal requires a structurally valid B-spline.") }
    }

    private func request(_ source: BSplineCurve3D, _ knot: Double, _ target: Int,
        _ tolerance: ModelingTolerance) throws -> Double {
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
        catch { throw BSplineKnotRemovalError.invalidInput("Knot parameter has no representable periodic identity.") }
        if !source.isPeriodic {
            guard knot > source.knots[source.degree], knot < source.knots[source.controlPointCount] else {
                throw BSplineKnotRemovalError.invalidInput("Removing an open endpoint or exterior knot would change its domain.")
            }
        }
        guard currentMultiplicity(source, parameter) > target else {
            throw BSplineKnotRemovalError.invalidInput("The knot must exist and its requested multiplicity must be lower.")
        }
        return parameter
    }

    private func currentMultiplicity(_ source: BSplineCurve3D, _ parameter: Double) -> Int {
        let range = source.isPeriodic ? source.degree..<source.controlPointCount : 0..<source.knots.count
        return range.reduce(0) { $0 + (source.knots[$1] == parameter ? 1 : 0) }
    }

    private func accept(_ bound: Double, _ requested: Double) throws {
        guard bound.isFinite else { throw BSplineKnotRemovalError.numericalFailure("Deviation enclosure exceeded finite arithmetic.") }
        guard bound <= requested else {
            throw BSplineKnotRemovalError.toleranceRejected(certifiedUpperBound: bound, requested: requested)
        }
    }

    private func line(_ surface: BSplineSurface3D, _ direction: SurfaceParameterDirection,
        _ index: Int) -> BSplineCurve3D {
        BSplineCurve3D(degree: direction == .u ? surface.uDegree : surface.vDegree,
            knots: direction == .u ? surface.uKnots : surface.vKnots,
            controlPoints: direction == .u ? surface.controlPoints[index] : surface.controlPoints.map { $0[index] },
            weights: direction == .u ? surface.weights[index] : surface.weights.map { $0[index] },
            isPeriodic: direction == .u ? surface.isUPeriodic : surface.isVPeriodic,
            periodicOrigin: direction == .u ? surface.uPeriodicOrigin : surface.vPeriodicOrigin)
    }
}
