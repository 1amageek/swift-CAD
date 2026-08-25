import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import XCTest
@testable import CADKernel

final class OffsetSurfaceParameterCurveImageIntegrationTests: XCTestCase {
    func testSurfaceOffsetEvaluatorOwnsOffsetPcurveImageCreation() throws {
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
        let sourceFace = try XCTUnwrap(source.brep.faces.values.first)
        let sourceSurface = try XCTUnwrap(
            source.brep.geometry.surfaces[sourceFace.surfaceID]
        )
        let targetFace = try XCTUnwrap(result.brep.faces.values.first)
        let targetSurface = try XCTUnwrap(
            result.brep.geometry.surfaces[targetFace.surfaceID]
        )

        var imageCount = 0
        for loop in result.brep.loops.values {
            for coedge in loop.coedges {
                guard case let .offsetSurfaceImage(image) = coedge.surfaceParameterCurve else {
                    XCTFail("Surface offset coedges must use offset-owned pcurve images.")
                    continue
                }
                imageCount += 1
                XCTAssertEqual(image.sourceSurface, sourceSurface)
                XCTAssertEqual(
                    try image.targetSurface(tolerance: .standard),
                    targetSurface
                )
                try image.validate(on: targetSurface, tolerance: .standard)
            }
        }
        XCTAssertEqual(imageCount, 4)
    }
}
