import CADCore
import Foundation
import Testing
@testable import CADGeometry

@Suite struct CurveIntersectionSupportTests {
    private let tolerance = ModelingTolerance.standard

    // These sources exercise retained metadata, not public intersection publication.
    private func retainedSource() throws -> (curve: Curve3D, source: CertifiedPlaneTorusIntersectionCurve) {
        let normal = try Vector3D(x: 0.6, y: 0.2, z: 1).normalized(tolerance: tolerance.distance)
        let plane = Surface3D.analytic(.plane(origin: .origin, normal: normal))
        let torus = Surface3D.analytic(.torus(center: .origin, axis: .unitZ, majorRadius: 3, minorRadius: 1))
        let source = try CertifiedPlaneTorusIntersectionCurve(planeSurface: plane, torusSurface: torus,
            componentKind: .positiveFullBranch, lowerMinorAngle: 0, upperMinorAngle: 2 * Double.pi,
            tolerance: tolerance)
        return (.analytic(.planeTorus(source)), source)
    }

    private func execution(_ budget: OriginalQueryBudget, sourceDepth: Int = 16) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32, remainingSourceDepth: sourceDepth))
    }

    @Test(.timeLimit(.minutes(1)))
    func retainedHostsSurviveSourceLifetimeButNearbyHostsDecline() throws {
        // The producing function has returned; the curve must retain its support values.
        let retained = try retainedSource()
        let plane = retained.source.planeSurface
        let torus = retained.source.torusSurface
        #expect(try retained.curve.otherIntersectionSupportSurface(on: plane, tolerance: tolerance) == torus)
        #expect(try retained.curve.otherIntersectionSupportSurface(on: torus, tolerance: tolerance) == plane)
        let normal = try Vector3D(x: 0.6, y: 0.2, z: 1).normalized(tolerance: tolerance.distance)
        let nearby = Surface3D.analytic(.plane(origin: .origin + normal * (tolerance.distance / 2), normal: normal))
        #expect(try DefaultAnalyticSurfaceEquivalenceResolver().areEquivalent(plane, nearby, tolerance: tolerance))
        #expect(try retained.curve.otherIntersectionSupportSurface(on: nearby, tolerance: tolerance) == nil)

        var direct = try execution(OriginalQueryBudget())
        #expect(try retained.curve.otherIntersectionSupportSurface(on: plane, tolerance: tolerance, using: &direct) == torus)
        #expect(try retained.curve.otherIntersectionSupportSurface(on: nearby, tolerance: tolerance, using: &direct) == nil)
        let parameterImage = Curve3D.parameterImage(try ParameterImageCurve3D(source: retained.curve, gain: 2, tolerance: tolerance))
        #expect(try parameterImage.otherIntersectionSupportSurface(on: plane, tolerance: tolerance, using: &direct) == torus)
        #expect(direct.sourceDepth == 1)

        let exact = try CertifiedAnalyticAnalyticIntersectionCurve(planeTorusCurve: retained.source,
            firstSurface: plane, secondSurface: torus, tolerance: tolerance)
        let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(intersection: exact, role: .first, tolerance: tolerance)
        let lift = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface: plane, parameterCurve: .certifiedAnalyticPair(pcurve)))
        #expect(try lift.otherIntersectionSupportSurface(on: plane, tolerance: tolerance, using: &direct) == torus)
    }

    @Test(.timeLimit(.minutes(1)))
    func rigidSupportTransferKeepsOriginalHostAndSourceDepth() throws {
        let retained = try retainedSource()
        let transform = RigidTransform3D.translated(by: Vector3D(x: 3, y: -2, z: 1))
        let image = Curve3D.rigidImage(try RigidImageCurve3D(source: retained.curve, transform: transform, tolerance: tolerance))
        let host = try transform.applying(to: retained.source.planeSurface, tolerance: tolerance)
        let other = try transform.applying(to: retained.source.torusSurface, tolerance: tolerance)
        var direct = try execution(OriginalQueryBudget())
        #expect(try image.otherIntersectionSupportSurface(on: host, tolerance: tolerance, using: &direct) == other)
        #expect(direct.sourceDepth == 1)
        var limited = try execution(OriginalQueryBudget(), sourceDepth: 0)
        do {
            _ = try image.otherIntersectionSupportSurface(on: host, tolerance: tolerance, using: &limited)
            Issue.record("Source-depth exhaustion must throw, never decline with nil.")
        } catch {
            guard let failure = retainedFailure(error) else { throw error }
            #expect(failure.context.resource?.axis == .sourceDepth)
            #expect(failure.kernelFailure.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func lookupKeepsCallerWorkAndCancellation() throws {
        let retained = try retainedSource()
        let host = retained.source.planeSurface
        let measured = try OriginalQueryBudget()
        var measuring = try execution(measured)
        #expect(try retained.curve.otherIntersectionSupportSurface(on: host, tolerance: tolerance, using: &measuring) != nil)
        let required = measured.snapshot.work
        #expect(required > 0)
        let exactBudget = try OriginalQueryBudget(workLimit: required)
        var exact = try execution(exactBudget)
        #expect(try retained.curve.otherIntersectionSupportSurface(on: host, tolerance: tolerance, using: &exact) != nil)
        for budget in [try OriginalQueryBudget(workLimit: required - 1), exactBudget] {
            var limited = try execution(budget)
            do {
                _ = try retained.curve.otherIntersectionSupportSurface(on: host, tolerance: tolerance, using: &limited)
                Issue.record("A support lookup must not reset the caller's work budget.")
            } catch {
                guard let scalar = geometryTestOriginalFailure(error) as? ExactScalarFailure,
                      case .resourceLimit(.work) = scalar else { throw error }
            }
        }
        let cancelledBudget = try OriginalQueryBudget(checkpoint: { throw ExactScalarFailure.cancelled })
        var cancelled = try execution(cancelledBudget)
        do {
            _ = try retained.curve.otherIntersectionSupportSurface(on: host, tolerance: tolerance, using: &cancelled)
            Issue.record("Support lookup must propagate caller cancellation.")
        } catch { #expect(geometryTestIsCancelled(error)) }
        #expect(cancelledBudget.snapshot.work == 0)
    }

    private func retainedFailure(_ error: any Error) -> OriginalQueryFailure? {
        if let retained = error as? OriginalQueryFailure { return retained }
        if let scalar = error as? ExactScalarFailure, case .admissionRejected(let underlying) = scalar {
            return retainedFailure(underlying)
        }
        return nil
    }
}
