import CADCore
import CADIR
import CADKernel
import Testing

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPlanReportsExactBoxFrameDifference() throws {
    let setup = booleanPlanBoxDocument(
        targetWidth: 40.0,
        targetHeight: 40.0,
        toolWidth: 20.0,
        toolHeight: 20.0
    )

    let result = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false
    )

    #expect(result.status == .supported)
    #expect(result.operation == .difference)
    #expect(result.keepTools == false)
    #expect(result.targetCount == 1)
    #expect(result.targetCellCount == 1)
    #expect(result.toolCellCount == 1)
    #expect(result.resultPrimitiveCount == 1)
    #expect(result.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 10,
        loopCount: 12,
        edgeCount: 24,
        vertexCount: 16
    ))
    #expect(result.operandKind == .axisAlignedBoxSolids)
    #expect(result.outputTopologyKind == .zThroughFrame)
    #expect(result.topologyNameSchemes == [
        .body,
        .frameOuterVertices,
        .frameHoleVertices,
        .frameOuterEdges,
        .frameHoleEdges,
        .frameBridgeEdges,
        .frameCapFaces,
        .frameOuterSideFaces,
        .frameHoleSideFaces,
    ])
    #expect(result.topologySlots.count == 51)
    #expect(result.topologySlots.first == BooleanEvaluationTopologySlot(role: .body))
    #expect(result.topologySlots.contains(BooleanEvaluationTopologySlot(
        role: .vertex,
        subshape: "frame:hole:corner:maxX:maxY:maxZ"
    )))
    #expect(result.topologySlots.contains(BooleanEvaluationTopologySlot(
        role: .edge,
        subshape: "frame:hole:zEdge:x:maxX:y:maxY"
    )))
    #expect(result.topologySlots.contains(BooleanEvaluationTopologySlot(
        role: .sideFace,
        subshape: "frame:holeFace:maxX"
    )))
    #expect(result.unsupportedCode == nil)
    #expect(result.checks.map(\.kind) == [.requestContract, .sourceBodies, .operandTopology, .capabilityDecision])
    #expect(result.checks.allSatisfy { $0.status == .passed })
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPlanTopologySlotsResolveGeneratedFrameNames() throws {
    let setup = booleanPlanBoxDocument(
        targetWidth: 40.0,
        targetHeight: 40.0,
        toolWidth: 20.0,
        toolHeight: 20.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false
    )
    let evaluated = try DocumentEvaluator().evaluate(booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    ))

    #expect(plan.outputTopologyKind == .zThroughFrame)
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPlanTopologySlotsResolveGeneratedCellUnionNames() throws {
    let setup = booleanPlanBoxDocument(
        targetWidth: 40.0,
        targetHeight: 40.0,
        toolWidth: 30.0,
        toolHeight: 30.0,
        toolCenterX: 10.0,
        toolCenterY: 10.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false
    )
    let evaluated = try DocumentEvaluator().evaluate(booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    ))

    #expect(plan.outputTopologyKind == .orthogonalCellUnion)
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPlanReportsUnsupportedCurvedOperandBeforeMutation() throws {
    let setup = booleanPlanCylinderToolDocument()

    let result = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: true
    )

    #expect(result.status == .unsupported)
    #expect(result.operation == .union)
    #expect(result.keepTools == true)
    #expect(result.operandKind == nil)
    #expect(result.outputTopologyKind == nil)
    #expect(result.resultTopologyCounts == nil)
    #expect(result.topologyNameSchemes.isEmpty)
    #expect(result.topologySlots.isEmpty)
    #expect(result.unsupportedCode == .unsupportedOperandTopology)
    #expect(result.message.contains("Boolean cannot evaluate before mutation"))
    #expect(result.checks.map(\.kind) == [.requestContract, .sourceBodies, .operandTopology])
    #expect(result.checks.last?.kind == .operandTopology)
    #expect(result.checks.last?.status == .unsupported)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPlanReportsSeparatedBRepUnionBeforeMutation() throws {
    let setup = booleanPlanCylinderToolDocument(toolCenterX: 50.0)

    let result = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: false
    )

    #expect(result.status == .supported)
    #expect(result.operation == .union)
    #expect(result.targetCount == 1)
    #expect(result.targetCellCount == 1)
    #expect(result.toolCellCount == 1)
    #expect(result.resultPrimitiveCount == 2)
    #expect(result.operandKind == .separatedSolidBodies)
    #expect(result.outputTopologyKind == .disjointSolidUnion)
    #expect(result.topologyNameSchemes == [.body, .copiedSourceTopology])
    #expect(result.resultTopologyCounts?.bodyCount == 1)
    #expect(result.resultTopologyCounts?.shellCount == 2)
    #expect((result.resultTopologyCounts?.faceCount ?? 0) > 6)
    #expect(result.topologySlots.contains(BooleanEvaluationTopologySlot(
        role: .sideFace,
        subshape: "copy:target:0:face:0"
    )))
    #expect(result.topologySlots.contains(BooleanEvaluationTopologySlot(
        role: .sideFace,
        subshape: "copy:tool:face:0"
    )))
    #expect(result.topologySlots.contains(BooleanEvaluationTopologySlot(
        role: .edge,
        subshape: "copy:tool:edge:0"
    )))
    #expect(result.unsupportedCode == nil)
    #expect(result.checks.map(\.kind) == [.requestContract, .sourceBodies, .operandTopology, .capabilityDecision])
    #expect(result.checks.allSatisfy { $0.status == .passed })
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationEvaluatesSeparatedBRepUnionWithStableCopiedTopologyNames() throws {
    let setup = booleanPlanCylinderToolDocument(toolCenterX: 50.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: false
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .union,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator().evaluate(document)

    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep.bodies.count == 1)
    #expect(evaluated.brep.shells.count == 2)
    #expect(evaluated.generatedNames.keys.contains {
        $0.components.contains(.feature(setup.targetFeatureID))
    } == false)
    #expect(evaluated.generatedNames.keys.contains {
        $0.components.contains(.feature(setup.toolFeatureID))
    } == false)
    guard case .body? = evaluated.generatedNames[PersistentName(components: [
        .feature(booleanID),
        .generated(GeneratedSubshapeRole.body.rawValue),
    ])] else {
        Issue.record("Separated B-rep union must publish a generated result body name.")
        return
    }
    #expect(evaluated.generatedNames.keys.contains(PersistentName(components: [
        .feature(booleanID),
        .generated(GeneratedSubshapeRole.sideFace.rawValue),
        .subshape("copy:target:0:face:0"),
    ])))
    #expect(evaluated.generatedNames.keys.contains(PersistentName(components: [
        .feature(booleanID),
        .generated(GeneratedSubshapeRole.sideFace.rawValue),
        .subshape("copy:tool:face:0"),
    ])))
    #expect(evaluated.generatedNames.keys.contains(PersistentName(components: [
        .feature(booleanID),
        .generated(GeneratedSubshapeRole.edge.rawValue),
        .subshape("copy:tool:edge:0"),
    ])))
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPlanReportsMultiTargetSeparatedBRepUnionBeforeMutation() throws {
    let setup = booleanPlanMultiTargetCylinderToolDocument()

    let result = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: setup.targetFeatureIDs.map(BooleanTargetReference.init(featureID:)),
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: true
    )

    #expect(result.status == .supported)
    #expect(result.operation == .union)
    #expect(result.keepTools)
    #expect(result.targetCount == 2)
    #expect(result.targetCellCount == 2)
    #expect(result.toolCellCount == 1)
    #expect(result.resultPrimitiveCount == 3)
    #expect(result.operandKind == .separatedSolidBodies)
    #expect(result.outputTopologyKind == .disjointSolidUnion)
    #expect(result.topologyNameSchemes == [.body, .copiedSourceTopology])
    #expect(result.resultTopologyCounts?.bodyCount == 1)
    #expect(result.resultTopologyCounts?.shellCount == 3)
    #expect(result.topologySlots.contains(BooleanEvaluationTopologySlot(
        role: .sideFace,
        subshape: "copy:target:1:face:0"
    )))
    #expect(result.topologySlots.contains(BooleanEvaluationTopologySlot(
        role: .edge,
        subshape: "copy:tool:edge:0"
    )))
    #expect(result.unsupportedCode == nil)
    #expect(result.checks.map(\.kind) == [.requestContract, .sourceBodies, .operandTopology, .capabilityDecision])
    #expect(result.checks.allSatisfy { $0.status == .passed })
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationEvaluatesMultiTargetSeparatedBRepUnionKeepToolsWithStableCopiedTopologyNames() throws {
    let setup = booleanPlanMultiTargetCylinderToolDocument()
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: setup.targetFeatureIDs.map(BooleanTargetReference.init(featureID:)),
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: true
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .union,
        keepTools: true
    )

    let evaluated = try DocumentEvaluator().evaluate(document)

    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep.bodies.count == 4)
    #expect(evaluated.brep.shells.count == 6)
    for targetFeatureID in setup.targetFeatureIDs {
        #expect(evaluated.generatedNames.keys.contains(PersistentName(components: [
            .feature(targetFeatureID),
            .generated(GeneratedSubshapeRole.body.rawValue),
        ])))
    }
    #expect(evaluated.generatedNames.keys.contains(PersistentName(components: [
        .feature(booleanID),
        .subshape("tool"),
        .feature(setup.toolFeatureID),
        .generated(GeneratedSubshapeRole.body.rawValue),
    ])))
    #expect(evaluated.generatedNames.keys.contains(PersistentName(components: [
        .feature(booleanID),
        .generated(GeneratedSubshapeRole.sideFace.rawValue),
        .subshape("copy:target:1:face:0"),
    ])))
    #expect(evaluated.generatedNames.keys.contains(PersistentName(components: [
        .feature(booleanID),
        .generated(GeneratedSubshapeRole.edge.rawValue),
        .subshape("copy:tool:edge:0"),
    ])))
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPlanReportsInvalidRequestAtRequestContractGate() throws {
    let setup = booleanPlanBoxDocument(
        targetWidth: 40.0,
        targetHeight: 40.0,
        toolWidth: 20.0,
        toolHeight: 20.0
    )

    let result = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [
            BooleanTargetReference(featureID: setup.targetFeatureID),
            BooleanTargetReference(featureID: setup.targetFeatureID),
        ],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false
    )

    #expect(result.status == .unsupported)
    #expect(result.unsupportedCode == .invalidRequest)
    #expect(result.checks == [
        BooleanEvaluationPreflightCheck(
            kind: .requestContract,
            status: .unsupported,
            message: result.message
        ),
    ])
    #expect(result.message.contains("Boolean target references must be unique"))
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPlanReportsMissingBodyAtSourceBodyGate() throws {
    let setup = booleanPlanBoxDocument(
        targetWidth: 40.0,
        targetHeight: 40.0,
        toolWidth: 20.0,
        toolHeight: 20.0
    )

    let result = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: FeatureID())],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false
    )

    #expect(result.status == .unsupported)
    #expect(result.unsupportedCode == .missingBody)
    #expect(result.checks.map(\.kind) == [.requestContract, .sourceBodies])
    #expect(result.checks.first?.status == .passed)
    #expect(result.checks.last?.status == .unsupported)
    #expect(result.message.contains("Boolean body reference could not be resolved"))
}

private struct BooleanPlanDocumentSetup {
    var document: CADDocument
    var targetFeatureID: FeatureID
    var toolFeatureID: FeatureID
}

private struct BooleanMultiTargetPlanDocumentSetup {
    var document: CADDocument
    var targetFeatureIDs: [FeatureID]
    var toolFeatureID: FeatureID
}

private func booleanPlanBoxDocument(
    targetWidth: Double,
    targetHeight: Double,
    toolWidth: Double,
    toolHeight: Double,
    toolCenterX: Double = 0.0,
    toolCenterY: Double = 0.0,
    depth: Double = 10.0,
    unit: LengthUnit = .millimeter
) -> BooleanPlanDocumentSetup {
    let targetProfileID = FeatureID()
    let targetID = FeatureID()
    let toolProfileID = FeatureID()
    let toolID = FeatureID()
    let targetProfile = booleanPlanProfileFeature(
        id: targetProfileID,
        sketch: booleanPlanRectangleSketch(
            width: targetWidth,
            height: targetHeight,
            centerX: 0.0,
            centerY: 0.0,
            unit: unit
        )
    )
    let target = booleanPlanExtrudeFeature(
        id: targetID,
        profileID: targetProfileID,
        depth: depth,
        unit: unit
    )
    let toolProfile = booleanPlanProfileFeature(
        id: toolProfileID,
        sketch: booleanPlanRectangleSketch(
            width: toolWidth,
            height: toolHeight,
            centerX: toolCenterX,
            centerY: toolCenterY,
            unit: unit
        )
    )
    let tool = booleanPlanExtrudeFeature(
        id: toolID,
        profileID: toolProfileID,
        depth: depth,
        unit: unit
    )
    let document = booleanPlanDocument(
        nodes: [
            targetProfileID: targetProfile,
            targetID: target,
            toolProfileID: toolProfile,
            toolID: tool,
        ],
        order: [targetProfileID, targetID, toolProfileID, toolID],
        dependencies: [
            DependencyEdge(source: targetProfileID, target: targetID),
            DependencyEdge(source: toolProfileID, target: toolID),
        ]
    )
    return BooleanPlanDocumentSetup(document: document, targetFeatureID: targetID, toolFeatureID: toolID)
}

private func booleanPlanMultiTargetCylinderToolDocument(
    depth: Double = 10.0,
    unit: LengthUnit = .millimeter
) -> BooleanMultiTargetPlanDocumentSetup {
    let firstProfileID = FeatureID()
    let firstTargetID = FeatureID()
    let secondProfileID = FeatureID()
    let secondTargetID = FeatureID()
    let toolProfileID = FeatureID()
    let toolID = FeatureID()
    let firstProfile = booleanPlanProfileFeature(
        id: firstProfileID,
        sketch: booleanPlanRectangleSketch(
            width: 16.0,
            height: 16.0,
            centerX: -50.0,
            centerY: 0.0,
            unit: unit
        )
    )
    let firstTarget = booleanPlanExtrudeFeature(
        id: firstTargetID,
        profileID: firstProfileID,
        depth: depth,
        unit: unit
    )
    let secondProfile = booleanPlanProfileFeature(
        id: secondProfileID,
        sketch: booleanPlanRectangleSketch(
            width: 16.0,
            height: 16.0,
            centerX: 0.0,
            centerY: 0.0,
            unit: unit
        )
    )
    let secondTarget = booleanPlanExtrudeFeature(
        id: secondTargetID,
        profileID: secondProfileID,
        depth: depth,
        unit: unit
    )
    let toolProfile = booleanPlanProfileFeature(
        id: toolProfileID,
        sketch: booleanPlanCircleSketch(
            radius: 6.0,
            centerX: 50.0,
            centerY: 0.0,
            unit: unit
        )
    )
    let tool = booleanPlanExtrudeFeature(
        id: toolID,
        profileID: toolProfileID,
        depth: depth,
        unit: unit
    )
    let document = booleanPlanDocument(
        nodes: [
            firstProfileID: firstProfile,
            firstTargetID: firstTarget,
            secondProfileID: secondProfile,
            secondTargetID: secondTarget,
            toolProfileID: toolProfile,
            toolID: tool,
        ],
        order: [
            firstProfileID,
            firstTargetID,
            secondProfileID,
            secondTargetID,
            toolProfileID,
            toolID,
        ],
        dependencies: [
            DependencyEdge(source: firstProfileID, target: firstTargetID),
            DependencyEdge(source: secondProfileID, target: secondTargetID),
            DependencyEdge(source: toolProfileID, target: toolID),
        ]
    )
    return BooleanMultiTargetPlanDocumentSetup(
        document: document,
        targetFeatureIDs: [firstTargetID, secondTargetID],
        toolFeatureID: toolID
    )
}

private func booleanPlanCylinderToolDocument(
    toolCenterX: Double = 0.0,
    toolCenterY: Double = 0.0,
    depth: Double = 10.0,
    unit: LengthUnit = .millimeter
) -> BooleanPlanDocumentSetup {
    let targetProfileID = FeatureID()
    let targetID = FeatureID()
    let toolProfileID = FeatureID()
    let toolID = FeatureID()
    let targetProfile = booleanPlanProfileFeature(
        id: targetProfileID,
        sketch: booleanPlanRectangleSketch(
            width: 24.0,
            height: 24.0,
            centerX: 0.0,
            centerY: 0.0,
            unit: unit
        )
    )
    let target = booleanPlanExtrudeFeature(
        id: targetID,
        profileID: targetProfileID,
        depth: depth,
        unit: unit
    )
    let toolProfile = booleanPlanProfileFeature(
        id: toolProfileID,
        sketch: booleanPlanCircleSketch(
            radius: 6.0,
            centerX: toolCenterX,
            centerY: toolCenterY,
            unit: unit
        )
    )
    let tool = booleanPlanExtrudeFeature(
        id: toolID,
        profileID: toolProfileID,
        depth: depth,
        unit: unit
    )
    let document = booleanPlanDocument(
        nodes: [
            targetProfileID: targetProfile,
            targetID: target,
            toolProfileID: toolProfile,
            toolID: tool,
        ],
        order: [targetProfileID, targetID, toolProfileID, toolID],
        dependencies: [
            DependencyEdge(source: targetProfileID, target: targetID),
            DependencyEdge(source: toolProfileID, target: toolID),
        ]
    )
    return BooleanPlanDocumentSetup(document: document, targetFeatureID: targetID, toolFeatureID: toolID)
}

private func booleanPlanDocument(
    nodes: [FeatureID: FeatureNode],
    order: [FeatureID],
    dependencies: [DependencyEdge]
) -> CADDocument {
    CADDocument(
        units: .millimeters,
        designGraph: DesignGraph(
            nodes: nodes,
            order: order,
            dependencies: dependencies,
            revision: DocumentRevision(1)
        )
    )
}

private func booleanPlanDocument(
    setup: BooleanPlanDocumentSetup,
    booleanID: FeatureID,
    operation: BooleanOperation,
    keepTools: Bool
) -> CADDocument {
    booleanPlanDocument(
        document: setup.document,
        booleanID: booleanID,
        targets: [setup.targetFeatureID],
        tool: setup.toolFeatureID,
        operation: operation,
        keepTools: keepTools
    )
}

private func booleanPlanDocument(
    setup: BooleanMultiTargetPlanDocumentSetup,
    booleanID: FeatureID,
    operation: BooleanOperation,
    keepTools: Bool
) -> CADDocument {
    booleanPlanDocument(
        document: setup.document,
        booleanID: booleanID,
        targets: setup.targetFeatureIDs,
        tool: setup.toolFeatureID,
        operation: operation,
        keepTools: keepTools
    )
}

private func booleanPlanDocument(
    document: CADDocument,
    booleanID: FeatureID,
    targets: [FeatureID],
    tool: FeatureID,
    operation: BooleanOperation,
    keepTools: Bool
) -> CADDocument {
    var document = document
    document.designGraph.nodes[booleanID] = FeatureNode(
        id: booleanID,
        operation: .boolean(BooleanFeature(
            targets: targets.map(BooleanTargetReference.init(featureID:)),
            tool: BooleanToolReference(featureID: tool),
            operation: operation,
            keepTools: keepTools
        )),
        inputs: targets.map { FeatureInput(featureID: $0, role: .target) }
            + [FeatureInput(featureID: tool, role: .body)],
        outputs: [FeatureOutput(role: .body)]
    )
    document.designGraph.order.append(booleanID)
    document.designGraph.dependencies.append(contentsOf: targets.map {
        DependencyEdge(source: $0, target: booleanID)
    })
    document.designGraph.dependencies.append(DependencyEdge(source: tool, target: booleanID))
    return document
}

private func expectPlannedTopologyNames(
    _ plan: BooleanEvaluationPlanResult,
    for featureID: FeatureID,
    in evaluated: EvaluatedDocument
) {
    let plannedNames = plan.topologyPersistentNames(featureID: featureID)
    #expect(Set(plannedNames).count == plannedNames.count)
    for name in plannedNames {
        #expect(evaluated.generatedNames[name] != nil)
    }
}

private func booleanPlanProfileFeature(id: FeatureID, sketch: Sketch) -> FeatureNode {
    FeatureNode(
        id: id,
        operation: .sketch(sketch),
        outputs: [FeatureOutput(role: .profile)]
    )
}

private func booleanPlanExtrudeFeature(
    id: FeatureID,
    profileID: FeatureID,
    depth: Double,
    unit: LengthUnit
) -> FeatureNode {
    FeatureNode(
        id: id,
        operation: .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: profileID),
            distance: .constant(.length(depth, unit: unit))
        )),
        inputs: [FeatureInput(featureID: profileID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
}

private func booleanPlanRectangleSketch(
    width: Double,
    height: Double,
    centerX: Double,
    centerY: Double,
    unit: LengthUnit
) -> Sketch {
    let halfWidth = width / 2.0
    let halfHeight = height / 2.0
    let bottomLeft = booleanPlanPoint(centerX - halfWidth, centerY - halfHeight, unit: unit)
    let bottomRight = booleanPlanPoint(centerX + halfWidth, centerY - halfHeight, unit: unit)
    let topRight = booleanPlanPoint(centerX + halfWidth, centerY + halfHeight, unit: unit)
    let topLeft = booleanPlanPoint(centerX - halfWidth, centerY + halfHeight, unit: unit)
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

private func booleanPlanCircleSketch(
    radius: Double,
    centerX: Double = 0.0,
    centerY: Double = 0.0,
    unit: LengthUnit
) -> Sketch {
    Sketch(
        plane: .xy,
        entities: [
            SketchEntityID(): .circle(SketchCircle(
                center: booleanPlanPoint(centerX, centerY, unit: unit),
                radius: .constant(.length(radius, unit: unit))
            )),
        ]
    )
}

private func booleanPlanPoint(_ x: Double, _ y: Double, unit: LengthUnit) -> SketchPoint {
    SketchPoint(
        x: .constant(.length(x, unit: unit)),
        y: .constant(.length(y, unit: unit))
    )
}
