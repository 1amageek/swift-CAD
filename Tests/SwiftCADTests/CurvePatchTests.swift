import Foundation
import Testing
import CADCore
import CADExchange
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Patch spans closed curves: a planar loop as its trimmed plane, a non-planar four-sided loop as
/// its Coons patch.
@Suite("Curve patch")
struct CurvePatchTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "patch"))
        try evaluated.brep.validate(tolerance: .standard)
        return evaluated
    }

    @Test(.timeLimit(.minutes(2)))
    func aClosedCircleAndALoopOfLinesSpanTheirPlanes() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let circle = try builder.sketch(on: .xy) { _ = $0.circle(center: point(0, 0), radius: length(0.01)) }.featureID
        let lines = try [(point(0.03, 0), point(0.05, 0)), (point(0.05, 0.02), point(0.05, 0)), (point(0.05, 0.02), point(0.03, 0))].map { start, end in
            try builder.sketch(on: .xy) { _ = $0.line(from: start, to: end) }.featureID
        }
        let disc = try builder.patch(curves: [CurveSectionReference(featureID: circle)])
        let triangle = try builder.patch(curves: lines.map { CurveSectionReference(featureID: $0) })
        let evaluated = try evaluate(builder)
        for (patch, area) in [(disc, Double.pi * 0.0001), (triangle, 0.0002)] {
            let faces = evaluated.subshapes.entries.compactMap { key, value -> FaceID? in
                guard key.featureID == patch, case let .face(id) = value else { return nil }
                return id
            }
            #expect(faces.count == 1)
            guard let face = faces.first, let surface = evaluated.brep.faces[face].flatMap({ evaluated.brep.geometry.surfaces[$0.surfaceID] }),
                  case .plane = surface else {
                Issue.record("A planar loop's patch is its plane.")
                continue
            }
            // Area measurement has no closed form for the disc's rational boundary (FB23.3).
            if patch == triangle {
                #expect(abs(try evaluated.brep.faceAreaMeasurement(of: face, tolerance: .standard).area - area) < 1e-12)
            }
        }
        let document = try builder.build(name: "patch")
        let sink = DataByteSink()
        let store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: sink)
        #expect(try store.loadDocument(from: BorrowedBytes(sink.bytes)).designGraph.nodes == document.designGraph.nodes)
    }

    @Test(.timeLimit(.minutes(2)))
    func aNonPlanarFourSidedLoopSpansItsCoonsPatch() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // Two lines on z = 0 and two arcs lifting between them in the planes x = 0 and x = 20 mm.
        let bottom = try builder.sketch(on: .xy) { _ = $0.line(from: point(0, 0), to: point(0.02, 0)) }.featureID
        let top = try builder.sketch(on: .xy) { _ = $0.line(from: point(0.02, 0.02), to: point(0, 0.02)) }.featureID
        let rails = try [0.0, 0.02].map { x in
            try builder.sketch(on: .plane(Plane3D(origin: Point3D(x: x, y: 0, z: 0), normal: .unitX))) { sketch in
                _ = sketch.spline(SketchSpline(controlPoints: [point(0, 0), point(0.005, 0.01), point(0.015, 0.01), point(0.02, 0)]))
            }.featureID
        }
        let patch = try builder.patch(curves: [bottom, rails[1], top, rails[0]].map { CurveSectionReference(featureID: $0) })
        let evaluated = try evaluate(builder)
        let surface = try #require(evaluated.subshapes.entries.compactMap { key, value -> Surface3D? in
            guard key.featureID == patch, case let .face(id) = value, let face = evaluated.brep.faces[id] else { return nil }
            return evaluated.brep.geometry.surfaces[face.surfaceID]
        }.first)
        guard case let .bSpline(spline) = surface else {
            Issue.record("A non-planar loop's patch is a Coons sheet.")
            return
        }
        // The arched rails lift the middle of the sheet.
        #expect(spline.controlPoints.joined().contains { $0.z > 0.005 })
    }

    @Test(.timeLimit(.minutes(2)))
    func aNonPlanarFiveSidedLoopSpansOneSheet() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A pentagon of lines on z = 0 but for one corner lifted 5 mm.
        let corners = (0..<5).map { k -> Point3D in
            let angle = 2 * Double.pi * Double(k) / 5
            return Point3D(x: 0.02 * cos(angle), y: 0.02 * sin(angle), z: k == 2 ? 0.005 : 0)
        }
        let path = FeatureID()
        try builder.append(id: path, name: "Pentagon", operation: .spatialPath(SpatialPathFeature(kind: .polyline,
            knots: (corners + [corners[0]]).map { SpatialPathKnot(position: $0) })))
        let patch = try builder.patch(curves: [CurveSectionReference(featureID: path)])
        let evaluated = try evaluate(builder)
        let faces = evaluated.subshapes.entries.compactMap { key, value -> FaceID? in
            guard key.featureID == patch, case let .face(id) = value else { return nil }
            return id
        }
        #expect(faces.count == 1)
        // The sheet passes through every corner.
        let surface = try #require(faces.first.flatMap { evaluated.brep.faces[$0] }.flatMap { evaluated.brep.geometry.surfaces[$0.surfaceID] })
        for corner in corners {
            #expect(try surface.parameterProjection(of: corner, tolerance: .standard).residual < 1e-9)
        }
    }
}
