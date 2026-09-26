import CADCore
import CADIR
import Testing
@testable import CADKernel

/// Every face of a box reports an outward normal pointing away from the box center, at the face
/// point nearest the query.
@Suite("Surface outward frame")
struct SurfaceOutwardFrameTests {
    @Test(.timeLimit(.minutes(1)))
    func boxFacesPointOutOfTheBody() throws {
        var document = CADDocument(units: .millimeters)
        let sketch = FeatureID()
        let body = FeatureID()
        let corners = [(-20.0, -10.0), (20.0, -10.0), (20.0, 10.0), (-20.0, 10.0)].map {
            SketchPoint(x: .constant(.length($0.0, unit: .millimeter)), y: .constant(.length($0.1, unit: .millimeter)))
        }
        var entities: [SketchEntityID: SketchEntity] = [:]
        for index in 0..<4 {
            entities[SketchEntityID()] = .line(SketchLine(start: corners[index], end: corners[(index + 1) % 4]))
        }
        try document.appendFeatures([
            FeatureNode(id: sketch, operation: .sketch(Sketch(plane: .xy, entities: entities)),
                outputs: [FeatureOutput(role: .profile)]),
            FeatureNode(id: body, operation: .extrude(ExtrudeFeature(
                profile: ProfileReference(featureID: sketch),
                distance: .constant(.length(10.0, unit: .millimeter))
            )), inputs: [FeatureInput(featureID: sketch, role: .profile)], outputs: [FeatureOutput(role: .body)]),
        ], tolerance: .standard)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let points = evaluated.brep.vertices.values.map(\.point)
        let center = Point3D(
            x: points.map(\.x).reduce(0, +) / Double(points.count),
            y: points.map(\.y).reduce(0, +) / Double(points.count),
            z: points.map(\.z).reduce(0, +) / Double(points.count)
        )
        let evaluator = SurfaceQueryEvaluator(tolerance: .standard)
        var checked = 0
        for (subshapeID, topology) in evaluated.subshapes.entries {
            guard case .face = topology else { continue }
            let reference = SurfaceReference(subshape: try evaluated.stableSubshapeReference(for: subshapeID))
            let probe = try evaluator.outwardFrame(nearestTo: center, on: reference, in: evaluated)
            let away = probe.point - center
            #expect(away.dot(probe.outwardNormal) > 0)
            let again = try evaluator.outwardFrame(at: probe.parameter, in: evaluated)
            #expect(again.outwardNormal == probe.outwardNormal)
            checked += 1
        }
        #expect(checked == 6)
    }
}
