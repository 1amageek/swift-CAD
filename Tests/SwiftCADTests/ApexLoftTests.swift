import Foundation
import Testing
import CADCore
import CADExchange
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Loft from a section to a vertex: a square to a pyramid of planar triangles, a circle to a cone
/// whose ruled faces meet at the apex.
@Suite("Loft to a vertex")
struct ApexLoftTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    /// A loft of `section` to the corner (0, 0, 30 mm) of a small box standing there.
    private func loft(_ section: (inout SketchBuilder) -> Void, kind: LoftResultKind = .solid) throws -> (EvaluatedDocument, FeatureID, DocumentBuilder) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sketch = try builder.sketch(on: .xy, section).featureID
        let marker = try builder.box(placement: PrimitivePlacement(origin: Point3D(x: 0, y: 0, z: 0.03), axis: .unitZ, referenceDirection: .unitX),
                                     width: length(0.005), depth: length(0.005), height: length(0.005))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "apex"))
        let vertex = try #require(before.subshapes.entries.first { key, value in
            guard key.featureID == marker, case let .vertex(id) = value, let point = before.brep.vertices[id]?.point else { return false }
            return (point - Point3D(x: 0, y: 0, z: 0.03)).length < 1e-12
        }?.key)
        let apex = LoftApex(source: marker, vertex: try builder.stableSubshape(vertex))
        let section: SectionReference = kind == .solid
            ? .profile(ProfileReference(featureID: sketch)) : .curve(CurveSectionReference(featureID: sketch))
        let loft = try builder.loft(sections: [LoftSectionReference(section: section)], options: LoftOptions(resultKind: kind), apex: apex)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "apex"))
        try evaluated.brep.validate(level: kind == .solid ? .volumetric : .exact, tolerance: .standard)
        return (evaluated, loft, builder)
    }

    private func body(_ loft: FeatureID, in evaluated: EvaluatedDocument) throws -> BodyID {
        try #require(evaluated.subshapes.entries.compactMap { key, value -> BodyID? in
            guard key.featureID == loft, case let .body(id) = value else { return nil }
            return id
        }.first)
    }

    @Test(.timeLimit(.minutes(2)))
    func aSquareLoftsToAPyramid() throws {
        let (evaluated, loft, builder) = try loft { _ = $0.rectangle(width: self.length(0.02), height: self.length(0.02)) }
        let pyramid = try body(loft, in: evaluated)
        let faces = try BodyTopologyScope(bodyID: pyramid, model: evaluated.brep).references.compactMap { reference -> FaceID? in
            if case let .face(id) = reference { return id }
            return nil
        }
        #expect(faces.count == 5)
        #expect(faces.allSatisfy { evaluated.brep.faces[$0].flatMap { evaluated.brep.geometry.surfaces[$0.surfaceID] }.map { if case .plane = $0 { true } else { false } } ?? false })
        // A third of the base times the height.
        let volume = try evaluated.brep.volume(of: pyramid, tolerance: .standard)
        #expect(abs(volume - 0.02 * 0.02 * 0.03 / 3) < 1e-12, "\(volume)")

        let document = try builder.build(name: "apex")
        let sink = DataByteSink()
        let store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: sink)
        #expect(try store.loadDocument(from: BorrowedBytes(sink.bytes)).designGraph.nodes == document.designGraph.nodes)
    }

    @Test(.timeLimit(.minutes(2)))
    func aCircleLoftsToACone() throws {
        let (evaluated, loft, _) = try loft { _ = $0.circle(center: SketchPoint(x: self.length(0), y: self.length(0)), radius: self.length(0.01)) }
        let cone = try body(loft, in: evaluated)
        let volume = try evaluated.brep.volume(of: cone, tolerance: .standard)
        #expect(abs(volume - Double.pi * 0.01 * 0.01 * 0.03 / 3) < 1e-10, "\(volume)")
    }

    @Test(.timeLimit(.minutes(2)))
    func aBentCurveLoftsToAVertexAsASheet() throws {
        // A sheet whose edge at v = 0 is a cubic through four points spanning no plane.
        let s = 0.02
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let row = [Point3D(x: 0, y: 0, z: 0), Point3D(x: s / 3, y: s / 3, z: s), Point3D(x: 2 * s / 3, y: -s / 3, z: s), Point3D(x: s, y: 0, z: 0)]
        let sheet = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 3, vDegree: 1, uKnots: [0, 0, 0, 0, 1, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [row, row.map { $0 + Vector3D(x: 0, y: 0, z: -s) }]
        ))
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "bent"))
        let key = try #require(source.subshapes.entries.first { key, value in
            guard key.featureID == sheet, case let .edge(id) = value, let edge = source.brep.edges[id],
                  case .bSpline? = source.brep.geometry.curves[edge.curveID],
                  let start = source.brep.vertices[edge.startVertexID]?.point,
                  let end = source.brep.vertices[edge.endVertexID]?.point else { return false }
            return abs(start.z) < 1e-12 && abs(end.z) < 1e-12
        }?.key)
        let bent = try builder.edgeCurves(of: sheet, bodyRole: .sheet, edges: [try builder.stableSubshape(key)])
        let apexPoint = Point3D(x: s / 2, y: 0.03, z: 0.03)
        let marker = try builder.box(placement: PrimitivePlacement(origin: apexPoint, axis: .unitZ, referenceDirection: .unitX),
                                     width: length(0.005), depth: length(0.005), height: length(0.005))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "bent"))
        let vertex = try #require(before.subshapes.entries.first { key, value in
            guard key.featureID == marker, case let .vertex(id) = value, let point = before.brep.vertices[id]?.point else { return false }
            return (point - apexPoint).length < 1e-12
        }?.key)
        let loft = try builder.loft(sections: [LoftSectionReference(section: .curve(CurveSectionReference(featureID: bent)))],
                                    options: LoftOptions(resultKind: .sheet),
                                    apex: LoftApex(source: marker, vertex: try builder.stableSubshape(vertex)))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "bent"))
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        let fan = try body(loft, in: evaluated)
        #expect(evaluated.brep.bodies[fan]?.kind == .sheet)
        // The ruled face from the curve to the vertex: its corners the curve's ends and the vertex.
        let points = try BodyTopologyScope(bodyID: fan, model: evaluated.brep).references.compactMap { reference -> Point3D? in
            guard case let .vertex(id) = reference else { return nil }
            return evaluated.brep.vertices[id]?.point
        }
        #expect(points.count == 3)
        for expected in [row[0], row[3], apexPoint] { #expect(points.contains { ($0 - expected).length < 1e-9 }) }
    }

    @Test(.timeLimit(.minutes(2)))
    func anOpenCurveLoftsToAFanSheet() throws {
        let (evaluated, loft, _) = try loft({ _ = $0.line(from: SketchPoint(x: self.length(-0.01), y: self.length(0)), to: SketchPoint(x: self.length(0.01), y: self.length(0))) }, kind: .sheet)
        #expect(evaluated.brep.bodies[try body(loft, in: evaluated)]?.kind == .sheet)
    }
}
