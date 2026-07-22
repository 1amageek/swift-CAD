import CADCore
import CADIR
import CADModeling
import CADTopology
import Testing
@testable import CADKernel

@Suite("General Boolean pipeline with coincident trims")
struct CoincidentBooleanGeneralPipelineTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func partiallyOverlappingCoplanarBoxesProduceValidatedExactIntersection() throws {
        let target = try box(
            origin: .origin,
            width: 0.040,
            depth: 0.020,
            height: 0.010
        )
        let tool = try box(
            origin: Point3D(x: 0.020, y: 0.005, z: 0.0),
            width: 0.030,
            depth: 0.010,
            height: 0.010
        )
        let sewn = try evaluate(.intersect, target: target, tool: tool)

        try sewn.brep.validate(level: .exact, tolerance: tolerance)
        #expect(sewn.brep.bodies.count == 1)
        #expect(sewn.brep.shells.count == 1)
        #expect(abs(try sewn.brep.volume(tolerance: tolerance) - 0.000_002) <= 1.0e-10)
    }

    @Test(.timeLimit(.minutes(1)))
    func partiallyOverlappingCoplanarBoxesProduceValidatedUnionAndDifference() throws {
        let target = try box(
            origin: .origin,
            width: 0.040,
            depth: 0.020,
            height: 0.010
        )
        let tool = try box(
            origin: Point3D(x: 0.020, y: 0.005, z: 0.0),
            width: 0.030,
            depth: 0.010,
            height: 0.010
        )
        let union = try evaluate(.union, target: target, tool: tool)
        let difference = try evaluate(.difference, target: target, tool: tool)

        try union.brep.validate(level: .exact, tolerance: tolerance)
        try difference.brep.validate(level: .exact, tolerance: tolerance)
        #expect(union.brep.bodies.count == 1)
        #expect(difference.brep.bodies.count == 1)
        #expect(abs(try union.brep.volume(tolerance: tolerance) - 0.000_009) <= 1.0e-10)
        #expect(abs(try difference.brep.volume(tolerance: tolerance) - 0.000_006) <= 1.0e-10)
        #expect(union.lineage.values.contains { $0.parents.isEmpty == false })
        #expect(difference.lineage.values.contains { $0.parents.isEmpty == false })
    }

    private func evaluate(
        _ operation: BooleanOperation,
        target: EvaluationResult,
        tool: EvaluationResult
    ) throws -> BRepSewingResult {
        let targetBodyID = try #require(target.brep.bodies.keys.first)
        let toolBodyID = try #require(tool.brep.bodies.keys.first)
        let model = try BRepModelCombiner().combined([target.brep, tool.brep])
        let sourceSubshapes = target.subshapes.merging(tool.subshapes) { current, _ in current }
        let pipeline = BooleanPipeline(evaluator: ExactBRepBooleanEvaluator())
        let intersectionGraph = try pipeline.intersectionGraph(
            targetBodyIDs: [targetBodyID],
            toolBodyID: toolBodyID,
            operation: operation,
            model: model,
            tolerance: tolerance
        )
        let uvSplitGraph = try pipeline.uvSplitGraph(
            intersectionGraph: intersectionGraph,
            model: model,
            tolerance: tolerance
        )
        let classificationGraph = try pipeline.classificationGraph(
            uvSplitGraph: uvSplitGraph,
            targetBodyIDs: [targetBodyID],
            toolBodyID: toolBodyID,
            model: model,
            tolerance: tolerance
        )
        let selectionGraph = try pipeline.regionSelectionGraph(
            operation: operation,
            classificationGraph: classificationGraph,
            tolerance: tolerance
        )
        let request = try ExactIntersectionFacePatchMaterializer().materialize(
            operation: operation,
            targetBodyIDs: [targetBodyID],
            toolBodyID: toolBodyID,
            featureID: FeatureID(),
            model: model,
            sourceSubshapes: sourceSubshapes,
            uvSplitGraph: uvSplitGraph,
            regionSelectionGraph: selectionGraph,
            tolerance: tolerance
        )
        return try DefaultBRepSewer().sew(request, tolerance: tolerance)
    }

    private func box(
        origin: Point3D,
        width: Double,
        depth: Double,
        height: Double
    ) throws -> EvaluationResult {
        let featureID = FeatureID()
        let node = FeatureNode(
            id: featureID,
            operation: .primitive(PrimitiveFeature(definition: .box(BoxPrimitive(
                placement: PrimitivePlacement(
                    origin: origin,
                    axis: .unitZ,
                    referenceDirection: .unitX
                ),
                width: .constant(.length(width, unit: .meter)),
                depth: .constant(.length(depth, unit: .meter)),
                height: .constant(.length(height, unit: .meter))
            )))),
            outputs: [FeatureOutput(role: .body)]
        )
        return try PrimitiveFeatureEvaluator().evaluate(
            feature: node,
            context: EvaluationContext(
                parameters: ResolvedParameterTable(values: [:], names: [:]),
                brep: BRepModel(),
                profiles: [:],
                tolerance: tolerance
            )
        )
    }
}
