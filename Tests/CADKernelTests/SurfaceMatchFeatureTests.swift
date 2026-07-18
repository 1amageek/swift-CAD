import Testing
import CADCore
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@Suite("Exact surface match")
struct SurfaceMatchFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func matchesPlanarSheetFramesWithVerifiedG2AndMergedFaceLineage() throws {
        let sourceID = FeatureID()
        let targetID = FeatureID()
        let featureID = FeatureID()
        let source = try PlanarSheetTestFixture.make(featureID: sourceID, tolerance: .standard)
        var target = try PlanarSheetTestFixture.make(featureID: targetID, tolerance: .standard)
        let targetBodyID = try bodyID(featureID: targetID, subshapes: target.subshapes)
        for vertexID in target.brep.vertices.keys {
            guard var vertex = target.brep.vertices[vertexID] else {
                throw TopologyError.missingReference("Surface match target fixture vertex is missing.")
            }
            vertex.point = vertex.point + .unitZ * 0.100
            target.brep.vertices[vertexID] = vertex
        }
        try DefaultPlanarBodyGeometryRebuilder().rebuild(
            featureID: targetID,
            bodyID: targetBodyID,
            in: &target.brep,
            tolerance: .standard
        )
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &target.brep, tolerance: .standard)
        let combined = merged(source.brep, target.brep)
        var subshapes = source.subshapes.entries
        subshapes.merge(target.subshapes.entries) { _, target in target }
        var lineage = source.lineage
        lineage.merge(target.lineage) { _, target in target }
        let feature = FeatureNode(
            id: featureID,
            operation: .surfaceMatch(SurfaceMatchFeature(
                source: SurfaceOperationTargetReference(featureID: sourceID),
                target: SurfaceOperationTargetReference(featureID: targetID),
                sourceParameter: SurfaceParameter(u: 0.0, v: 0.0),
                targetParameter: SurfaceParameter(u: 0.0, v: 0.0),
                continuity: .curvature
            )),
            inputs: [
                FeatureInput(featureID: sourceID, role: .sheet),
                FeatureInput(featureID: targetID, role: .target),
            ],
            outputs: [FeatureOutput(role: .sheet)]
        )
        let result = try SurfaceMatchFeatureEvaluator().evaluate(
            feature: feature,
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: combined,
                profiles: [:],
                subshapes: SubshapeIndex(subshapes),
                lineage: lineage,
                tolerance: .standard
            )
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.vertices.values.allSatisfy { abs($0.point.z - 0.100) <= 1.0e-12 })
        let faceLineage = try #require(result.lineage.values.first { $0.output.role == "face" })
        #expect(faceLineage.relation == .merged)
        #expect(faceLineage.parents.count == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func consumesSourceAndTargetWhilePreservingUnrelatedSheetIdentity() throws {
        let sourceID = FeatureID()
        let targetID = FeatureID()
        let unrelatedID = FeatureID()
        let source = try PlanarSheetTestFixture.make(featureID: sourceID, tolerance: .standard)
        var target = try PlanarSheetTestFixture.make(featureID: targetID, tolerance: .standard)
        let unrelated = try PlanarSheetTestFixture.make(featureID: unrelatedID, tolerance: .standard)
        let targetBodyID = try bodyID(featureID: targetID, subshapes: target.subshapes)
        for vertexID in target.brep.vertices.keys {
            guard var vertex = target.brep.vertices[vertexID] else {
                throw TopologyError.missingReference("Surface match target fixture vertex is missing.")
            }
            vertex.point = vertex.point + .unitZ * 0.100
            target.brep.vertices[vertexID] = vertex
        }
        try DefaultPlanarBodyGeometryRebuilder().rebuild(
            featureID: targetID,
            bodyID: targetBodyID,
            in: &target.brep,
            tolerance: .standard
        )
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &target.brep, tolerance: .standard)
        let fixture = try EvaluationFixtureCombiner.combine([
            (source.brep, source.subshapes, source.lineage),
            (target.brep, target.subshapes, target.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let result = try SurfaceMatchFeatureEvaluator().evaluate(
            feature: FeatureNode(
                id: FeatureID(),
                operation: .surfaceMatch(SurfaceMatchFeature(
                    source: SurfaceOperationTargetReference(featureID: sourceID),
                    target: SurfaceOperationTargetReference(featureID: targetID),
                    sourceParameter: SurfaceParameter(u: 0.0, v: 0.0),
                    targetParameter: SurfaceParameter(u: 0.0, v: 0.0),
                    continuity: .curvature
                )),
                inputs: [
                    FeatureInput(featureID: sourceID, role: .sheet),
                    FeatureInput(featureID: targetID, role: .target),
                ],
                outputs: [FeatureOutput(role: .sheet)]
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

        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.bodies.count == 2)
        #expect(result.removedSubshapeIDs.isDisjoint(with: unrelated.subshapes.entries.keys))
        #expect(unrelated.brep.bodies.keys.allSatisfy { result.brep.bodies[$0] == unrelated.brep.bodies[$0] })
    }

    private func bodyID(
        featureID: FeatureID,
        subshapes: SubshapeIndex
    ) throws -> BodyID {
        let subshapeID = SubshapeID(
            featureID: featureID,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        )
        guard case let .body(bodyID) = subshapes[subshapeID] else {
            throw TopologyError.missingReference("Surface match fixture body is missing.")
        }
        return bodyID
    }

    private func merged(_ first: BRepModel, _ second: BRepModel) -> BRepModel {
        var result = first
        result.geometry.curves.merge(second.geometry.curves) { _, value in value }
        result.geometry.surfaces.merge(second.geometry.surfaces) { _, value in value }
        result.bodies.merge(second.bodies) { _, value in value }
        result.shells.merge(second.shells) { _, value in value }
        result.faces.merge(second.faces) { _, value in value }
        result.loops.merge(second.loops) { _, value in value }
        result.edges.merge(second.edges) { _, value in value }
        result.vertices.merge(second.vertices) { _, value in value }
        return result
    }
}
