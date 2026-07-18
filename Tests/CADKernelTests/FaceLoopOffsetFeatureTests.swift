import CADCore
import CADIR
import CADTopology
import Testing
@testable import CADKernel

@Suite("Face Loop Offset Feature")
struct FaceLoopOffsetFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func splitsStrictlyConvexPentagonWithDeterministicExactTopology() throws {
        var document = makeConvexPentagonExtrudeDocument()
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let offsetFeatureID = FeatureID()
        let sourceFaceID = SubshapeID(
            featureID: extrudeFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        )
        let offsetFeature = FeatureNode(
            id: offsetFeatureID,
            operation: .faceLoopOffset(FaceLoopOffsetFeature(
                target: FaceLoopOffsetTargetReference(featureID: extrudeFeatureID),
                face: try source.stableSubshapeReference(for: sourceFaceID),
                distance: .constant(.length(2.0, unit: .millimeter))
            )),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.nodes[offsetFeatureID] = offsetFeature
        document.designGraph.order.append(offsetFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(
            source: extrudeFeatureID,
            target: offsetFeatureID
        ))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let offsetEdges = evaluated.subshapes.entries.filter { subshapeID, reference in
            guard case .edge = reference else {
                return false
            }
            return subshapeID.featureID == offsetFeatureID
                && subshapeID.role == "faceLoopOffset.offsetEdge"
        }
        let centerFaceSubshapeID = SubshapeID(
            featureID: offsetFeatureID,
            role: "faceLoopOffset.centerFace",
            ordinal: 0
        )
        guard case let .face(centerFaceID) = try #require(
            evaluated.subshapes.entries[centerFaceSubshapeID]
        ) else {
            Issue.record("Expected the generated center face.")
            return
        }
        let centerFace = try #require(evaluated.brep.faces[centerFaceID])
        let centerLoopID = try #require(centerFace.loops.first)
        let centerLoop = try #require(evaluated.brep.loops[centerLoopID])
        let outputLineage = evaluated.lineage.values.filter {
            $0.output.featureID == offsetFeatureID
        }

        #expect(evaluated.brep.faces.count == 8)
        #expect(evaluated.brep.edges.count == 20)
        #expect(evaluated.brep.vertices.count == 15)
        #expect(offsetEdges.count == 5)
        #expect(offsetEdges.map { $0.key.ordinal }.sorted() == [0, 1, 2, 3, 4])
        #expect(centerLoop.edges.count == 5)
        #expect(centerLoop.edges.allSatisfy { edge in
            guard let parameterCurve = edge.surfaceParameterCurve,
                  case .affine = parameterCurve else {
                return false
            }
            return true
        })
        #expect(outputLineage.count == 13)
        #expect(outputLineage.filter { $0.relation == .generated }.count == 10)
        #expect(outputLineage.filter { $0.relation == .preserved }.count == 1)
        let splitLineage = outputLineage.filter { $0.relation == .split }
        #expect(splitLineage.count == 2)
        #expect(splitLineage.allSatisfy { $0.parents == [sourceFaceID] })
        #expect(evaluated.brep == repeated.brep)
        #expect(evaluated.subshapes == repeated.subshapes)
        #expect(evaluated.lineage == repeated.lineage)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - source.brep.volume(tolerance: .standard)) <= 1.0e-12)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    }
}

func makeConvexPentagonExtrudeDocument() -> CADDocument {
    let points = [
        Point2D(x: -18.0, y: -8.0),
        Point2D(x: 4.0, y: -16.0),
        Point2D(x: 22.0, y: -2.0),
        Point2D(x: 12.0, y: 16.0),
        Point2D(x: -16.0, y: 12.0),
    ]
    let sketchFeatureID = FeatureID()
    let extrudeFeatureID = FeatureID()
    let depthParameterID = ParameterID()
    let entityIDs = points.indices.map { _ in SketchEntityID() }
    var entities: [SketchEntityID: SketchEntity] = [:]
    var constraints: [SketchConstraint] = []
    for index in points.indices {
        let nextIndex = (index + 1) % points.count
        entities[entityIDs[index]] = .line(SketchLine(
            start: sketchPoint(points[index]),
            end: sketchPoint(points[nextIndex])
        ))
        constraints.append(.coincident(
            .lineEnd(entityIDs[index]),
            .lineStart(entityIDs[nextIndex])
        ))
    }
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(Sketch(
            plane: .xy,
            entities: entities,
            constraints: constraints
        )),
        outputs: [FeatureOutput(role: .profile)]
    )
    let extrudeFeature = FeatureNode(
        id: extrudeFeatureID,
        operation: .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: .reference(depthParameterID),
            direction: .normal
        )),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    return CADDocument(
        units: .millimeters,
        parameters: ParameterTable(parameters: [
            depthParameterID: Parameter(
                id: depthParameterID,
                name: "depth",
                expression: .constant(.length(10.0, unit: .millimeter)),
                kind: .length
            )
        ]),
        designGraph: DesignGraph(
            nodes: [
                sketchFeatureID: sketchFeature,
                extrudeFeatureID: extrudeFeature,
            ],
            order: [sketchFeatureID, extrudeFeatureID],
            dependencies: [DependencyEdge(
                source: sketchFeatureID,
                target: extrudeFeatureID
            )],
            revision: DocumentRevision(2)
        )
    )
}

private func sketchPoint(_ point: Point2D) -> SketchPoint {
    SketchPoint(
        x: .constant(.length(point.x, unit: .millimeter)),
        y: .constant(.length(point.y, unit: .millimeter))
    )
}
