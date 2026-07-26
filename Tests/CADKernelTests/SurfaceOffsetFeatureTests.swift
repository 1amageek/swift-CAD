import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@Suite("Exact surface offset")
struct SurfaceOffsetFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func offsetsPlanarSheetAndPreservesTopologyLineage() throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let source = try planarSheet(featureID: sourceID)
        let feature = FeatureNode(
            id: featureID,
            operation: .surfaceOffset(SurfaceOffsetFeature(
                target: try surfaceOperationTarget(
                    featureID: sourceID,
                    model: source.brep,
                    subshapes: source.subshapes
                ),
                distance: .constant(.length(0.005, unit: .meter))
            )),
            inputs: [FeatureInput(featureID: sourceID, role: .target)],
            outputs: [FeatureOutput(role: .sheet)]
        )
        let result = try SurfaceOffsetFeatureEvaluator().evaluate(
            feature: feature,
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: source.brep,
                profiles: [:],
                subshapes: source.subshapes,
                lineage: source.lineage,
                tolerance: .standard
            )
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.faces.count == 1)
        #expect(result.brep.edges.count == 4)
        #expect(result.brep.vertices.count == 4)
        #expect(result.brep.vertices.values.allSatisfy { abs($0.point.z - 0.005) <= 1.0e-12 })
        let outputLineage = result.lineage.values.filter { $0.output.featureID == featureID }
        #expect(outputLineage.count == 10)
        #expect(outputLineage.allSatisfy { $0.relation == .preserved })
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesUnrelatedSheetAndSelectionIdentity() throws {
        let sourceID = FeatureID()
        let unrelatedID = FeatureID()
        let source = try PlanarSheetTestFixture.make(featureID: sourceID, tolerance: .standard)
        let unrelated = try PlanarSheetTestFixture.make(featureID: unrelatedID, tolerance: .standard)
        let fixture = try EvaluationFixtureCombiner.combine([
            (source.brep, source.subshapes, source.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let result = try SurfaceOffsetFeatureEvaluator().evaluate(
            feature: FeatureNode(
                id: FeatureID(),
                operation: .surfaceOffset(SurfaceOffsetFeature(
                    target: try surfaceOperationTarget(
                        featureID: sourceID,
                        model: fixture.brep,
                        subshapes: fixture.subshapes
                    ),
                    distance: .constant(.length(0.005, unit: .meter))
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
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

    @Test(.timeLimit(.minutes(1)))
    func rejectsSelectedFaceOwnedByAnotherBody() throws {
        let sourceID = FeatureID()
        let unrelatedID = FeatureID()
        let featureID = FeatureID()
        let source = try PlanarSheetTestFixture.make(
            featureID: sourceID,
            tolerance: .standard
        )
        let unrelated = try PlanarSheetTestFixture.make(
            featureID: unrelatedID,
            tolerance: .standard
        )
        let fixture = try EvaluationFixtureCombiner.combine([
            (source.brep, source.subshapes, source.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let unrelatedTarget = try surfaceOperationTarget(
            featureID: unrelatedID,
            model: fixture.brep,
            subshapes: fixture.subshapes
        )
        let mismatchedTarget = SurfaceOperationTargetReference(
            featureID: sourceID,
            face: unrelatedTarget.face
        )

        do {
            _ = try SurfaceOffsetFeatureEvaluator().evaluate(
                feature: FeatureNode(
                    id: featureID,
                    operation: .surfaceOffset(SurfaceOffsetFeature(
                        target: mismatchedTarget,
                        distance: .constant(.length(0.005, unit: .meter))
                    )),
                    inputs: [
                        FeatureInput(featureID: sourceID, role: .target),
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
            Issue.record(
                "A selected face owned by another body must not be accepted."
            )
        } catch let error as KernelError {
            #expect(error.code == .missingReference)
            #expect(error.featureID == featureID)
        }
    }

    private func planarSheet(
        featureID: FeatureID
    ) throws -> (brep: BRepModel, subshapes: SubshapeIndex, lineage: [SubshapeID: TopologyLineage]) {
        let points = [
            Point3D(x: -0.020, y: -0.010, z: 0.0),
            Point3D(x: 0.020, y: -0.010, z: 0.0),
            Point3D(x: 0.020, y: 0.010, z: 0.0),
            Point3D(x: -0.020, y: 0.010, z: 0.0),
        ]
        let surface = Surface3D.plane(Plane3D(origin: points[0], normal: .unitZ))
        let edges = try points.indices.map { index in
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let delta = end - start
            let startUV = try surface.parameterProjection(of: start, tolerance: .standard)
            let endUV = try surface.parameterProjection(of: end, tolerance: .standard)
            return BRepSewingEdge(
                stableID: "surfaceOffsetSource:edge:\(index)",
                curve: .line(Line3D(origin: start, direction: try delta.normalized(tolerance: 1.0e-9))),
                startParameter: 0.0,
                endParameter: delta.length,
                startPoint: start,
                endPoint: end,
                surfaceParameterCurve: .polyline([
                    SurfaceParameter(u: startUV.u, v: startUV.v),
                    SurfaceParameter(u: endUV.u, v: endUV.v),
                ])
            )
        }
        let sewn = try DefaultBRepSewer().sew(BRepSewingRequest(
            featureID: featureID,
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "surfaceOffsetSource:shell",
                patches: [BRepSewingFacePatch(
                    stableID: "surfaceOffsetSource:face",
                    surface: surface,
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "surfaceOffsetSource:outer",
                        role: .outer,
                        edges: edges
                    )]
                )]
            )]
        ), tolerance: .standard)
        return (sewn.brep, SubshapeIndex(sewn.subshapes), sewn.lineage)
    }
}
