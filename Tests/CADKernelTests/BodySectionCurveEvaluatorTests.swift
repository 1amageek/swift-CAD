import CADCore
import CADGeometry
import CADIR
import Foundation
import Testing
@testable import CADKernel

/// Two bodies meet along section pieces lying on both of their faces; bodies apart have none.
@Suite("Body section curves")
struct BodySectionCurveEvaluatorTests {
    private func square(_ x: Double, _ y: Double, _ side: Double) -> [SketchEntityID: SketchEntity] {
        let corners = [(x, y), (x + side, y), (x + side, y + side), (x, y + side)].map {
            SketchPoint(x: .constant(.length($0.0, unit: .meter)), y: .constant(.length($0.1, unit: .meter)))
        }
        var entities: [SketchEntityID: SketchEntity] = [:]
        for index in 0..<4 {
            entities[SketchEntityID()] = .line(SketchLine(start: corners[index], end: corners[(index + 1) % 4]))
        }
        return entities
    }

    private func twoBoxes(offset: Double) throws -> EvaluatedDocument {
        var document = CADDocument(units: .meters)
        var features: [FeatureNode] = []
        for (x, height) in [(0.0, 2.0), (offset, 1.0)] {
            let sketch = FeatureID()
            features.append(FeatureNode(id: sketch, operation: .sketch(Sketch(plane: .xy, entities: square(x, x, 2))),
                                        outputs: [FeatureOutput(role: .profile)]))
            features.append(FeatureNode(id: FeatureID(), operation: .extrude(ExtrudeFeature(
                profile: ProfileReference(featureID: sketch), distance: .constant(.length(height, unit: .meter))
            )), inputs: [FeatureInput(featureID: sketch, role: .profile)], outputs: [FeatureOutput(role: .body)]))
        }
        try document.appendFeatures(features, tolerance: .standard)
        return try DocumentEvaluator(tolerance: .standard).evaluate(document)
    }

    @Test(.timeLimit(.minutes(1)))
    func overlappingBoxesMeetOnBothBoundaries() throws {
        let evaluated = try twoBoxes(offset: 1)
        let bodies = Array(evaluated.brep.bodies.keys)
        #expect(bodies.count == 2)
        let sections = try BodySectionCurveEvaluator(tolerance: .standard).sections(between: bodies[0], and: bodies[1], in: evaluated.brep)
        #expect(!sections.isEmpty)
        // Every section point is on the boundary of both boxes: box one is [0, 2]² × [0, 2],
        // box two [1, 3]² × [0, 1].
        func onBoundary(_ p: Point3D, _ lower: Point3D, _ upper: Point3D) -> Bool {
            let inside = p.x >= lower.x - 1e-9 && p.x <= upper.x + 1e-9 && p.y >= lower.y - 1e-9 && p.y <= upper.y + 1e-9
                && p.z >= lower.z - 1e-9 && p.z <= upper.z + 1e-9
            let onFace = [abs(p.x - lower.x), abs(p.x - upper.x), abs(p.y - lower.y), abs(p.y - upper.y),
                          abs(p.z - lower.z), abs(p.z - upper.z)].contains { $0 < 1e-9 }
            return inside && onFace
        }
        for section in sections {
            for i in 0...4 {
                let p = try section.curve.point(at: section.lower + (section.upper - section.lower) * Double(i) / 4, tolerance: .standard)
                #expect(onBoundary(p, Point3D(x: 0, y: 0, z: 0), Point3D(x: 2, y: 2, z: 2)))
                #expect(onBoundary(p, Point3D(x: 1, y: 1, z: 0), Point3D(x: 3, y: 3, z: 1)))
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func bodiesApartHaveNoSection() throws {
        let evaluated = try twoBoxes(offset: 5)
        let bodies = Array(evaluated.brep.bodies.keys)
        #expect(try BodySectionCurveEvaluator(tolerance: .standard).sections(between: bodies[0], and: bodies[1], in: evaluated.brep).isEmpty)
    }
}
