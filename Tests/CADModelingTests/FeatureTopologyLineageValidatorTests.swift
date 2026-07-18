import Testing
import CADCore
import CADIR
import CADTopology
@testable import CADModeling

@Suite("Feature topology lineage validator")
struct FeatureTopologyLineageValidatorTests {
    @Test
    func rejectsMissingOutputLineage() {
        let output = SubshapeID(featureID: FeatureID(), role: "body", ordinal: 0)
        let result = EvaluationResult(
            brep: BRepModel(),
            subshapes: [output: .body(BodyID())]
        )

        #expect(throws: KernelError.self) {
            try FeatureTopologyLineageValidator().validate(result)
        }
    }

    @Test
    func rejectsOutputOwnedByDifferentFeature() {
        let featureID = FeatureID()
        let output = SubshapeID(featureID: FeatureID(), role: "body", ordinal: 0)
        let result = EvaluationResult(
            brep: BRepModel(),
            subshapes: [output: .body(BodyID())],
            lineage: [
                output: TopologyLineage(output: output, relation: .generated),
            ]
        )

        #expect(throws: KernelError.self) {
            try FeatureTopologyLineageValidator().validate(
                result,
                featureID: featureID
            )
        }
    }

    @Test
    func requiresMultipleOutputsForSplitParent() {
        let parent = SubshapeID(featureID: FeatureID(), role: "face", ordinal: 0)
        let output = SubshapeID(featureID: FeatureID(), role: "face", ordinal: 0)
        let result = EvaluationResult(
            brep: BRepModel(),
            subshapes: [output: .face(FaceID())],
            lineage: [
                output: TopologyLineage(output: output, parents: [parent], relation: .split),
            ]
        )

        #expect(throws: KernelError.self) {
            try FeatureTopologyLineageValidator().validate(result)
        }
    }

    @Test
    func acceptsCompleteSplitCoverage() throws {
        let parent = SubshapeID(featureID: FeatureID(), role: "face", ordinal: 0)
        let first = SubshapeID(featureID: FeatureID(), role: "face", ordinal: 0)
        let second = SubshapeID(featureID: FeatureID(), role: "face", ordinal: 1)
        let result = EvaluationResult(
            brep: BRepModel(),
            subshapes: [
                first: .face(FaceID()),
                second: .face(FaceID()),
            ],
            lineage: [
                first: TopologyLineage(output: first, parents: [parent], relation: .split),
                second: TopologyLineage(output: second, parents: [parent], relation: .split),
            ]
        )

        try FeatureTopologyLineageValidator().validate(result)
    }

    @Test
    func acceptsSplitParentAlsoConsumedByMergedOutput() throws {
        let splitParent = SubshapeID(featureID: FeatureID(), role: "face", ordinal: 0)
        let mergedParent = SubshapeID(featureID: FeatureID(), role: "face", ordinal: 1)
        let splitOutput = SubshapeID(featureID: FeatureID(), role: "face", ordinal: 0)
        let mergedOutput = SubshapeID(featureID: splitOutput.featureID, role: "face", ordinal: 1)
        let result = EvaluationResult(
            brep: BRepModel(),
            subshapes: [
                splitOutput: .face(FaceID()),
                mergedOutput: .face(FaceID()),
            ],
            lineage: [
                splitOutput: TopologyLineage(
                    output: splitOutput,
                    parents: [splitParent],
                    relation: .split
                ),
                mergedOutput: TopologyLineage(
                    output: mergedOutput,
                    parents: [mergedParent, splitParent].sorted(),
                    relation: .merged
                ),
            ]
        )

        try FeatureTopologyLineageValidator().validate(result)
    }
}
