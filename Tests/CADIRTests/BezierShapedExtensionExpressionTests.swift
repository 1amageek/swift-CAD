import Foundation
import Testing
import CADCore
@testable import CADIR

/// A persisted shaped extension follows the parameters its curve's points reference.
@Suite struct BezierShapedExtensionExpressionTests {
    @Test func theExtensionFollowsAParameterOfItsCurve() throws {
        let heightID = ParameterID()
        var table = ParameterTable(parameters: [
            heightID: Parameter(id: heightID, name: "height", expression: .constant(Quantity(value: 0.004, kind: .length)), kind: .length),
        ])
        func length(_ value: Double) -> CADExpression { .constant(Quantity(value: value, kind: .length)) }
        let coordinates: [CADExpression] = [length(0), length(0), length(0.004), length(0.002), length(0.008), length(0.001), length(0.01), .reference(heightID)]
        let x = CADExpression.bezierShapedExtension(shape: .arc(spanCount: 3), coordinates: coordinates, length: length(0.006), coordinateIndex: 8)
        #expect(try table.inferredKind(for: x) == .length)
        #expect(x.referencedParameterIDs == [heightID])
        let before = try table.resolvedValue(for: x).value
        let direct = try BezierShapedExtension(tolerance: .standard).newPoints(
            shape: .arc(spanCount: 3),
            controlPoints: [Point2D(x: 0, y: 0), Point2D(x: 0.004, y: 0.002), Point2D(x: 0.008, y: 0.001), Point2D(x: 0.01, y: 0.004)],
            length: 0.006
        )
        #expect(abs(before - direct[4].x) < 1e-15)
        table.parameters[heightID]?.expression = .constant(Quantity(value: 0.006, kind: .length))
        #expect(abs(try table.resolvedValue(for: x).value - before) > 1e-6)
    }
}
