import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
import SwiftCAD

/// Unjoin faces separates a body into the shells of one sheet body in its place: each chosen face
/// a shell of its own, the rest one shell per piece that still hangs together, the source consumed.
@Suite("Unjoin faces")
struct UnjoinFacesFeatureTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private let side = 0.02

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "unjoin faces"))
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

    private func shellFaceCounts(of body: Body, in evaluated: EvaluatedDocument) -> [Int] {
        body.shellIDs.map { evaluated.brep.shells[$0]?.faceIDs.count ?? 0 }.sorted()
    }

    /// The stable references of the box's faces whose plane normal `keep` accepts.
    private func faces(
        of box: FeatureID, in evaluated: EvaluatedDocument, builder: DocumentBuilder,
        where keep: (Vector3D) -> Bool
    ) throws -> [StableSubshapeReference] {
        try evaluated.subshapes.entries.filter { key, value in
            guard key.featureID == box, case let .face(faceID) = value, let face = evaluated.brep.faces[faceID],
                  case let .plane(plane) = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            return keep(plane.normal)
        }.keys.sorted().map { try builder.stableSubshape($0) }
    }

    @Test(.timeLimit(.minutes(2)))
    func everyFaceBecomesAShellOfItsOwnInTheBodysPlace() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(side), depth: length(side), height: length(side))
        let unjoined = try builder.unjoinFaces(box, selection: .everyFace)
        let evaluated = try evaluate(builder)
        let sheet = try body(of: unjoined, in: evaluated)
        #expect(sheet.kind == .sheet)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(shellFaceCounts(of: sheet, in: evaluated) == [1, 1, 1, 1, 1, 1])
        // No face is shared, so each keeps four edges of its own.
        #expect(evaluated.brep.edges.count == 24)
        // Nothing of the box is left, and every new face leads back to a box face.
        #expect(evaluated.subshapes.entries.keys.allSatisfy { $0.featureID == unjoined })
        let faceOutputs = evaluated.lineage.values.filter {
            if case .face = evaluated.subshapes[$0.output] { return true } else { return false }
        }
        #expect(faceOutputs.count == 6)
        #expect(faceOutputs.allSatisfy { $0.parents.contains { $0.featureID == box } })
    }

    @Test(.timeLimit(.minutes(2)))
    func chosenFacesLeaveAndTheRestStayJoinedByPiece() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(side), depth: length(side), height: length(side))
        let evaluatedBox = try evaluate(builder)
        let top = try faces(of: box, in: evaluatedBox, builder: builder) { $0.z > 0.5 }
        let sides = try faces(of: box, in: evaluatedBox, builder: builder) { abs($0.z) < 0.5 }
        #expect(top.count == 1)
        #expect(sides.count == 4)

        var topOnly = builder
        let lid = try topOnly.unjoinFaces(box, selection: .faces(top))
        let lidEvaluated = try evaluate(topOnly)
        #expect(shellFaceCounts(of: try body(of: lid, in: lidEvaluated), in: lidEvaluated) == [1, 5])

        // Without their sides the top and bottom no longer meet: six pieces.
        var sidesOnly = builder
        let walls = try sidesOnly.unjoinFaces(box, selection: .faces(sides))
        let wallsEvaluated = try evaluate(sidesOnly)
        #expect(shellFaceCounts(of: try body(of: walls, in: wallsEvaluated), in: wallsEvaluated) == [1, 1, 1, 1, 1, 1])
    }

    @Test(.timeLimit(.minutes(2)))
    func theSeparatedFacesJoinBackIntoTheSolid() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(side), depth: length(side), height: length(side))
        let unjoined = try builder.unjoinFaces(box, selection: .everyFace)
        let pieces = try (0..<6).map { try builder.extract(unjoined, selection: .component(index: $0, count: 6)) }
        let joined = try builder.joinBodies(pieces, mode: .sewnSolid)
        let evaluated = try evaluate(builder)
        let solid = try body(of: joined, in: evaluated)
        #expect(solid.kind == .solid)
        #expect(abs(try evaluated.brep.volume(of: solid.id, tolerance: .standard) - side * side * side) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func aFaceOfAnotherBodyIsRefused() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(side), depth: length(side), height: length(side))
        let other = try builder.box(width: length(side), depth: length(side), height: length(side))
        let evaluated = try evaluate(builder)
        let foreign = try faces(of: other, in: evaluated, builder: builder) { $0.z > 0.5 }
        _ = try builder.unjoinFaces(box, selection: .faces(foreign))
        #expect(throws: KernelError.self) { try evaluate(builder) }
        #expect(throws: FeatureEvaluationError.self) { try UnjoinFacesSelection.faces([]).validate() }
    }

    @Test(.timeLimit(.minutes(2)))
    func theNativePackageKeepsTheSelection() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(side), depth: length(side), height: length(side))
        let evaluatedBox = try evaluate(builder)
        let top = try faces(of: box, in: evaluatedBox, builder: builder) { $0.z > 0.5 }
        let chosen = try builder.unjoinFaces(box, selection: .faces(top))
        let every = try builder.unjoinFaces(chosen, selection: .everyFace)
        let document = try builder.build(name: "unjoin faces persistence")
        let pipeline = CADPipeline(tolerance: .standard)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))
        #expect(loaded.designGraph.nodes[chosen]?.operation == .unjoinFaces(UnjoinFacesFeature(
            target: PatternTargetReference(featureID: box), selection: .faces(top)
        )))
        #expect(loaded.designGraph.nodes[every]?.operation == .unjoinFaces(UnjoinFacesFeature(
            target: PatternTargetReference(featureID: chosen), selection: .everyFace
        )))
    }
}
