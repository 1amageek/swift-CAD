import Testing
import CADCore
import CADIR
@testable import CADKernel

@Suite("Document evaluator incremental execution")
struct DocumentEvaluatorIncrementalTests {
    @Test(.timeLimit(.minutes(1)))
    func revisionOnlyChangeReusesEveryFeatureAndMesh() throws {
        let fixture = makeIndependentExtrusionFixture()
        let evaluator = DocumentEvaluator()
        let initial = try evaluator.evaluate(fixture.document)
        var edited = fixture.document
        edited.designGraph.revision = edited.designGraph.revision.advanced()
        edited.parameters.revision = edited.parameters.revision.advanced()

        let incremental = try evaluator.evaluate(edited, reusing: initial)

        #expect(incremental.evaluationMetrics.totalFeatureCount == 4)
        #expect(incremental.evaluationMetrics.rebuiltFeatureCount == 0)
        #expect(incremental.evaluationMetrics.reusedFeatureCount == 4)
        #expect(incremental.evaluationMetrics.invalidatedFeatureCount == 0)
        #expect(incremental.evaluationMetrics.replayFallbackCount == 0)
        #expect(incremental.evaluationMetrics.tessellatedBodyCount == 0)
        #expect(incremental.evaluationMetrics.reusedMeshCount == 2)
        #expect(incremental.brep == initial.brep)
        #expect(incremental.meshes == initial.meshes)
        try incremental.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func independentParameterChangeRebuildsOnlyItsExtrusionAndBodyMesh() throws {
        let fixture = makeIndependentExtrusionFixture()
        let evaluator = DocumentEvaluator()
        let initial = try evaluator.evaluate(fixture.document)
        let initialFirstBodyID = try bodyID(for: fixture.firstExtrudeFeatureID, in: initial)
        var edited = fixture.document
        var depth = try #require(edited.parameters.parameters[fixture.secondDepthParameterID])
        depth.expression = .constant(.length(18.0, unit: .millimeter))
        edited.parameters.parameters[fixture.secondDepthParameterID] = depth
        edited.parameters.revision = edited.parameters.revision.advanced()

        let incremental = try evaluator.evaluate(edited, reusing: initial)
        let full = try evaluator.evaluate(edited)

        #expect(incremental.evaluationMetrics.totalFeatureCount == 4)
        #expect(incremental.evaluationMetrics.rebuiltFeatureCount == 1)
        #expect(incremental.evaluationMetrics.reusedFeatureCount == 3)
        #expect(incremental.evaluationMetrics.invalidatedFeatureCount == 1)
        #expect(incremental.evaluationMetrics.replayFallbackCount == 0)
        #expect(incremental.evaluationMetrics.tessellatedBodyCount == 1)
        #expect(incremental.evaluationMetrics.reusedMeshCount == 1)
        #expect(try bodyID(for: fixture.firstExtrudeFeatureID, in: incremental) == initialFirstBodyID)
        #expect(meshMultiset(incremental.meshes.values) == meshMultiset(full.meshes.values))
        #expect(incremental.brep.bodies.count == full.brep.bodies.count)
        #expect(Set(incremental.generatedNames.keys) == Set(full.generatedNames.keys))
        try incremental.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchParameterChangeInvalidatesItsDependentExtrusionOnly() throws {
        let fixture = makeIndependentExtrusionFixture()
        let evaluator = DocumentEvaluator()
        let initial = try evaluator.evaluate(fixture.document)
        var edited = fixture.document
        var width = try #require(edited.parameters.parameters[fixture.secondWidthParameterID])
        width.expression = .constant(.length(55.0, unit: .millimeter))
        edited.parameters.parameters[fixture.secondWidthParameterID] = width
        edited.parameters.revision = edited.parameters.revision.advanced()

        let incremental = try evaluator.evaluate(edited, reusing: initial)
        let full = try evaluator.evaluate(edited)

        #expect(incremental.evaluationMetrics.rebuiltFeatureCount == 2)
        #expect(incremental.evaluationMetrics.reusedFeatureCount == 2)
        #expect(incremental.evaluationMetrics.invalidatedFeatureCount == 2)
        #expect(incremental.evaluationMetrics.tessellatedBodyCount == 1)
        #expect(incremental.evaluationMetrics.reusedMeshCount == 1)
        #expect(meshMultiset(incremental.meshes.values) == meshMultiset(full.meshes.values))
        try incremental.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func independentBodiesApplyLinearTopologyMutationsWithoutReadingPriorBodies() throws {
        let evaluator = DocumentEvaluator()
        let single = try evaluator.evaluate(makeLiteralBoxDocument(bodyCount: 1).document)
        let many = try evaluator.evaluate(makeLiteralBoxDocument(bodyCount: 32).document)

        #expect(single.evaluationMetrics.topologyMutationCount > 0)
        #expect(
            many.evaluationMetrics.topologyMutationCount
                == single.evaluationMetrics.topologyMutationCount * 32
        )
        #expect(many.evaluationMetrics.scopedBodyReadCount == 0)
        #expect(many.evaluationMetrics.maximumScopedBodyReadCount == 0)
        #expect(many.brep.bodies.count == 32)
        try many.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func booleanReadsOnlyItsOperandsFromALargerDocument() throws {
        let evaluator = DocumentEvaluator()
        var fixture = try makeLiteralBoxDocument(bodyCount: 8)
        let booleanFeatureID = FeatureID()
        let targetFeatureID = fixture.bodyFeatureIDs[0]
        let toolFeatureID = fixture.bodyFeatureIDs[1]
        try fixture.document.appendFeatures([
            FeatureNode(
                id: booleanFeatureID,
                operation: .boolean(BooleanFeature(
                    targets: [BooleanTargetReference(featureID: targetFeatureID)],
                    tool: BooleanToolReference(featureID: toolFeatureID),
                    operation: .union
                )),
                inputs: [
                    FeatureInput(featureID: targetFeatureID, role: .target),
                    FeatureInput(featureID: toolFeatureID, role: .body),
                ],
                outputs: [FeatureOutput(role: .body)]
            ),
        ])

        let evaluated = try evaluator.evaluate(fixture.document)

        #expect(evaluated.evaluationMetrics.scopedBodyReadCount == 2)
        #expect(evaluated.evaluationMetrics.maximumScopedBodyReadCount == 2)
        #expect(evaluated.brep.bodies.count == 7)
        try evaluated.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func validatedGraphStableReplacementRebuildsOnlyItsBranch() throws {
        let fixture = try makeLiteralBoxDocument(bodyCount: 8)
        let evaluator = DocumentEvaluator()
        let source = try ValidatedCADDocument(fixture.document)
        let initial = try evaluator.evaluate(source)
        let editedFeatureID = fixture.bodyFeatureIDs[4]
        var replacement = try #require(
            source.document.designGraph.nodes[editedFeatureID]
        )
        guard case let .extrude(extrude) = replacement.operation else {
            Issue.record("Expected an extrusion feature.")
            return
        }
        replacement.operation = .extrude(ExtrudeFeature(
            profile: extrude.profile,
            distance: .constant(.length(12.0, unit: .millimeter)),
            direction: extrude.direction,
            operation: extrude.operation
        ))
        let editedSource = try source.replacingGraphStableFeature(replacement)

        let incremental = try evaluator.evaluate(editedSource, reusing: initial)
        let full = try evaluator.evaluate(editedSource)

        #expect(incremental.evaluationMetrics.rebuiltFeatureCount == 1)
        #expect(incremental.evaluationMetrics.reusedFeatureCount == 15)
        #expect(incremental.evaluationMetrics.invalidatedFeatureCount == 1)
        #expect(incremental.evaluationMetrics.tessellatedBodyCount == 1)
        #expect(incremental.evaluationMetrics.reusedMeshCount == 7)
        #expect(meshMultiset(incremental.meshes.values) == meshMultiset(full.meshes.values))
        #expect(
            incremental.incrementalEvaluationState?.graph.documentIdentity
                == editedSource.identity
        )
        try incremental.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func siblingValidatedBranchesNeverShareGraphStableProvenance() throws {
        let fixture = try makeLiteralBoxDocument(bodyCount: 2)
        let evaluator = DocumentEvaluator()
        let source = try ValidatedCADDocument(fixture.document)
        let initial = try evaluator.evaluate(source)
        let editedFeatureID = fixture.bodyFeatureIDs[0]
        let firstBranch = try replacingExtrudeDistance(
            12.0,
            featureID: editedFeatureID,
            in: source
        )
        let secondBranch = try replacingExtrudeDistance(
            14.0,
            featureID: editedFeatureID,
            in: source
        )
        let firstEvaluation = try evaluator.evaluate(firstBranch, reusing: initial)

        let secondEvaluation = try evaluator.evaluate(
            secondBranch,
            reusing: firstEvaluation
        )
        let full = try evaluator.evaluate(secondBranch)

        #expect(
            firstEvaluation.incrementalEvaluationState?.graph.graphStableChanges(
                for: secondBranch
            ) == nil
        )
        #expect(secondEvaluation.evaluationMetrics.rebuiltFeatureCount == 1)
        #expect(meshMultiset(secondEvaluation.meshes.values) == meshMultiset(full.meshes.values))
        try secondEvaluation.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func suppressingOneIndependentBodyRemovesOnlyItsMesh() throws {
        let fixture = try makeLiteralBoxDocument(bodyCount: 2)
        let evaluator = DocumentEvaluator()
        let initial = try evaluator.evaluate(fixture.document)
        var edited = fixture.document
        let suppressedFeatureID = fixture.bodyFeatureIDs[1]
        var suppressedFeature = try #require(
            edited.designGraph.nodes[suppressedFeatureID]
        )
        suppressedFeature.isSuppressed = true
        try edited.replaceFeature(suppressedFeature)

        let incremental = try evaluator.evaluate(edited, reusing: initial)
        let full = try evaluator.evaluate(edited)

        #expect(incremental.meshes == full.meshes)
        #expect(incremental.meshes.count == 1)
        #expect(incremental.evaluationMetrics.tessellatedBodyCount == 0)
        #expect(incremental.evaluationMetrics.reusedMeshCount == 1)
        try incremental.validate()
    }
}

private struct IndependentExtrusionFixture {
    var document: CADDocument
    var firstExtrudeFeatureID: FeatureID
    var secondDepthParameterID: ParameterID
    var secondWidthParameterID: ParameterID
}

private struct LiteralBoxDocumentFixture {
    var document: CADDocument
    var bodyFeatureIDs: [FeatureID]
}

private func makeLiteralBoxDocument(bodyCount: Int) throws -> LiteralBoxDocumentFixture {
    var features: [FeatureNode] = []
    var bodyFeatureIDs: [FeatureID] = []
    features.reserveCapacity(bodyCount * 2)
    bodyFeatureIDs.reserveCapacity(bodyCount)

    for _ in 0..<bodyCount {
        let sketchFeatureID = FeatureID()
        let bodyFeatureID = FeatureID()
        features.append(
            FeatureNode(
                id: sketchFeatureID,
                operation: .sketch(literalRectangleSketch()),
                outputs: [FeatureOutput(role: .profile)]
            )
        )
        features.append(
            FeatureNode(
                id: bodyFeatureID,
                operation: .extrude(ExtrudeFeature(
                    profile: ProfileReference(featureID: sketchFeatureID),
                    distance: .constant(.length(10.0, unit: .millimeter))
                )),
                inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
                outputs: [FeatureOutput(role: .body)]
            )
        )
        bodyFeatureIDs.append(bodyFeatureID)
    }

    var document = CADDocument(units: .millimeters)
    try document.appendFeatures(features)
    return LiteralBoxDocumentFixture(
        document: document,
        bodyFeatureIDs: bodyFeatureIDs
    )
}

private func literalRectangleSketch() -> Sketch {
    let halfWidth = CADExpression.constant(.length(20.0, unit: .millimeter))
    let halfHeight = CADExpression.constant(.length(10.0, unit: .millimeter))
    let negativeHalfWidth = CADExpression.constant(.length(-20.0, unit: .millimeter))
    let negativeHalfHeight = CADExpression.constant(.length(-10.0, unit: .millimeter))
    let bottomLeft = SketchPoint(x: negativeHalfWidth, y: negativeHalfHeight)
    let bottomRight = SketchPoint(x: halfWidth, y: negativeHalfHeight)
    let topRight = SketchPoint(x: halfWidth, y: halfHeight)
    let topLeft = SketchPoint(x: negativeHalfWidth, y: halfHeight)
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

private func makeIndependentExtrusionFixture() -> IndependentExtrusionFixture {
    let firstWidthID = ParameterID()
    let firstHeightID = ParameterID()
    let firstDepthID = ParameterID()
    let secondWidthID = ParameterID()
    let secondHeightID = ParameterID()
    let secondDepthID = ParameterID()
    let parameters = ParameterTable(parameters: [
        firstWidthID: lengthParameter(id: firstWidthID, name: "firstWidth", value: 40.0),
        firstHeightID: lengthParameter(id: firstHeightID, name: "firstHeight", value: 20.0),
        firstDepthID: lengthParameter(id: firstDepthID, name: "firstDepth", value: 10.0),
        secondWidthID: lengthParameter(id: secondWidthID, name: "secondWidth", value: 30.0),
        secondHeightID: lengthParameter(id: secondHeightID, name: "secondHeight", value: 15.0),
        secondDepthID: lengthParameter(id: secondDepthID, name: "secondDepth", value: 6.0),
    ])

    let firstSketchFeatureID = FeatureID()
    let firstExtrudeFeatureID = FeatureID()
    let secondSketchFeatureID = FeatureID()
    let secondExtrudeFeatureID = FeatureID()
    let firstSketchFeature = FeatureNode(
        id: firstSketchFeatureID,
        operation: .sketch(rectangleSketch(widthID: firstWidthID, heightID: firstHeightID)),
        outputs: [FeatureOutput(role: .profile)]
    )
    let firstExtrudeFeature = extrusionFeature(
        id: firstExtrudeFeatureID,
        sketchFeatureID: firstSketchFeatureID,
        depthParameterID: firstDepthID
    )
    let secondSketchFeature = FeatureNode(
        id: secondSketchFeatureID,
        operation: .sketch(rectangleSketch(widthID: secondWidthID, heightID: secondHeightID)),
        outputs: [FeatureOutput(role: .profile)]
    )
    let secondExtrudeFeature = extrusionFeature(
        id: secondExtrudeFeatureID,
        sketchFeatureID: secondSketchFeatureID,
        depthParameterID: secondDepthID
    )
    let graph = DesignGraph(
        nodes: [
            firstSketchFeatureID: firstSketchFeature,
            firstExtrudeFeatureID: firstExtrudeFeature,
            secondSketchFeatureID: secondSketchFeature,
            secondExtrudeFeatureID: secondExtrudeFeature,
        ],
        order: [
            firstSketchFeatureID,
            firstExtrudeFeatureID,
            secondSketchFeatureID,
            secondExtrudeFeatureID,
        ],
        dependencies: [
            DependencyEdge(source: firstSketchFeatureID, target: firstExtrudeFeatureID),
            DependencyEdge(source: secondSketchFeatureID, target: secondExtrudeFeatureID),
        ],
        revision: DocumentRevision(4)
    )
    return IndependentExtrusionFixture(
        document: CADDocument(units: .millimeters, parameters: parameters, designGraph: graph),
        firstExtrudeFeatureID: firstExtrudeFeatureID,
        secondDepthParameterID: secondDepthID,
        secondWidthParameterID: secondWidthID
    )
}

private func lengthParameter(id: ParameterID, name: String, value: Double) -> Parameter {
    Parameter(
        id: id,
        name: name,
        expression: .constant(.length(value, unit: .millimeter)),
        kind: .length
    )
}

private func extrusionFeature(
    id: FeatureID,
    sketchFeatureID: FeatureID,
    depthParameterID: ParameterID
) -> FeatureNode {
    FeatureNode(
        id: id,
        operation: .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: .reference(depthParameterID)
        )),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
}

private func rectangleSketch(widthID: ParameterID, heightID: ParameterID) -> Sketch {
    let two = CADExpression.constant(.scalar(2.0))
    let minusOne = CADExpression.constant(.scalar(-1.0))
    let halfWidth = CADExpression.divide(.reference(widthID), two)
    let halfHeight = CADExpression.divide(.reference(heightID), two)
    let negativeHalfWidth = CADExpression.multiply(minusOne, halfWidth)
    let negativeHalfHeight = CADExpression.multiply(minusOne, halfHeight)
    let bottomLeft = SketchPoint(x: negativeHalfWidth, y: negativeHalfHeight)
    let bottomRight = SketchPoint(x: halfWidth, y: negativeHalfHeight)
    let topRight = SketchPoint(x: halfWidth, y: halfHeight)
    let topLeft = SketchPoint(x: negativeHalfWidth, y: halfHeight)
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

private func bodyID(for featureID: FeatureID, in document: EvaluatedDocument) throws -> BodyID {
    for (name, reference) in document.generatedNames
    where name.components.contains(.feature(featureID)) {
        if case let .body(bodyID) = reference {
            return bodyID
        }
    }
    throw FeatureEvaluationError.missingInput("Feature body was not generated.")
}

private func meshMultiset<Meshes: Sequence>(_ meshes: Meshes) -> [Mesh: Int]
where Meshes.Element == Mesh {
    var result: [Mesh: Int] = [:]
    for mesh in meshes {
        result[mesh, default: 0] += 1
    }
    return result
}

private func replacingExtrudeDistance(
    _ distance: Double,
    featureID: FeatureID,
    in source: ValidatedCADDocument
) throws -> ValidatedCADDocument {
    var replacement = try #require(source.document.designGraph.nodes[featureID])
    guard case let .extrude(extrude) = replacement.operation else {
        throw FeatureEvaluationError.invalidGraph("Expected an extrusion feature.")
    }
    replacement.operation = .extrude(ExtrudeFeature(
        profile: extrude.profile,
        distance: .constant(.length(distance, unit: .millimeter)),
        direction: extrude.direction,
        operation: extrude.operation
    ))
    return try source.replacingGraphStableFeature(replacement)
}
