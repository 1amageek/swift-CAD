import CADCore
import CADIR
import CADModeling
import CADTopology
import Foundation
import Testing
@testable import CADKernel

@Suite("Face Draft Feature")
struct FaceDraftFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func draftsOneFaceAsDeterministicExactSolidWithPreservedLineage() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let targetID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.sideFace.rawValue,
            ordinal: 0
        )
        let neutralID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        )
        let target = try source.stableSubshapeReference(for: targetID)
        let neutral = try source.stableSubshapeReference(for: neutralID)
        let draftFeatureID = FeatureID()
        try appendFaceDraft(
            featureID: draftFeatureID,
            sourceFeatureID: sourceFeatureID,
            faces: [target],
            neutralFace: neutral,
            angle: .constant(.angle(10.0, unit: .degree)),
            to: &document
        )

        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let evaluated = try evaluator.evaluate(document)
        let repeated = try evaluator.evaluate(document)
        let body = try #require(evaluated.brep.bodies.values.first)
        let outputLineage = evaluated.lineage.values.filter {
            $0.output.featureID == draftFeatureID
        }
        let resolvedTarget = try StableSubshapeResolver().topologyReference(
            for: target,
            model: evaluated.brep,
            subshapes: evaluated.subshapes,
            lineage: evaluated.lineage,
            tolerance: .standard
        )
        let resolvedNeutral = try StableSubshapeResolver().topologyReference(
            for: neutral,
            model: evaluated.brep,
            subshapes: evaluated.subshapes,
            lineage: evaluated.lineage,
            tolerance: .standard
        )
        let targetPlane = try plane(for: resolvedTarget, in: evaluated.brep)
        let neutralPlane = try plane(for: resolvedNeutral, in: evaluated.brep)

        #expect(body.kind == .solid)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(try evaluated.brep.volume(tolerance: .standard) > source.brep.volume(tolerance: .standard))
        #expect(abs(targetPlane.normal.dot(neutralPlane.normal)) > 0.01)
        #expect(outputLineage.count == 27)
        #expect(outputLineage.allSatisfy {
            $0.relation == .preserved && $0.parents.count == 1
        })
        #expect(evaluated.brep.loops.values.flatMap(\.coedges).allSatisfy {
            $0.surfaceParameterCurve != nil
        })
        #expect(evaluated.brep == repeated.brep)
        #expect(evaluated.subshapes == repeated.subshapes)
        #expect(evaluated.lineage == repeated.lineage)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func draftsAdjacentFacesWithACommonSolvedVertexDisplacement() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let faces = try [0, 1].map { ordinal in
            try source.stableSubshapeReference(for: SubshapeID(
                featureID: sourceFeatureID,
                role: GeneratedSubshapeRole.sideFace.rawValue,
                ordinal: ordinal
            ))
        }
        let neutral = try source.stableSubshapeReference(for: SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        ))
        let draftFeatureID = FeatureID()
        try appendFaceDraft(
            featureID: draftFeatureID,
            sourceFeatureID: sourceFeatureID,
            faces: faces,
            neutralFace: neutral,
            angle: .constant(.angle(7.0, unit: .degree)),
            to: &document
        )

        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let evaluated = try evaluator.evaluate(document)
        let repeated = try evaluator.evaluate(document)

        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(try evaluated.brep.volume(tolerance: .standard) > source.brep.volume(tolerance: .standard))
        #expect(evaluated.brep == repeated.brep)
        #expect(evaluated.subshapes == repeated.subshapes)
        #expect(evaluated.lineage == repeated.lineage)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func draftsNegativeAngleAsAnExactContractingSolid() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let source = try evaluator.evaluate(document)
        let target = try source.stableSubshapeReference(for: SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.sideFace.rawValue,
            ordinal: 0
        ))
        let neutral = try source.stableSubshapeReference(for: SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        ))
        let draftFeatureID = FeatureID()
        try appendFaceDraft(
            featureID: draftFeatureID,
            sourceFeatureID: sourceFeatureID,
            faces: [target],
            neutralFace: neutral,
            angle: .constant(.angle(-10.0, unit: .degree)),
            to: &document
        )

        let evaluated = try evaluator.evaluate(document)
        let repeated = try evaluator.evaluate(document)

        #expect(try evaluated.brep.volume(tolerance: .standard) < source.brep.volume(tolerance: .standard))
        #expect(evaluated.brep.loops.values.flatMap(\.coedges).allSatisfy {
            $0.surfaceParameterCurve != nil
        })
        #expect(evaluated.brep == repeated.brep)
        #expect(evaluated.subshapes == repeated.subshapes)
        #expect(evaluated.lineage == repeated.lineage)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesUnrelatedBodyAndSelectionIdentity() throws {
        let targetDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let unrelatedDocument = makeRectangleExtrudeDocument(
            width: 30.0,
            height: 15.0,
            depth: 5.0,
            documentUnits: .meters
        )
        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let target = try evaluator.evaluate(targetDocument)
        let unrelated = try evaluator.evaluate(unrelatedDocument)
        let targetFeatureID = try #require(targetDocument.designGraph.order.last)
        let targetFace = try target.stableSubshapeReference(for: SubshapeID(
            featureID: targetFeatureID,
            role: GeneratedSubshapeRole.sideFace.rawValue,
            ordinal: 0
        ))
        let neutralFace = try target.stableSubshapeReference(for: SubshapeID(
            featureID: targetFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        ))
        let fixture = try EvaluationFixtureCombiner.combine([
            (target.brep, target.subshapes, target.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])

        let result = try FaceDraftFeatureEvaluator().evaluate(
            feature: FeatureNode(
                id: FeatureID(),
                operation: .faceDraft(FaceDraftFeature(
                    target: FaceDraftTargetReference(featureID: targetFeatureID),
                    faces: [targetFace],
                    neutralFace: neutralFace,
                    angle: .constant(.angle(8.0, unit: .degree))
                )),
                inputs: [FeatureInput(featureID: targetFeatureID, role: .target)],
                outputs: [FeatureOutput(role: .body)]
            ),
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: fixture.brep,
                profiles: [:],
                subshapes: fixture.subshapes,
                lineage: fixture.lineage,
                tolerance: .standard
            )
        )

        #expect(result.brep.bodies.count == 2)
        #expect(result.removedSubshapeIDs == Set(target.subshapes.entries.keys))
        #expect(result.removedSubshapeIDs.isDisjoint(with: unrelated.subshapes.entries.keys))
        for bodyID in unrelated.brep.bodies.keys {
            #expect(result.brep.bodies[bodyID] == unrelated.brep.bodies[bodyID])
        }
        try result.brep.validate(level: .volumetric, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsFaceOwnedByAnotherTargetBody() throws {
        let targetDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let foreignDocument = makeRectangleExtrudeDocument(
            width: 30.0,
            height: 15.0,
            depth: 5.0,
            documentUnits: .meters
        )
        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let target = try evaluator.evaluate(targetDocument)
        let foreign = try evaluator.evaluate(foreignDocument)
        let targetFeatureID = try #require(targetDocument.designGraph.order.last)
        let foreignFeatureID = try #require(foreignDocument.designGraph.order.last)
        let foreignFace = try foreign.stableSubshapeReference(for: SubshapeID(
            featureID: foreignFeatureID,
            role: GeneratedSubshapeRole.sideFace.rawValue,
            ordinal: 0
        ))
        let neutralFace = try target.stableSubshapeReference(for: SubshapeID(
            featureID: targetFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        ))
        let fixture = try EvaluationFixtureCombiner.combine([
            (target.brep, target.subshapes, target.lineage),
            (foreign.brep, foreign.subshapes, foreign.lineage),
        ])
        let featureID = FeatureID()

        do {
            _ = try FaceDraftFeatureEvaluator().evaluate(
                feature: FeatureNode(
                    id: featureID,
                    operation: .faceDraft(FaceDraftFeature(
                        target: FaceDraftTargetReference(featureID: targetFeatureID),
                        faces: [foreignFace],
                        neutralFace: neutralFace,
                        angle: .constant(.angle(8.0, unit: .degree))
                    )),
                    inputs: [FeatureInput(featureID: targetFeatureID, role: .target)],
                    outputs: [FeatureOutput(role: .body)]
                ),
                context: EvaluationContext(
                    parameters: ResolvedParameterTable(),
                    brep: fixture.brep,
                    profiles: [:],
                    subshapes: fixture.subshapes,
                    lineage: fixture.lineage,
                    tolerance: .standard
                )
            )
            Issue.record("A face owned by another target body must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .missingReference)
            #expect(error.featureID == featureID)
            #expect(error.tolerance == .standard)
        } catch {
            Issue.record("Expected a typed KernelError, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsNinetyDegreeDraftWithTypedDiagnostic() throws {
        let document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let target = try source.stableSubshapeReference(for: SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.sideFace.rawValue,
            ordinal: 0
        ))
        let neutral = try source.stableSubshapeReference(for: SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        ))
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            operation: .faceDraft(FaceDraftFeature(
                target: FaceDraftTargetReference(featureID: sourceFeatureID),
                faces: [target],
                neutralFace: neutral,
                angle: .constant(.angle(90.0, unit: .degree))
            )),
            inputs: [FeatureInput(featureID: sourceFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        let context = EvaluationContext(
            parameters: source.parameters,
            brep: source.brep,
            profiles: [:],
            curves: source.curves,
            subshapes: source.subshapes,
            lineage: source.lineage,
            tolerance: .standard
        )

        do {
            _ = try FaceDraftFeatureEvaluator().evaluate(feature: feature, context: context)
            Issue.record("A 90 degree face draft must be rejected.")
        } catch let error as KernelError {
            #expect(error.phase == .evaluation)
            #expect(error.code == .unsupportedCapability)
            #expect(error.featureID == featureID)
            #expect(error.tolerance == .standard)
            let residual = try #require(error.residual)
            #expect(abs(residual - Double.pi / 2.0) <= 1.0e-12)
        } catch {
            Issue.record("Expected a typed KernelError, got \(error).")
        }
    }

    private func appendFaceDraft(
        featureID: FeatureID,
        sourceFeatureID: FeatureID,
        faces: [StableSubshapeReference],
        neutralFace: StableSubshapeReference,
        angle: CADExpression,
        to document: inout CADDocument
    ) throws {
        let operation = FeatureOperation.faceDraft(FaceDraftFeature(
            target: FaceDraftTargetReference(featureID: sourceFeatureID),
            faces: faces,
            neutralFace: neutralFace,
            angle: angle
        ))
        let node = try FeatureNodeFactory.make(
            operation: operation,
            id: featureID,
            in: document,
            tolerance: .standard
        )
        document.designGraph.nodes[featureID] = node
        document.designGraph.order.append(featureID)
        document.designGraph.dependencies.append(DependencyEdge(
            source: sourceFeatureID,
            target: featureID
        ))
        document.designGraph.revision = document.designGraph.revision.advanced()
    }

    private func plane(
        for reference: TopologyReference,
        in model: BRepModel
    ) throws -> Plane3D {
        guard case let .face(faceID) = reference,
              let face = model.faces[faceID],
              case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: .standard,
                message: "Face draft fixture requires a planar face."
            )
        }
        return plane
    }
}
