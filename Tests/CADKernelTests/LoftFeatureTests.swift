import Testing
import CADCore
import CADIR
@testable import CADKernel

@Test(.timeLimit(.minutes(1)))
func loftCreatesClosedRuledSolidBRep() throws {
    let (document, loftID) = ruledRectangleLoftDocument(resultKind: .solid)

    let evaluated = try DocumentEvaluator().evaluate(document)
    let body = try #require(evaluated.brep.bodies.values.first)

    #expect(evaluated.brep.bodies.count == 1)
    #expect(evaluated.brep.shells.count == 1)
    #expect(evaluated.brep.faces.count == 6)
    #expect(evaluated.brep.edges.count == 12)
    #expect(evaluated.brep.vertices.count == 8)
    #expect(body.kind == .solid)
    #expect(evaluated.generatedNames.values.filter(\.isLoftFace).count == 6)
    #expect(evaluated.generatedNames.values.filter(\.isLoftEdge).count == 12)
    #expect(evaluated.generatedNames.values.filter(\.isLoftVertex).count == 8)
    #expect(evaluated.generatedNames[PersistentName(components: [
        .feature(loftID),
        .generated(GeneratedSubshapeRole.body.rawValue),
    ])] != nil)
    try evaluated.brep.validate()
}

@Test(.timeLimit(.minutes(1)))
func loftCreatesOpenRuledSheetBRepWhenResultKindIsSheet() throws {
    let (document, _) = ruledRectangleLoftDocument(resultKind: .sheet)

    let evaluated = try DocumentEvaluator().evaluate(document)
    let body = try #require(evaluated.brep.bodies.values.first)

    #expect(evaluated.brep.bodies.count == 1)
    #expect(evaluated.brep.shells.count == 1)
    #expect(evaluated.brep.faces.count == 4)
    #expect(evaluated.brep.edges.count == 12)
    #expect(evaluated.brep.vertices.count == 8)
    #expect(body.kind == .sheet)
    #expect(evaluated.generatedNames.values.filter(\.isLoftFace).count == 4)
    try evaluated.brep.validate()
}

@Test(.timeLimit(.minutes(1)))
func loftRejectsMismatchedSectionBoundarySamplesBeforeProducingGeometry() throws {
    let document = mismatchedLoftDocument()

    #expect(throws: FeatureEvaluationError.self) {
        _ = try DocumentEvaluator().evaluate(document)
    }
}

@Test(.timeLimit(.minutes(1)))
func loftUsesExplicitSectionStartSampleIndexForGeneratedVertexOrder() throws {
    let (document, loftID) = ruledRectangleLoftDocument(
        resultKind: .solid,
        firstSectionStartSampleIndex: 1
    )

    let evaluated = try DocumentEvaluator().evaluate(document)
    let vertexReference = try #require(evaluated.generatedNames[PersistentName(components: [
        .feature(loftID),
        .generated(GeneratedSubshapeRole.vertex.rawValue),
        .index(0),
    ])])
    guard case .vertex(let vertexID) = vertexReference else {
        Issue.record("Loft generated vertex 0 must resolve to a vertex reference.")
        return
    }
    let vertex = try #require(evaluated.brep.vertices[vertexID])
    let firstProfileID = document.designGraph.order[0]
    let firstProfileNode = try #require(document.designGraph.nodes[firstProfileID])
    guard case .sketch(let sketch) = firstProfileNode.operation else {
        Issue.record("Loft first section must be a sketch profile.")
        return
    }
    let profiles = try SketchProfileExtractor().extractProfiles(
        from: sketch,
        sourceFeatureID: firstProfileID,
        parameters: ResolvedParameterTable()
    )
    let expectedStartPoint = try #require(profiles.first?.vertices[1])

    #expect(vertex.point.isApproximatelyEqual(to: expectedStartPoint, tolerance: 1.0e-12))
}

@Test(.timeLimit(.minutes(1)))
func profileExtractionCanonicalizesLoopStartForLoftSampleIndexes() throws {
    let firstProfiles = try SketchProfileExtractor().extractProfiles(
        from: loftRectangleSketch(width: 4.0, height: 2.0, plane: .xy),
        sourceFeatureID: FeatureID(),
        parameters: ResolvedParameterTable()
    )
    let secondProfiles = try SketchProfileExtractor().extractProfiles(
        from: loftRectangleSketchWithMixedSegmentDirections(width: 4.0, height: 2.0),
        sourceFeatureID: FeatureID(),
        parameters: ResolvedParameterTable()
    )
    let first = try #require(firstProfiles.first)
    let second = try #require(secondProfiles.first)

    #expect(first.vertices.count == second.vertices.count)
    for (left, right) in zip(first.vertices, second.vertices) {
        #expect(left.isApproximatelyEqual(to: right, tolerance: 1.0e-12))
    }
    #expect(first.vertices[0].isApproximatelyEqual(
        to: Point3D(x: -0.002, y: -0.001, z: 0.0),
        tolerance: 1.0e-12
    ))
    #expect(first.vertices[1].isApproximatelyEqual(
        to: Point3D(x: 0.002, y: -0.001, z: 0.0),
        tolerance: 1.0e-12
    ))
}

@Test(.timeLimit(.minutes(1)))
func loftRejectsInvalidExplicitSectionStartSampleIndex() throws {
    let (document, _) = ruledRectangleLoftDocument(
        resultKind: .solid,
        firstSectionStartSampleIndex: 4
    )

    #expect(throws: FeatureEvaluationError.self) {
        _ = try DocumentEvaluator().evaluate(document)
    }
}

private func ruledRectangleLoftDocument(
    resultKind: LoftResultKind,
    firstSectionStartSampleIndex: Int? = nil,
    secondSectionStartSampleIndex: Int? = nil
) -> (CADDocument, FeatureID) {
    let firstProfileID = FeatureID()
    let secondProfileID = FeatureID()
    let loftID = FeatureID()
    let secondPlane = SketchPlane.plane(Plane3D(
        origin: Point3D(x: 0.0, y: 0.0, z: 0.010),
        normal: .unitZ
    ))
    let loft = LoftFeature(
        sections: [
            LoftSectionReference(
                profile: ProfileReference(featureID: firstProfileID),
                startSampleIndex: firstSectionStartSampleIndex
            ),
            LoftSectionReference(
                profile: ProfileReference(featureID: secondProfileID),
                startSampleIndex: secondSectionStartSampleIndex
            ),
        ],
        options: LoftOptions(resultKind: resultKind)
    )
    let document = CADDocument(
        units: .millimeters,
        designGraph: DesignGraph(
            nodes: [
                firstProfileID: FeatureNode(
                    id: firstProfileID,
                    operation: .sketch(loftRectangleSketch(width: 4.0, height: 2.0, plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                secondProfileID: FeatureNode(
                    id: secondProfileID,
                    operation: .sketch(loftRectangleSketch(width: 6.0, height: 3.0, plane: secondPlane)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                loftID: FeatureNode(
                    id: loftID,
                    operation: .loft(loft),
                    inputs: [
                        FeatureInput(featureID: firstProfileID, role: .profile),
                        FeatureInput(featureID: secondProfileID, role: .profile),
                    ],
                    outputs: [FeatureOutput(role: resultKind == .solid ? .body : .sheet)]
                ),
            ],
            order: [firstProfileID, secondProfileID, loftID],
            dependencies: [
                DependencyEdge(source: firstProfileID, target: loftID),
                DependencyEdge(source: secondProfileID, target: loftID),
            ],
            revision: DocumentRevision(3)
        )
    )
    return (document, loftID)
}

private func mismatchedLoftDocument() -> CADDocument {
    let firstProfileID = FeatureID()
    let secondProfileID = FeatureID()
    let loftID = FeatureID()
    let loft = LoftFeature(sections: [
        LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
        LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
    ])
    return CADDocument(
        units: .millimeters,
        designGraph: DesignGraph(
            nodes: [
                firstProfileID: FeatureNode(
                    id: firstProfileID,
                    operation: .sketch(loftRectangleSketch(width: 4.0, height: 2.0, plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                secondProfileID: FeatureNode(
                    id: secondProfileID,
                    operation: .sketch(loftTriangleSketch()),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                loftID: FeatureNode(
                    id: loftID,
                    operation: .loft(loft),
                    inputs: [
                        FeatureInput(featureID: firstProfileID, role: .profile),
                        FeatureInput(featureID: secondProfileID, role: .profile),
                    ],
                    outputs: [FeatureOutput(role: .body)]
                ),
            ],
            order: [firstProfileID, secondProfileID, loftID],
            dependencies: [
                DependencyEdge(source: firstProfileID, target: loftID),
                DependencyEdge(source: secondProfileID, target: loftID),
            ],
            revision: DocumentRevision(3)
        )
    )
}

private func loftRectangleSketch(width: Double, height: Double, plane: SketchPlane) -> Sketch {
    let halfWidth = width * 0.5
    let halfHeight = height * 0.5
    let bottomLeft = loftPoint(x: -halfWidth, y: -halfHeight)
    let bottomRight = loftPoint(x: halfWidth, y: -halfHeight)
    let topRight = loftPoint(x: halfWidth, y: halfHeight)
    let topLeft = loftPoint(x: -halfWidth, y: halfHeight)
    let bottomID = SketchEntityID()
    let rightID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()
    return Sketch(
        plane: plane,
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
        ],
        dimensions: []
    )
}

private func loftRectangleSketchWithMixedSegmentDirections(width: Double, height: Double) -> Sketch {
    let halfWidth = width * 0.5
    let halfHeight = height * 0.5
    let bottomLeft = loftPoint(x: -halfWidth, y: -halfHeight)
    let bottomRight = loftPoint(x: halfWidth, y: -halfHeight)
    let topRight = loftPoint(x: halfWidth, y: halfHeight)
    let topLeft = loftPoint(x: -halfWidth, y: halfHeight)
    return Sketch(
        plane: .xy,
        entities: [
            SketchEntityID(): .line(SketchLine(start: topLeft, end: topRight)),
            SketchEntityID(): .line(SketchLine(start: bottomRight, end: bottomLeft)),
            SketchEntityID(): .line(SketchLine(start: topRight, end: bottomRight)),
            SketchEntityID(): .line(SketchLine(start: bottomLeft, end: topLeft)),
        ],
        constraints: [],
        dimensions: []
    )
}

private func loftTriangleSketch() -> Sketch {
    let first = loftPoint(x: -2.0, y: -1.0)
    let second = loftPoint(x: 2.0, y: -1.0)
    let third = loftPoint(x: 0.0, y: 2.0)
    let firstID = SketchEntityID()
    let secondID = SketchEntityID()
    let thirdID = SketchEntityID()
    return Sketch(
        plane: .plane(Plane3D(origin: Point3D(x: 0.0, y: 0.0, z: 0.010), normal: .unitZ)),
        entities: [
            firstID: .line(SketchLine(start: first, end: second)),
            secondID: .line(SketchLine(start: second, end: third)),
            thirdID: .line(SketchLine(start: third, end: first)),
        ],
        constraints: [
            .coincident(.lineEnd(firstID), .lineStart(secondID)),
            .coincident(.lineEnd(secondID), .lineStart(thirdID)),
            .coincident(.lineEnd(thirdID), .lineStart(firstID)),
        ],
        dimensions: []
    )
}

private func loftPoint(x: Double, y: Double) -> SketchPoint {
    SketchPoint(
        x: .constant(.length(x, unit: .millimeter)),
        y: .constant(.length(y, unit: .millimeter))
    )
}

private extension TopologyReference {
    var isLoftFace: Bool {
        if case .face = self {
            return true
        }
        return false
    }

    var isLoftEdge: Bool {
        if case .edge = self {
            return true
        }
        return false
    }

    var isLoftVertex: Bool {
        if case .vertex = self {
            return true
        }
        return false
    }
}
