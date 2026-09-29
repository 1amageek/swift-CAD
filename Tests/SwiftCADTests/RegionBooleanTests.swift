import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
import SwiftCAD

/// The Region Boolean divides space by every operand's faces: each bounded region becomes a
/// solid component of one body, which replaces the operands.
@Suite("Region Boolean")
struct RegionBooleanTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    private func box(_ builder: inout DocumentBuilder, at origin: Point3D, size: Double) throws -> FeatureID {
        try builder.box(
            placement: PrimitivePlacement(origin: origin, axis: .unitZ, referenceDirection: .unitX),
            width: length(size), depth: length(size), height: length(size)
        )
    }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "region"))
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        return evaluated
    }

    /// The volumes of the region body's components, smallest first, each measured on its own
    /// extraction.
    private func componentVolumes(_ builder: DocumentBuilder, region: FeatureID, count: Int) throws -> [Double] {
        var builder = builder
        let pieces = try (0..<count).map { try builder.extract(region, selection: .component(index: $0, count: count)) }
        let evaluated = try evaluate(builder)
        return try pieces.map { piece in
            guard case let .body(bodyID) = evaluated.subshapes[SubshapeID(featureID: piece, role: "body", ordinal: 0)] else {
                throw KernelError(phase: .evaluation, code: .missingReference, tolerance: .standard, message: "No body.")
            }
            return try evaluated.brep.volume(of: bodyID, tolerance: .standard)
        }.sorted()
    }

    /// Two 20 mm cubes overlapping by a 10 mm cube give three cells: each cube's own part and
    /// the part they share.
    @Test(.timeLimit(.minutes(3)))
    func overlappingBoxesGiveThreeCells() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let first = try box(&builder, at: .origin, size: 0.02)
        let second = try box(&builder, at: Point3D(x: 0.01, y: 0.01, z: 0.01), size: 0.02)
        let region = try builder.boolean(targets: [first], tool: second, operation: .region)
        let evaluated = try evaluate(builder)
        #expect(evaluated.brep.bodies.count == 1)
        let body = try #require(evaluated.brep.bodies.values.first)
        #expect(body.kind == .solid && body.solidComponents?.count == 3)
        let volumes = try componentVolumes(builder, region: region, count: 3)
        #expect(zip(volumes, [1e-6, 7e-6, 7e-6]).allSatisfy { abs($0 - $1) < 1e-15 })
    }

    /// A cube inside a larger one: the inner cube is one cell and the shell between them,
    /// holding a void where the inner cube is, the other.
    @Test(.timeLimit(.minutes(3)))
    func aNestedBoxIsACellAndAVoidOfTheOther() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let outer = try box(&builder, at: .origin, size: 0.02)
        let inner = try box(&builder, at: Point3D(x: 0.005, y: 0.005, z: 0.005), size: 0.01)
        let region = try builder.boolean(targets: [outer], tool: inner, operation: .region)
        let evaluated = try evaluate(builder)
        let body = try #require(evaluated.brep.bodies.values.first)
        #expect(body.solidComponents?.count == 2)
        #expect(body.solidComponents?.map(\.voidShellIDs.count).sorted() == [0, 1])
        let volumes = try componentVolumes(builder, region: region, count: 2)
        #expect(abs(volumes[0] - 1e-6) < 1e-15 && abs(volumes[1] - 7e-6) < 1e-15)
    }

    /// A sheet crossing a cube divides it; the parts of the sheet outside enclose nothing and go.
    @Test(.timeLimit(.minutes(3)))
    func aSheetDividesTheCubeItCrosses() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let cube = try box(&builder, at: .origin, size: 0.02)
        let plain = try evaluate(builder)
        let bounds = try BRepBodyBoundingBoxBuilder().bounds(
            for: try #require(plain.brep.bodies.keys.first), in: plain.brep, tolerance: .standard
        )
        let z = bounds.minimum.z + 0.005
        let sheet = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [-0.05, 0.05].map { y in [-0.05, 0.05].map { Point3D(x: $0, y: y, z: z) } }
        ))
        let region = try builder.boolean(targets: [cube], tool: sheet, operation: .region)
        let evaluated = try evaluate(builder)
        #expect(evaluated.brep.bodies.count == 1)
        let volumes = try componentVolumes(builder, region: region, count: 2)
        #expect(abs(volumes[0] - 2e-6) < 1e-15 && abs(volumes[1] - 6e-6) < 1e-15)
    }

    /// Operands that touch nothing enclose nothing new: separate cubes are cells of their own.
    @Test(.timeLimit(.minutes(3)))
    func separateBoxesStayTheirOwnCells() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let first = try box(&builder, at: .origin, size: 0.01)
        let second = try box(&builder, at: Point3D(x: 0.05, y: 0, z: 0), size: 0.01)
        _ = try builder.boolean(targets: [first], tool: second, operation: .region)
        let body = try #require(try evaluate(builder).brep.bodies.values.first)
        #expect(body.solidComponents?.count == 2)
    }

    @Test func aRegionTakesNoMaterial() throws {
        let region = BooleanFeature(
            targets: [BooleanTargetReference(featureID: FeatureID())],
            tools: [BooleanToolReference(featureID: FeatureID())],
            operation: .region, toolMaterial: .inside
        )
        #expect(throws: FeatureEvaluationError.self) { try region.validate() }
    }
}
