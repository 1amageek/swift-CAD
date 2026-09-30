import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
import SwiftCAD

/// Reverse turns a sheet over in its place: every face faces the other way with its surface and
/// trim unchanged, and the source sheet is consumed.
@Suite("Reverse sheet")
struct ReverseSheetFeatureTests {
    private let side = 0.02

    private func quad(_ builder: inout DocumentBuilder, _ a: Point3D, _ b: Point3D, _ c: Point3D, _ d: Point3D) throws -> FeatureID {
        try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[a, b], [d, c]]
        ))
    }

    private func corner(_ x: Double, _ y: Double, _ z: Double) -> Point3D {
        Point3D(x: x * side, y: y * side, z: z * side)
    }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "reverse sheet"))
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        return evaluated
    }

    private func body(of featureID: FeatureID, in evaluated: EvaluatedDocument) throws -> Body {
        guard case let .body(bodyID) = evaluated.subshapes[SubshapeID(featureID: featureID, role: "body", ordinal: 0)],
              let body = evaluated.brep.bodies[bodyID] else {
            throw KernelError(phase: .evaluation, code: .missingReference, tolerance: .standard, message: "No body.")
        }
        return body
    }

    /// The outward direction of each face of `body` at its surface's parameter centre: the surface
    /// normal, turned over where the face is reversed.
    private func faceNormals(of body: Body, in evaluated: EvaluatedDocument) throws -> [Vector3D] {
        try body.shellIDs.flatMap { evaluated.brep.shells[$0]?.faceIDs ?? [] }.map { faceID in
            let face = try #require(evaluated.brep.faces[faceID])
            let surface = try #require(evaluated.brep.geometry.surfaces[face.surfaceID])
            let normal = try surface.differentialGeometry(u: 0.5, v: 0.5, tolerance: .standard).normal
            return face.orientation == .forward ? normal : normal * -1
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func aSheetFacesTheOtherWay() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let floor = try quad(&builder, corner(0, 0, 0), corner(1, 0, 0), corner(1, 1, 0), corner(0, 1, 0))
        let before = try faceNormals(of: try body(of: floor, in: try evaluate(builder)), in: try evaluate(builder))
        let reversed = try builder.reverseSheet(floor)
        let evaluated = try evaluate(builder)
        let sheet = try body(of: reversed, in: evaluated)
        #expect(sheet.kind == .sheet)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.edges.count == 4)
        let after = try faceNormals(of: sheet, in: evaluated)
        #expect(before.count == 1 && after.count == 1)
        #expect(before[0].dot(after[0]) < -0.999)
        #expect(evaluated.subshapes.entries.keys.allSatisfy { $0.featureID == reversed })
        #expect(evaluated.lineage.values.contains { $0.output.featureID == reversed && $0.parents.contains { $0.featureID == floor } })
    }

    @Test(.timeLimit(.minutes(2)))
    func aJoinedSheetTurnsOverWhole() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let floor = try quad(&builder, corner(0, 0, 0), corner(1, 0, 0), corner(1, 1, 0), corner(0, 1, 0))
        let wall = try quad(&builder, corner(0, 0, 0), corner(0, 0, 1), corner(1, 0, 1), corner(1, 0, 0))
        let joined = try builder.joinBodies([floor, wall], mode: .sewnSheet)
        let before = try faceNormals(of: try body(of: joined, in: try evaluate(builder)), in: try evaluate(builder))
        let reversed = try builder.reverseSheet(joined)
        let evaluated = try evaluate(builder)
        let sheet = try body(of: reversed, in: evaluated)
        #expect(sheet.shellIDs.count == 1)
        #expect(evaluated.brep.faces.count == 2)
        // Still sewn along the shared edge.
        #expect(evaluated.brep.edges.count == 7)
        let after = try faceNormals(of: sheet, in: evaluated)
        #expect(Set(before.map { $0.z.rounded() }) == Set(after.map { (-$0.z).rounded() }))
        #expect(Set(before.map { $0.y.rounded() }) == Set(after.map { (-$0.y).rounded() }))
        // Turned over twice, it faces as it did.
        let again = try builder.reverseSheet(reversed)
        let twice = try evaluate(builder)
        let restored = try faceNormals(of: try body(of: again, in: twice), in: twice)
        #expect(Set(restored.map { $0.z.rounded() }) == Set(before.map { $0.z.rounded() }))
    }

    @Test(.timeLimit(.minutes(2)))
    func aSolidIsNotTurnedOver() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(
            width: .constant(.length(side, unit: .meter)), depth: .constant(.length(side, unit: .meter)),
            height: .constant(.length(side, unit: .meter))
        )
        #expect(throws: (any Error).self) { try builder.reverseSheet(box) }
    }

    @Test(.timeLimit(.minutes(2)))
    func theNativePackageKeepsTheReversal() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let floor = try quad(&builder, corner(0, 0, 0), corner(1, 0, 0), corner(1, 1, 0), corner(0, 1, 0))
        let reversed = try builder.reverseSheet(floor)
        let pipeline = CADPipeline(tolerance: .standard)
        let sink = DataByteSink()
        try pipeline.writePackage(for: try builder.build(name: "reverse persistence"), to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))
        #expect(loaded.designGraph.nodes[reversed]?.operation == .reverseSheet(ReverseSheetFeature(
            target: PatternTargetReference(featureID: floor)
        )))
    }

    @Test(.timeLimit(.minutes(2)))
    func openEdgesAreTheOnesOneFaceUses() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let floor = try quad(&builder, corner(0, 0, 0), corner(1, 0, 0), corner(1, 1, 0), corner(0, 1, 0))
        let wall = try quad(&builder, corner(0, 0, 0), corner(0, 0, 1), corner(1, 0, 1), corner(1, 0, 0))
        let joined = try builder.joinBodies([floor, wall], mode: .sewnSheet)
        let box = try builder.box(
            width: .constant(.length(side, unit: .meter)), depth: .constant(.length(side, unit: .meter)),
            height: .constant(.length(side, unit: .meter))
        )
        let evaluated = try evaluate(builder)
        let resolver = OpenBoundaryLoopResolver()
        #expect(resolver.boundaryEdgeIDs(in: try body(of: joined, in: evaluated), model: evaluated.brep).count == 6)
        #expect(resolver.boundaryEdgeIDs(in: try body(of: box, in: evaluated), model: evaluated.brep).isEmpty)
    }
}
