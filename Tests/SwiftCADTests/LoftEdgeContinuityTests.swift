import Foundation
import Testing
import CADCore
import CADExchange
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A Loft between edges of two boxes leaves one box's top face and arrives at the other's bottom
/// face tangent (G1) or curvature (G2) continuous with them.
@Suite("Loft edge continuity")
struct SurfaceEdgeContinuityTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "loft"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return evaluated
    }

    /// The edge of `box` along X at `y` and `z`, as its stable reference and whether it runs
    /// toward -X.
    private func edge(of box: FeatureID, y: Double, z: Double, in builder: DocumentBuilder) throws -> (StableSubshapeReference, Bool) {
        let evaluated = try evaluate(builder)
        let match = try #require(evaluated.subshapes.entries.first { key, value in
            guard key.featureID == box, case let .edge(id) = value, let edge = evaluated.brep.edges[id],
                  let start = evaluated.brep.vertices[edge.startVertexID]?.point,
                  let end = evaluated.brep.vertices[edge.endVertexID]?.point else { return false }
            return [start, end].allSatisfy { abs($0.y - y) < 1e-12 && abs($0.z - z) < 1e-12 }
        })
        guard case let .edge(id) = match.value, let edge = evaluated.brep.edges[id],
              let start = evaluated.brep.vertices[edge.startVertexID]?.point,
              let end = evaluated.brep.vertices[edge.endVertexID]?.point else {
            throw KernelError.unsupportedEvaluation(tolerance: .standard, message: "The edge vanished.")
        }
        return (try builder.stableSubshape(match.key), end.x < start.x)
    }

    /// Box A spans [0, 20 mm]³; box B [0, 20] × [-70, -50] × [30, 50] mm. The loft runs from A's
    /// top front edge (y = 0, z = 20 mm) to B's bottom back edge (y = -50, z = 30 mm).
    private func loft(order: SurfaceEdgeContinuity.Order?, tension: Double = 1) throws -> (DocumentBuilder, FeatureID) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let first = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let second = try builder.box(
            placement: PrimitivePlacement(origin: Point3D(x: 0, y: -0.07, z: 0.03), axis: .unitZ, referenceDirection: .unitX),
            width: length(0.02), depth: length(0.02), height: length(0.02)
        )
        let (firstEdge, firstReversed) = try edge(of: first, y: 0, z: 0.02, in: builder)
        let (secondEdge, secondReversed) = try edge(of: second, y: -0.05, z: 0.03, in: builder)
        let firstCurve = try builder.edgeCurves(of: first, edges: [firstEdge])
        let secondCurve = try builder.edgeCurves(of: second, edges: [secondEdge])
        let sections = [(first, firstEdge, firstCurve, firstReversed), (second, secondEdge, secondCurve, secondReversed)].map { body, edge, curve, reversed in
            LoftSectionReference(
                section: .curve(CurveSectionReference(featureID: curve, isReversed: reversed)),
                continuity: order.map { SurfaceEdgeContinuity(source: body, bodyRole: .body, edge: edge, order: $0, tension: tension) }
            )
        }
        let loft = try builder.loft(sections: sections, options: LoftOptions(resultKind: .sheet))
        return (builder, loft)
    }

    /// The loft's surface at the points along its two edges: their normals and the normal
    /// curvature across the edge.
    private func boundary(_ evaluated: EvaluatedDocument, loft: FeatureID) throws -> [(normal: Vector3D, curvature: Double)] {
        let surfaces = evaluated.subshapes.entries.compactMap { key, value -> Surface3D? in
            guard key.featureID == loft, case let .face(id) = value, let face = evaluated.brep.faces[id] else { return nil }
            return evaluated.brep.geometry.surfaces[face.surfaceID]
        }
        let surface = try #require(surfaces.first)
        #expect(surfaces.count == 1)
        return try [0.004, 0.01, 0.016].flatMap { x in
            try [Point3D(x: x, y: 0, z: 0.02), Point3D(x: x, y: -0.05, z: 0.03)].map { point in
                let projected = try surface.parameterProjection(of: point, tolerance: .standard)
                let geometry = try surface.differentialGeometry(u: projected.u, v: projected.v, tolerance: .standard)
                return (geometry.normal, geometry.normalCurvatureV)
            }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func aTangentLoftLeavesAndMeetsTheFacesInTheirPlanes() throws {
        let (builder, loft) = try loft(order: .tangent)
        let evaluated = try evaluate(builder)
        #expect(evaluated.brep.bodies.count == 3)
        let samples = try boundary(evaluated, loft: loft)
        #expect(samples.allSatisfy { abs(abs($0.normal.z) - 1) < 1e-9 })
        // A cubic across the gap bends at its ends.
        #expect(samples.allSatisfy { abs($0.curvature) > 1 })

        let (ruledBuilder, ruledLoft) = try self.loft(order: nil)
        let ruledSamples = try boundary(try evaluate(ruledBuilder), loft: ruledLoft)
        #expect(ruledSamples.allSatisfy { abs(abs($0.normal.z) - 1) > 1e-3 })

        let document = try builder.build(name: "loft")
        let sink = DataByteSink()
        let store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: sink)
        let restored = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        #expect(restored.designGraph.nodes == document.designGraph.nodes)
    }

    @Test(.timeLimit(.minutes(2)))
    func aCurvatureLoftIsFlatAcrossItsEdges() throws {
        let (builder, loft) = try loft(order: .curvature, tension: 1.5)
        let samples = try boundary(try evaluate(builder), loft: loft)
        #expect(samples.allSatisfy { abs(abs($0.normal.z) - 1) < 1e-9 && abs($0.curvature) < 1e-6 })
    }

    /// A loft between the first-quadrant quarters of the top rim of a 10 mm cylinder and the bottom
    /// rim of a 15 mm one 30 mm above, with continuity along both when `order` is given.
    private func cylinders(order: SurfaceEdgeContinuity.Order?, allowance: Double?) throws -> (DocumentBuilder, FeatureID) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let lower = try builder.cylinder(radius: length(0.01), height: length(0.02))
        let upper = try builder.cylinder(
            placement: PrimitivePlacement(origin: Point3D(x: 0, y: 0, z: 0.05), axis: .unitZ, referenceDirection: .unitX),
            radius: length(0.015), height: length(0.02)
        )
        let evaluated = try evaluate(builder)
        /// The rim's quarter at `z` between +X and +Y; its edge curve runs from +X to +Y.
        func rim(of cylinder: FeatureID, z: Double) throws -> StableSubshapeReference {
            let key = try #require(evaluated.subshapes.entries.first { key, value in
                guard key.featureID == cylinder, case let .edge(id) = value, let edge = evaluated.brep.edges[id],
                      let curve = evaluated.brep.geometry.curves[edge.curveID], case .circle = curve,
                      let start = evaluated.brep.vertices[edge.startVertexID]?.point,
                      let end = evaluated.brep.vertices[edge.endVertexID]?.point else { return false }
                return abs(start.z - z) < 1e-12 && start.x + end.x > 1e-9 && start.y + end.y > 1e-9
            }?.key)
            return try builder.stableSubshape(key)
        }
        let rims = [(lower, try rim(of: lower, z: 0.02)), (upper, try rim(of: upper, z: 0.05))]
        let curves = try rims.map { try builder.edgeCurves(of: $0.0, edges: [$0.1]) }
        let loft = try builder.loft(sections: zip(rims, curves).map { rim, curve in
            LoftSectionReference(section: .curve(CurveSectionReference(featureID: curve)), continuity: order.map {
                SurfaceEdgeContinuity(source: rim.0, bodyRole: .body, edge: rim.1, order: $0, angularAllowance: allowance)
            })
        }, options: LoftOptions(resultKind: .sheet))
        return (builder, loft)
    }

    @Test(.timeLimit(.minutes(3)))
    func aLoftLeavesACylindersSideTangentWithinItsAllowance() throws {
        let (builder, loft) = try cylinders(order: .tangent, allowance: 1e-3)
        let evaluated = try evaluate(builder)
        let surfaces = evaluated.subshapes.entries.compactMap { key, value -> Surface3D? in
            guard key.featureID == loft, case let .face(id) = value, let face = evaluated.brep.faces[id] else { return nil }
            return evaluated.brep.geometry.surfaces[face.surfaceID]
        }
        #expect(surfaces.isEmpty == false)
        // Along both rims the loft's normal is the cylinders' radial normal.
        var checked = 0
        for angle in stride(from: 0.2, to: 1.5, by: 0.3) {
            for (radius, z) in [(0.01, 0.02), (0.015, 0.05)] {
                let point = Point3D(x: radius * cos(angle), y: radius * sin(angle), z: z)
                for surface in surfaces {
                    guard case let .projected(projected) = try surface.parameterProjectionResult(of: point, tolerance: .standard),
                          projected.residual < 1e-7 else { continue }
                    let normal = try surface.differentialGeometry(u: projected.u, v: projected.v, tolerance: .standard).normal
                    #expect(abs(normal.z) < 1e-3 && abs(abs(normal.x * cos(angle) + normal.y * sin(angle)) - 1) < 1e-6)
                    checked += 1
                }
            }
        }
        #expect(checked >= 10)
    }

    @Test(.timeLimit(.minutes(2)))
    func continuityWithACurvedFaceNeedsAnAllowanceAndTangencyOnly() throws {
        for (order, allowance, code) in [(SurfaceEdgeContinuity.Order.tangent, nil, KernelErrorCode.invalidInput),
                                         (.curvature, 1e-3, .unsupportedCapability)] as [(SurfaceEdgeContinuity.Order, Double?, KernelErrorCode)] {
            do {
                _ = try evaluate(try cylinders(order: order, allowance: allowance).0)
                Issue.record("Continuity \(order) with a cylinder's side and allowance \(String(describing: allowance)) must be refused.")
            } catch let error as KernelError {
                #expect(error.code == code)
            }
        }
    }
}

/// A Loft's Simplify makes its flat faces trimmed planes.
@Suite("Loft simplify")
struct LoftSimplifyTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    @Test(.timeLimit(.minutes(2)))
    func aLoftBetweenTwoSquaresHasPlanarSides() throws {
        func evaluate(simplify: Bool) throws -> EvaluatedDocument {
            var builder = DocumentBuilder(units: .meters, tolerance: .standard)
            let lower = try builder.sketch(on: .xy) { $0.rectangle(width: length(0.02), height: length(0.02)) }
            let upper = try builder.sketch(on: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 0.03), normal: .unitZ))) {
                $0.rectangle(width: length(0.01), height: length(0.01))
            }
            _ = try builder.loft(sections: [lower, upper].map { LoftSectionReference(profile: $0) },
                                 options: LoftOptions(simplify: simplify))
            let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "loft"))
            try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
            return evaluated
        }
        func planes(_ evaluated: EvaluatedDocument) -> Int {
            evaluated.brep.faces.values.filter { face in
                if case .plane = evaluated.brep.geometry.surfaces[face.surfaceID] { return true }
                return false
            }.count
        }
        let plain = try evaluate(simplify: false)
        let simplified = try evaluate(simplify: true)
        #expect(planes(plain) == 2)
        #expect(planes(simplified) == 6 && simplified.brep.faces.count == 6)
        // A frustum of squares 20 and 10 mm, 30 mm high.
        let volume = 0.03 / 3 * (0.0004 + 0.0001 + (0.0004 * 0.0001).squareRoot())
        #expect(abs(try simplified.brep.volume(tolerance: .standard) - volume) < 1e-12)
    }
}
