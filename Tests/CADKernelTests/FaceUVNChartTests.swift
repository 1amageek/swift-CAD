import CADCore
import CADGeometry
import CADIR
import Foundation
import Testing
import CADModeling
@testable import CADKernel

/// A face's UVN chart reads a point as normalized face parameters and a height along the outward
/// normal, and places a coordinate back; charts of two faces carry a point between them.
@Suite("Face UVN chart")
struct FaceUVNChartTests {
    private func box() throws -> (EvaluatedDocument, [SurfaceReference: Vector3D]) {
        var document = CADDocument(units: .millimeters)
        let sketch = FeatureID(), body = FeatureID()
        let corners = [(-20.0, -10.0), (20.0, -10.0), (20.0, 10.0), (-20.0, 10.0)].map {
            SketchPoint(x: .constant(.length($0.0, unit: .millimeter)), y: .constant(.length($0.1, unit: .millimeter)))
        }
        var entities: [SketchEntityID: SketchEntity] = [:]
        for index in 0..<4 {
            entities[SketchEntityID()] = .line(SketchLine(start: corners[index], end: corners[(index + 1) % 4]))
        }
        try document.appendFeatures([
            FeatureNode(id: sketch, operation: .sketch(Sketch(plane: .xy, entities: entities)), outputs: [FeatureOutput(role: .profile)]),
            FeatureNode(id: body, operation: .extrude(ExtrudeFeature(
                profile: ProfileReference(featureID: sketch), distance: .constant(.length(10.0, unit: .millimeter))
            )), inputs: [FeatureInput(featureID: sketch, role: .profile)], outputs: [FeatureOutput(role: .body)]),
        ], tolerance: .standard)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        var faces: [SurfaceReference: Vector3D] = [:]
        let points = evaluated.brep.vertices.values.map(\.point)
        let center = Point3D(x: points.map(\.x).reduce(0, +) / Double(points.count),
                             y: points.map(\.y).reduce(0, +) / Double(points.count),
                             z: points.map(\.z).reduce(0, +) / Double(points.count))
        for (subshapeID, topology) in evaluated.subshapes.entries {
            guard case .face = topology else { continue }
            let reference = SurfaceReference(subshape: try evaluated.stableSubshapeReference(for: subshapeID))
            faces[reference] = try SurfaceQueryEvaluator(tolerance: .standard)
                .outwardFrame(nearestTo: center, on: reference, in: evaluated).outwardNormal
        }
        return (evaluated, faces)
    }

    @Test(.timeLimit(.minutes(1)))
    func coordinatesRoundTripAndTheFaceCenterIsAtOneHalf() throws {
        let (document, faces) = try box()
        #expect(faces.count == 6)
        for (reference, normal) in faces {
            let chart = try FaceUVNChart(face: reference, in: document, tolerance: .standard)
            let center = try chart.point(at: UVNCoordinate(s: 0.5, t: 0.5, n: 0))
            let lifted = center + normal * 3
            let coordinate = try chart.coordinate(of: lifted)
            #expect(abs(coordinate.s - 0.5) < 1.0e-9 && abs(coordinate.t - 0.5) < 1.0e-9)
            #expect(abs(coordinate.n - 3) < 1.0e-9)
            let probe = Point3D(x: center.x + 1, y: center.y - 2, z: center.z + 0.5) + normal * 1.5
            #expect((try chart.point(at: chart.coordinate(of: probe)) - probe).length < 1.0e-9)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aCoordinateOnOneFaceLandsOnAnother() throws {
        let (document, faces) = try box()
        let top = try #require(faces.first { $0.value.z > 0.5 }?.key)
        let side = try #require(faces.first { $0.value.x > 0.5 }?.key)
        let from = try FaceUVNChart(face: top, in: document, tolerance: .standard)
        let to = try FaceUVNChart(face: side, in: document, tolerance: .standard)
        let onTop = try from.point(at: UVNCoordinate(s: 0.25, t: 0.75, n: 0))
        let moved = try to.point(at: from.coordinate(of: onTop))
        let back = try to.coordinate(of: moved)
        #expect(abs(back.s - 0.25) < 1.0e-9 && abs(back.t - 0.75) < 1.0e-9 && abs(back.n) < 1.0e-9)
        // The side face is a plane of constant x: the moved point is on it.
        #expect(abs(moved.x - (try to.point(at: UVNCoordinate(s: 0.5, t: 0.5, n: 0))).x) < 1.0e-12)
    }

    @Test func aPeriodicParameterReadsTheFaceRangeAcrossTheSeam() throws {
        let interval = try ScalarInterval(lower: -0.5, upper: 0.5)
        let period = 2 * Double.pi
        #expect(abs(FaceUVNChart.unwrapped(period - 0.25, domain: .periodic(period: period), interval: interval) + 0.25) < 1.0e-12)
        #expect(abs(FaceUVNChart.unwrapped(0.25, domain: .periodic(period: period), interval: interval) - 0.25) < 1.0e-12)
        #expect(FaceUVNChart.unwrapped(7, domain: .unbounded, interval: interval) == 7)
    }
}
