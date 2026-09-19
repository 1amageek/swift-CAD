import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR

@Suite("Spatial path editing")
struct SpatialPathTests {
    private func path() -> SpatialPathFeature {
        SpatialPathFeature(kind: .bezier, knots: [
            SpatialPathKnot(position: .origin, outgoing: Vector3D(x: 1, y: 2, z: 3)),
            SpatialPathKnot(position: Point3D(x: 4, y: 3, z: 2), incoming: Vector3D(x: -1, y: 1, z: 2)),
        ])
    }

    @Test(.timeLimit(.minutes(1)))
    func insertionPreservesSpatialCurveAndIDs() throws {
        var value = path()
        let original = value
        let before = try value.exactCurve(tolerance: .standard)
        let split = 0.3
        let inserted = try value.insert(after: value.knots[0].id, fraction: split, tolerance: .standard)
        #expect(value.knots[1].id == inserted)
        #expect(value.knots.first?.id == original.knots.first?.id)
        #expect(value.knots.last?.id == original.knots.last?.id)
        let after = try value.exactCurve(tolerance: .standard)
        for index in 0...100 {
            let parameter = Double(index) / 100
            let mapped = parameter <= split ? parameter / split : 1 + (parameter - split) / (1 - split)
            let expected = try before.point(at: parameter, tolerance: .standard)
            let actual = try after.point(at: mapped, tolerance: .standard)
            #expect((expected - actual).length < 1e-10)
        }
        #expect(try JSONDecoder().decode(SpatialPathFeature.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test(.timeLimit(.minutes(1)))
    func knotMovementRetainsArmsAndModesHaveDistinctSemantics() throws {
        var value = path()
        let id = value.knots[0].id
        let arm = value.knots[0].outgoing
        try value.move(knotID: id, handle: .position, to: Point3D(x: 2, y: 4, z: 6), tolerance: .standard)
        #expect(value.knots[0].outgoing == arm)
        try value.setMode(.symmetric, knotID: id, tolerance: .standard)
        try value.move(knotID: id, handle: .outgoing, to: Point3D(x: 4, y: 4, z: 8), tolerance: .standard)
        #expect(value.knots[0].incoming == -value.knots[0].outgoing)
        try value.setMode(.smooth, knotID: id, tolerance: .standard)
        let oppositeLength = value.knots[0].incoming.length
        try value.move(knotID: id, handle: .outgoing, to: Point3D(x: 2, y: 4, z: 12), tolerance: .standard)
        #expect(abs(value.knots[0].incoming.length - oppositeLength) < 1e-10)
        #expect(value.knots[0].incoming.z < 0)
        try value.setMode(.corner, knotID: id, tolerance: .standard)
        let opposite = value.knots[0].incoming
        try value.move(knotID: id, handle: .outgoing, to: Point3D(x: 7, y: 4, z: 6), tolerance: .standard)
        #expect(value.knots[0].incoming == opposite)
    }

    @Test(.timeLimit(.minutes(1)))
    func failedEditsPreserveSourceAndClosedInsertionWraps() throws {
        var value = path()
        let original = value
        #expect(throws: (any Error).self) {
            try value.remove(knotID: value.knots[0].id, tolerance: .standard)
        }
        #expect(value == original)
        #expect(throws: (any Error).self) {
            try value.move(knotID: value.knots[0].id, handle: .position,
                           to: Point3D(x: .nan, y: 0, z: 0), tolerance: .standard)
        }
        #expect(value == original)
        #expect(throws: (any Error).self) {
            try value.insert(after: value.knots[1].id, fraction: 0.5, tolerance: .standard)
        }
        #expect(value == original)
        var closed = SpatialPathFeature(kind: .polyline, knots: [
            SpatialPathKnot(position: .origin),
            SpatialPathKnot(position: Point3D(x: 2, y: 0, z: 1)),
            SpatialPathKnot(position: Point3D(x: 0, y: 2, z: 3)),
        ], isClosed: true)
        let id = try closed.insert(after: closed.knots[2].id, fraction: 0.5, tolerance: .standard)
        #expect(closed.knots[3].position == Point3D(x: 0, y: 1, z: 1.5))
        try closed.remove(knotID: id, tolerance: .standard)
        let before = closed
        try closed.reverse(tolerance: .standard)
        try closed.reverse(tolerance: .standard)
        #expect(closed == before)
        let exact = try closed.exactCurve(tolerance: .standard)
        #expect(try exact.point(at: 0, tolerance: .standard) == exact.point(at: 3, tolerance: .standard))
    }

    @Test(.timeLimit(.minutes(1)))
    func operationRoundTripAndTranslationRetainIdentity() throws {
        let value = path()
        let operation = FeatureOperation.spatialPath(value)
        #expect(try JSONDecoder().decode(FeatureOperation.self, from: JSONEncoder().encode(operation)) == operation)
        let document = CADDocument(units: .meters)
        let node = try FeatureNodeFactory.make(operation: operation, in: document, tolerance: .standard)
        #expect(node.inputs.isEmpty)
        #expect(node.outputs.map(\.role) == [.curve])
    }
}
