import Foundation
import Testing
import CADCore
@testable import CADIR

@Suite("Sketch tangency constraint schema")
struct SketchTangencyConstraintTests {
    @Test(.timeLimit(.minutes(1)))
    func roundTripsEveryExplicitTangencyBranch() throws {
        let first = SketchEntityID()
        let second = SketchEntityID()
        let constraints: [SketchConstraint] = [
            .tangent(.lineCircular(line: first, circular: second, side: .left)),
            .tangent(.lineCircular(line: first, circular: second, side: .right)),
            .tangent(.circularCircular(first: first, second: second, contact: .external)),
            .tangent(.circularCircular(first: first, second: second, contact: .firstContainsSecond)),
            .tangent(.circularCircular(first: first, second: second, contact: .secondContainsFirst)),
        ]

        for constraint in constraints {
            let data = try JSONEncoder().encode(constraint)
            #expect(try JSONDecoder().decode(SketchConstraint.self, from: data) == constraint)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsUnknownTangencyFieldsAndTheRemovedSchema() throws {
        let first = SketchEntityID().rawValue.uuidString
        let second = SketchEntityID().rawValue.uuidString
        let unknownField = Data("""
        {
          "kind": "tangent",
          "tangency": {
            "kind": "lineCircular",
            "line": "\(first)",
            "circular": "\(second)",
            "side": "left",
            "legacyBranch": true
          }
        }
        """.utf8)
        let removedSchema = Data("""
        {
          "kind": "tangent",
          "first": "\(first)",
          "second": "\(second)"
        }
        """.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SketchConstraint.self, from: unknownField)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SketchConstraint.self, from: removedSchema)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsSelfTangencyDuringEncodingAndDecoding() throws {
        let entityID = SketchEntityID()
        let constraint = SketchConstraint.tangent(.circularCircular(
            first: entityID,
            second: entityID,
            contact: .external
        ))

        #expect(throws: SketchError.self) {
            try JSONEncoder().encode(constraint)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func circularTangencyGraphIncludesBothCarrierDegreesOfFreedom() throws {
        let first = SketchEntityID()
        let second = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                first: .circle(SketchCircle(
                    center: point(0.0, 0.0),
                    radius: length(1.0)
                )),
                second: .arc(SketchArc(
                    center: point(2.0, 0.0),
                    radius: length(0.5),
                    startAngle: angle(0.0),
                    endAngle: angle(1.0)
                )),
            ],
            constraints: [
                .tangent(.circularCircular(first: first, second: second, contact: .external)),
            ]
        )

        let graph = try sketch.constraintGraph(tolerance: .standard)

        #expect(graph.equations.map(\.kind) == [.tangent])
        #expect(graph.nodes.contains(SketchConstraintNode(
            reference: .circleRadius(first),
            degreeOfFreedom: .radius
        )))
        #expect(graph.nodes.contains(SketchConstraintNode(
            reference: .arcRadius(second),
            degreeOfFreedom: .radius
        )))
        #expect(graph.nodes.contains(SketchConstraintNode(
            reference: .arcCenter(second),
            degreeOfFreedom: .x
        )))
    }
}

private func point(_ x: Double, _ y: Double) -> SketchPoint {
    SketchPoint(x: length(x), y: length(y))
}

private func length(_ value: Double) -> CADExpression {
    .constant(.length(value, unit: .meter))
}

private func angle(_ value: Double) -> CADExpression {
    .constant(.angle(value, unit: .radian))
}
