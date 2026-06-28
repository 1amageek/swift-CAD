import CADCore
import CADIR
import CADKernel
import Testing

@Test(.timeLimit(.minutes(1)))
func sweepEvaluationPlanReportsExactStraightExtrude() throws {
    let setup = makeSweepPlanDocument(pathSketch: sweepPlanLinePathSketch(plane: .yz))

    let result = try SweepEvaluationPlanService().plan(
        document: setup.document,
        sections: [.profile(ProfileReference(featureID: setup.profileFeatureID))],
        path: SweepPathReference(featureID: setup.pathFeatureID)
    )

    #expect(result.status == .supported)
    #expect(result.evaluationKind == .exactStraightExtrude)
    #expect(result.outputTopologyKind == .exactStraightSolid)
    #expect(result.booleanSupportKind == .newBody)
    #expect(result.sectionState == .identity)
    #expect(result.guideStrategies == [.none])
    #expect(result.pathSegmentCount == 1)
    guard case .straight(let profileNormalComponent) = result.pathShape else {
        Issue.record("Expected a straight sweep path.")
        return
    }
    #expect(abs(profileNormalComponent - 1.0) < 1.0e-9)
}

@Test(.timeLimit(.minutes(1)))
func sweepEvaluationPlanReportsProfilePlaneParallelUnsupported() throws {
    let setup = makeSweepPlanDocument(pathSketch: sweepPlanLinePathSketch(plane: .xy))

    let result = try SweepEvaluationPlanService().plan(
        document: setup.document,
        sections: [.profile(ProfileReference(featureID: setup.profileFeatureID))],
        path: SweepPathReference(featureID: setup.pathFeatureID),
        options: SweepOptions(alignment: .parallel)
    )

    #expect(result.status == .unsupported)
    #expect(result.unsupportedCode == .profilePlaneDegenerateParallelAlignment)
    #expect(result.evaluationKind == nil)
    #expect(result.checks.last?.kind == .capabilityDecision)
    #expect(result.checks.last?.status == .unsupported)
    guard case .straight(let profileNormalComponent) = result.pathShape else {
        Issue.record("Expected a straight sweep path.")
        return
    }
    #expect(profileNormalComponent < 1.0e-9)
}

@Test(.timeLimit(.minutes(1)))
func sweepEvaluationPlanReportsGuideStrategyBeforeMutation() throws {
    let setup = makeSweepPlanDocument(
        pathSketch: sweepPlanLinePathSketch(plane: .yz),
        guideSketches: [sweepPlanGuideSketch(offset: 2.0)]
    )
    let guideID = try #require(setup.guideFeatureIDs.first)

    let result = try SweepEvaluationPlanService().plan(
        document: setup.document,
        sections: [.profile(ProfileReference(featureID: setup.profileFeatureID))],
        path: SweepPathReference(featureID: setup.pathFeatureID),
        guides: [SweepGuideReference(featureID: guideID)],
        options: SweepOptions(guideMethod: .point)
    )

    #expect(result.status == .supported)
    #expect(result.sectionState == .guided)
    #expect(result.guideCount == 1)
    #expect(result.guideStrategies == [.pointSimilarity])
    #expect(result.checks.contains { $0.kind == .guideConstraints && $0.status == .passed })
}

@Test(.timeLimit(.minutes(1)))
func sweepEvaluationPlanReportsUnsolvedGuideBeforeMutation() throws {
    let setup = makeSweepPlanDocument(
        pathSketch: sweepPlanLinePathSketch(plane: .yz),
        guideSketches: [sweepPlanGuideSketch(offset: 5.0)]
    )
    let guideID = try #require(setup.guideFeatureIDs.first)

    let result = try SweepEvaluationPlanService().plan(
        document: setup.document,
        sections: [.profile(ProfileReference(featureID: setup.profileFeatureID))],
        path: SweepPathReference(featureID: setup.pathFeatureID),
        guides: [SweepGuideReference(featureID: guideID)],
        options: SweepOptions(guideMethod: .point)
    )

    #expect(result.status == .unsupported)
    #expect(result.unsupportedCode == .invalidGuideConstraintSet)
    #expect(result.checks.last?.kind == .guideConstraints)
    #expect(result.checks.last?.status == .unsupported)
    #expect(result.message.contains("guide constraints do not solve"))
    #expect(result.message.contains("initially touch"))
}

@Test(.timeLimit(.minutes(1)))
func sweepEvaluationPlanReportsRoundMultiCurvePathUnsupported() throws {
    let setup = makeSweepPlanDocument(pathSketch: sweepPlanConnectedTwoLinePathSketch())

    let result = try SweepEvaluationPlanService().plan(
        document: setup.document,
        sections: [.profile(ProfileReference(featureID: setup.profileFeatureID))],
        path: SweepPathReference(featureID: setup.pathFeatureID),
        options: SweepOptions(cornerStyle: .round)
    )

    #expect(result.status == .unsupported)
    #expect(result.unsupportedCode == .roundCornerMultiCurvePath)
    #expect(result.pathSegmentCount == 2)
    #expect(result.checks.last?.kind == .pathChain)
    #expect(result.checks.last?.status == .unsupported)
}

private struct SweepPlanDocumentSetup {
    var document: CADDocument
    var profileFeatureID: FeatureID
    var pathFeatureID: FeatureID
    var guideFeatureIDs: [FeatureID]
}

private func makeSweepPlanDocument(
    pathSketch: Sketch,
    guideSketches: [Sketch] = []
) -> SweepPlanDocumentSetup {
    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let guideFeatureIDs = guideSketches.map { _ in FeatureID() }
    var nodes: [FeatureID: FeatureNode] = [
        profileFeatureID: FeatureNode(
            id: profileFeatureID,
            name: "Plan Profile",
            operation: .sketch(sweepPlanRectangleSketch()),
            outputs: [
                FeatureOutput(role: .profile),
                FeatureOutput(role: .curve),
            ]
        ),
        pathFeatureID: FeatureNode(
            id: pathFeatureID,
            name: "Plan Path",
            operation: .sketch(pathSketch),
            outputs: [FeatureOutput(role: .curve)]
        ),
    ]
    var order = [profileFeatureID, pathFeatureID]
    for (index, guideSketch) in guideSketches.enumerated() {
        let guideID = guideFeatureIDs[index]
        nodes[guideID] = FeatureNode(
            id: guideID,
            name: "Plan Guide \(index)",
            operation: .sketch(guideSketch),
            outputs: [FeatureOutput(role: .curve)]
        )
        order.append(guideID)
    }
    return SweepPlanDocumentSetup(
        document: CADDocument(
            units: .millimeters,
            designGraph: DesignGraph(
                nodes: nodes,
                order: order,
                revision: DocumentRevision(order.count)
            )
        ),
        profileFeatureID: profileFeatureID,
        pathFeatureID: pathFeatureID,
        guideFeatureIDs: guideFeatureIDs
    )
}

private func sweepPlanRectangleSketch() -> Sketch {
    let bottomID = SketchEntityID()
    let rightID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            bottomID: .line(SketchLine(
                start: sweepPlanPoint(0.0, 0.0),
                end: sweepPlanPoint(4.0, 0.0)
            )),
            rightID: .line(SketchLine(
                start: sweepPlanPoint(4.0, 0.0),
                end: sweepPlanPoint(4.0, 2.0)
            )),
            topID: .line(SketchLine(
                start: sweepPlanPoint(4.0, 2.0),
                end: sweepPlanPoint(0.0, 2.0)
            )),
            leftID: .line(SketchLine(
                start: sweepPlanPoint(0.0, 2.0),
                end: sweepPlanPoint(0.0, 0.0)
            )),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .lineStart(rightID)),
            .coincident(.lineEnd(rightID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .lineStart(bottomID)),
        ]
    )
}

private func sweepPlanLinePathSketch(plane: SketchPlane) -> Sketch {
    let lineID = SketchEntityID()
    return Sketch(
        plane: plane,
        entities: [
            lineID: .line(SketchLine(
                start: sweepPlanPoint(0.0, 0.0),
                end: sweepPlanPoint(0.0, 20.0)
            )),
        ]
    )
}

private func sweepPlanConnectedTwoLinePathSketch() -> Sketch {
    let firstID = SketchEntityID()
    let secondID = SketchEntityID()
    return Sketch(
        plane: .yz,
        entities: [
            firstID: .line(SketchLine(
                start: sweepPlanPoint(0.0, 0.0),
                end: sweepPlanPoint(0.0, 10.0)
            )),
            secondID: .line(SketchLine(
                start: sweepPlanPoint(0.0, 10.0),
                end: sweepPlanPoint(5.0, 15.0)
            )),
        ],
        constraints: [
            .coincident(.lineEnd(firstID), .lineStart(secondID)),
        ]
    )
}

private func sweepPlanGuideSketch(offset: Double) -> Sketch {
    let lineID = SketchEntityID()
    return Sketch(
        plane: .yz,
        entities: [
            lineID: .line(SketchLine(
                start: sweepPlanPoint(offset, 0.0),
                end: sweepPlanPoint(offset, 20.0)
            )),
        ]
    )
}

private func sweepPlanPoint(_ x: Double, _ y: Double) -> SketchPoint {
    SketchPoint(
        x: .constant(.length(x, unit: .millimeter)),
        y: .constant(.length(y, unit: .millimeter))
    )
}
