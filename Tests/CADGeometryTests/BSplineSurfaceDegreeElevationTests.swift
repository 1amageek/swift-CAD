import CADCore
import Foundation
import Testing
@testable import CADGeometry

/// Raising a B-spline surface's degree keeps the surface, its continuity and its weights.
@Suite struct BSplineSurfaceDegreeElevationTests {
    private let tolerance = ModelingTolerance.standard

    /// A rational surface, quadratic in u with a doubled interior knot and cubic in v with a simple
    /// interior knot.
    private func surface() -> BSplineSurface3D {
        let uCount = 5
        let vCount = 5
        var points: [[Point3D]] = []
        var weights: [[Double]] = []
        for v in 0..<vCount {
            points.append((0..<uCount).map { u in
                Point3D(x: Double(u), y: Double(v), z: sin(Double(u * 3 + v)) * 0.4)
            })
            weights.append((0..<uCount).map { u in 1 + 0.25 * Double((u + v) % 3) })
        }
        return BSplineSurface3D(
            uDegree: 2, vDegree: 3,
            uKnots: [0, 0, 0, 0.4, 0.4, 1, 1, 1],
            vKnots: [0, 0, 0, 0, 0.5, 1, 1, 1, 1],
            controlPoints: points, weights: weights
        )
    }

    @Test(arguments: [SurfaceParameterDirection.u, .v])
    func theRaisedSurfaceIsTheSameSurface(direction: SurfaceParameterDirection) throws {
        let original = surface()
        let raised = try original.elevatingDegree(direction: direction, tolerance: tolerance)
        switch direction {
        case .u:
            #expect(raised.uDegree == 3)
            #expect(raised.uKnots == [0, 0, 0, 0, 0.4, 0.4, 0.4, 1, 1, 1, 1])
            #expect(raised.uControlPointCount == 7)
            #expect(raised.vKnots == original.vKnots)
        case .v:
            #expect(raised.vDegree == 4)
            #expect(raised.vKnots == [0, 0, 0, 0, 0, 0.5, 0.5, 1, 1, 1, 1, 1])
            #expect(raised.vControlPointCount == 7)
            #expect(raised.uKnots == original.uKnots)
        }
        var largest = 0.0
        for i in 0...20 {
            for j in 0...20 {
                let u = Double(i) / 20
                let v = Double(j) / 20
                let before = try original.point(u: u, v: v, tolerance: tolerance)
                let after = try raised.point(u: u, v: v, tolerance: tolerance)
                largest = max(largest, (after - before).length)
            }
        }
        #expect(largest < 1e-10, "Largest deviation \(largest)")
        #expect(raised.weights.allSatisfy { $0.allSatisfy { $0 > 0 } })
    }

    @Test(arguments: [SurfaceParameterDirection.u, .v])
    func directElevationKeepsGeometryAndCallerResources(direction: SurfaceParameterDirection) throws {
        let original = surface()
        let ordinary = try original.elevatingDegree(direction: direction, tolerance: tolerance)
        let measured = try OriginalQueryBudget()
        var execution = OriginalQueryExecution(budget: measured,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        let direct = try original.elevatingDegree(direction: direction, tolerance: tolerance, using: &execution)
        #expect(direct == ordinary)
        #expect(measured.snapshot.work > 0)
        #expect(measured.snapshot.storageBytes > 0)

        // A scalar-only owner must reach the same body without a child query execution.
        var scalar = GeometryTestScalarRecorder()
        #expect(try original.elevatingDegree(direction: direction, tolerance: tolerance, using: &scalar) == ordinary)
        #expect(scalar.work == measured.snapshot.work)
        #expect(scalar.storageBytes == measured.snapshot.storageBytes)

        let required = measured.snapshot
        let exactBudget = try OriginalQueryBudget(workLimit: required.work, storageByteLimit: required.storageBytes)
        var exact = OriginalQueryExecution(budget: exactBudget,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        #expect(try original.elevatingDegree(direction: direction, tolerance: tolerance, using: &exact) == ordinary)
        #expect(exactBudget.snapshot.work == required.work)
        #expect(exactBudget.snapshot.storageBytes == required.storageBytes)
        do {
            _ = try original.elevatingDegree(direction: direction, tolerance: tolerance, using: &exact)
            Issue.record("A second elevation must retain the caller's exhausted work budget.")
        } catch {
            guard let scalar = geometryTestOriginalFailure(error) as? ExactScalarFailure,
                  case .resourceLimit(.work) = scalar else { throw error }
        }
        for resource in [ExactResource.work, .storage] {
            let budget = try OriginalQueryBudget(
                workLimit: resource == .work ? required.work - 1 : required.work,
                storageByteLimit: resource == .storage ? required.storageBytes - 1 : required.storageBytes)
            var limited = OriginalQueryExecution(budget: budget,
                limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
            do {
                _ = try original.elevatingDegree(direction: direction, tolerance: tolerance, using: &limited)
                Issue.record("Degree elevation must reject N-1 caller resources.")
            } catch {
                guard let scalar = geometryTestOriginalFailure(error) as? ExactScalarFailure,
                      case .resourceLimit(let actual) = scalar, actual == resource else { throw error }
            }
        }
        let cancelledBudget = try OriginalQueryBudget(checkpoint: { throw ExactScalarFailure.cancelled })
        var cancelled = OriginalQueryExecution(budget: cancelledBudget,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        do {
            _ = try original.elevatingDegree(direction: direction, tolerance: tolerance, using: &cancelled)
            Issue.record("Degree elevation must observe the caller's cancellation.")
        } catch {
            #expect(geometryTestIsCancelled(error))
        }
        #expect(cancelledBudget.snapshot.work == 0)
        #expect(cancelledBudget.snapshot.storageBytes == 0)
    }

    @Test func theDenseRaisedControlLimitIsUnchanged() throws {
        let count = 513
        let knots = [0.0, 0.0] + (1..<(count - 1)).map { Double($0) / Double(count - 1) } + [1.0, 1.0]
        let row = (0..<count).map { Point3D(x: Double($0), y: 0, z: 0) }
        let original = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: knots, vKnots: [0, 0, 1, 1],
            controlPoints: [row, row.map { Point3D(x: $0.x, y: 1, z: 0) }])
        do {
            _ = try original.elevatingDegree(direction: .u, tolerance: tolerance)
            Issue.record("A raised dense system with 1,025 controls must be refused.")
        } catch let error as GeometryError {
            guard case .invalidMatrixElementCount(let actual) = error else { throw error }
            #expect(actual == 1_025)
        }
    }

    @Test func anUnclampedDirectionIsRefused() throws {
        var unclamped = surface()
        unclamped.uKnots = [0, 0.1, 0.2, 0.4, 0.5, 0.8, 0.9, 1]
        #expect(throws: GeometryError.self) {
            _ = try unclamped.elevatingDegree(direction: .u, tolerance: tolerance)
        }
    }
}
