import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
import SwiftCAD

/// Wrap carries a body from its UVN coordinates on one face to the same coordinates on another,
/// keeping its topology and trims, and replaces it unless it is kept.
@Suite("Wrap")
struct WrapFeatureTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private let side = 0.02
    /// The half-width of the flat sheet the cube stands on: the sheet's parameters run 0…1 over
    /// 2 × `half` metres.
    private let half = 0.05

    private struct Fixture {
        var builder: DocumentBuilder
        var cube: FeatureID
        var sheet: FeatureID
        /// The cube's corner nearest the origin, which stands on the sheet.
        var minimum: Point3D
    }

    /// A 20 mm cube standing on a flat sheet, whose parameters are x and y over ±`half`.
    private func cubeOnSheet() throws -> Fixture {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let cube = try builder.box(width: length(side), depth: length(side), height: length(side))
        let plain = try evaluate(builder)
        let bounds = try BRepBodyBoundingBoxBuilder().bounds(for: try bodyID(of: cube, in: plain), in: plain.brep, tolerance: .standard)
        let z = bounds.minimum.z
        let sheet = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [-half, half].map { y in [-half, half].map { Point3D(x: $0, y: y, z: z) } }
        ))
        return Fixture(builder: builder, cube: cube, sheet: sheet, minimum: bounds.minimum)
    }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "wrap"))
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        return evaluated
    }

    private func bodyID(of featureID: FeatureID, in evaluated: EvaluatedDocument) throws -> BodyID {
        guard case let .body(bodyID) = evaluated.subshapes[SubshapeID(featureID: featureID, role: "body", ordinal: 0)] else {
            throw KernelError(phase: .evaluation, code: .missingReference, tolerance: .standard, message: "No body.")
        }
        return bodyID
    }

    private func volume(of featureID: FeatureID, in evaluated: EvaluatedDocument) throws -> Double {
        try evaluated.brep.volume(of: try bodyID(of: featureID, in: evaluated), tolerance: .standard)
    }

    /// The extremes of the vertices of `featureID`'s body.
    private func bounds(of featureID: FeatureID, in evaluated: EvaluatedDocument) throws -> (minimum: Point3D, maximum: Point3D) {
        let body = try #require(evaluated.brep.bodies[try bodyID(of: featureID, in: evaluated)])
        var points: [Point3D] = []
        for shellID in body.shellIDs {
            for faceID in try #require(evaluated.brep.shells[shellID]).faceIDs {
                for loopID in try #require(evaluated.brep.faces[faceID]).loops {
                    points += try evaluated.brep.orderedVertexIDs(for: loopID).map { try #require(evaluated.brep.vertices[$0]).point }
                }
            }
        }
        let first = try #require(points.first)
        return points.reduce((first, first)) { box, point in
            (Point3D(x: min(box.0.x, point.x), y: min(box.0.y, point.y), z: min(box.0.z, point.z)),
             Point3D(x: max(box.1.x, point.x), y: max(box.1.y, point.y), z: max(box.1.z, point.z)))
        }
    }

    /// The stable reference of `feature`'s first face whose support `keep` accepts.
    private func face(
        of feature: FeatureID, in evaluated: EvaluatedDocument, builder: DocumentBuilder,
        where keep: (Surface3D) -> Bool = { _ in true }
    ) throws -> StableSubshapeReference {
        let matches = evaluated.subshapes.entries.filter { key, value in
            guard key.featureID == feature, case let .face(faceID) = value, let face = evaluated.brep.faces[faceID],
                  let surface = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            return keep(surface)
        }.keys.sorted()
        return try builder.stableSubshape(try #require(matches.first))
    }

    private func isClose(_ a: Point3D, _ b: Point3D, within distance: Double = 1e-6) -> Bool {
        (a - b).length <= distance
    }

    @Test(.timeLimit(.minutes(4)))
    func aFaceOntoItselfLeavesTheBodyWhereItWasAndReplacesIt() throws {
        var fixture = try cubeOnSheet()
        let plain = try evaluate(fixture.builder)
        let sheetFace = try face(of: fixture.sheet, in: plain, builder: fixture.builder)
        let wrapped = try fixture.builder.wrap(fixture.cube, from: sheetFace, onto: sheetFace)
        let evaluated = try evaluate(fixture.builder)
        // The cube is replaced; the sheet stays.
        #expect(evaluated.brep.bodies.count == 2)
        #expect(evaluated.brep.bodies[try bodyID(of: wrapped, in: evaluated)]?.kind == .solid)
        #expect(abs(try volume(of: wrapped, in: evaluated) - side * side * side) < 1e-12)
        let box = try bounds(of: wrapped, in: evaluated)
        #expect(isClose(box.minimum, fixture.minimum))
        #expect(isClose(box.maximum, fixture.minimum + Vector3D(x: side, y: side, z: side)))
        #expect(evaluated.lineage.values.contains { $0.output.featureID == wrapped && $0.parents.contains { $0.featureID == fixture.cube } })
        #expect(evaluated.brep.faces.values.filter { face in
            evaluated.brep.bodies[try! bodyID(of: wrapped, in: evaluated)]!.shellIDs.contains { evaluated.brep.shells[$0]!.faceIDs.contains(face.id) }
        }.count == 6)
    }

    @Test(.timeLimit(.minutes(4)))
    func offsetsMoveAKeptBodysCopyAcrossAndAwayFromTheFace() throws {
        var fixture = try cubeOnSheet()
        let plain = try evaluate(fixture.builder)
        let sheetFace = try face(of: fixture.sheet, in: plain, builder: fixture.builder)
        // A quarter of the sheet's parameter span is a quarter of its 2 × half width.
        let moved = try fixture.builder.wrap(
            fixture.cube, from: sheetFace, onto: sheetFace,
            options: WrapOptions(offsetU: 0.25, offsetN: length(0.01)),
            keepsTarget: true
        )
        let evaluated = try evaluate(fixture.builder)
        #expect(evaluated.brep.bodies.count == 3)
        #expect(abs(try volume(of: fixture.cube, in: evaluated) - side * side * side) < 1e-12)
        #expect(abs(try volume(of: moved, in: evaluated) - side * side * side) < 1e-12)
        let shift = Vector3D(x: 0.5 * half, y: 0, z: 0.01)
        let box = try bounds(of: moved, in: evaluated)
        #expect(isClose(box.minimum, fixture.minimum + shift))
        #expect(isClose(box.maximum, fixture.minimum + Vector3D(x: side, y: side, z: side) + shift))
    }

    @Test(.timeLimit(.minutes(4)))
    func eachFaceIsReadWhereItsBodyIsPlaced() throws {
        var fixture = try cubeOnSheet()
        let plain = try evaluate(fixture.builder)
        let sheetFace = try face(of: fixture.sheet, in: plain, builder: fixture.builder)
        // The reference sheet sits 1 cm lower, so the cube stands 1 cm above it; the target sheet
        // sits 5 cm higher, and the cube lands 1 cm above that.
        let lifted = try fixture.builder.wrap(
            fixture.cube, from: sheetFace, onto: sheetFace,
            referencePlacement: .translated(by: Vector3D(x: 0, y: 0, z: -0.01)),
            targetPlacement: .translated(by: Vector3D(x: 0, y: 0, z: 0.05))
        )
        let evaluated = try evaluate(fixture.builder)
        let shift = Vector3D(x: 0, y: 0, z: 0.06)
        let box = try bounds(of: lifted, in: evaluated)
        #expect(isClose(box.minimum, fixture.minimum + shift))
        #expect(isClose(box.maximum, fixture.minimum + Vector3D(x: side, y: side, z: side) + shift))
    }

    /// The cube bent onto a cylinder's side: its s and t spans become angle and height, its
    /// heights radii above the cylinder, so its volume is the annular sector's.
    private func bentOntoCylinder(options: WrapOptions) throws -> (volume: Double, expected: Double) {
        var fixture = try cubeOnSheet()
        let radius = 0.1
        let cylinder = try fixture.builder.cylinder(radius: length(radius), height: length(0.2))
        let plain = try evaluate(fixture.builder)
        let sheetFace = try face(of: fixture.sheet, in: plain, builder: fixture.builder)
        let side = try face(of: cylinder, in: plain, builder: fixture.builder) { surface in
            if case .cylinder = surface { return true }
            return false
        }
        let chart = try FaceUVNChart(face: SurfaceReference(subshape: side), in: plain, tolerance: .standard)
        let bent = try fixture.builder.wrap(fixture.cube, from: sheetFace, onto: side, options: options)
        let evaluated = try evaluate(fixture.builder)
        #expect(evaluated.brep.bodies[try bodyID(of: bent, in: evaluated)]?.kind == .solid)
        let fraction = self.side / (2 * half)
        let angle = fraction * chart.box.u.width
        let height = fraction * chart.box.v.width
        let outer = radius + self.side
        let expected = angle * height * (outer * outer - radius * radius) / 2
        return (try volume(of: bent, in: evaluated), expected)
    }

    @Test(.timeLimit(.minutes(6)))
    func aCubeBentOntoACylinderIsAnAnnularSector() throws {
        let result = try bentOntoCylinder(options: WrapOptions())
        #expect(abs(result.volume - result.expected) <= result.expected * 1e-5)
    }

    @Test(.timeLimit(.minutes(6)))
    func aMirroredWrapTurnsItsFacesSoTheBodyStaysRightSideOut() throws {
        let result = try bentOntoCylinder(options: WrapOptions(mirrors: true))
        #expect(result.volume > 0)
        #expect(abs(result.volume - result.expected) <= result.expected * 1e-5)
    }

    @Test(.timeLimit(.minutes(4)))
    func aBodyWrappedOnceAroundAClosedFaceIsRefused() throws {
        // The cube spans a fifth of the sheet's s; five times as wide it reaches all the way round
        // the cylinder's side, whose two ends would meet across the seam.
        var fixture = try cubeOnSheet()
        let cylinder = try fixture.builder.cylinder(radius: length(0.1), height: length(0.2))
        let plain = try evaluate(fixture.builder)
        let sheetFace = try face(of: fixture.sheet, in: plain, builder: fixture.builder)
        let side = try face(of: cylinder, in: plain, builder: fixture.builder) { surface in
            if case .cylinder = surface { return true }
            return false
        }
        let chart = try FaceUVNChart(face: SurfaceReference(subshape: side), in: plain, tolerance: .standard)
        let turn = try #require(chart.periodSpan(alongS: true))
        _ = try fixture.builder.wrap(fixture.cube, from: sheetFace, onto: side, options: WrapOptions(scaleU: 5 * turn))
        do {
            _ = try evaluate(fixture.builder)
            Issue.record("A full-turn wrap must be refused.")
        } catch {
            #expect(String(describing: error).contains("meet itself"), "\(error)")
        }
    }

    @Test(.timeLimit(.minutes(4)))
    func aZeroNormalScaleIsRefusedBeforeEvaluation() throws {
        var fixture = try cubeOnSheet()
        let plain = try evaluate(fixture.builder)
        let sheetFace = try face(of: fixture.sheet, in: plain, builder: fixture.builder)
        #expect(throws: FeatureEvaluationError.self) {
            try fixture.builder.wrap(fixture.cube, from: sheetFace, onto: sheetFace, options: WrapOptions(scaleN: 0))
        }
    }

    @Test(.timeLimit(.minutes(4)))
    func aWrapRoundTripsThroughItsEncoding() throws {
        var fixture = try cubeOnSheet()
        let plain = try evaluate(fixture.builder)
        let sheetFace = try face(of: fixture.sheet, in: plain, builder: fixture.builder)
        let wrap = WrapFeature(
            target: PatternTargetReference(featureID: fixture.cube),
            referenceFace: sheetFace, targetFace: sheetFace,
            referencePlacement: .translated(by: Vector3D(x: 0.1, y: 0, z: 0)),
            options: WrapOptions(scaleU: 2, scaleV: 0.5, scaleN: 1.5, offsetU: 0.1, offsetV: -0.2,
                                 offsetN: length(0.003), mirrors: true, flipsUV: true, flipsNormal: true),
            keepsTarget: true
        )
        let operation = FeatureOperation.wrap(wrap)
        let decoded = try JSONDecoder().decode(FeatureOperation.self, from: try JSONEncoder().encode(operation))
        #expect(decoded == operation)
        var invalid = wrap
        invalid.options.scaleU = 0
        #expect(throws: (any Error).self) { try JSONEncoder().encode(FeatureOperation.wrap(invalid)) }
    }
}
