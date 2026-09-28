import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Where two bodies' faces meet: the Boolean pipeline's face-pair intersections, split and
/// trimmed to both faces (its UV split graph), as curve pieces. Project Body Body turns them
/// into curves.
public struct BodySectionCurveEvaluator: Sendable {
    /// One piece of the section: `curve` between `lower` and `upper`.
    public struct Section: Sendable {
        public var curve: Curve3D
        public var lower: Double
        public var upper: Double
    }

    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The pieces, in the graph's face-pair order; empty when the bodies do not meet. A tangent
    /// contact (a point) or coincident faces (an area) give no piece.
    public func sections(between first: BodyID, and second: BodyID, in model: BRepModel) throws -> [Section] {
        guard first != second else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                              message: "A body's section needs two different bodies.")
        }
        let pipeline = BooleanPipeline(evaluator: ExactBRepBooleanEvaluator())
        // Union's intersection graph: disjoint bodies are a valid union with no face pair,
        // where an intersection would refuse them.
        let intersections = try pipeline.intersectionGraph(
            targetBodyIDs: [first], toolBodyID: second, operation: .union, model: model, tolerance: tolerance
        )
        let split = try pipeline.uvSplitGraph(intersectionGraph: intersections, model: model, tolerance: tolerance)
        var sections: [Section] = []
        for faceSplit in split.splits {
            for component in faceSplit.components {
                switch component.geometry {
                case .transverseSegment(let start, let end):
                    let chord = end.point - start.point
                    let length = chord.length
                    guard length > tolerance.distance else { continue }
                    sections.append(Section(
                        curve: .line(Line3D(origin: start.point, direction: chord * (1 / length))),
                        lower: 0, upper: length
                    ))
                case .closedCurve(let closed):
                    let range = try Self.closedRange(of: closed.intersection.curve, tolerance: tolerance)
                    sections.append(Section(curve: closed.intersection.curve, lower: range.lower, upper: range.upper))
                case .trimmedCurve(let chain):
                    for segment in chain.segments {
                        let lower = min(segment.startParameter, segment.endParameter)
                        let upper = max(segment.startParameter, segment.endParameter)
                        guard upper > lower else { continue }
                        sections.append(Section(curve: segment.intersection.curve, lower: lower, upper: upper))
                    }
                case .tangent, .coincident:
                    continue
                }
            }
        }
        return sections
    }

    /// A closed section runs over one whole period or its closed domain.
    static func closedRange(of curve: Curve3D, tolerance: ModelingTolerance) throws -> (lower: Double, upper: Double) {
        switch curve.parameterDomain {
        case .periodic(let period):
            return (0, period)
        case .closed(let lower, let upper):
            return (lower, upper)
        case .unbounded:
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A closed section cannot run over an unbounded curve.")
        }
    }
}
