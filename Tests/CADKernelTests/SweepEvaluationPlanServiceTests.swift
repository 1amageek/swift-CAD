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
    #expect(result.guideStrategyCandidates == [.none])
    #expect(result.resolvedGuideStrategy == nil)
    #expect(result.guideStrategyResolutions == [
        SweepGuideStrategyResolution(
            strategy: .none,
            status: .notRequired,
            message: "Sweep has no guide constraints."
        ),
    ])
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
    #expect(result.guideStrategyCandidates == [.pointSimilarity])
    #expect(result.resolvedGuideStrategy == .pointSimilarity)
    #expect(result.guideStrategyResolutions == [
        SweepGuideStrategyResolution(
            strategy: .pointSimilarity,
            status: .resolved,
            message: "Sweep guide constraints solve as pointSimilarity."
        ),
    ])
    #expect(result.checks.contains { $0.kind == .guideConstraints && $0.status == .passed })
}

@Test(.timeLimit(.minutes(1)))
func sweepEvaluationPlanReportsResolvedRadialRailStrategyBeforeMutation() throws {
    let pathLength = 20.0
    let setup = try makeSweepPlanDocument(
        pathSketch: sweepPlanLinePathSketch(plane: .yz, length: pathLength),
        profileSketch: sweepPlanRadialPointRailProfileSketch(),
        guideSketches: sweepPlanRadialPointRailGuideSketches(pathLength: pathLength)
    )

    let result = try SweepEvaluationPlanService().plan(
        document: setup.document,
        sections: [.profile(ProfileReference(featureID: setup.profileFeatureID))],
        path: SweepPathReference(featureID: setup.pathFeatureID),
        guides: setup.guideFeatureIDs.map { SweepGuideReference(featureID: $0) },
        options: SweepOptions(guideMethod: .point)
    )

    #expect(result.status == .supported)
    #expect(result.sectionState == .guided)
    #expect(result.guideCount == 5)
    #expect(result.guideStrategyCandidates.contains(.pointMeanValueCageRail))
    #expect(result.guideStrategyCandidates.contains(.pointRadialRail))
    #expect(result.resolvedGuideStrategy == .pointRadialRail)
    #expect(result.guideStrategyResolutions.contains {
        $0.strategy == .pointRadialRail && $0.status == .resolved
    })
    #expect(result.guideStrategyResolutions.contains {
        $0.strategy == .pointMeanValueCageRail && $0.status == .candidate
    })
    #expect(result.checks.contains {
        $0.kind == .guideConstraints &&
            $0.status == .passed &&
            $0.message.contains(SweepEvaluationCapabilities.GuideStrategy.pointRadialRail.rawValue)
    })
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
    #expect(result.guideStrategyCandidates == [.pointSimilarity])
    #expect(result.resolvedGuideStrategy == nil)
    #expect(result.guideStrategyResolutions.count == 1)
    #expect(result.guideStrategyResolutions.first?.strategy == .pointSimilarity)
    #expect(result.guideStrategyResolutions.first?.status == .failed)
    #expect(result.guideStrategyResolutions.first?.unsupportedCode == .invalidGuideConstraintSet)
    #expect(result.guideStrategyResolutions.first?.message.contains("initially touch") == true)
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
    profileSketch: Sketch = sweepPlanRectangleSketch(),
    guideSketches: [Sketch] = []
) -> SweepPlanDocumentSetup {
    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let guideFeatureIDs = guideSketches.map { _ in FeatureID() }
    var nodes: [FeatureID: FeatureNode] = [
        profileFeatureID: FeatureNode(
            id: profileFeatureID,
            name: "Plan Profile",
            operation: .sketch(profileSketch),
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

private func sweepPlanLinePathSketch(plane: SketchPlane, length: Double = 20.0) -> Sketch {
    let lineID = SketchEntityID()
    return Sketch(
        plane: plane,
        entities: [
            lineID: .line(SketchLine(
                start: sweepPlanPoint(0.0, 0.0),
                end: sweepPlanPoint(0.0, length)
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

private func sweepPlanRadialPointRailSourcePoints() -> [Point2D] {
    [
        Point2D(x: -20.0, y: -10.0),
        Point2D(x: 22.0, y: -10.0),
        Point2D(x: 6.0, y: 0.0),
        Point2D(x: 22.0, y: 12.0),
        Point2D(x: -18.0, y: 12.0),
    ]
}

private func sweepPlanRadialPointRailTargetPoints() -> [Point2D] {
    [
        Point2D(x: -24.0, y: -8.0),
        Point2D(x: 26.0, y: -12.0),
        Point2D(x: 10.0, y: 2.0),
        Point2D(x: 18.0, y: 16.0),
        Point2D(x: -20.0, y: 14.0),
    ]
}

private func sweepPlanRadialPointRailProfileSketch() -> Sketch {
    let sourcePoints = sweepPlanRadialPointRailSourcePoints()
    let entityIDs = sourcePoints.map { _ in SketchEntityID() }
    var entities: [SketchEntityID: SketchEntity] = [:]
    var constraints: [SketchConstraint] = []
    for index in sourcePoints.indices {
        let nextIndex = (index + 1) % sourcePoints.count
        entities[entityIDs[index]] = .line(SketchLine(
            start: sweepPlanPoint(sourcePoints[index].x, sourcePoints[index].y),
            end: sweepPlanPoint(sourcePoints[nextIndex].x, sourcePoints[nextIndex].y)
        ))
        constraints.append(.coincident(
            .lineEnd(entityIDs[index]),
            .lineStart(entityIDs[nextIndex])
        ))
    }
    return Sketch(
        plane: .xy,
        entities: entities,
        constraints: constraints
    )
}

private func sweepPlanRadialPointRailGuideSketches(pathLength: Double) throws -> [Sketch] {
    let sourcePoints = sweepPlanRadialPointRailSourcePoints()
    let targetPoints = sweepPlanRadialPointRailTargetPoints()
    guard sourcePoints.count == targetPoints.count else {
        throw FeatureEvaluationError.invalidGraph("Radial point rail plan targets must match source points.")
    }
    return try sourcePoints.indices.map { index in
        try sweepPlanLineSketch(
            start: sweepPlanPoint3D(sourcePoints[index], z: 0.0),
            end: sweepPlanPoint3D(targetPoints[index], z: pathLength)
        )
    }
}

private func sweepPlanLineSketch(start: Point3D, end: Point3D) throws -> Sketch {
    let tolerance = ModelingTolerance.standard
    let delta = end - start
    let direction = try delta.normalized(tolerance: tolerance.distance)
    let helper = abs(direction.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
    let normal = try direction.cross(helper).normalized(tolerance: tolerance.distance)
    let basis = try sweepPlanSketchPlaneBasis(for: normal, tolerance: tolerance)
    let localEnd = Point2D(
        x: delta.dot(basis.u),
        y: delta.dot(basis.v)
    )
    let lineID = SketchEntityID()
    return Sketch(
        plane: .plane(Plane3D(origin: start, normal: normal)),
        entities: [
            lineID: .line(SketchLine(
                start: SketchPoint(
                    x: .constant(.length(0.0, unit: .meter)),
                    y: .constant(.length(0.0, unit: .meter))
                ),
                end: SketchPoint(
                    x: .constant(.length(localEnd.x, unit: .meter)),
                    y: .constant(.length(localEnd.y, unit: .meter))
                )
            )),
        ]
    )
}

private func sweepPlanSketchPlaneBasis(
    for planeNormal: Vector3D,
    tolerance: ModelingTolerance
) throws -> (u: Vector3D, v: Vector3D) {
    let normal = try planeNormal.normalized(tolerance: tolerance.distance)
    let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
    let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
    let v = normal.cross(u)
    return (u, v)
}

private func sweepPlanPoint3D(_ point: Point2D, z: Double) -> Point3D {
    Point3D(
        x: point.x * 0.001,
        y: point.y * 0.001,
        z: z * 0.001
    )
}

private func sweepPlanPoint(_ x: Double, _ y: Double) -> SketchPoint {
    SketchPoint(
        x: .constant(.length(x, unit: .millimeter)),
        y: .constant(.length(y, unit: .millimeter))
    )
}
