import Testing
import CADCore
import CADIR
@testable import CADKernel

@Test(.timeLimit(.minutes(1)))
func loftCreatesClosedRuledSolidBRep() throws {
    let (document, loftID) = ruledRectangleLoftDocument(resultKind: .solid)

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let body = try #require(evaluated.brep.bodies.values.first)

    #expect(evaluated.brep.bodies.count == 1)
    #expect(evaluated.brep.shells.count == 1)
    #expect(evaluated.brep.faces.count == 6)
    #expect(evaluated.brep.edges.count == 12)
    #expect(evaluated.brep.vertices.count == 8)
    #expect(body.kind == .solid)
    #expect(evaluated.subshapes.entries.values.filter(\.isLoftFace).count == 6)
    #expect(evaluated.subshapes.entries.values.filter(\.isLoftEdge).count == 12)
    #expect(evaluated.subshapes.entries.values.filter(\.isLoftVertex).count == 8)
    #expect(evaluated.subshapes[SubshapeID(
        featureID: loftID,
        role: GeneratedSubshapeRole.body.rawValue,
        ordinal: 0
    )] != nil)
    try evaluated.brep.validate(level: .exact, tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftCreatesOpenRuledSheetBRepWhenResultKindIsSheet() throws {
    let (document, _) = ruledRectangleLoftDocument(resultKind: .sheet)

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let body = try #require(evaluated.brep.bodies.values.first)

    #expect(evaluated.brep.bodies.count == 1)
    #expect(evaluated.brep.shells.count == 1)
    #expect(evaluated.brep.faces.count == 4)
    #expect(evaluated.brep.edges.count == 12)
    #expect(evaluated.brep.vertices.count == 8)
    #expect(body.kind == .sheet)
    #expect(evaluated.subshapes.entries.values.filter(\.isLoftFace).count == 4)
    #expect(evaluated.brep.geometry.surfaces.values.filter(\.isBSplineSurface).count == 4)
    try evaluated.brep.validate(tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftCreatesClosedSectionLoopSheetBRep() throws {
    let (document, loftID) = closedSectionLoopLoftDocument()

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let body = try #require(evaluated.brep.bodies.values.first)

    #expect(evaluated.brep.bodies.count == 1)
    #expect(evaluated.brep.shells.count == 1)
    #expect(evaluated.brep.faces.count == 12)
    #expect(evaluated.brep.edges.count == 24)
    #expect(evaluated.brep.vertices.count == 12)
    #expect(body.kind == .sheet)
    #expect(evaluated.subshapes.entries.values.filter(\.isLoftFace).count == 12)
    #expect(evaluated.subshapes.entries.values.filter(\.isLoftEdge).count == 24)
    #expect(evaluated.subshapes.entries.values.filter(\.isLoftVertex).count == 12)
    #expect(evaluated.subshapes[SubshapeID(
        featureID: loftID,
        role: GeneratedSubshapeRole.body.rawValue,
        ordinal: 0
    )] != nil)
    try evaluated.brep.validate(tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftCreatesRuledBSplineSideFacesForNonPlanarSections() throws {
    let (document, _) = nonPlanarSectionLoftDocument()

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let body = try #require(evaluated.brep.bodies.values.first)
    let sideSurfaces = evaluated.brep.geometry.surfaces.values.compactMap(\.bSplineSurface)
    let capSurfaceCount = evaluated.brep.geometry.surfaces.values.filter(\.isPlaneSurface).count

    #expect(body.kind == .solid)
    #expect(evaluated.meshes.count == 1)
    #expect(evaluated.brep.faces.count == 6)
    #expect(sideSurfaces.count == 4)
    #expect(capSurfaceCount == 2)
    for surface in sideSurfaces {
        #expect(surface.uDegree == 1)
        #expect(surface.vDegree == 1)
        #expect(surface.uControlPointCount == 2)
        #expect(surface.vControlPointCount == 2)
    }
    try evaluated.brep.validate(tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftPreservesExactCircularSectionsInRuledSolid() throws {
    let document = ruledCircleLoftDocument()

    let evaluated = try DocumentEvaluator(
        tolerance: .standard,
        artifactPolicy: .deferred
    ).evaluate(document)
    _ = try MeshTessellator(tolerance: .standard).tessellate(model: evaluated.brep)
    let body = try #require(evaluated.brep.bodies.values.first)
    let curves = evaluated.brep.geometry.curves.values.compactMap(\.bSplineCurve)
    let circularBoundaries = curves.filter { $0.degree == 2 && $0.isRational }
    let connectors = curves.filter { $0.degree == 1 }
    let sideSurfaces = evaluated.brep.geometry.surfaces.values.compactMap(\.bSplineSurface)

    #expect(body.kind == .solid)
    #expect(evaluated.brep.faces.count == 6)
    #expect(evaluated.brep.edges.count == 12)
    #expect(evaluated.brep.vertices.count == 8)
    #expect(curves.count == 12)
    #expect(circularBoundaries.count == 8)
    #expect(connectors.count == 4)
    #expect(sideSurfaces.count == 4)
    for surface in sideSurfaces {
        #expect(surface.uDegree == 2)
        #expect(surface.vDegree == 1)
        #expect(surface.isRational)
    }
    #expect(evaluated.brep.loops.values.allSatisfy { loop in
        loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
    })
    try evaluated.brep.validate(level: .exact, tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftPreservesRectangularHoleAsOneWatertightSolid() throws {
    let (document, _) = rectangularHoleLoftDocument(resultKind: .solid)

    let evaluated = try DocumentEvaluator(
        tolerance: .standard,
        artifactPolicy: .deferred
    ).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)
    let body = try #require(evaluated.brep.bodies[bodyID])

    #expect(body.kind == .solid)
    #expect(evaluated.brep.bodies.count == 1)
    #expect(evaluated.brep.shells.count == 1)
    #expect(evaluated.brep.faces.count == 10)
    #expect(evaluated.brep.edges.count == 24)
    #expect(evaluated.brep.vertices.count == 16)
    #expect(evaluated.brep.loops.values.filter { $0.role == .inner }.count == 2)
    let expectedVolume = (0.040 * 0.040 - 0.020 * 0.020) * 0.010
    let actualVolume = try evaluated.brep.volume(tolerance: .standard)
    #expect(
        abs(actualVolume - expectedVolume) <= 1.0e-12,
        "Expected hollow Loft volume \(expectedVolume), got \(actualVolume)."
    )

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
    #expect(try classifier.classify(
        Point3D(x: 0.015, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    try evaluated.brep.validate(level: .exact, tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftPreservesCircularHoleAsExactRationalBoundary() throws {
    let document = circularHoleLoftDocument()

    let evaluated = try DocumentEvaluator(
        tolerance: .standard,
        artifactPolicy: .deferred
    ).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)
    let rationalBoundaryCurves = evaluated.brep.geometry.curves.values
        .compactMap(\.bSplineCurve)
        .filter { $0.degree == 2 && $0.isRational }
    let rationalSideSurfaces = evaluated.brep.geometry.surfaces.values
        .compactMap(\.bSplineSurface)
        .filter(\.isRational)

    #expect(evaluated.brep.faces.count == 10)
    #expect(evaluated.brep.edges.count == 24)
    #expect(evaluated.brep.vertices.count == 16)
    #expect(rationalBoundaryCurves.count == 8)
    #expect(rationalSideSurfaces.count == 4)
    let expectedVolume = (0.040 * 0.040 - Double.pi * 0.010 * 0.010) * 0.010
    let actualVolume = try evaluated.brep.volume(tolerance: .standard)
    #expect(
        abs(actualVolume - expectedVolume) <= 1.0e-12,
        "Expected circular-hole Loft volume \(expectedVolume), got \(actualVolume)."
    )

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
    #expect(try classifier.classify(
        Point3D(x: 0.015, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    try evaluated.brep.validate(level: .exact, tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftHoleAwareSheetKeepsEachBoundaryAsAnOpenShell() throws {
    let (document, _) = rectangularHoleLoftDocument(resultKind: .sheet)

    let evaluated = try DocumentEvaluator(
        tolerance: .standard,
        artifactPolicy: .deferred
    ).evaluate(document)
    let body = try #require(evaluated.brep.bodies.values.first)

    #expect(body.kind == .sheet)
    #expect(evaluated.brep.bodies.count == 1)
    #expect(evaluated.brep.shells.count == 2)
    #expect(evaluated.brep.faces.count == 8)
    #expect(evaluated.brep.edges.count == 24)
    #expect(evaluated.brep.vertices.count == 16)
    #expect(evaluated.brep.geometry.surfaces.values.filter(\.isBSplineSurface).count == 8)
    try evaluated.brep.validate(level: .exact, tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftSmoothSurfaceModePreservesHoleWallsAndVolume() throws {
    let (document, _) = rectangularHoleLoftDocument(
        resultKind: .solid,
        surfaceMode: .smooth
    )

    let evaluated = try DocumentEvaluator(
        tolerance: .standard,
        artifactPolicy: .deferred
    ).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)
    let sideSurfaces = evaluated.brep.geometry.surfaces.values
        .compactMap(\.bSplineSurface)

    #expect(sideSurfaces.count == 8)
    #expect(sideSurfaces.allSatisfy { surface in
        surface.vDegree == 3 && surface.vControlPointCount == 4
    })
    let expectedVolume = (0.040 * 0.040 - 0.020 * 0.020) * 0.010
    let actualVolume = try evaluated.brep.volume(tolerance: .standard)
    #expect(
        abs(actualVolume - expectedVolume) <= 1.0e-12,
        "Expected smooth hollow Loft volume \(expectedVolume), got \(actualVolume)."
    )
    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
    try evaluated.brep.validate(level: .exact, tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftGuideCanConstrainAnInteriorHoleBoundary() throws {
    let (document, _) = rectangularHoleLoftDocument(
        resultKind: .solid,
        guidesInnerBoundary: true
    )

    let evaluated = try DocumentEvaluator(
        tolerance: .standard,
        artifactPolicy: .deferred
    ).evaluate(document)

    #expect(evaluated.brep.bodies.count == 1)
    #expect(evaluated.brep.shells.count == 1)
    #expect(evaluated.brep.faces.count == 11)
    #expect(evaluated.brep.edges.count == 27)
    #expect(evaluated.brep.vertices.count == 18)
    #expect(evaluated.brep.vertices.values.contains { vertex in
        vertex.point.isApproximatelyEqual(
            to: Point3D(x: 0.010, y: 0.0, z: 0.0),
            tolerance: 1.0e-12
        )
    })
    #expect(evaluated.brep.vertices.values.contains { vertex in
        vertex.point.isApproximatelyEqual(
            to: Point3D(x: 0.010, y: 0.0, z: 0.010),
            tolerance: 1.0e-12
        )
    })
    try evaluated.brep.validate(level: .exact, tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftSmoothSurfaceModeCreatesCubicSideFacesAndConnectorEdges() throws {
    let (document, _) = smoothThreeSectionLoftDocument()

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let body = try #require(evaluated.brep.bodies.values.first)
    let sideSurfaces = evaluated.brep.geometry.surfaces.values.compactMap(\.bSplineSurface)
    let connectorCurves = evaluated.brep.geometry.curves.values.compactMap(\.bSplineCurve)

    #expect(body.kind == .solid)
    #expect(sideSurfaces.count == 8)
    #expect(connectorCurves.count == 8)
    for surface in sideSurfaces {
        #expect(surface.uDegree == 1)
        #expect(surface.vDegree == 3)
        #expect(surface.uControlPointCount == 2)
        #expect(surface.vControlPointCount == 4)
    }
    for curve in connectorCurves {
        #expect(curve.degree == 3)
        #expect(curve.controlPointCount == 4)
    }
    try evaluated.brep.validate(tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftSmoothSurfaceModeCreatesCubicClosedSectionLoopSheet() throws {
    let (document, _) = closedSectionLoopLoftDocument(
        resultKind: .sheet,
        surfaceMode: .smooth
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let body = try #require(evaluated.brep.bodies.values.first)
    let sideSurfaces = evaluated.brep.geometry.surfaces.values.compactMap(\.bSplineSurface)
    let connectorCurves = evaluated.brep.geometry.curves.values.compactMap(\.bSplineCurve)

    #expect(body.kind == .sheet)
    #expect(sideSurfaces.count == 12)
    #expect(connectorCurves.count == 12)
    for surface in sideSurfaces {
        #expect(surface.uDegree == 1)
        #expect(surface.vDegree == 3)
        #expect(surface.uControlPointCount == 2)
        #expect(surface.vControlPointCount == 4)
    }
    for curve in connectorCurves {
        #expect(curve.degree == 3)
        #expect(curve.controlPointCount == 4)
    }
    try evaluated.brep.validate(tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftSmoothTangentScaleControlsCubicConnectorHandles() throws {
    let (defaultDocument, defaultLoftID) = smoothThreeSectionLoftDocument()
    let (scaledDocument, scaledLoftID) = smoothThreeSectionLoftDocument(smoothTangentScale: 0.25)

    let defaultCurve = try firstSmoothConnectorCurve(
        in: try DocumentEvaluator(tolerance: .standard).evaluate(defaultDocument),
        loftID: defaultLoftID
    )
    let scaledCurve = try firstSmoothConnectorCurve(
        in: try DocumentEvaluator(tolerance: .standard).evaluate(scaledDocument),
        loftID: scaledLoftID
    )

    #expect(defaultCurve.controlPointCount == 4)
    #expect(scaledCurve.controlPointCount == 4)
    #expect(defaultCurve.controlPoints[0].isApproximatelyEqual(to: scaledCurve.controlPoints[0], tolerance: 1.0e-12))
    #expect(defaultCurve.controlPoints[3].isApproximatelyEqual(to: scaledCurve.controlPoints[3], tolerance: 1.0e-12))

    let defaultStartHandleLength = (defaultCurve.controlPoints[1] - defaultCurve.controlPoints[0]).length
    let scaledStartHandleLength = (scaledCurve.controlPoints[1] - scaledCurve.controlPoints[0]).length
    let defaultEndHandleLength = (defaultCurve.controlPoints[2] - defaultCurve.controlPoints[3]).length
    let scaledEndHandleLength = (scaledCurve.controlPoints[2] - scaledCurve.controlPoints[3]).length

    #expect(defaultStartHandleLength > 0.0)
    #expect(defaultEndHandleLength > 0.0)
    #expect(abs(scaledStartHandleLength - defaultStartHandleLength * 0.25) <= 1.0e-12)
    #expect(abs(scaledEndHandleLength - defaultEndHandleLength * 0.25) <= 1.0e-12)
    try defaultDocument.validate(tolerance: .standard)
    try scaledDocument.validate(tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftSectionSmoothTangentScaleOverridesGlobalScale() throws {
    let (defaultDocument, defaultLoftID) = smoothThreeSectionLoftDocument()
    let (sectionScaledDocument, sectionScaledLoftID) = smoothThreeSectionLoftDocument(
        sectionSmoothTangentScales: [0.25, nil, nil]
    )

    let defaultCurve = try firstSmoothConnectorCurve(
        in: try DocumentEvaluator(tolerance: .standard).evaluate(defaultDocument),
        loftID: defaultLoftID
    )
    let sectionScaledCurve = try firstSmoothConnectorCurve(
        in: try DocumentEvaluator(tolerance: .standard).evaluate(sectionScaledDocument),
        loftID: sectionScaledLoftID
    )

    let defaultStartHandleLength = (defaultCurve.controlPoints[1] - defaultCurve.controlPoints[0]).length
    let sectionScaledStartHandleLength =
        (sectionScaledCurve.controlPoints[1] - sectionScaledCurve.controlPoints[0]).length
    let defaultEndHandleLength = (defaultCurve.controlPoints[2] - defaultCurve.controlPoints[3]).length
    let sectionScaledEndHandleLength =
        (sectionScaledCurve.controlPoints[2] - sectionScaledCurve.controlPoints[3]).length

    #expect(defaultStartHandleLength > 0.0)
    #expect(defaultEndHandleLength > 0.0)
    #expect(abs(sectionScaledStartHandleLength - defaultStartHandleLength * 0.25) <= 1.0e-12)
    #expect(abs(sectionScaledEndHandleLength - defaultEndHandleLength) <= 1.0e-12)
    try sectionScaledDocument.validate(tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftSectionZeroSmoothTangentModeClampsConnectorHandle() throws {
    let (defaultDocument, defaultLoftID) = smoothThreeSectionLoftDocument()
    let (zeroModeDocument, zeroModeLoftID) = smoothThreeSectionLoftDocument(
        sectionSmoothTangentModes: [.zero, .automatic, .automatic]
    )

    let defaultCurve = try firstSmoothConnectorCurve(
        in: try DocumentEvaluator(tolerance: .standard).evaluate(defaultDocument),
        loftID: defaultLoftID
    )
    let zeroModeCurve = try firstSmoothConnectorCurve(
        in: try DocumentEvaluator(tolerance: .standard).evaluate(zeroModeDocument),
        loftID: zeroModeLoftID
    )

    let defaultStartHandleLength = (defaultCurve.controlPoints[1] - defaultCurve.controlPoints[0]).length
    let zeroStartHandleLength = (zeroModeCurve.controlPoints[1] - zeroModeCurve.controlPoints[0]).length
    let defaultEndHandleLength = (defaultCurve.controlPoints[2] - defaultCurve.controlPoints[3]).length
    let zeroEndHandleLength = (zeroModeCurve.controlPoints[2] - zeroModeCurve.controlPoints[3]).length

    #expect(defaultStartHandleLength > 0.0)
    #expect(abs(zeroStartHandleLength) <= 1.0e-12)
    #expect(abs(zeroEndHandleLength - defaultEndHandleLength) <= 1.0e-12)
    try zeroModeDocument.validate(tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftRejectsInvalidSmoothTangentScale() throws {
    let (document, _) = smoothThreeSectionLoftDocument(smoothTangentScale: 0.0)

    #expect(throws: FeatureEvaluationError.self) {
        _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    }
}

@Test(.timeLimit(.minutes(1)))
func loftRejectsInvalidSectionSmoothTangentScale() throws {
    let (document, _) = smoothThreeSectionLoftDocument(
        sectionSmoothTangentScales: [0.0, nil, nil]
    )

    #expect(throws: FeatureEvaluationError.self) {
        _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    }
}

@Test(.timeLimit(.minutes(1)))
func loftResamplesMismatchedSectionBoundarySamplesBeforeProducingGeometry() throws {
    let document = mismatchedLoftDocument()

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let body = try #require(evaluated.brep.bodies.values.first)
    let sideSurfaces = evaluated.brep.geometry.surfaces.values.compactMap(\.bSplineSurface)
    let capSurfaceCount = evaluated.brep.geometry.surfaces.values.filter(\.isPlaneSurface).count

    #expect(body.kind == .solid)
    #expect(evaluated.brep.faces.count == 6)
    #expect(evaluated.brep.edges.count == 12)
    #expect(evaluated.brep.vertices.count == 8)
    #expect(sideSurfaces.count == 4)
    #expect(capSurfaceCount == 2)
    try evaluated.brep.validate(tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftRejectsClosedSectionLoopForSolidOutput() throws {
    let (document, _) = closedSectionLoopLoftDocument(resultKind: .solid)

    #expect(throws: FeatureEvaluationError.self) {
        _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    }
}

@Test(.timeLimit(.minutes(1)))
func loftRejectsClosedSectionLoopWithTwoSections() throws {
    let (document, _) = ruledRectangleLoftDocument(
        resultKind: .sheet,
        closesSectionLoop: true
    )

    #expect(throws: FeatureEvaluationError.self) {
        _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    }
}

@Test(.timeLimit(.minutes(1)))
func loftUsesExplicitSectionStartSampleIndexForGeneratedVertexOrder() throws {
    let (document, loftID) = ruledRectangleLoftDocument(
        resultKind: .solid,
        firstSectionStartSampleIndex: 1
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let vertexReference = try #require(evaluated.subshapes[SubshapeID(
        featureID: loftID,
        role: GeneratedSubshapeRole.vertex.rawValue,
        ordinal: 0
    )])
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
    let profiles = try SketchProfileExtractor(tolerance: .standard).extractProfiles(
        from: sketch,
        sourceFeatureID: firstProfileID,
        parameters: ResolvedParameterTable()
    )
    let expectedStartPoint = try #require(profiles.first?.vertices[1])

    #expect(vertex.point.isApproximatelyEqual(to: expectedStartPoint, tolerance: 1.0e-12))
}

@Test(.timeLimit(.minutes(1)))
func loftGuideEndpointSetsSectionSeamForGeneratedVertexOrder() throws {
    let (document, loftID) = guidedRectangleLoftDocument()

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let vertexReference = try #require(evaluated.subshapes[SubshapeID(
        featureID: loftID,
        role: GeneratedSubshapeRole.vertex.rawValue,
        ordinal: 0
    )])
    guard case .vertex(let vertexID) = vertexReference else {
        Issue.record("Loft generated vertex 0 must resolve to a vertex reference.")
        return
    }
    let vertex = try #require(evaluated.brep.vertices[vertexID])

    #expect(vertex.point.isApproximatelyEqual(
        to: Point3D(x: 0.002, y: -0.001, z: 0.0),
        tolerance: 1.0e-12
    ))
}

@Test(.timeLimit(.minutes(1)))
func loftGuideContactInsideExactBoundarySegmentCreatesPartitionVertex() throws {
    let (document, loftID) = guidedRectangleLoftDocument(
        guideSketch: loftVerticalGuideSketch(
            x: 0.0,
            y: -1.0,
            zStart: 0.0,
            zEnd: 10.0
        )
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let firstVertexReference = try #require(evaluated.subshapes[SubshapeID(
        featureID: loftID,
        role: GeneratedSubshapeRole.vertex.rawValue,
        ordinal: 0
    )])
    guard case let .vertex(firstVertexID) = firstVertexReference else {
        Issue.record("Loft generated vertex 0 must resolve to a vertex reference.")
        return
    }
    let firstVertex = try #require(evaluated.brep.vertices[firstVertexID])

    #expect(firstVertex.point.isApproximatelyEqual(
        to: Point3D(x: 0.0, y: -0.001, z: 0.0),
        tolerance: 1.0e-12
    ))
    #expect(evaluated.brep.vertices.count == 10)
    #expect(evaluated.brep.edges.count == 15)
    #expect(evaluated.brep.faces.count == 7)
    try evaluated.brep.validate(level: .exact, tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftGuideResolvesExactInteriorContactOnEveryIntermediateSection() throws {
    let planes: [SketchPlane] = [
        .xy,
        .plane(Plane3D(
            origin: Point3D(x: 0.0, y: 0.0, z: 0.005),
            normal: .unitZ
        )),
        .plane(Plane3D(
            origin: Point3D(x: 0.0, y: 0.0, z: 0.010),
            normal: .unitZ
        )),
    ]
    let (document, _) = multiSectionGuidedRectangleLoftDocument(
        guideSketches: [loftVerticalGuideSketch(
            x: 0.0,
            y: -1.0,
            zStart: 0.0,
            zEnd: 10.0
        )],
        profilePlanes: planes
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

    #expect(evaluated.brep.vertices.count == 15)
    #expect(evaluated.brep.edges.count == 25)
    #expect(evaluated.brep.faces.count == 12)
    #expect(evaluated.brep.vertices.values.contains { vertex in
        vertex.point.isApproximatelyEqual(
            to: Point3D(x: 0.0, y: -0.001, z: 0.005),
            tolerance: 1.0e-12
        )
    })
    try evaluated.brep.validate(level: .exact, tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftMultipleInteriorGuideContactsShareExactSectionIndexes() throws {
    let (document, _) = guidedRectangleLoftDocument(guideSketches: [
        loftVerticalGuideSketch(x: 0.0, y: -1.0, zStart: 0.0, zEnd: 10.0),
        loftVerticalGuideSketch(x: 0.0, y: 1.0, zStart: 0.0, zEnd: 10.0),
    ])

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

    #expect(evaluated.brep.vertices.count == 12)
    #expect(evaluated.brep.edges.count == 18)
    #expect(evaluated.brep.faces.count == 8)
    let points = evaluated.brep.vertices.values.map(\.point)
    for expected in [
        Point3D(x: 0.0, y: -0.001, z: 0.0),
        Point3D(x: 0.0, y: 0.001, z: 0.0),
        Point3D(x: 0.0, y: -0.001, z: 0.010),
        Point3D(x: 0.0, y: 0.001, z: 0.010),
    ] {
        #expect(points.contains { point in
            point.isApproximatelyEqual(to: expected, tolerance: 1.0e-12)
        })
    }
    try evaluated.brep.validate(level: .exact, tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftCurvedGuideCreatesRailFollowingIntermediateRings() throws {
    let (document, loftID) = guidedRectangleLoftDocument(
        guideSketch: loftCurvedGuideSketch(x: 2.0, y: -1.0, zStart: 0.0, zEnd: 10.0)
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let body = try #require(evaluated.brep.bodies.values.first)
    let rail = try loftConnectorCurve(
        ordinal: 8,
        loftID: loftID,
        in: evaluated
    )
    let railMiddle = try rail.point(at: 0.5, tolerance: .standard)

    #expect(body.kind == .solid)
    #expect(evaluated.brep.vertices.count == 8)
    #expect(evaluated.brep.faces.count == 6)
    #expect(rail.degree == 3)
    #expect(railMiddle.x > 0.0025)
    #expect(abs(railMiddle.y + 0.001) <= 1.0e-12)
    #expect(railMiddle.z > 0.0 && railMiddle.z < 0.010)
    #expect(evaluated.brep.loops.values.allSatisfy { loop in
        loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
    })
    try evaluated.brep.validate(level: .exact, tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftMultipleCurvedGuidesCreateDistinctRailConstrainedVertices() throws {
    let (document, loftID) = guidedRectangleLoftDocument(guideSketches: [
        loftCurvedGuideSketch(x: 2.0, y: -1.0, zStart: 0.0, zEnd: 10.0, localXOffset: -0.003),
        loftCurvedGuideSketch(x: -2.0, y: 1.0, zStart: 0.0, zEnd: 10.0, localXOffset: 0.003),
    ])

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let body = try #require(evaluated.brep.bodies.values.first)
    let nonlinearRails = try (8..<12).compactMap { ordinal -> BSplineCurve3D? in
        let curve = try loftConnectorCurve(
            ordinal: ordinal,
            loftID: loftID,
            in: evaluated
        )
        return curve.degree > 1 ? curve : nil
    }
    let railMiddlePoints = try nonlinearRails.map {
        try $0.point(at: 0.5, tolerance: .standard)
    }

    #expect(body.kind == .solid)
    #expect(evaluated.brep.vertices.count == 8)
    #expect(evaluated.brep.faces.count == 6)
    #expect(nonlinearRails.count == 2)
    #expect(railMiddlePoints.contains { $0.x > 0.0025 && abs($0.y + 0.001) <= 1.0e-12 })
    #expect(railMiddlePoints.contains { $0.x < -0.0025 && abs($0.y - 0.001) <= 1.0e-12 })
    try evaluated.brep.validate(level: .exact, tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftRejectsMultipleGuidesSharingBoundarySamples() throws {
    let (document, _) = guidedRectangleLoftDocument(guideSketches: [
        loftCurvedGuideSketch(x: 2.0, y: -1.0, zStart: 0.0, zEnd: 10.0, localXOffset: -0.003),
        loftCurvedGuideSketch(x: 2.0, y: -1.0, zStart: 0.0, zEnd: 10.0, localXOffset: -0.0015),
    ])

    #expect(throws: FeatureEvaluationError.self) {
        _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    }
}

@Test(.timeLimit(.minutes(1)))
func loftCurvedGuideAddsRailRingsBetweenMultipleProfileSections() throws {
    let (document, loftID) = multiSectionGuidedRectangleLoftDocument(guideSketches: [
        loftCurvedGuideSketch(x: 2.0, y: -1.0, zStart: 0.0, zEnd: 10.0),
    ])

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let body = try #require(evaluated.brep.bodies.values.first)
    let lowerRail = try loftConnectorCurve(ordinal: 12, loftID: loftID, in: evaluated)
    let upperRail = try loftConnectorCurve(ordinal: 16, loftID: loftID, in: evaluated)
    let lowerEnd = try lowerRail.point(at: 1.0, tolerance: .standard)
    let upperStart = try upperRail.point(at: 0.0, tolerance: .standard)

    #expect(body.kind == .solid)
    #expect(evaluated.brep.vertices.count == 12)
    #expect(evaluated.brep.faces.count == 10)
    #expect(lowerRail.degree == 3)
    #expect(upperRail.degree == 3)
    #expect(lowerEnd.isApproximatelyEqual(to: upperStart, tolerance: 1.0e-12))
    #expect(lowerEnd.isApproximatelyEqual(
        to: Point3D(x: 0.00425, y: -0.001, z: 0.005),
        tolerance: 1.0e-12
    ))
    try evaluated.brep.validate(level: .exact, tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func profileExtractionCanonicalizesLoopStartForLoftSampleIndexes() throws {
    let firstProfiles = try SketchProfileExtractor(tolerance: .standard).extractProfiles(
        from: loftRectangleSketch(width: 4.0, height: 2.0, plane: .xy),
        sourceFeatureID: FeatureID(),
        parameters: ResolvedParameterTable()
    )
    let secondProfiles = try SketchProfileExtractor(tolerance: .standard).extractProfiles(
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
        _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    }
}

@Test(.timeLimit(.minutes(1)))
func loftSectionResamplingPreservesDrawnCornersAcrossMismatchedCounts() throws {
    let document = rectangleToOctagonLoftDocument()
    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

    #expect(evaluated.brep.vertices.count == 16)
    let points = evaluated.brep.vertices.values.map(\.point)
    // All four drawn rectangle corners must appear exactly in the matched
    // ring; uniform perimeter-fraction sampling of the 4 x 2 rectangle at 8
    // samples lands 0.5 mm away from two of them.
    let corners = [
        Point3D(x: -0.002, y: -0.001, z: 0.0),
        Point3D(x: 0.002, y: -0.001, z: 0.0),
        Point3D(x: 0.002, y: 0.001, z: 0.0),
        Point3D(x: -0.002, y: 0.001, z: 0.0),
    ]
    for corner in corners {
        #expect(points.contains { $0.isApproximatelyEqual(to: corner, tolerance: 1.0e-9) })
    }
    try evaluated.brep.validate(tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func downwardConcaveSectionPrismLoftMeshIsOutwardOriented() throws {
    let (document, _) = downwardConcaveSectionPrismLoftDocument()

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let mesh = try #require(evaluated.meshes.values.first)

    // The loft advances from z = +10 mm down to the .xy plane, against the
    // sections' counterclockwise winding normal (+Z). The SIGNED divergence
    // volume is the regression: an inside-out shell still matches on
    // abs(volume) but integrates negative. 775 mm^2 section, 10 mm height.
    let expected = 775.0e-6 * 0.010
    let signedVolume = loftSignedMeshVolume(mesh)
    #expect(signedVolume > 0.0)
    #expect(abs(signedVolume - expected) <= 1.0e-9)
    try evaluated.brep.validate(tolerance: .standard)
}

@Test(.timeLimit(.minutes(1)))
func loftRejectsMixedDirectionSolidSectionStack() throws {
    // Rectangle sections at z = 0, z = +10, z = +5: the second connection
    // advances against the first, which one shell orientation cannot express.
    let (document, _) = mixedDirectionThreeSectionLoftDocument()

    do {
        _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        Issue.record("Mixed-direction loft must be rejected.")
    } catch let error as KernelError {
        #expect(error.code == .nonManifoldResult)
    }
}

@Test(.timeLimit(.minutes(1)))
func concaveSectionPrismLoftMeshVolumeMatchesSectionAreaTimesHeight() throws {
    let (document, _) = concaveSectionPrismLoftDocument()

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let mesh = try #require(evaluated.meshes.values.first)

    // The cap plane normal must follow the loop winding (Newell), not the sign
    // of the first fan corner, or a concave section flips one cap and corrupts
    // the divergence volume. 40x20 rectangle minus the 10x5 notch triangle
    // = 775 mm^2, prism height 10 mm.
    let expected = 775.0e-6 * 0.010
    #expect(abs(abs(loftSignedMeshVolume(mesh)) - expected) <= 1.0e-9)
    try evaluated.brep.validate(tolerance: .standard)
}

private func loftSignedMeshVolume(_ mesh: Mesh) -> Double {
    guard let origin = mesh.positions.first else {
        return 0.0
    }
    var signedVolume = 0.0
    var index = 0
    while index + 2 < mesh.indices.count {
        let first = mesh.positions[Int(mesh.indices[index])] - origin
        let second = mesh.positions[Int(mesh.indices[index + 1])] - origin
        let third = mesh.positions[Int(mesh.indices[index + 2])] - origin
        signedVolume += first.dot(second.cross(third)) / 6.0
        index += 3
    }
    return signedVolume
}

private func rectangleToOctagonLoftDocument() -> (CADDocument) {
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
                    operation: .sketch(loftOctagonSketch()),
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

/// Convex cut-corner octagon on a plane parallel to .xy at z = 10 mm.
private func loftOctagonSketch() -> Sketch {
    let corners = [
        loftPoint(x: 2.0, y: 1.0), loftPoint(x: 1.0, y: 2.0),
        loftPoint(x: -1.0, y: 2.0), loftPoint(x: -2.0, y: 1.0),
        loftPoint(x: -2.0, y: -1.0), loftPoint(x: -1.0, y: -2.0),
        loftPoint(x: 1.0, y: -2.0), loftPoint(x: 2.0, y: -1.0),
    ]
    let ids = (0..<8).map { _ in SketchEntityID() }
    var entities: [SketchEntityID: SketchEntity] = [:]
    var constraints: [SketchConstraint] = []
    for index in 0..<8 {
        entities[ids[index]] = .line(SketchLine(
            start: corners[index],
            end: corners[(index + 1) % 8]
        ))
        constraints.append(.coincident(.lineEnd(ids[index]), .lineStart(ids[(index + 1) % 8])))
    }
    return Sketch(
        plane: .plane(Plane3D(origin: Point3D(x: 0.0, y: 0.0, z: 0.010), normal: .unitZ)),
        entities: entities,
        constraints: constraints,
        dimensions: []
    )
}

private func downwardConcaveSectionPrismLoftDocument() -> (CADDocument, FeatureID) {
    let firstProfileID = FeatureID()
    let secondProfileID = FeatureID()
    let loftID = FeatureID()
    let firstPlane = SketchPlane.plane(Plane3D(
        origin: Point3D(x: 0.0, y: 0.0, z: 0.010),
        normal: .unitZ
    ))
    let loft = LoftFeature(
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
        ],
        options: LoftOptions(resultKind: .solid)
    )
    let document = CADDocument(
        units: .millimeters,
        designGraph: DesignGraph(
            nodes: [
                firstProfileID: FeatureNode(
                    id: firstProfileID,
                    operation: .sketch(concaveNotchSketch(plane: firstPlane)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                secondProfileID: FeatureNode(
                    id: secondProfileID,
                    operation: .sketch(concaveNotchSketch(plane: .xy)),
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
    return (document, loftID)
}

private func mixedDirectionThreeSectionLoftDocument() -> (CADDocument, FeatureID) {
    let firstProfileID = FeatureID()
    let secondProfileID = FeatureID()
    let thirdProfileID = FeatureID()
    let loftID = FeatureID()
    let loft = LoftFeature(
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: thirdProfileID)),
        ],
        options: LoftOptions(resultKind: .solid)
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
                    operation: .sketch(loftRectangleSketch(
                        width: 5.0,
                        height: 2.5,
                        plane: loftTranslatedPlane(x: 0.0, z: 10.0)
                    )),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                thirdProfileID: FeatureNode(
                    id: thirdProfileID,
                    operation: .sketch(loftRectangleSketch(
                        width: 4.0,
                        height: 2.0,
                        plane: loftTranslatedPlane(x: 0.0, z: 5.0)
                    )),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                loftID: FeatureNode(
                    id: loftID,
                    operation: .loft(loft),
                    inputs: [
                        FeatureInput(featureID: firstProfileID, role: .profile),
                        FeatureInput(featureID: secondProfileID, role: .profile),
                        FeatureInput(featureID: thirdProfileID, role: .profile),
                    ],
                    outputs: [FeatureOutput(role: .body)]
                ),
            ],
            order: [firstProfileID, secondProfileID, thirdProfileID, loftID],
            dependencies: [
                DependencyEdge(source: firstProfileID, target: loftID),
                DependencyEdge(source: secondProfileID, target: loftID),
                DependencyEdge(source: thirdProfileID, target: loftID),
            ],
            revision: DocumentRevision(4)
        )
    )
    return (document, loftID)
}

private func concaveSectionPrismLoftDocument() -> (CADDocument, FeatureID) {
    let firstProfileID = FeatureID()
    let secondProfileID = FeatureID()
    let loftID = FeatureID()
    let secondPlane = SketchPlane.plane(Plane3D(
        origin: Point3D(x: 0.0, y: 0.0, z: 0.010),
        normal: .unitZ
    ))
    let loft = LoftFeature(
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
        ],
        options: LoftOptions(resultKind: .solid)
    )
    let document = CADDocument(
        units: .millimeters,
        designGraph: DesignGraph(
            nodes: [
                firstProfileID: FeatureNode(
                    id: firstProfileID,
                    operation: .sketch(concaveNotchSketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                secondProfileID: FeatureNode(
                    id: secondProfileID,
                    operation: .sketch(concaveNotchSketch(plane: secondPlane)),
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
    return (document, loftID)
}

private func concaveNotchSketch(plane: SketchPlane) -> Sketch {
    func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: .millimeter)),
            y: .constant(.length(y, unit: .millimeter))
        )
    }
    func line(_ start: SketchPoint, _ end: SketchPoint) -> SketchEntity {
        .line(SketchLine(start: start, end: end))
    }
    // 40 x 20 mm rectangle whose top edge carries a triangular notch dipping to
    // (20, 15): a concave outline whose first fan corners can face either way.
    return Sketch(
        plane: plane,
        entities: [
            SketchEntityID(): line(point(0.0, 0.0), point(40.0, 0.0)),
            SketchEntityID(): line(point(40.0, 0.0), point(40.0, 20.0)),
            SketchEntityID(): line(point(40.0, 20.0), point(25.0, 20.0)),
            SketchEntityID(): line(point(25.0, 20.0), point(20.0, 15.0)),
            SketchEntityID(): line(point(20.0, 15.0), point(15.0, 20.0)),
            SketchEntityID(): line(point(15.0, 20.0), point(0.0, 20.0)),
            SketchEntityID(): line(point(0.0, 20.0), point(0.0, 0.0)),
        ]
    )
}

private func rectangularHoleLoftDocument(
    resultKind: LoftResultKind,
    guidesInnerBoundary: Bool = false,
    surfaceMode: LoftSurfaceMode = .ruled
) -> (CADDocument, FeatureID) {
    let firstProfileID = FeatureID()
    let secondProfileID = FeatureID()
    let guideID = guidesInnerBoundary ? FeatureID() : nil
    let loftID = FeatureID()
    let secondPlane = SketchPlane.plane(Plane3D(
        origin: Point3D(x: 0.0, y: 0.0, z: 0.010),
        normal: .unitZ
    ))
    let loft = LoftFeature(
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
        ],
        guides: guideID.map { [LoftGuideReference(featureID: $0)] } ?? [],
        options: LoftOptions(resultKind: resultKind, surfaceMode: surfaceMode)
    )
    var nodes: [FeatureID: FeatureNode] = [
        firstProfileID: FeatureNode(
            id: firstProfileID,
            operation: .sketch(loftRectangularHoleSketch(plane: .xy)),
            outputs: [FeatureOutput(role: .profile)]
        ),
        secondProfileID: FeatureNode(
            id: secondProfileID,
            operation: .sketch(loftRectangularHoleSketch(plane: secondPlane)),
            outputs: [FeatureOutput(role: .profile)]
        ),
    ]
    if let guideID {
        nodes[guideID] = FeatureNode(
            id: guideID,
            operation: .sketch(loftVerticalGuideSketch(
                x: 10.0,
                y: 0.0,
                zStart: 0.0,
                zEnd: 10.0
            )),
            outputs: [FeatureOutput(role: .curve)]
        )
    }
    nodes[loftID] = FeatureNode(
        id: loftID,
        operation: .loft(loft),
        inputs: [
            FeatureInput(featureID: firstProfileID, role: .profile),
            FeatureInput(featureID: secondProfileID, role: .profile),
        ] + (guideID.map { [FeatureInput(featureID: $0, role: .guide)] } ?? []),
        outputs: [FeatureOutput(role: resultKind == .solid ? .body : .sheet)]
    )
    let orderedGuideIDs = guideID.map { [$0] } ?? []
    return (
        CADDocument(
            units: .millimeters,
            designGraph: DesignGraph(
                nodes: nodes,
                order: [firstProfileID, secondProfileID] + orderedGuideIDs + [loftID],
                dependencies: [
                    DependencyEdge(source: firstProfileID, target: loftID),
                    DependencyEdge(source: secondProfileID, target: loftID),
                ] + orderedGuideIDs.map { guideID in
                    DependencyEdge(source: guideID, target: loftID)
                },
                revision: DocumentRevision(3 + orderedGuideIDs.count)
            )
        ),
        loftID
    )
}

private func circularHoleLoftDocument() -> CADDocument {
    let firstProfileID = FeatureID()
    let secondProfileID = FeatureID()
    let loftID = FeatureID()
    let secondPlane = SketchPlane.plane(Plane3D(
        origin: Point3D(x: 0.0, y: 0.0, z: 0.010),
        normal: .unitZ
    ))
    let loft = LoftFeature(
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
        ],
        options: LoftOptions(resultKind: .solid, surfaceMode: .ruled)
    )
    return CADDocument(
        units: .millimeters,
        designGraph: DesignGraph(
            nodes: [
                firstProfileID: FeatureNode(
                    id: firstProfileID,
                    operation: .sketch(loftCircularHoleSketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                secondProfileID: FeatureNode(
                    id: secondProfileID,
                    operation: .sketch(loftCircularHoleSketch(plane: secondPlane)),
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

private func loftRectangularHoleSketch(plane: SketchPlane) -> Sketch {
    let outerHalfExtent = 20.0
    let innerHalfExtent = 10.0
    let outer = [
        loftPoint(x: -outerHalfExtent, y: -outerHalfExtent),
        loftPoint(x: outerHalfExtent, y: -outerHalfExtent),
        loftPoint(x: outerHalfExtent, y: outerHalfExtent),
        loftPoint(x: -outerHalfExtent, y: outerHalfExtent),
    ]
    let inner = [
        loftPoint(x: -innerHalfExtent, y: -innerHalfExtent),
        loftPoint(x: innerHalfExtent, y: -innerHalfExtent),
        loftPoint(x: innerHalfExtent, y: innerHalfExtent),
        loftPoint(x: -innerHalfExtent, y: innerHalfExtent),
    ]
    var entities: [SketchEntityID: SketchEntity] = [:]
    for points in [outer, inner] {
        for index in points.indices {
            entities[SketchEntityID()] = .line(SketchLine(
                start: points[index],
                end: points[(index + 1) % points.count]
            ))
        }
    }
    return Sketch(plane: plane, entities: entities)
}

private func loftCircularHoleSketch(plane: SketchPlane) -> Sketch {
    var entities = loftRectangleSketch(
        width: 40.0,
        height: 40.0,
        plane: plane
    ).entities
    entities[SketchEntityID()] = .circle(SketchCircle(
        center: loftPoint(x: 0.0, y: 0.0),
        radius: .constant(.length(10.0, unit: .millimeter))
    ))
    return Sketch(plane: plane, entities: entities)
}

private func ruledRectangleLoftDocument(
    resultKind: LoftResultKind,
    firstSectionStartSampleIndex: Int? = nil,
    secondSectionStartSampleIndex: Int? = nil,
    closesSectionLoop: Bool = false
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
        options: LoftOptions(resultKind: resultKind, closesSectionLoop: closesSectionLoop)
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

private func nonPlanarSectionLoftDocument() -> (CADDocument, FeatureID) {
    let firstProfileID = FeatureID()
    let secondProfileID = FeatureID()
    let loftID = FeatureID()
    let tiltedPlane = SketchPlane.plane(Plane3D(
        origin: Point3D(x: 0.0, y: 0.0, z: 0.010),
        normal: Vector3D(x: 0.0, y: -0.3713906763541037, z: 0.9284766908852594)
    ))
    let loft = LoftFeature(
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
        ],
        options: LoftOptions(resultKind: .solid)
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
                    operation: .sketch(loftRectangleSketch(width: 6.0, height: 3.0, plane: tiltedPlane)),
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
    return (document, loftID)
}

private func ruledCircleLoftDocument() -> CADDocument {
    let firstProfileID = FeatureID()
    let secondProfileID = FeatureID()
    let loftID = FeatureID()
    let secondPlane = SketchPlane.plane(Plane3D(
        origin: Point3D(x: 0.0, y: 0.0, z: 0.010),
        normal: .unitZ
    ))
    let loft = LoftFeature(
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
        ],
        options: LoftOptions(resultKind: .solid, surfaceMode: .ruled)
    )
    return CADDocument(
        units: .millimeters,
        designGraph: DesignGraph(
            nodes: [
                firstProfileID: FeatureNode(
                    id: firstProfileID,
                    operation: .sketch(loftCircleSketch(radius: 2.0, plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                secondProfileID: FeatureNode(
                    id: secondProfileID,
                    operation: .sketch(loftCircleSketch(radius: 3.0, plane: secondPlane)),
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

private func smoothThreeSectionLoftDocument(
    smoothTangentScale: Double = 1.0,
    sectionSmoothTangentScales: [Double?] = [nil, nil, nil],
    sectionSmoothTangentModes: [LoftSectionSmoothTangentMode] = [.automatic, .automatic, .automatic]
) -> (CADDocument, FeatureID) {
    guard sectionSmoothTangentScales.count == 3,
          sectionSmoothTangentModes.count == 3 else {
        return (CADDocument(units: .millimeters), FeatureID())
    }
    let firstProfileID = FeatureID()
    let secondProfileID = FeatureID()
    let thirdProfileID = FeatureID()
    let loftID = FeatureID()
    let loft = LoftFeature(
        sections: [
            LoftSectionReference(
                profile: ProfileReference(featureID: firstProfileID),
                smoothTangentScale: sectionSmoothTangentScales[0],
                smoothTangentMode: sectionSmoothTangentModes[0]
            ),
            LoftSectionReference(
                profile: ProfileReference(featureID: secondProfileID),
                smoothTangentScale: sectionSmoothTangentScales[1],
                smoothTangentMode: sectionSmoothTangentModes[1]
            ),
            LoftSectionReference(
                profile: ProfileReference(featureID: thirdProfileID),
                smoothTangentScale: sectionSmoothTangentScales[2],
                smoothTangentMode: sectionSmoothTangentModes[2]
            ),
        ],
        options: LoftOptions(
            resultKind: .solid,
            surfaceMode: .smooth,
            smoothTangentScale: smoothTangentScale
        )
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
                    operation: .sketch(loftRectangleSketch(
                        width: 5.0,
                        height: 2.5,
                        plane: loftTranslatedPlane(x: 3.0, z: 5.0)
                    )),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                thirdProfileID: FeatureNode(
                    id: thirdProfileID,
                    operation: .sketch(loftRectangleSketch(
                        width: 4.0,
                        height: 2.0,
                        plane: loftTranslatedPlane(x: 0.0, z: 10.0)
                    )),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                loftID: FeatureNode(
                    id: loftID,
                    operation: .loft(loft),
                    inputs: [
                        FeatureInput(featureID: firstProfileID, role: .profile),
                        FeatureInput(featureID: secondProfileID, role: .profile),
                        FeatureInput(featureID: thirdProfileID, role: .profile),
                    ],
                    outputs: [FeatureOutput(role: .body)]
                ),
            ],
            order: [firstProfileID, secondProfileID, thirdProfileID, loftID],
            dependencies: [
                DependencyEdge(source: firstProfileID, target: loftID),
                DependencyEdge(source: secondProfileID, target: loftID),
                DependencyEdge(source: thirdProfileID, target: loftID),
            ],
            revision: DocumentRevision(4)
        )
    )
    return (document, loftID)
}

private func firstSmoothConnectorCurve(
    in evaluated: EvaluatedDocument,
    loftID: FeatureID
) throws -> BSplineCurve3D {
    let firstConnectorID = SubshapeID(
        featureID: loftID,
        role: GeneratedSubshapeRole.edge.rawValue,
        ordinal: 12
    )
    guard case .edge(let edgeID) = evaluated.subshapes[firstConnectorID],
          let edge = evaluated.brep.edges[edgeID],
          let curve = evaluated.brep.geometry.curves[edge.curveID]?.bSplineCurve else {
        throw FeatureEvaluationError.invalidGraph("Missing first smooth Loft connector curve.")
    }
    return curve
}

private func loftConnectorCurve(
    ordinal: Int,
    loftID: FeatureID,
    in evaluated: EvaluatedDocument
) throws -> BSplineCurve3D {
    let subshapeID = SubshapeID(
        featureID: loftID,
        role: GeneratedSubshapeRole.edge.rawValue,
        ordinal: ordinal
    )
    guard case .edge(let edgeID) = evaluated.subshapes[subshapeID],
          let edge = evaluated.brep.edges[edgeID],
          let curve = evaluated.brep.geometry.curves[edge.curveID]?.bSplineCurve else {
        throw FeatureEvaluationError.invalidGraph(
            "Missing exact Loft connector curve at ordinal \(ordinal)."
        )
    }
    return curve
}

private func closedSectionLoopLoftDocument(
    resultKind: LoftResultKind = .sheet,
    surfaceMode: LoftSurfaceMode = .ruled
) -> (CADDocument, FeatureID) {
    let firstProfileID = FeatureID()
    let secondProfileID = FeatureID()
    let thirdProfileID = FeatureID()
    let loftID = FeatureID()
    let loft = LoftFeature(
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: thirdProfileID)),
        ],
        options: LoftOptions(
            resultKind: resultKind,
            closesSectionLoop: true,
            surfaceMode: surfaceMode
        )
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
                    operation: .sketch(loftRectangleSketch(
                        width: 4.0,
                        height: 2.0,
                        plane: loftTranslatedPlane(x: 6.0, z: 4.0)
                    )),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                thirdProfileID: FeatureNode(
                    id: thirdProfileID,
                    operation: .sketch(loftRectangleSketch(
                        width: 4.0,
                        height: 2.0,
                        plane: loftTranslatedPlane(x: 0.0, z: 8.0)
                    )),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                loftID: FeatureNode(
                    id: loftID,
                    operation: .loft(loft),
                    inputs: [
                        FeatureInput(featureID: firstProfileID, role: .profile),
                        FeatureInput(featureID: secondProfileID, role: .profile),
                        FeatureInput(featureID: thirdProfileID, role: .profile),
                    ],
                    outputs: [FeatureOutput(role: resultKind == .solid ? .body : .sheet)]
                ),
            ],
            order: [firstProfileID, secondProfileID, thirdProfileID, loftID],
            dependencies: [
                DependencyEdge(source: firstProfileID, target: loftID),
                DependencyEdge(source: secondProfileID, target: loftID),
                DependencyEdge(source: thirdProfileID, target: loftID),
            ],
            revision: DocumentRevision(4)
        )
    )
    return (document, loftID)
}

private func guidedRectangleLoftDocument(
    guideSketch: Sketch = loftVerticalGuideSketch(x: 2.0, y: -1.0, zStart: 0.0, zEnd: 10.0)
) -> (CADDocument, FeatureID) {
    guidedRectangleLoftDocument(guideSketches: [guideSketch])
}

private func guidedRectangleLoftDocument(
    guideSketches: [Sketch]
) -> (CADDocument, FeatureID) {
    let firstProfileID = FeatureID()
    let secondProfileID = FeatureID()
    let guideIDs = guideSketches.map { _ in FeatureID() }
    let loftID = FeatureID()
    let secondPlane = SketchPlane.plane(Plane3D(
        origin: Point3D(x: 0.0, y: 0.0, z: 0.010),
        normal: .unitZ
    ))
    let loft = LoftFeature(
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
        ],
        guides: guideIDs.map { guideID in
            LoftGuideReference(featureID: guideID)
        },
        options: LoftOptions(resultKind: .solid)
    )
    var nodes: [FeatureID: FeatureNode] = [
        firstProfileID: FeatureNode(
            id: firstProfileID,
            operation: .sketch(loftRectangleSketch(width: 4.0, height: 2.0, plane: .xy)),
            outputs: [FeatureOutput(role: .profile)]
        ),
        secondProfileID: FeatureNode(
            id: secondProfileID,
            operation: .sketch(loftRectangleSketch(width: 4.0, height: 2.0, plane: secondPlane)),
            outputs: [FeatureOutput(role: .profile)]
        ),
    ]
    for (guideID, guideSketch) in zip(guideIDs, guideSketches) {
        nodes[guideID] = FeatureNode(
            id: guideID,
            operation: .sketch(guideSketch),
            outputs: [FeatureOutput(role: .curve)]
        )
    }
    nodes[loftID] = FeatureNode(
        id: loftID,
        operation: .loft(loft),
        inputs: [
            FeatureInput(featureID: firstProfileID, role: .profile),
            FeatureInput(featureID: secondProfileID, role: .profile),
        ] + guideIDs.map { guideID in
            FeatureInput(featureID: guideID, role: .guide)
        },
        outputs: [FeatureOutput(role: .body)]
    )
    let document = CADDocument(
        units: .millimeters,
        designGraph: DesignGraph(
            nodes: nodes,
            order: [firstProfileID, secondProfileID] + guideIDs + [loftID],
            dependencies: [
                DependencyEdge(source: firstProfileID, target: loftID),
                DependencyEdge(source: secondProfileID, target: loftID),
            ] + guideIDs.map { guideID in
                DependencyEdge(source: guideID, target: loftID)
            },
            revision: DocumentRevision(3 + guideIDs.count)
        )
    )
    return (document, loftID)
}

private func multiSectionGuidedRectangleLoftDocument(
    guideSketches: [Sketch],
    profilePlanes providedProfilePlanes: [SketchPlane]? = nil
) -> (CADDocument, FeatureID) {
    let profileIDs = (0..<3).map { _ in FeatureID() }
    let guideIDs = guideSketches.map { _ in FeatureID() }
    let loftID = FeatureID()
    let defaultProfilePlanes: [SketchPlane] = [
        .xy,
        .plane(Plane3D(
            origin: Point3D(x: 0.00225, y: 0.0, z: 0.005),
            normal: .unitZ
        )),
        .plane(Plane3D(
            origin: Point3D(x: 0.0, y: 0.0, z: 0.010),
            normal: .unitZ
        )),
    ]
    let profilePlanes = providedProfilePlanes ?? defaultProfilePlanes
    guard profilePlanes.count == profileIDs.count else {
        return (CADDocument(units: .millimeters), FeatureID())
    }
    let loft = LoftFeature(
        sections: profileIDs.map { profileID in
            LoftSectionReference(profile: ProfileReference(featureID: profileID))
        },
        guides: guideIDs.map { guideID in
            LoftGuideReference(featureID: guideID)
        },
        options: LoftOptions(resultKind: .solid)
    )
    var nodes: [FeatureID: FeatureNode] = [:]
    for (profileID, plane) in zip(profileIDs, profilePlanes) {
        nodes[profileID] = FeatureNode(
            id: profileID,
            operation: .sketch(loftRectangleSketch(width: 4.0, height: 2.0, plane: plane)),
            outputs: [FeatureOutput(role: .profile)]
        )
    }
    for (guideID, guideSketch) in zip(guideIDs, guideSketches) {
        nodes[guideID] = FeatureNode(
            id: guideID,
            operation: .sketch(guideSketch),
            outputs: [FeatureOutput(role: .curve)]
        )
    }
    nodes[loftID] = FeatureNode(
        id: loftID,
        operation: .loft(loft),
        inputs: profileIDs.map { profileID in
            FeatureInput(featureID: profileID, role: .profile)
        } + guideIDs.map { guideID in
            FeatureInput(featureID: guideID, role: .guide)
        },
        outputs: [FeatureOutput(role: .body)]
    )
    let document = CADDocument(
        units: .millimeters,
        designGraph: DesignGraph(
            nodes: nodes,
            order: profileIDs + guideIDs + [loftID],
            dependencies: profileIDs.map { profileID in
                DependencyEdge(source: profileID, target: loftID)
            } + guideIDs.map { guideID in
                DependencyEdge(source: guideID, target: loftID)
            },
            revision: DocumentRevision(1 + profileIDs.count + guideIDs.count)
        )
    )
    return (document, loftID)
}

private func loftTranslatedPlane(x: Double, z: Double) -> SketchPlane {
    .plane(Plane3D(
        origin: Point3D(x: x / 1000.0, y: 0.0, z: z / 1000.0),
        normal: .unitZ
    ))
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

private func loftCircleSketch(radius: Double, plane: SketchPlane) -> Sketch {
    Sketch(
        plane: plane,
        entities: [
            SketchEntityID(): .circle(SketchCircle(
                center: loftPoint(x: 0.0, y: 0.0),
                radius: .constant(.length(radius, unit: .millimeter))
            )),
        ]
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

private func loftVerticalGuideSketch(x: Double, y: Double, zStart: Double, zEnd: Double) -> Sketch {
    let lineID = SketchEntityID()
    return Sketch(
        plane: .plane(Plane3D(
            origin: Point3D(x: x / 1000.0, y: y / 1000.0, z: zStart / 1000.0),
            normal: .unitY
        )),
        entities: [
            lineID: .line(SketchLine(
                start: SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
                end: SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length((zEnd - zStart) / 1000.0, unit: .meter)))
            )),
        ],
        constraints: [],
        dimensions: []
    )
}

private func loftCurvedGuideSketch(
    x: Double,
    y: Double,
    zStart: Double,
    zEnd: Double,
    localXOffset: Double = -0.003
) -> Sketch {
    let splineID = SketchEntityID()
    return Sketch(
        plane: .plane(Plane3D(
            origin: Point3D(x: x / 1000.0, y: y / 1000.0, z: zStart / 1000.0),
            normal: .unitY
        )),
        entities: [
            splineID: .spline(SketchSpline(controlPoints: [
                SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
                SketchPoint(x: .constant(.length(localXOffset, unit: .meter)), y: .constant(.length(0.0025, unit: .meter))),
                SketchPoint(x: .constant(.length(localXOffset, unit: .meter)), y: .constant(.length(0.0075, unit: .meter))),
                SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length((zEnd - zStart) / 1000.0, unit: .meter))),
            ])),
        ],
        constraints: [],
        dimensions: []
    )
}

private func loftPoint(x: Double, y: Double) -> SketchPoint {
    SketchPoint(
        x: .constant(.length(x, unit: .millimeter)),
        y: .constant(.length(y, unit: .millimeter))
    )
}

private extension Surface3D {
    var isPlaneSurface: Bool {
        if case .plane = self {
            return true
        }
        return false
    }

    var isBSplineSurface: Bool {
        bSplineSurface != nil
    }

    var bSplineSurface: BSplineSurface3D? {
        if case .bSpline(let surface) = self {
            return surface
        }
        return nil
    }
}

private extension Curve3D {
    var bSplineCurve: BSplineCurve3D? {
        if case .bSpline(let curve) = self {
            return curve
        }
        return nil
    }
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
