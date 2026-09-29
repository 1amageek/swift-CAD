import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
import SwiftCAD

/// Booleans between solids and sheets, each operand's material taken as its Material says: a
/// sheet facing a solid is solid behind its normals by default, a sheet facing a sheet is an
/// empty shell.
@Suite("Sheet Boolean")
struct SheetBooleanTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    /// A 20 mm cube and a horizontal sheet at `height`, larger than the cube, facing +z (or -z).
    private func operands(height: Double, sheetHalfWidth: Double = 0.05, facingDown: Bool = false) throws
        -> (builder: DocumentBuilder, box: FeatureID, sheet: FeatureID, boxBounds: BoundingBox3D) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let plain = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        let bodyID = try #require(plain.brep.bodies.keys.first)
        let bounds = try BRepBodyBoundingBoxBuilder().bounds(for: bodyID, in: plain.brep, tolerance: .standard)
        let z = bounds.minimum.z + height
        let xs = [-sheetHalfWidth, sheetHalfWidth], ys = facingDown ? [sheetHalfWidth, -sheetHalfWidth] : [-sheetHalfWidth, sheetHalfWidth]
        let sheet = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: ys.map { y in xs.map { Point3D(x: $0 + (bounds.minimum.x + bounds.maximum.x) / 2, y: y + (bounds.minimum.y + bounds.maximum.y) / 2, z: z) } }
        ))
        return (builder, box, sheet, bounds)
    }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "sheet boolean"))
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        return evaluated
    }

    private let cube = 0.02 * 0.02 * 0.02

    @Test(.timeLimit(.minutes(2)))
    func aSheetToolRemovesTheSideBehindItsNormals() throws {
        var fixture = try operands(height: 0.005)
        _ = try fixture.builder.boolean(targets: [fixture.box], tool: fixture.sheet, operation: .difference)
        let evaluated = try evaluate(fixture.builder)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.75 * cube) < 1e-12)
        let body = try #require(evaluated.brep.bodies.values.first)
        #expect(body.kind == .solid)
        let bounds = try BRepBodyBoundingBoxBuilder().bounds(for: body.id, in: evaluated.brep, tolerance: .standard)
        #expect(abs(bounds.minimum.z - (fixture.boxBounds.minimum.z + 0.005)) < 1e-9)
    }

    @Test(.timeLimit(.minutes(2)))
    func intersectKeepsTheSideBehindAndOutsideMaterialFlipsIt() throws {
        var fixture = try operands(height: 0.005)
        _ = try fixture.builder.boolean(targets: [fixture.box], tool: fixture.sheet, operation: .intersect)
        #expect(abs(try evaluate(fixture.builder).brep.volume(tolerance: .standard) - 0.25 * cube) < 1e-12)

        var outside = try operands(height: 0.005)
        _ = try outside.builder.boolean(targets: [outside.box], tool: outside.sheet, operation: .difference, toolMaterial: .outside)
        #expect(abs(try evaluate(outside.builder).brep.volume(tolerance: .standard) - 0.25 * cube) < 1e-12)

        var facingDown = try operands(height: 0.005, facingDown: true)
        _ = try facingDown.builder.boolean(targets: [facingDown.box], tool: facingDown.sheet, operation: .difference)
        #expect(abs(try evaluate(facingDown.builder).brep.volume(tolerance: .standard) - 0.25 * cube) < 1e-12)
    }

    /// A slice by a sheet cuts the solid in two along it.
    @Test(.timeLimit(.minutes(2)))
    func aSheetSlicesASolidInTwo() throws {
        var fixture = try operands(height: 0.012)
        _ = try fixture.builder.boolean(targets: [fixture.box], tool: fixture.sheet, operation: .slice)
        let evaluated = try evaluate(fixture.builder)
        #expect(evaluated.brep.shells.count == 2)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - cube) < 1e-12)
    }

    /// A sheet target is an empty shell: a solid tool trims it, and it keeps what lies inside.
    @Test(.timeLimit(.minutes(2)))
    func aSolidToolTrimsASheetTarget() throws {
        var difference = try operands(height: 0.01)
        _ = try difference.builder.boolean(targets: [difference.sheet], tool: difference.box, operation: .difference)
        let holed = try evaluate(difference.builder)
        let holedBody = try #require(holed.brep.bodies.values.first)
        #expect(holedBody.kind == .sheet)
        #expect(holed.brep.faces.count == 1)
        #expect(holed.brep.faces.values.first?.loops.count == 2)

        var intersect = try operands(height: 0.01)
        _ = try intersect.builder.boolean(targets: [intersect.sheet], tool: intersect.box, operation: .intersect)
        let inside = try evaluate(intersect.builder)
        let insideBody = try #require(inside.brep.bodies.values.first)
        #expect(insideBody.kind == .sheet)
        // The kept square is the cube's cross-section: its corners are the cube's.
        let xs = inside.brep.vertices.values.map(\.point.x), ys = inside.brep.vertices.values.map(\.point.y)
        #expect(inside.brep.faces.count == 1 && inside.brep.vertices.count == 4)
        #expect(abs((xs.max() ?? 0) - (xs.min() ?? 0) - 0.02) < 1e-9)
        #expect(abs((ys.max() ?? 0) - (ys.min() ?? 0) - 0.02) < 1e-9)
    }

    /// A sheet that does not reach across the solid leaves a side undefined: a typed failure.
    @Test(.timeLimit(.minutes(2)))
    func aSheetThatDoesNotReachAcrossIsRefused() throws {
        var fixture = try operands(height: 0.005, sheetHalfWidth: 0.004)
        _ = try fixture.builder.boolean(targets: [fixture.box], tool: fixture.sheet, operation: .difference)
        #expect(throws: KernelError.self) { try evaluate(fixture.builder) }
    }

    @Test func theBooleanOutputFollowsItsTargetsAndMaterial() throws {
        let boolean = BooleanFeature(targets: [], tools: [], operation: .union)
        #expect(try boolean.resultPort(targetPorts: [.body]) == .body)
        #expect(try boolean.resultPort(targetPorts: [.sheet]) == .sheet)
        #expect(try BooleanFeature(targets: [], tools: [], operation: .union, targetMaterial: .empty).resultPort(targetPorts: [.body]) == .sheet)
        #expect(try BooleanFeature(targets: [], tools: [], operation: .union, targetMaterial: .inside).resultPort(targetPorts: [.sheet]) == .body)
        #expect(throws: FeatureEvaluationError.self) { try boolean.resultPort(targetPorts: [.body, .sheet]) }
    }

    /// Two sheets are empty shells: a difference splits the target along the crossing, an
    /// intersection has no material to keep.
    @Test(.timeLimit(.minutes(2)))
    func sheetsSplitEachOtherAndShareNoMaterial() throws {
        func crossing() throws -> (DocumentBuilder, FeatureID, FeatureID) {
            var builder = DocumentBuilder(units: .meters, tolerance: .standard)
            let flat = try builder.bSplineSurface(BSplineSurface3D(
                uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
                controlPoints: [-0.02, 0.02].map { y in [-0.02, 0.02].map { Point3D(x: $0, y: y, z: 0) } }
            ))
            let upright = try builder.bSplineSurface(BSplineSurface3D(
                uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
                controlPoints: [-0.01, 0.01].map { z in [-0.03, 0.03].map { Point3D(x: 0.005, y: $0, z: z) } }
            ))
            return (builder, flat, upright)
        }
        var (builder, flat, upright) = try crossing()
        _ = try builder.boolean(targets: [flat], tool: upright, operation: .difference)
        let split = try evaluate(builder)
        #expect(split.brep.bodies.values.first?.kind == .sheet)
        #expect(split.brep.faces.count == 2)

        var (empty, first, second) = try crossing()
        _ = try empty.boolean(targets: [first], tool: second, operation: .intersect)
        #expect(throws: KernelError.self) { try evaluate(empty) }
    }

    /// A union with a sheet's half-space has no closed boundary: refused, not a broken solid.
    @Test(.timeLimit(.minutes(2)))
    func aUnionWithASheetHalfSpaceIsRefused() throws {
        var fixture = try operands(height: 0.005)
        _ = try fixture.builder.boolean(targets: [fixture.box], tool: fixture.sheet, operation: .union)
        #expect(throws: KernelError.self) { try evaluate(fixture.builder) }
    }

    @Test func materialsRoundTripAndDefaultWhenAbsent() throws {
        let boolean = BooleanFeature(
            targets: [BooleanTargetReference(featureID: FeatureID())],
            tools: [BooleanToolReference(featureID: FeatureID())],
            operation: .difference, targetMaterial: .empty, toolMaterial: .outside
        )
        #expect(try JSONDecoder().decode(BooleanFeature.self, from: JSONEncoder().encode(boolean)) == boolean)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(boolean)) as? [String: Any])
        object.removeValue(forKey: "targetMaterial")
        object.removeValue(forKey: "toolMaterial")
        let older = try JSONDecoder().decode(BooleanFeature.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(older.targetMaterial == .default && older.toolMaterial == .default)
    }

    /// A vertical sheet only a little larger than the cube (a cut's cutter) at `y`, facing +y.
    private func tightVerticalSheet(_ builder: inout DocumentBuilder, bounds: BoundingBox3D, y: Double, alongX: Bool = true) throws -> FeatureID {
        let margin = 0.003
        let zs = [bounds.minimum.z - margin, bounds.maximum.z + margin]
        if alongX {
            let xs = [bounds.minimum.x - margin, bounds.maximum.x + margin]
            return try builder.bSplineSurface(BSplineSurface3D(
                uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
                controlPoints: zs.map { z in xs.reversed().map { Point3D(x: $0, y: y, z: z) } }
            ))
        }
        let ys = [bounds.minimum.y - margin, bounds.maximum.y + margin]
        return try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: zs.map { z in ys.map { Point3D(x: y, y: $0, z: z) } }
        ))
    }

    /// A cutter only a little larger than the solid still classifies every face of it: rays run
    /// along the cutter's normal first.
    @Test(.timeLimit(.minutes(2)))
    func aTightCutterSlicesAndItsPiecesSliceAgain() throws {
        var fixture = try operands(height: 0.5)
        let bounds = fixture.boxBounds
        let first = try tightVerticalSheet(&fixture.builder, bounds: bounds, y: bounds.minimum.y + 0.007)
        let once = try fixture.builder.boolean(targets: [fixture.box], tool: first, operation: .slice, toolMaterial: .inside)
        let sliced: EvaluatedDocument
        do {
            sliced = try evaluate(fixture.builder)
        } catch {
            Issue.record("FIRST SLICE: \(error)")
            return
        }
        #expect(sliced.brep.shells.count == 2 + 1)
        let second = try tightVerticalSheet(&fixture.builder, bounds: bounds, y: bounds.minimum.x + 0.012, alongX: false)
        _ = try fixture.builder.boolean(targets: [once], tool: second, operation: .slice, toolMaterial: .inside)
        let twice = try evaluate(fixture.builder)
        let solidShells = twice.brep.bodies.values.filter { $0.kind == .solid }.flatMap(\.shellIDs)
        #expect(solidShells.count == 4)
        #expect(abs(try twice.brep.bodies.values.filter { $0.kind == .solid }.map { try twice.brep.volume(of: $0.id, tolerance: .standard) }.reduce(0, +) - cube) < 1e-12)
    }

    /// A line extruded along a slanted direction is a slanted plane: it slices the cube in two.
    @Test(.timeLimit(.minutes(2)))
    func aSlantedExtrudedLineSlicesTheCube() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let line = try builder.sketch(on: .xy) { sketch in
            _ = sketch.line(
                from: SketchPoint(x: length(-0.1), y: length(0.007)),
                to: SketchPoint(x: length(0.1), y: length(0.007))
            )
        }
        var document = try builder.build(name: "slanted")
        let sheetID = FeatureID()
        try document.appendFeatures([try FeatureNodeFactory.make(
            operation: .extrude(ExtrudeFeature(
                section: .curve(CurveSectionReference(featureID: line.featureID)),
                distance: length(0.1),
                startDistance: length(-0.1),
                direction: .vector(Vector3D(x: 0, y: 0.5, z: 1)),
                resultKind: .sheet
            )),
            id: sheetID, in: document, tolerance: .standard
        )], tolerance: .standard)
        let sliceID = FeatureID()
        try document.appendFeatures([try FeatureNodeFactory.make(
            operation: .boolean(BooleanFeature(
                targets: [BooleanTargetReference(featureID: box)],
                tools: [BooleanToolReference(featureID: sheetID)],
                operation: .slice,
                toolMaterial: .inside
            )),
            id: sliceID, in: document, tolerance: .standard
        )], tolerance: .standard)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        guard case let .body(sliced) = evaluated.subshapes[SubshapeID(featureID: sliceID, role: "body", ordinal: 0)] else {
            Issue.record("The slice has no body.")
            return
        }
        #expect(evaluated.brep.bodies[sliced]?.shellIDs.count == 2)
        #expect(abs(try evaluated.brep.volume(of: sliced, tolerance: .standard) - cube) < 1e-12)
    }
}
