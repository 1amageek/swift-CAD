import CADCore
@testable import CADGeometry
import Synchronization

/// Exercises the ordinary and callback entry points after their L5/L6 migration.
public enum L6PublicCurveSurfaceFixtures {
    private enum Rejection: Error, Equatable { case caller }
    private struct Counts { var work = 0; var bytes = 0; var allocations = 0 }
    private final class Caller: Sendable {
        let counts = Mutex(Counts())
        let maximumWork: Int
        let maximumBytes: Int
        let cancellingAllocation: Int?
        init(work: Int = 80_000_000, bytes: Int = 1_073_741_824, cancellingAllocation: Int? = nil) {
            maximumWork = work; maximumBytes = bytes; self.cancellingAllocation = cancellingAllocation
        }
        func consume(_ depth: Int) throws {
            try counts.withLock { state in
                guard depth == 0, state.work < maximumWork else { throw Rejection.caller }
                state.work += 1
            }
        }
        func retain(_ bytes: Int) throws {
            try counts.withLock { state in
                let sum = state.bytes.addingReportingOverflow(bytes)
                guard bytes >= 0, !sum.overflow, sum.partialValue <= maximumBytes else { throw Rejection.caller }
                state.bytes = sum.partialValue; state.allocations += 1
                if state.allocations == cancellingAllocation { throw CancellationError() }
            }
        }
        var allocations: Int { counts.withLock { $0.allocations } }
        var work: Int { counts.withLock { $0.work } }
    }

    private static func rich(_ curve: BSplineCurve3D, _ surface: BSplineSurface3D,
        options: CurveSurfaceIntersectionOptions = .init(), caller: Caller? = nil,
        sourceDepth: Int = 1, algebraDepth: Int = 32,
        tolerance: ModelingTolerance = .standard) throws -> CurveSurfaceIntersectionResult {
        let resolver = DefaultCurveSurfaceIntersector()
        if let caller {
            return try resolver.intersectionResult(curve: .bSpline(curve), surface: .bSpline(surface),
                options: options, tolerance: tolerance, maximumSpanCount: 1, maximumSubdivisionDepth: 0,
                remainingSourceDepth: sourceDepth, consumeWork: { try caller.consume($0) },
                consumeStorage: { try caller.retain($0) }, maximumAlgebraicDepth: algebraDepth)
        }
        return try resolver.intersectionResult(curve: .bSpline(curve), surface: .bSpline(surface),
            options: options, tolerance: tolerance)
    }

    private static func discrete(_ curve: BSplineCurve3D, _ surface: BSplineSurface3D,
        options: CurveSurfaceIntersectionOptions = .init(), caller: Caller? = nil,
        tolerance: ModelingTolerance = .standard) throws -> [CurveSurfaceIntersection] {
        let resolver = DefaultCurveSurfaceIntersector()
        if let caller {
            return try resolver.intersections(curve: .bSpline(curve), surface: .bSpline(surface),
                options: options, tolerance: tolerance, maximumSpanCount: 1, maximumSubdivisionDepth: 0,
                remainingSourceDepth: 1, consumeWork: { try caller.consume($0) },
                consumeStorage: { try caller.retain($0) }, maximumAlgebraicDepth: 32)
        }
        return try resolver.intersections(curve: .bSpline(curve), surface: .bSpline(surface),
            options: options, tolerance: tolerance)
    }

    public static func verifyWeightedContact() throws {
        let curve = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1], controlPoints: [
            .init(x: -1, y: 0.25, z: 1), .init(x: 0, y: 0.25, z: -1), .init(x: 1, y: 0.25, z: 1)])
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [
                [.init(x: -2, y: -2, z: 0), .init(x: 2, y: -2, z: 0)],
                [.init(x: -2, y: 2, z: 0), .init(x: 2, y: 2, z: 0)]],
            weights: [[1, 1.5], [2, 1]])
        let tolerance = ModelingTolerance(distance: 1e-9, angle: 1e-10)
        let options = CurveSurfaceIntersectionOptions(maximumSubdivisionDepth: 12, maximumIterations: 64)
        let maximumWork = 16_777_216
        let maximumBytes = maximumWork * MemoryLayout<OriginalRationalIntersectionCells.Cell>.stride
        var baseline: [CurveSurfaceIntersection]? = nil
        for admitted in [false, true] {
            let richCaller: Caller? = admitted ? Caller(work: maximumWork, bytes: maximumBytes) : nil
            let discreteCaller: Caller? = admitted ? Caller(work: maximumWork, bytes: maximumBytes) : nil
            let result = try rich(curve, surface, options: options, caller: richCaller, tolerance: tolerance)
            let points = try discrete(curve, surface, options: options, caller: discreteCaller, tolerance: tolerance)
            guard let owner = result.originalExactGeometricRelation, let point = result.points.first else {
                throw NativeExactFixtures.Failure.invalidEvidence
            }
            try NativeExactFixtures.require(result.points.count == 1 && points == result.points)
            if let baseline { try NativeExactFixtures.require(points == baseline) }
            else { baseline = points }
            try NativeExactFixtures.require(result.originalNativePoints == nil && result.originalNativeRelations == nil
                && !result.hasPositiveDimensionalSolutions && !owner.hasPositiveDimensionalImage)
            try NativeExactFixtures.require(point.kind == .tangent && point.curveParameter == 0.5
                && point.residual <= tolerance.distance && point.iterations > 0 && point.iterations <= 64)
            let expectedU = (15 - Double(193).squareRoot()) / 2
            let expectedV = (7 - 4 * expectedU) / 9
            try NativeExactFixtures.require(abs(point.surfaceU - expectedU) <= tolerance.distance
                && abs(point.surfaceV - expectedV) <= tolerance.distance)
            let curvePoint = try curve.point(at: point.curveParameter, tolerance: tolerance)
            let surfacePoint = try surface.point(u: point.surfaceU, v: point.surfaceV, tolerance: tolerance)
            try NativeExactFixtures.require(point.point.isApproximatelyEqual(to: .init(x: 0, y: 0.25, z: 0),
                tolerance: tolerance.distance) && (curvePoint - surfacePoint).length <= tolerance.distance)
            if let richCaller, let discreteCaller {
                try NativeExactFixtures.require(richCaller.work > 0 && richCaller.work <= maximumWork
                    && discreteCaller.work > 0 && discreteCaller.work <= maximumWork)
            }
            try weightedContactProof(owner, curve: curve, surface: surface)
        }
        print("PASS migrated weighted CS tangent, original TUV/equations, all four routes under work16777216/depth32")
    }

    private static func weightedContactProof(_ owner: borrowing NativeExactGeometricRelation,
        curve: BSplineCurve3D, surface: BSplineSurface3D) throws {
        guard case .curveSurface(let retainedCurve, let retainedSurface, let range, let domain) = owner.parameterRelation.source else {
            throw NativeExactFixtures.Failure.invalidEvidence
        }
        try NativeExactFixtures.require(retainedCurve == curve && retainedSurface == surface && range == nil && domain == nil)
        let relation = owner.parameterRelation.relation, source = relation.original
        try NativeExactFixtures.require(relation.components.count == 1)
        try NativeExactFixtures.require(owner.geometry.strata.count == 1)
        // CS retains its original curve-image proof; isolatedParameters is the SSI shortcut.
        try NativeExactFixtures.require(owner.geometry.evidenceKind == .originalCurveImage)
        try NativeExactFixtures.require(source.rawEquations.count == 3)
        try NativeExactFixtures.require(source.firstParameters == 0..<1)
        try NativeExactFixtures.require(source.secondParameters == 1..<3)
        var ledger = try NativeExactFixtures.ledger()
        let partition = relation.selection.partition
        let cells = try ExactRealCellDomain<ExactRationalScalarDomain>(retaining: partition.source, using: &ledger)
        let cell = try owner.geometry.sourceCell(of: owner.geometry.identifier(at: 0))
        let sample = try cells.sample(of: cell, in: partition, using: &ledger)
        try NativeExactFixtures.require(sample.coordinates.count == 3
            && owner.geometry.strata[0].parameterDimension == 0 && owner.geometry.strata[0].imageDimension == 0)
        let field = sample.field
        try NativeExactFixtures.require(field.compare(sample.coordinates[0], field.binary64(exactly: 0.5,
            using: &ledger), using: &ledger) == .equal)
        // Evaluate every original homogeneous equation at the retained exact TUV,
        // independently of the numerical residual and the reduced predicate.
        for law in source.rawEquations {
            try ledger.admitDepth(value: law.depth.value, coefficient: law.depth.coefficient)
            var sum = try field.integer(0, using: &ledger)
            for term in law.terms {
                var value = try field.importing(term.coefficient, using: &ledger)
                for axis in term.powers.indices {
                    for _ in 0..<term.powers[axis] {
                        value = try field.multiplying(value, sample.coordinates[axis], using: &ledger)
                    }
                }
                sum = try field.adding(sum, value, using: &ledger)
            }
            try NativeExactFixtures.require(field.sign(of: sum, using: &ledger) == .zero)
        }
        let u = sample.coordinates[1], v = sample.coordinates[2]
        let quadratic = try field.adding(field.subtracting(field.multiplying(u, u, using: &ledger),
            field.multiplying(field.integer(15, using: &ledger), u, using: &ledger), using: &ledger),
            field.integer(8, using: &ledger), using: &ledger)
        let correspondence = try field.subtracting(field.adding(field.multiplying(field.integer(4, using: &ledger),
            u, using: &ledger), field.multiplying(field.integer(9, using: &ledger), v, using: &ledger), using: &ledger),
            field.integer(7, using: &ledger), using: &ledger)
        try NativeExactFixtures.require(field.sign(of: quadratic, using: &ledger) == .zero
            && field.sign(of: correspondence, using: &ledger) == .zero)
    }

    public static func verify() throws {
        let plane = NativeExactFixtures.plane()
        for admitted in [false, true] {
            let caller: Caller? = admitted ? Caller() : nil
            var curve = NativeExactFixtures.curve([-1, 1])
            let result = try rich(curve, plane, caller: caller)
            guard let owner = result.originalExactGeometricRelation else { throw NativeExactFixtures.Failure.invalidEvidence }
            try NativeExactFixtures.require(result.points.count == 1 && result.points[0].kind == .transverse)
            try NativeExactFixtures.require(result.originalNativePoints == nil && result.originalNativeRelations == nil)
            curve.controlPoints.removeAll()
            if case .curveSurface(let retained, _, _, _) = owner.parameterRelation.source {
                try NativeExactFixtures.require(retained.controlPoints.count == 2)
            } else { throw NativeExactFixtures.Failure.invalidEvidence }
            var ledger = try NativeExactFixtures.ledger()
            try NativeExactFixtures.member([(1, 2), (1, 4), (1, 2)], owner.parameterRelation, expected: true, &ledger)
            let points = try discrete(NativeExactFixtures.curve([-1, 1]), plane,
                caller: admitted ? Caller() : nil)
            try NativeExactFixtures.require(points.count == 1 && points[0].curveParameter == 0.5)
            let empty = try rich(NativeExactFixtures.curve([1, 2]), plane,
                caller: admitted ? Caller() : nil)
            try NativeExactFixtures.require(empty.points.isEmpty && empty.originalExactGeometricRelation?.geometry.isEmpty == true)
            let positive = try rich(NativeExactFixtures.curve([0, 0]), plane,
                caller: admitted ? Caller() : nil)
            try NativeExactFixtures.require(positive.hasPositiveDimensionalSolutions && positive.points.isEmpty)
            try nonDiscrete { _ = try discrete(NativeExactFixtures.curve([0, 0]), plane,
                caller: admitted ? Caller() : nil) }
            print("PASS migrated CS rich/discrete caller=\(admitted), retained lifetime, empty and positive owner")
        }
        let folded = BSplineSurface3D(uDegree: 2, vDegree: 1,
            uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [
                [.init(x: 1, y: 0, z: 0), .init(x: -1, y: 0, z: 0), .init(x: 1, y: 0, z: 0)],
                [.init(x: 1, y: 1, z: 0), .init(x: -1, y: 1, z: 0), .init(x: 1, y: 1, z: 0)]])
        let tuples = try rich(NativeExactFixtures.curve([-1, 1]), folded)
        try NativeExactFixtures.require(tuples.points.count == 2 && tuples.points[0].surfaceU != tuples.points[1].surfaceU)
        try NativeExactFixtures.require(tuples.points.allSatisfy { $0.point.x == 0.25 && $0.point.y == 0.5 })
        let weighted = try rich(NativeExactFixtures.curve([-1, 1], weights: [1, 2]), plane)
        try NativeExactFixtures.require(weighted.points.count == 1 && abs(weighted.points[0].curveParameter - 1.0 / 3) <= ModelingTolerance.standard.distance)
        let singleton = try rich(NativeExactFixtures.curve([-1, 1]), plane,
            options: .init(curveRange: .init(lower: 0.5, upper: 0.5)))
        try NativeExactFixtures.require(singleton.points.count == 1 && singleton.points[0].curveParameter == 0.5)
        try failures(plane, folded)
        try verifyApplicability()
        print("PASS migrated CS distinct UV, rational weights, singleton and independent caller failures")
    }

    public static func verifyApplicability() throws {
        let curve = NativeExactFixtures.curve([-1, 1]), plane = NativeExactFixtures.plane()
        for mode in 0..<3 {
            var source = curve, target = plane
            if mode != 1 { source.knots = [-2, -1, 1, 2] }
            if mode != 0 { target.uKnots = [-2, -1, 1, 2]; target.vKnots = [-2, -1, 1, 2] }
            let result = try rich(source, target)
            guard let owner = result.originalExactGeometricRelation, result.points.count == 1 else {
                throw NativeExactFixtures.Failure.invalidEvidence
            }
            var ledger = try NativeExactFixtures.ledger()
            let parameters: [(Int, Int)] = [mode == 1 ? (1, 2) : (0, 1),
                mode == 0 ? (1, 4) : (-1, 2), mode == 0 ? (1, 2) : (0, 1)]
            try NativeExactFixtures.member(parameters, owner.parameterRelation, expected: true, &ledger)
        }
        let multiCurve = BSplineCurve3D(degree: 1, knots: [0, 0, 0.5, 1, 1], controlPoints: [
            curve.controlPoints[0], .init(x: 0.25, y: 0.5, z: 0), curve.controlPoints[1]])
        let multiSurface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 0.5, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [
                [.init(x: 0, y: 0, z: 0), .init(x: 0.5, y: 0, z: 0), .init(x: 1, y: 0, z: 0)],
                [.init(x: 0, y: 1, z: 0), .init(x: 0.5, y: 1, z: 0), .init(x: 1, y: 1, z: 0)]])
        var periodicCurve = curve, periodicSurface = plane
        periodicCurve.isPeriodic = true; periodicCurve.knots = [0, 1, 2, 3]
        periodicCurve.controlPoints[1] = periodicCurve.controlPoints[0]
        periodicSurface.isUPeriodic = true; periodicSurface.uKnots = [0, 1, 2, 3]
        for row in periodicSurface.controlPoints.indices {
            periodicSurface.controlPoints[row][1] = periodicSurface.controlPoints[row][0]
        }
        for (source, target) in [(multiCurve, plane), (curve, multiSurface),
            (periodicCurve, plane), (curve, periodicSurface)] {
            try source.validate(tolerance: .standard); try target.validate(tolerance: .standard)
            let caller = Caller(work: 0, bytes: 0)
            let invocation = try CurveSurfaceQueryInvocation(maximumSubdivisionDepth: 0,
                maximumSpanCount: 64, remainingSourceDepth: 1, consumeWork: { try caller.consume($0) },
                consumeStorage: { try caller.retain($0) }, maximumAlgebraicDepth: 32)
            let result = try NativeExactPublicCurveSurfaceProducer().resolve(curve: .bSpline(source),
                surface: .bSpline(target), options: .init(), tolerance: .standard,
                invocation: invocation, retainingRelations: true)
            try NativeExactFixtures.require(result == nil && caller.work == 0 && caller.allocations == 0)
        }
        let fallback = Caller()
        let legacy = try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(multiCurve),
            surface: .bSpline(plane), options: .init(), tolerance: .standard,
            maximumSpanCount: 64, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
            consumeWork: { try fallback.consume($0) }, consumeStorage: { try fallback.retain($0) },
            maximumAlgebraicDepth: 32)
        try NativeExactFixtures.require(legacy.points.count == 1 && legacy.originalExactGeometricRelation == nil
            && legacy.originalNativePoints?.coverageChartCount == 2 && fallback.work > 0)
        for degenerate in [false, true] {
            var source = curve
            source.knots = degenerate ? [0, 0, 0, 0] : [0, 0, 1]
            let caller = Caller()
            do { _ = try rich(source, plane, caller: caller); throw NativeExactFixtures.Failure.invalidEvidence }
            catch GeometryError.invalidDistance(let value) {
                try NativeExactFixtures.require(value == (degenerate ? 0 : 3) && caller.work > 0)
            }
        }
        print("PASS migrated CS nonclamped source, uncharged family decline and original multi-span fallback")
    }

    private static func failures(_ plane: BSplineSurface3D, _ folded: BSplineSurface3D) throws {
        let curve = NativeExactFixtures.curve([-1, 1])
        for caller in [Caller(work: 0), Caller(bytes: 0)] {
            do { _ = try rich(curve, plane, caller: caller); throw NativeExactFixtures.Failure.invalidEvidence }
            catch Rejection.caller { }
        }
        try resource { _ = try rich(curve, plane, options: .init(maximumSubdivisionCells: 1), caller: Caller()) }
        try resource { _ = try rich(curve, plane, caller: Caller(), sourceDepth: 0) }
        try resource { _ = try rich(NativeExactFixtures.curve([-0.5, -0.5, 0.5]), plane,
            options: .init(maximumPolynomialDegree: 1), caller: Caller()) }
        try resource { _ = try rich(NativeExactFixtures.curve([-0.5, -0.5, 0.5]), plane,
            caller: Caller(), algebraDepth: 0) }
        try resource { _ = try rich(curve, folded, options: .init(maximumCandidateCount: 1), caller: Caller()) }
        var invalid = curve; invalid.weights = [1, -1]
        let charged = Caller()
        do { _ = try rich(invalid, plane, caller: charged); throw NativeExactFixtures.Failure.invalidEvidence }
        catch is GeometryError { try NativeExactFixtures.require(charged.work > 0) }
        for empty in [false, true] {
            let source = NativeExactFixtures.curve(empty ? [1, 2] : [-1, 1])
            let measured = Caller()
            _ = try rich(source, plane, caller: measured)
            let cancelled = Caller(cancellingAllocation: measured.allocations)
            do { _ = try rich(source, plane, caller: cancelled); throw NativeExactFixtures.Failure.invalidEvidence }
            catch is CancellationError { }
            try NativeExactFixtures.require(cancelled.allocations == measured.allocations)
        }
    }

    private static func resource(_ body: () throws -> Void) throws {
        do { try body(); throw NativeExactFixtures.Failure.invalidEvidence }
        catch let error as KernelError { try NativeExactFixtures.require(error.code == .resourceLimitExceeded) }
    }
    private static func nonDiscrete(_ body: () throws -> Void) throws {
        do { try body(); throw NativeExactFixtures.Failure.invalidEvidence }
        catch let error as KernelError { try NativeExactFixtures.require(error.code == .nonDiscreteIntersection) }
    }
}
