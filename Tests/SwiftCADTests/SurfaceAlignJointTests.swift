import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
@testable import CADKernel
@testable import SwiftCAD

/// Two edges of one sheet aligned in one dialog (Plasticity's Align Surface, video align-3): the
/// second keeps the first, its rows refined to reach only the stretch beside it, so both edges
/// hold their continuity along their whole length when the references agree where they meet.
@Suite("Align Surface joint")
struct SurfaceAlignJointTests {
    private let s = 0.02

    /// The first edge, x = s, of the sheet aligned to `pieceX` and then its y = s edge to `pieceY`:
    /// where along the first edge (fractions of its length) it is still on `pieceX` and tangent to it.
    private func firstEdgeHolds(
        pieceX: BSplineSurface3D, pieceY: BSplineSurface3D, keepsOtherEdges: Bool, at fractions: [Double]
    ) throws -> (first: [Bool], secondHolds: Bool) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        func evaluate() throws -> EvaluatedDocument {
            try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "joint"))
        }
        func edge(of feature: FeatureID, where test: (Point3D, Point3D) -> Bool) throws -> StableSubshapeReference {
            let evaluated = try evaluate()
            let key = try #require(evaluated.subshapes.entries.first { key, value in
                guard key.featureID == feature, case let .edge(id) = value, let edge = evaluated.brep.edges[id],
                      let a = evaluated.brep.vertices[edge.startVertexID]?.point, let b = evaluated.brep.vertices[edge.endVertexID]?.point else { return false }
                return test(a, b)
            }?.key)
            return try builder.stableSubshape(key)
        }
        let grid = (0...3).map { j in (0...3).map { i in Point3D(x: s * Double(i) / 3, y: s * Double(j) / 3, z: 0) } }
        let flat = try builder.bSplineSurface(BSplineSurface3D(uDegree: 3, vDegree: 3, uKnots: [0, 0, 0, 0, 1, 1, 1, 1],
                                                               vKnots: [0, 0, 0, 0, 1, 1, 1, 1], controlPoints: grid))
        let x = try builder.bSplineSurface(pieceX), y = try builder.bSplineSurface(pieceY)
        let first = try builder.alignSurface(
            target: flat, targetEdge: try edge(of: flat) { abs($0.x - s) < 1e-12 && abs($1.x - s) < 1e-12 },
            reference: x, referenceEdge: try edge(of: x) { abs($0.x - s) < 1e-12 && abs($1.x - s) < 1e-12 }
        )
        let second = try builder.alignSurface(
            target: first, targetEdge: try edge(of: first) { abs($0.y - s) < 1e-12 && abs($1.y - s) < 1e-12 },
            reference: y, referenceEdge: try edge(of: y) { abs($0.y - s) < 1e-12 && abs($1.y - s) < 1e-12 },
            keepsOtherEdges: keepsOtherEdges
        )
        let evaluated = try evaluate()
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        let faces = evaluated.subshapes.entries.compactMap { key, value -> Face? in
            guard key.featureID == second, case let .face(id) = value else { return nil }
            return evaluated.brep.faces[id]
        }
        let result = try #require(faces.first.flatMap { evaluated.brep.geometry.surfaces[$0.surfaceID] })
        func holds(_ point: Point3D, on reference: Surface3D) throws -> Bool {
            guard case let .projected(on) = try result.parameterProjectionResult(of: point, tolerance: .standard), on.residual < 1e-9,
                  case let .projected(there) = try reference.parameterProjectionResult(of: point, tolerance: .standard) else { return false }
            let a = try result.normal(u: on.u, v: on.v, tolerance: .standard), b = try reference.normal(u: there.u, v: there.v, tolerance: .standard)
            return a.cross(b).length < 1e-8
        }
        let firstHolds = try fractions.map { t in try holds(try Surface3D.bSpline(pieceX).point(u: 0, v: t, tolerance: .standard), on: .bSpline(pieceX)) }
        let secondHolds = try [0.1, 0.5, 0.9].allSatisfy { t in try holds(try Surface3D.bSpline(pieceY).point(u: 0, v: t, tolerance: .standard), on: .bSpline(pieceY)) }
        return (firstHolds, secondHolds)
    }

    /// Two pieces of one tilted plane, agreeing where they meet: both edges hold all along, the
    /// corner included.
    @Test(.timeLimit(.minutes(5)))
    func twoEdgesOfASheetKeepTheirContinuityTogether() throws {
        let plane = { (x: Double, y: Double) in Point3D(x: x, y: y, z: (x + y) / 4) }
        let pieceX = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
                                      controlPoints: [[plane(s, 0), plane(2 * s, 0)], [plane(s, s), plane(2 * s, s)]])
        let pieceY = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
                                      controlPoints: [[plane(0, s), plane(0, 2 * s)], [plane(s, s), plane(s, 2 * s)]])
        let result = try firstEdgeHolds(pieceX: pieceX, pieceY: pieceY, keepsOtherEdges: true, at: [0.1, 0.5, 0.9, 1.0])
        #expect(result.first == [true, true, true, true] && result.secondHolds, "\(result)")
    }

    /// Two arches bending away past the corner, which no sheet meets tangentially at once there:
    /// kept, the first edge holds away from the corner; not kept, the second alignment's rows run
    /// the sheet's whole length and move the first edge everywhere.
    @Test(.timeLimit(.minutes(5)))
    func theSecondAlignmentKeepsTheFirstAwayFromTheCorner() throws {
        let archX = BSplineSurface3D(uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: s, y: 0, z: 0), Point3D(x: 1.5 * s, y: 0, z: 0.005), Point3D(x: 2 * s, y: 0, z: 0)],
                            [Point3D(x: s, y: s, z: 0), Point3D(x: 1.5 * s, y: s, z: 0.005), Point3D(x: 2 * s, y: s, z: 0)]])
        let archY = BSplineSurface3D(uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: 0, y: s, z: 0), Point3D(x: 0, y: 1.5 * s, z: 0.005), Point3D(x: 0, y: 2 * s, z: 0)],
                            [Point3D(x: s, y: s, z: 0), Point3D(x: s, y: 1.5 * s, z: 0.005), Point3D(x: s, y: 2 * s, z: 0)]])
        let kept = try firstEdgeHolds(pieceX: archX, pieceY: archY, keepsOtherEdges: true, at: [0.1, 0.5])
        #expect(kept.first == [true, true] && kept.secondHolds, "\(kept)")
        let moved = try firstEdgeHolds(pieceX: archX, pieceY: archY, keepsOtherEdges: false, at: [0.1, 0.5])
        #expect(moved.first.contains(false), "\(moved)")
    }
}
