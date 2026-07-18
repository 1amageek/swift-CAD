import Synchronization
import Testing
import CADCore
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@available(macOS 15.0, *)
@Test(.timeLimit(.minutes(1)))
func documentEvaluatorBuildsGeneratedGeometryOnce() throws {
    let featureEvaluator = CountingFeatureEvaluator()
    let tessellator = CountingTessellator()
    let evaluator = DocumentEvaluator(
        featureEvaluator: featureEvaluator,
        tessellator: tessellator,
        tolerance: .standard
    )

    let evaluated = try evaluator.evaluate(rectangleExtrudeDocument())

    #expect(evaluated.brep.bodies.count == 1)
    #expect(featureEvaluator.evaluationCount == 1)
    #expect(tessellator.tessellationCount == 1)
}

@Test(.timeLimit(.minutes(1)))
func documentEvaluatorValidatesInjectedFeatureEvaluatorOutput() throws {
    let evaluator = DocumentEvaluator(
        featureEvaluator: InvalidTopologyFeatureEvaluator(),
        tolerance: .standard
    )

    #expect(throws: TopologyError.self) {
        try evaluator.evaluate(rectangleExtrudeDocument())
    }
}

@Test(.timeLimit(.minutes(1)))
func documentEvaluatorRejectsForeignFeatureTopologyOwnership() throws {
    let document = rectangleExtrudeDocument()
    let featureID = try #require(document.designGraph.order.last)
    let evaluator = DocumentEvaluator(
        featureEvaluator: ForeignFeatureOutputEvaluator(),
        tolerance: .standard
    )

    do {
        _ = try evaluator.evaluate(document)
        Issue.record("Foreign feature topology ownership must be rejected.")
    } catch let error as KernelError {
        #expect(error.phase == .topology)
        #expect(error.code == .topologyFailure)
        #expect(error.featureID == featureID)
    }
}

@available(macOS 15.0, *)
private final class CountingFeatureEvaluator: FeatureEvaluating, Sendable {
    private let count = Mutex(0)
    private let base = DefaultFeatureEvaluator()

    var evaluationCount: Int {
        count.withLock { $0 }
    }

    func evaluate(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        count.withLock { $0 += 1 }
        return try base.evaluate(feature: feature, context: context)
    }
}

@available(macOS 15.0, *)
private final class CountingTessellator: Tessellating, Sendable {
    private let count = Mutex(0)
    private let base = MeshTessellator(tolerance: .standard)

    var tessellationCount: Int {
        count.withLock { $0 }
    }

    func tessellate(
        model: BRepModel,
        options: TessellationOptions
    ) throws -> [BodyID: Mesh] {
        count.withLock { $0 += 1 }
        return try base.tessellate(model: model, options: options)
    }
}

private struct InvalidTopologyFeatureEvaluator: FeatureEvaluating {
    private let base = DefaultFeatureEvaluator()

    func evaluate(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        var result = try base.evaluate(feature: feature, context: context)
        guard let vertexID = result.brep.vertices.keys.first else {
            throw FeatureEvaluationError.emptyResult("Expected generated vertices.")
        }
        result.brep.vertices.removeValue(forKey: vertexID)
        return result
    }
}

private struct ForeignFeatureOutputEvaluator: FeatureEvaluating {
    private let base = DefaultFeatureEvaluator()

    func evaluate(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        var result = try base.evaluate(feature: feature, context: context)
        guard let original = result.subshapes.keys.sorted().first,
              let reference = result.subshapes.removeValue(forKey: original),
              let lineage = result.lineage.removeValue(forKey: original) else {
            throw FeatureEvaluationError.emptyResult("Expected generated topology output.")
        }
        let foreign = SubshapeID(
            featureID: FeatureID(),
            role: original.role,
            ordinal: original.ordinal
        )
        result.subshapes[foreign] = reference
        result.lineage[foreign] = TopologyLineage(
            output: foreign,
            parents: lineage.parents,
            relation: lineage.relation
        )
        return result
    }
}

private func rectangleExtrudeDocument() -> CADDocument {
    let sketchID = FeatureID()
    let extrudeID = FeatureID()
    let sketch = FeatureNode(
        id: sketchID,
        operation: .sketch(rectangleSketch()),
        outputs: [FeatureOutput(role: .profile)]
    )
    let extrude = FeatureNode(
        id: extrudeID,
        operation: .extrude(
            ExtrudeFeature(
                profile: ProfileReference(featureID: sketchID),
                distance: .constant(.length(10.0, unit: .millimeter)),
                direction: .normal
            )
        ),
        inputs: [FeatureInput(featureID: sketchID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    return CADDocument(
        units: .millimeters,
        designGraph: DesignGraph(
            nodes: [sketchID: sketch, extrudeID: extrude],
            order: [sketchID, extrudeID],
            dependencies: [DependencyEdge(source: sketchID, target: extrudeID)],
            revision: DocumentRevision(2)
        )
    )
}

private func rectangleSketch() -> Sketch {
    let lowX = CADExpression.constant(.length(-20.0, unit: .millimeter))
    let highX = CADExpression.constant(.length(20.0, unit: .millimeter))
    let lowY = CADExpression.constant(.length(-10.0, unit: .millimeter))
    let highY = CADExpression.constant(.length(10.0, unit: .millimeter))
    let bottomLeft = SketchPoint(x: lowX, y: lowY)
    let bottomRight = SketchPoint(x: highX, y: lowY)
    let topRight = SketchPoint(x: highX, y: highY)
    let topLeft = SketchPoint(x: lowX, y: highY)
    let bottomID = SketchEntityID()
    let rightID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            bottomID: .line(SketchLine(start: bottomLeft, end: bottomRight)),
            rightID: .line(SketchLine(start: bottomRight, end: topRight)),
            topID: .line(SketchLine(start: topRight, end: topLeft)),
            leftID: .line(SketchLine(start: topLeft, end: bottomLeft)),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .lineStart(rightID)),
            .coincident(.lineEnd(rightID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .lineStart(bottomID)),
        ]
    )
}
