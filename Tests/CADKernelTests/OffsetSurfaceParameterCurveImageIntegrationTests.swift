import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Testing
@testable import CADKernel

@Suite struct OffsetSurfaceParameterCurveImageIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func surfaceOffsetEvaluatorOwnsOffsetPcurveImageCreation() throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let source = try PlanarSheetTestFixture.make(
            featureID: sourceID,
            tolerance: .standard
        )
        let target = try surfaceOperationTarget(
            featureID: sourceID,
            fixture: source
        )
        let result = try SurfaceOffsetFeatureEvaluator().evaluate(
            feature: FeatureNode(
                id: featureID,
                operation: .surfaceOffset(SurfaceOffsetFeature(
                    target: target,
                    distance: .constant(.length(0.005, unit: .meter))
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
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
        let sourceFace = try #require(source.brep.faces.values.first)
        let sourceSurface = try #require(source.brep.geometry.surfaces[sourceFace.surfaceID])
        let targetFace = try #require(result.brep.faces.values.first)
        let targetSurface = try #require(result.brep.geometry.surfaces[targetFace.surfaceID])

        var imageCount = 0
        for loop in result.brep.loops.values {
            for coedge in loop.coedges {
                guard case let .offsetSurfaceImage(image) = coedge.surfaceParameterCurve else {
                    Issue.record("Surface offset coedges must use offset-owned pcurve images.")
                    continue
                }
                imageCount += 1
                #expect(image.sourceSurface == sourceSurface)
                #expect(try image.targetSurface(tolerance: .standard) == targetSurface)
                try image.validate(on: targetSurface, tolerance: .standard)
            }
        }
        #expect(imageCount == 4)
    }
}
