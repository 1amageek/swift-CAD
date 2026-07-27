import CADCore
import CADIR
import CADModeling
import CADTopology
import Testing
@testable import CADKernel

@Suite("Edge Offset Feature")
struct EdgeOffsetFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func splitsStrictlyConvexPentagonWithDeterministicExactTopology() throws {
        var document = makeConvexPentagonExtrudeDocument()
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let offsetFeatureID = FeatureID()
        let supportFaceSubshapeID = SubshapeID(
            featureID: extrudeFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        )
        guard case let .face(supportFaceID) = try #require(
            source.subshapes.entries[supportFaceSubshapeID]
        ) else {
            Issue.record("Expected the start-face subshape to reference a face.")
            return
        }
        let supportFace = try #require(source.brep.faces[supportFaceID])
        let supportLoopID = try #require(supportFace.loops.first)
        let supportLoop = try #require(source.brep.loops[supportLoopID])
        let selectedEdgeID = try #require(supportLoop.edges.first?.edgeID)
        let selectedEdgeSubshapeID = try #require(
            source.subshapes.entries.first { subshapeID, reference in
                subshapeID.featureID == extrudeFeatureID
                    && reference == .edge(selectedEdgeID)
            }?.key
        )
        let offsetFeature = FeatureNode(
            id: offsetFeatureID,
            operation: .edgeOffset(EdgeOffsetFeature(
                target: EdgeOffsetTargetReference(featureID: extrudeFeatureID),
                edge: try source.stableSubshapeReference(for: selectedEdgeSubshapeID),
                supportFace: try source.stableSubshapeReference(for: supportFaceSubshapeID),
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
        let generatedEdgeIDs: Set<EdgeID> = Set(evaluated.subshapes.entries.compactMap { subshapeID, reference in
            guard subshapeID.featureID == offsetFeatureID,
                  case let .edge(edgeID) = reference else {
                return nil
            }
            return edgeID
        })
        let generatedEdgeUses = evaluated.brep.loops.values
            .flatMap(\.edges)
            .filter { generatedEdgeIDs.contains($0.edgeID) }
        let outputLineage = evaluated.lineage.values.filter {
            $0.output.featureID == offsetFeatureID
        }

        #expect(evaluated.brep.faces.count == 8)
        #expect(evaluated.brep.edges.count == 18)
        #expect(evaluated.brep.vertices.count == 12)
        #expect(generatedEdgeIDs.count == 5)
        #expect(generatedEdgeUses.isEmpty == false)
        #expect(generatedEdgeUses.allSatisfy { $0.surfaceParameterCurve != nil })
        #expect(outputLineage.count == 10)
        #expect(outputLineage.filter { $0.relation == .generated }.count == 3)
        #expect(outputLineage.filter { $0.relation == .preserved }.count == 1)
        let splitLineage = outputLineage.filter { $0.relation == .split }
        #expect(splitLineage.count == 6)
        let splitGroups = Dictionary(grouping: splitLineage) { $0.parents[0] }
        #expect(splitGroups.values.allSatisfy { $0.count == 2 })
        #expect(evaluated.brep == repeated.brep)
        #expect(evaluated.subshapes == repeated.subshapes)
        #expect(evaluated.lineage == repeated.lineage)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - source.brep.volume(tolerance: .standard)) <= 1.0e-12)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func symmetricOffsetSplitsBothAdjacentFacesWithUniqueTopology() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let offsetFeatureID = FeatureID()
        let supportFaceSubshapeID = SubshapeID(
            featureID: extrudeFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        )
        guard case let .face(supportFaceID) = try #require(
            source.subshapes.entries[supportFaceSubshapeID]
        ) else {
            Issue.record("Expected the start-face subshape to reference a face.")
            return
        }
        let supportFace = try #require(source.brep.faces[supportFaceID])
        let supportLoopID = try #require(supportFace.loops.first)
        let supportLoop = try #require(source.brep.loops[supportLoopID])
        let selectedEdgeID = try #require(supportLoop.edges.first?.edgeID)
        let selectedEdgeSubshapeID = try #require(
            source.subshapes.entries.first { subshapeID, reference in
                subshapeID.featureID == extrudeFeatureID
                    && reference == .edge(selectedEdgeID)
            }?.key
        )
        let offsetFeature = FeatureNode(
            id: offsetFeatureID,
            operation: .edgeOffset(EdgeOffsetFeature(
                target: EdgeOffsetTargetReference(featureID: extrudeFeatureID),
                edge: try source.stableSubshapeReference(for: selectedEdgeSubshapeID),
                supportFace: try source.stableSubshapeReference(for: supportFaceSubshapeID),
                distance: .constant(.length(2.0, unit: .millimeter)),
                isSymmetric: true
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
        let offsetEdges = evaluated.subshapes.entries.filter { subshapeID, reference in
            guard case .edge = reference else {
                return false
            }
            return subshapeID.featureID == offsetFeatureID
                && subshapeID.role == "edgeOffset.offsetEdge"
        }
        let remainderFaces = evaluated.subshapes.entries.filter { subshapeID, reference in
            guard case .face = reference else {
                return false
            }
            return subshapeID.featureID == offsetFeatureID
                && subshapeID.role == "edgeOffset.remainderFace"
        }
        let outputLineage = evaluated.lineage.values.filter {
            $0.output.featureID == offsetFeatureID
        }

        #expect(evaluated.brep.faces.count == 8)
        #expect(evaluated.brep.edges.count == 18)
        #expect(evaluated.brep.vertices.count == 12)
        #expect(offsetEdges.map { $0.key.ordinal }.sorted() == [0, 1])
        #expect(remainderFaces.map { $0.key.ordinal }.sorted() == [0, 1])
        #expect(outputLineage.count == 19)
        #expect(outputLineage.filter { $0.relation == .generated }.count == 6)
        #expect(outputLineage.filter { $0.relation == .preserved }.count == 1)
        #expect(outputLineage.filter { $0.relation == .split }.count == 12)
        #expect(Set(evaluated.brep.edges.keys).count == evaluated.brep.edges.count)
        #expect(Set(evaluated.brep.vertices.keys).count == evaluated.brep.vertices.count)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - source.brep.volume(tolerance: .standard)) <= 1.0e-12)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsOffsetThatCollapsesTheSupportFaceBoundary() throws {
        var document = makeConvexPentagonExtrudeDocument()
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let supportFaceSubshapeID = SubshapeID(
            featureID: extrudeFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        )
        guard case let .face(supportFaceID) = try #require(
            source.subshapes.entries[supportFaceSubshapeID]
        ) else {
            Issue.record("Expected the start-face subshape to reference a face.")
            return
        }
        let supportFace = try #require(source.brep.faces[supportFaceID])
        let supportLoopID = try #require(supportFace.loops.first)
        let supportLoop = try #require(source.brep.loops[supportLoopID])
        let selectedEdgeID = try #require(supportLoop.edges.first?.edgeID)
        let selectedEdgeSubshapeID = try #require(
            source.subshapes.entries.first { subshapeID, reference in
                subshapeID.featureID == extrudeFeatureID
                    && reference == .edge(selectedEdgeID)
            }?.key
        )
        let offsetFeatureID = FeatureID()
        document.designGraph.nodes[offsetFeatureID] = FeatureNode(
            id: offsetFeatureID,
            operation: .edgeOffset(EdgeOffsetFeature(
                target: EdgeOffsetTargetReference(featureID: extrudeFeatureID),
                edge: try source.stableSubshapeReference(
                    for: selectedEdgeSubshapeID
                ),
                supportFace: try source.stableSubshapeReference(
                    for: supportFaceSubshapeID
                ),
                distance: .constant(.length(100.0, unit: .millimeter))
            )),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.order.append(offsetFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(
            source: extrudeFeatureID,
            target: offsetFeatureID
        ))
        document.designGraph.revision = document.designGraph.revision.advanced()

        do {
            _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
            Issue.record("A collapsing edge offset must not succeed.")
        } catch let error as KernelError {
            #expect(error.code == .invalidInput)
            #expect(error.featureID == offsetFeatureID)
            #expect(error.tolerance == .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsSupportFaceOwnedByAnotherTargetBody() throws {
        let firstDocument = makeConvexPentagonExtrudeDocument()
        let secondDocument = makeConvexPentagonExtrudeDocument()
        let firstFeatureID = try #require(firstDocument.designGraph.order.last)
        let secondFeatureID = try #require(secondDocument.designGraph.order.last)
        let first = try DocumentEvaluator(tolerance: .standard).evaluate(firstDocument)
        let second = try DocumentEvaluator(tolerance: .standard).evaluate(secondDocument)
        let combined = try EvaluationFixtureCombiner.combine([
            (first.brep, first.subshapes, first.lineage),
            (second.brep, second.subshapes, second.lineage),
        ])
        let supportFaceSubshapeID = SubshapeID(
            featureID: secondFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        )
        guard case let .face(supportFaceID) = try #require(
            second.subshapes.entries[supportFaceSubshapeID]
        ) else {
            Issue.record("Expected the start-face subshape to reference a face.")
            return
        }
        let supportFace = try #require(second.brep.faces[supportFaceID])
        let supportLoopID = try #require(supportFace.loops.first)
        let supportLoop = try #require(second.brep.loops[supportLoopID])
        let selectedEdgeID = try #require(supportLoop.edges.first?.edgeID)
        let selectedEdgeSubshapeID = try #require(
            second.subshapes.entries.first { subshapeID, reference in
                subshapeID.featureID == secondFeatureID
                    && reference == .edge(selectedEdgeID)
            }?.key
        )
        let offsetFeatureID = FeatureID()

        do {
            _ = try EdgeOffsetFeatureEvaluator().evaluate(
                feature: FeatureNode(
                    id: offsetFeatureID,
                    operation: .edgeOffset(EdgeOffsetFeature(
                        target: EdgeOffsetTargetReference(
                            featureID: firstFeatureID
                        ),
                        edge: try second.stableSubshapeReference(
                            for: selectedEdgeSubshapeID
                        ),
                        supportFace: try second.stableSubshapeReference(
                            for: supportFaceSubshapeID
                        ),
                        distance: .constant(.length(2.0, unit: .millimeter))
                    )),
                    inputs: [FeatureInput(featureID: firstFeatureID, role: .target)],
                    outputs: [FeatureOutput(role: .body)]
                ),
                context: EvaluationContext(
                    parameters: ResolvedParameterTable(),
                    brep: combined.brep,
                    profiles: [:],
                    subshapes: combined.subshapes,
                    lineage: combined.lineage,
                    tolerance: .standard
                )
            )
            Issue.record("A support face from another body must not be offset.")
        } catch let error as KernelError {
            #expect(error.code == .missingReference)
            #expect(error.featureID == offsetFeatureID)
            #expect(error.tolerance == .standard)
        }
    }
}
