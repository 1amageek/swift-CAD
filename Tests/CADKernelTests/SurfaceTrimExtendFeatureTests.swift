import Testing
import CADCore
import CADIR
import CADModeling
@testable import CADKernel

@Suite("Exact surface trim and extend")
struct SurfaceTrimExtendFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func trimsRectangularPlanarSheetToContainedUVDomains() throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let source = try PlanarSheetTestFixture.make(featureID: sourceID, tolerance: .standard)
        let result = try SurfaceTrimFeatureEvaluator().evaluate(
            feature: FeatureNode(
                id: featureID,
                operation: .surfaceTrim(SurfaceTrimFeature(
                    target: SurfaceOperationTargetReference(featureID: sourceID),
                    uDomain: .closed(-0.010, 0.010),
                    vDomain: .closed(-0.005, 0.005)
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
            context: context(source)
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        let points = result.brep.vertices.values.map(\.point)
        #expect(abs((try #require(points.map(\.x).max())) - 0.010) <= 1.0e-12)
        #expect(abs((try #require(points.map(\.x).min())) + 0.010) <= 1.0e-12)
        #expect(abs((try #require(points.map(\.y).max())) - 0.005) <= 1.0e-12)
        #expect(abs((try #require(points.map(\.y).min())) + 0.005) <= 1.0e-12)
        #expect(result.lineage.values.allSatisfy { $0.relation == .preserved })
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesUnrelatedSheetAcrossTrimAndExtend() throws {
        let sourceID = FeatureID()
        let unrelatedID = FeatureID()
        let source = try PlanarSheetTestFixture.make(featureID: sourceID, tolerance: .standard)
        let unrelated = try PlanarSheetTestFixture.make(featureID: unrelatedID, tolerance: .standard)
        let fixture = try EvaluationFixtureCombiner.combine([
            (source.brep, source.subshapes, source.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let evaluationContext = EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: fixture.brep,
            profiles: [:],
            subshapes: fixture.subshapes,
            lineage: fixture.lineage,
            tolerance: .standard
        )
        let trimResult = try SurfaceTrimFeatureEvaluator().evaluate(
            feature: FeatureNode(
                id: FeatureID(),
                operation: .surfaceTrim(SurfaceTrimFeature(
                    target: SurfaceOperationTargetReference(featureID: sourceID),
                    uDomain: .closed(-0.010, 0.010),
                    vDomain: .closed(-0.005, 0.005)
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
            context: evaluationContext
        )
        let extendResult = try SurfaceExtendFeatureEvaluator().evaluate(
            feature: FeatureNode(
                id: FeatureID(),
                operation: .surfaceExtend(SurfaceExtendFeature(
                    target: SurfaceOperationTargetReference(featureID: sourceID),
                    distances: SurfaceExtensionDistances(
                        lowerU: .constant(.length(0.005, unit: .meter)),
                        upperU: .constant(.length(0.005, unit: .meter)),
                        lowerV: .constant(.length(0.005, unit: .meter)),
                        upperV: .constant(.length(0.005, unit: .meter))
                    )
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
            context: evaluationContext
        )

        for result in [trimResult, extendResult] {
            try result.brep.validate(level: .exact, tolerance: .standard)
            #expect(result.brep.bodies.count == 2)
            #expect(result.removedSubshapeIDs.isDisjoint(with: unrelated.subshapes.entries.keys))
            #expect(unrelated.brep.bodies.keys.allSatisfy { result.brep.bodies[$0] == unrelated.brep.bodies[$0] })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func extendsEveryPlanarSheetSideByPhysicalDistance() throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let source = try PlanarSheetTestFixture.make(featureID: sourceID, tolerance: .standard)
        let result = try SurfaceExtendFeatureEvaluator().evaluate(
            feature: FeatureNode(
                id: featureID,
                operation: .surfaceExtend(SurfaceExtendFeature(
                    target: SurfaceOperationTargetReference(featureID: sourceID),
                    distances: SurfaceExtensionDistances(
                        lowerU: .constant(.length(0.005, unit: .meter)),
                        upperU: .constant(.length(0.005, unit: .meter)),
                        lowerV: .constant(.length(0.005, unit: .meter)),
                        upperV: .constant(.length(0.005, unit: .meter))
                    )
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
            context: context(source)
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        let points = result.brep.vertices.values.map(\.point)
        #expect(abs((try #require(points.map(\.x).max())) - 0.025) <= 1.0e-12)
        #expect(abs((try #require(points.map(\.x).min())) + 0.025) <= 1.0e-12)
        #expect(abs((try #require(points.map(\.y).max())) - 0.015) <= 1.0e-12)
        #expect(abs((try #require(points.map(\.y).min())) + 0.015) <= 1.0e-12)
        #expect(result.lineage.values.allSatisfy { $0.relation == .preserved })
    }

    private func context(_ fixture: PlanarSheetTestFixture) -> EvaluationContext {
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
