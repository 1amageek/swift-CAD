import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
import SwiftCAD

/// Joining sheets sews them along their exactly matching edges into one body: faces turned over
/// to agree with the first sheet, and a closed result enclosing an outward-facing solid.
@Suite("Join sheets")
struct JoinSheetsFeatureTests {
    private let side = 0.02

    /// A bilinear sheet through four corners in order; the order decides which side is front.
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
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "join sheets"))
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

    /// The six faces of a cube, some wound so they face in and some out.
    private func cubeSides(_ builder: inout DocumentBuilder) throws -> [FeatureID] {
        [
            try quad(&builder, corner(0, 0, 0), corner(1, 0, 0), corner(1, 1, 0), corner(0, 1, 0)),
            try quad(&builder, corner(0, 0, 1), corner(1, 0, 1), corner(1, 1, 1), corner(0, 1, 1)),
            try quad(&builder, corner(0, 0, 0), corner(0, 0, 1), corner(1, 0, 1), corner(1, 0, 0)),
            try quad(&builder, corner(0, 1, 0), corner(1, 1, 0), corner(1, 1, 1), corner(0, 1, 1)),
            try quad(&builder, corner(0, 0, 0), corner(0, 1, 0), corner(0, 1, 1), corner(0, 0, 1)),
            try quad(&builder, corner(1, 0, 0), corner(1, 0, 1), corner(1, 1, 1), corner(1, 1, 0)),
        ]
    }

    @Test(.timeLimit(.minutes(2)))
    func sheetsThatCloseBecomeAnOutwardFacingSolid() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sides = try cubeSides(&builder)
        let joined = try builder.joinBodies(sides, mode: .sewnSolid)
        let evaluated = try evaluate(builder)
        let solid = try body(of: joined, in: evaluated)
        #expect(solid.kind == .solid)
        #expect(solid.shellIDs.count == 1)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(abs(try evaluated.brep.volume(of: solid.id, tolerance: .standard) - side * side * side) < 1e-12)
        // Every sewn edge is shared by two faces.
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.lineage.values.contains { lineage in
            lineage.output.featureID == joined && lineage.parents.contains { $0.featureID == sides[3] }
        })
    }

    @Test(.timeLimit(.minutes(2)))
    func openSheetsSewIntoOneSheetWhicheverWayTheyFace() throws {
        for flipped in [false, true] {
            var builder = DocumentBuilder(units: .meters, tolerance: .standard)
            let floor = try quad(&builder, corner(0, 0, 0), corner(1, 0, 0), corner(1, 1, 0), corner(0, 1, 0))
            let wall = flipped
                ? try quad(&builder, corner(0, 0, 0), corner(1, 0, 0), corner(1, 0, 1), corner(0, 0, 1))
                : try quad(&builder, corner(0, 0, 0), corner(0, 0, 1), corner(1, 0, 1), corner(1, 0, 0))
            let joined = try builder.joinBodies([floor, wall], mode: .sewnSheet)
            let evaluated = try evaluate(builder)
            let sheet = try body(of: joined, in: evaluated)
            #expect(sheet.kind == .sheet)
            #expect(sheet.shellIDs.count == 1)
            #expect(evaluated.brep.faces.count == 2)
            #expect(evaluated.brep.edges.count == 7)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func sheetsThatDoNotMeetAreRefused() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let first = try quad(&builder, corner(0, 0, 0), corner(1, 0, 0), corner(1, 1, 0), corner(0, 1, 0))
        let second = try quad(&builder, corner(2, 0, 0), corner(3, 0, 0), corner(3, 1, 0), corner(2, 1, 0))
        _ = try builder.joinBodies([first, second], mode: .sewnSheet)
        #expect(throws: KernelError.self) { try evaluate(builder) }
    }

    @Test(.timeLimit(.minutes(2)))
    func threeSheetsOnOneEdgeAreRefused() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let floor = try quad(&builder, corner(0, 0, 0), corner(1, 0, 0), corner(1, 1, 0), corner(0, 1, 0))
        let up = try quad(&builder, corner(0, 0, 0), corner(0, 0, 1), corner(1, 0, 1), corner(1, 0, 0))
        let down = try quad(&builder, corner(0, 0, 0), corner(1, 0, 0), corner(1, 0, -1), corner(0, 0, -1))
        _ = try builder.joinBodies([floor, up, down], mode: .sewnSheet)
        #expect(throws: KernelError.self) { try evaluate(builder) }
    }

    @Test(.timeLimit(.minutes(2)))
    func solidsAndSheetsDoNotJoinTogether() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sheet = try quad(&builder, corner(0, 0, 0), corner(1, 0, 0), corner(1, 1, 0), corner(0, 1, 0))
        let box = try builder.box(
            width: .constant(.length(side, unit: .meter)), depth: .constant(.length(side, unit: .meter)),
            height: .constant(.length(side, unit: .meter))
        )
        // The graph refuses a solid where a sheet is sewn, and a sheet where solids combine.
        #expect(throws: KernelError.self) { try builder.joinBodies([sheet, box], mode: .sewnSheet) }
        #expect(throws: KernelError.self) { try builder.joinBodies([sheet, box], mode: .solidComponents) }
    }

    @Test(.timeLimit(.minutes(2)))
    func theClosureQueryChoosesTheModeAndAMismatchIsRefused() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sides = try cubeSides(&builder)
        let evaluated = try evaluate(builder)
        #expect(try JoinSheetClosure().closes(sheets: sides.map { JoinBodiesTargetReference(featureID: $0) }, in: evaluated))
        #expect(try JoinSheetClosure().closes(sheets: sides.prefix(5).map { JoinBodiesTargetReference(featureID: $0) }, in: evaluated) == false)
        _ = try builder.joinBodies(sides, mode: .sewnSheet)
        #expect(throws: KernelError.self) { try evaluate(builder) }
        var open = DocumentBuilder(units: .meters, tolerance: .standard)
        let five = Array(try cubeSides(&open).prefix(5))
        _ = try open.joinBodies(five, mode: .sewnSolid)
        #expect(throws: KernelError.self) { try evaluate(open) }
    }

    @Test(.timeLimit(.minutes(2)))
    func aPlacedSheetJoinsWhereItIsPlaced() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let floor = try quad(&builder, corner(0, 0, 0), corner(1, 0, 0), corner(1, 1, 0), corner(0, 1, 0))
        // The wall is evaluated five sides away and placed back against the floor.
        let wall = try quad(&builder, corner(5, 0, 0), corner(5, 0, 1), corner(6, 0, 1), corner(6, 0, 0))
        let back = try RigidTransform3D(
            basisX: .unitX, basisY: .unitY, basisZ: .unitZ,
            translation: Vector3D(x: -5 * side, y: 0, z: 0), tolerance: .standard
        )
        let targets = [JoinBodiesTargetReference(featureID: floor), JoinBodiesTargetReference(featureID: wall, placement: back)]
        #expect(try JoinSheetClosure().closes(sheets: targets, in: try evaluate(builder)) == false)
        #expect(throws: KernelError.self) {
            try JoinSheetClosure().closes(sheets: targets.map { JoinBodiesTargetReference(featureID: $0.featureID) }, in: try evaluate(builder))
        }
        var document = try builder.build(name: "placed join")
        let joined = FeatureID()
        try document.appendFeatures([try FeatureNodeFactory.make(
            operation: .joinBodies(JoinBodiesFeature(targets: targets, mode: .sewnSheet)),
            id: joined, in: document, tolerance: .standard
        )], tolerance: .standard)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        let sheet = try body(of: joined, in: evaluated)
        #expect(sheet.kind == .sheet)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.edges.count == 7)
        // No stage identity escapes into the evaluated document.
        #expect(evaluated.subshapes.entries.keys.allSatisfy { $0.featureID == joined || $0.featureID == floor || $0.featureID == wall })
    }
}
