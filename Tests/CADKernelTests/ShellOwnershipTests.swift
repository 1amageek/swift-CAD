import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Testing
@testable import CADKernel

@Suite("Shell ownership")
struct ShellOwnershipTests {
    @Test(.timeLimit(.minutes(1)))
    func scopesReplacementAndLineageToTheTargetBody() throws {
        let target = try evaluatedSolid()
        let unrelated = try evaluatedSolid()
        let targetFeatureID = try #require(target.document.designGraph.order.last)
        let removedFace = try stableStartFace(featureID: targetFeatureID, in: target)
        let fixture = try EvaluationFixtureCombiner.combine([
            (target.brep, target.subshapes, target.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let shellFeatureID = FeatureID()

        let result = try ShellFeatureEvaluator().evaluate(
            feature: feature(
                id: shellFeatureID,
                sourceFeatureID: targetFeatureID,
                removedFaces: [removedFace],
                thickness: 0.002
            ),
            context: context(for: fixture)
        )
        let targetSubshapeIDs = Set(target.subshapes.entries.keys)
        let unrelatedSubshapeIDs = Set(unrelated.subshapes.entries.keys)
        let outputLineage = result.lineage.values.filter {
            $0.output.featureID == shellFeatureID
        }

        #expect(result.removedSubshapeIDs == targetSubshapeIDs)
        #expect(result.removedSubshapeIDs.isDisjoint(with: unrelatedSubshapeIDs))
        #expect(outputLineage.isEmpty == false)
        #expect(outputLineage.allSatisfy {
            Set($0.parents).isSubset(of: targetSubshapeIDs)
        })
        for bodyID in unrelated.brep.bodies.keys {
            #expect(result.brep.bodies[bodyID] == unrelated.brep.bodies[bodyID])
        }
        try result.brep.validate(level: .volumetric, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsRemovalFaceOwnedByAnotherTargetBody() throws {
        let target = try evaluatedSolid()
        let foreign = try evaluatedSolid()
        let targetFeatureID = try #require(target.document.designGraph.order.last)
        let foreignFeatureID = try #require(foreign.document.designGraph.order.last)
        let foreignFace = try stableStartFace(featureID: foreignFeatureID, in: foreign)
        let fixture = try EvaluationFixtureCombiner.combine([
            (target.brep, target.subshapes, target.lineage),
            (foreign.brep, foreign.subshapes, foreign.lineage),
        ])
        let shellFeatureID = FeatureID()

        do {
            _ = try ShellFeatureEvaluator().evaluate(
                feature: feature(
                    id: shellFeatureID,
                    sourceFeatureID: targetFeatureID,
                    removedFaces: [foreignFace],
                    thickness: 0.002
                ),
                context: context(for: fixture)
            )
            Issue.record("A removal face owned by another target body must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .missingReference)
            #expect(error.featureID == shellFeatureID)
            #expect(error.subshapeID == foreignFace.subshapeID)
            #expect(error.tolerance == .standard)
        } catch {
            Issue.record("Expected a typed KernelError, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func ignoresUnrelatedVerticesWhenComputingCavityDepth() throws {
        let target = try evaluatedSolid()
        let translatedDocument = try makeRectangleExtrudeDocument(
            width: 40.0,
            height: 2_000.0,
            depth: 10.0,
            documentUnits: .meters,
            sketchPlane: .zx
        ).translatingSources(
            by: Vector3D(x: 1.0, y: 0.0, z: 0.0),
            tolerance: .standard
        )
        let unrelated = try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(translatedDocument)
        let targetFeatureID = try #require(target.document.designGraph.order.last)
        let removedFace = try stableStartFace(featureID: targetFeatureID, in: target)
        let shellFeatureID = FeatureID()
        let fixture = try EvaluationFixtureCombiner.combine([
            (target.brep, target.subshapes, target.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])

        let isolated = try ShellFeatureEvaluator().evaluate(
            feature: feature(
                id: shellFeatureID,
                sourceFeatureID: targetFeatureID,
                removedFaces: [removedFace],
                thickness: 0.002
            ),
            context: context(for: (
                target.brep,
                target.subshapes,
                target.lineage
            ))
        )
        let combined = try ShellFeatureEvaluator().evaluate(
            feature: feature(
                id: shellFeatureID,
                sourceFeatureID: targetFeatureID,
                removedFaces: [removedFace],
                thickness: 0.002
            ),
            context: context(for: fixture)
        )
        let isolatedVolume = try isolated.brep.volume(tolerance: .standard)
        let combinedTargetVolume = try combined.brep.volume(tolerance: .standard)
            - unrelated.brep.volume(tolerance: .standard)

        #expect(abs(combinedTargetVolume - isolatedVolume) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsMultipleRemovalFaces() throws {
        let source = try evaluatedSolid()
        let sourceFeatureID = try #require(source.document.designGraph.order.last)
        let face = try stableStartFace(featureID: sourceFeatureID, in: source)
        let shellFeatureID = FeatureID()

        do {
            _ = try ShellFeatureEvaluator().evaluate(
                feature: feature(
                    id: shellFeatureID,
                    sourceFeatureID: sourceFeatureID,
                    removedFaces: [face, face],
                    thickness: 0.002
                ),
                context: context(for: (
                    source.brep,
                    source.subshapes,
                    source.lineage
                ))
            )
            Issue.record("The bounded shell contract must reject multiple removal faces.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
            #expect(error.featureID == shellFeatureID)
            #expect(error.tolerance == .standard)
        } catch {
            Issue.record("Expected a typed KernelError, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsThicknessThatDoesNotFitBodyDimensions() throws {
        let source = try evaluatedSolid()
        let sourceFeatureID = try #require(source.document.designGraph.order.last)
        let face = try stableStartFace(featureID: sourceFeatureID, in: source)
        let shellFeatureID = FeatureID()

        do {
            _ = try ShellFeatureEvaluator().evaluate(
                feature: feature(
                    id: shellFeatureID,
                    sourceFeatureID: sourceFeatureID,
                    removedFaces: [face],
                    thickness: 0.100
                ),
                context: context(for: (
                    source.brep,
                    source.subshapes,
                    source.lineage
                ))
            )
            Issue.record("A shell thickness that removes the cavity must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
            #expect(error.featureID == shellFeatureID)
            #expect(error.tolerance == .standard)
        } catch {
            Issue.record("Expected a typed KernelError, got \(error).")
        }
    }

    private func evaluatedSolid() throws -> EvaluatedDocument {
        try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(makeRectangleExtrudeDocument(documentUnits: .meters))
    }

    private func stableStartFace(
        featureID: FeatureID,
        in document: EvaluatedDocument
    ) throws -> StableSubshapeReference {
        try document.stableSubshapeReference(for: SubshapeID(
            featureID: featureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        ))
    }

    private func feature(
        id: FeatureID,
        sourceFeatureID: FeatureID,
        removedFaces: [StableSubshapeReference],
        thickness: Double
    ) -> FeatureNode {
        FeatureNode(
            id: id,
            operation: .shell(ShellFeature(
                target: ShellTargetReference(featureID: sourceFeatureID),
                removedFaces: removedFaces,
                thickness: .constant(.length(thickness, unit: .meter))
            )),
            inputs: [FeatureInput(featureID: sourceFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
    }

    private func context(
        for fixture: (
            brep: BRepModel,
            subshapes: SubshapeIndex,
            lineage: [SubshapeID: TopologyLineage]
        )
    ) -> EvaluationContext {
        EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: fixture.brep,
            profiles: [:],
            subshapes: fixture.subshapes,
            lineage: fixture.lineage,
            tolerance: .standard
        )
    }
}
