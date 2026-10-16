import CADCore
import CADGeometry
import Synchronization
import Testing
@testable import CADTopology

@Suite("Native dependency callback and pcurve contracts")
struct NativeDependencyContractTests {
    private enum AdmissionFailure: Error { case rejected }
    private let tolerance = ModelingTolerance.standard

    private func execution(_ budget: OriginalQueryBudget) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 8))
    }

    private func retainedAdmissionFailure(_ error: any Error) -> Bool {
        if error is AdmissionFailure { return true }
        if let query = error as? OriginalQueryFailure { return retainedAdmissionFailure(query.originalError) }
        if let scalar = error as? ExactScalarFailure, case .admissionRejected(let cause) = scalar {
            return retainedAdmissionFailure(cause)
        }
        return false
    }

    @Test(.timeLimit(.minutes(1)))
    func classifierPropagatesCallerAdmissionFailure() throws {
        let curve = Curve3D.line(Line3D(origin: Point3D(x: 0, y: 0, z: 0), direction: .unitX))
        let visits = Mutex(0)
        let budget = try OriginalQueryBudget(consumeWorkUnits: { _ in
            let count = visits.withLock { value in value += 1; return value }
            if count == 2 { throw AdmissionFailure.rejected }
        })
        var admitted = try execution(budget)
        do {
            _ = try BRepEdgeGeometryClassifier().kind(curve: curve, from: 0, to: 1, tolerance: tolerance, using: &admitted)
            Issue.record("Rejected original admission returned a classifier result.")
        } catch { #expect(retainedAdmissionFailure(error)) }
        #expect(visits.withLock { $0 } == 2)
        #expect(try BRepEdgeGeometryClassifier().kind(curve: curve, from: 0, to: 1,
            tolerance: tolerance) == .open)
    }

    @Test(.timeLimit(.minutes(1)))
    func originalMagnitudeContainsScaledNormWithoutOverflow() {
        let large = OriginalDistanceMagnitude.bounds(3e200, 4e200, 0)
        #expect(large.lower <= 5e200 && large.upper >= 5e200)
        #expect(large.upper.isFinite)
        let zero = OriginalDistanceMagnitude.bounds(0, 0, 0)
        #expect(zero.lower == 0 && zero.upper == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func supportBoundLoopBorrowsAdmissionAndPreservesClosure() throws {
        let surface = Surface3D.plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 0), normal: .unitZ))
        let curves: [SurfaceParameterCurve] = [
            .constantV(v: 0, uStart: 0, uEnd: 1),
            .constantU(u: 1, vStart: 0, vEnd: 1),
            .constantV(v: 1, uStart: 1, uEnd: 0),
            .constantU(u: 0, vStart: 1, vEnd: 0)
        ]
        let visits = Mutex(0)
        let budget = try OriginalQueryBudget(consumeWorkUnits: { _ in visits.withLock { $0 += 1 } })
        var admitted = try execution(budget)
        let result = try SurfaceParameterLoopUnwrapper().unwrap(curves, on: surface,
            tolerance: tolerance, context: "Native callback contract", maximumSubdivisionDepth: 8,
            remainingSourceDepth: 16, using: &admitted)
        #expect(result.count == 4)
        let first = try #require(result.first?.chartStart)
        let last = try #require(result.last?.chartEnd)
        // Chart representatives obey the existing plane closure allowance;
        // they are proposals from original bounds, not exact source stations.
        #expect(abs(first.u - last.u) <= tolerance.distance * 8)
        #expect(abs(first.v - last.v) <= tolerance.distance * 8)
        #expect(result.indices.allSatisfy { result[$0].curve == curves[$0] })
        #expect(visits.withLock { $0 } > 4)
        var refusal = try execution(OriginalQueryBudget(consumeWorkUnits: { _ in throw AdmissionFailure.rejected }))
        do {
            _ = try SurfaceParameterLoopUnwrapper().unwrap(curves, on: surface,
                tolerance: tolerance, context: "Rejected admission", maximumSubdivisionDepth: 8,
                remainingSourceDepth: 16, using: &refusal)
            Issue.record("Rejected original admission returned an unwrapped loop.")
        } catch { #expect(retainedAdmissionFailure(error)) }
    }

    @Test(.timeLimit(.minutes(1)))
    func sphericalParameterEncloserUsesAnalyticChartProducer() throws {
        let curve = SurfaceParameterCurve.sphericalGreatCircle(cosine: .unitX, sine: .unitZ,
            startParameter: 0, endParameter: 0.25)
        let budget = try OriginalQueryBudget()
        var admission = try execution(budget)
        let result = try CertifiedSurfaceParameterCurveEncloser().enclosures(for: curve,
            maximumWidth: 1, tolerance: tolerance, using: &admission)
        #expect(!result.isEmpty)
        #expect(result.first?.lowerFraction == 0)
        #expect(result.last?.upperFraction == 1)
        // The canonical spherical chart uses atan2(-x, y); +X is longitude 3pi/2.
        let longitude = 1.5 * Double.pi
        #expect(result.allSatisfy { $0.u.lower <= longitude && $0.u.upper >= longitude })
        #expect(result.first!.v.lower <= 0 && result.last!.v.upper >= 0.25)
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicSeamBorrowsSameWorkAndRejectsFailure() throws {
        let surface = Surface3D.cylinder(Cylinder3D(origin: Point3D(x: 0, y: 0, z: 0), axis: .unitZ, radius: 1))
        let first = SurfaceParameterCurve.constantU(u: 0, vStart: 0, vEnd: 1)
        let second = SurfaceParameterCurve.constantU(u: 2 * Double.pi, vStart: 1, vEnd: 0)
        let visits = Mutex(0)
        let budget = try OriginalQueryBudget(consumeWorkUnits: { _ in visits.withLock { $0 += 1 } })
        var admitted = try execution(budget)
        #expect(try OriginalPeriodicSeamProof.proves(first: first, second: second, on: surface,
            tolerance: tolerance, remainingSourceDepth: 16, maximumSubdivisionDepth: 8,
            using: &admitted))
        #expect(visits.withLock { $0 } > 4)
        var refusal = try execution(OriginalQueryBudget(consumeWorkUnits: { _ in throw AdmissionFailure.rejected }))
        do {
            _ = try OriginalPeriodicSeamProof.proves(first: first, second: second, on: surface,
                tolerance: tolerance, remainingSourceDepth: 16, maximumSubdivisionDepth: 8,
                using: &refusal)
            Issue.record("Rejected original admission returned a seam proof.")
        } catch { #expect(retainedAdmissionFailure(error)) }
    }
}
