import CADCore
import CADIR
import CADModeling
import CADTopology
import Testing
@testable import CADKernel

@Suite("Coincident Boolean face ownership")
struct CoincidentBooleanFaceOwnershipResolverTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func sameOutwardFacesHaveDeterministicOperationOwnership() throws {
        let fixture = try fixture(reverseToolFace: false)
        let union = try actions(.union, fixture: fixture)
        let intersection = try actions(.intersect, fixture: fixture)
        let difference = try actions(.difference, fixture: fixture)

        #expect(union[fixture.targetFaceID] == .keep)
        #expect(union[fixture.toolFaceID] == .discard)
        #expect(intersection[fixture.targetFaceID] == .keep)
        #expect(intersection[fixture.toolFaceID] == .discard)
        #expect(difference[fixture.targetFaceID] == .discard)
        #expect(difference[fixture.toolFaceID] == .discard)
    }

    @Test(.timeLimit(.minutes(1)))
    func oppositeOutwardFacesRemoveSharedInterfaceForUnionAndIntersection() throws {
        let fixture = try fixture(reverseToolFace: true)
        let union = try actions(.union, fixture: fixture)
        let intersection = try actions(.intersect, fixture: fixture)
        let difference = try actions(.difference, fixture: fixture)

        #expect(union.values.allSatisfy { $0 == .discard })
        #expect(intersection.values.allSatisfy { $0 == .discard })
        #expect(difference[fixture.targetFaceID] == .keep)
        #expect(difference[fixture.toolFaceID] == .discard)
    }

    @Test(.timeLimit(.minutes(1)))
    func forcedOwnershipBypassesBoundaryPointClassificationWithoutDuplicatingFace() throws {
        let fixture = try fixture(reverseToolFace: false)
        let ownership = try actions(.union, fixture: fixture)
        let patches = try ClosedIntersectionUnsplitFaceMaterializer().patches(
            operation: .union,
            targetBodyIDs: [fixture.targetBodyID],
            toolBodyID: fixture.toolBodyID,
            splitFaceIDs: [],
            forcedActions: ownership,
            model: fixture.model,
            sourceSubshapes: fixture.sourceSubshapes,
            tolerance: tolerance
        )

        #expect(patches.count == 1)
        try #require(patches.first).validate(tolerance: tolerance)
    }

    private func actions(
        _ operation: BooleanOperation,
        fixture: Fixture
    ) throws -> [FaceID: BooleanRegionSelectionAction] {
        try CoincidentBooleanFaceOwnershipResolver().resolve(
            operation: operation,
            uvSplitGraph: BooleanUVSplitGraph(splits: [BooleanFaceSplit(
                facePair: BooleanFacePairCandidate(
                    targetFaceID: fixture.targetFaceID,
                    toolFaceID: fixture.toolFaceID
                ),
                components: [BooleanFaceSplitComponent(
                    id: BooleanFaceSplitComponentID(ordinal: 0),
                    geometry: .coincident
                )]
            )]),
            model: fixture.model,
            tolerance: tolerance
        ).forcedActions
    }

    private func fixture(reverseToolFace: Bool) throws -> Fixture {
        let target = try PlanarSheetTestFixture.make(
            featureID: FeatureID(),
            tolerance: tolerance
        )
        var tool = try PlanarSheetTestFixture.make(
            featureID: FeatureID(),
            tolerance: tolerance
        )
        let targetBodyID = try #require(target.brep.bodies.keys.first)
        let targetBody = try #require(target.brep.bodies[targetBodyID])
        let targetShell = try #require(target.brep.shells[targetBody.shellIDs[0]])
        let targetFaceID = targetShell.faceIDs[0]
        let toolBodyID = try #require(tool.brep.bodies.keys.first)
        let toolBody = try #require(tool.brep.bodies[toolBodyID])
        let toolShell = try #require(tool.brep.shells[toolBody.shellIDs[0]])
        let toolFaceID = toolShell.faceIDs[0]
        if reverseToolFace {
            var face = try #require(tool.brep.faces[toolFaceID])
            face.orientation = .reversed
            tool.brep.faces[toolFaceID] = face
        }
        let model = try BRepModelCombiner().combined([target.brep, tool.brep])
        return Fixture(
            model: model,
            targetBodyID: targetBodyID,
            toolBodyID: toolBodyID,
            targetFaceID: targetFaceID,
            toolFaceID: toolFaceID,
            sourceSubshapes: target.subshapes.entries.merging(tool.subshapes.entries) {
                current, _ in current
            }
        )
    }

    private struct Fixture {
        let model: BRepModel
        let targetBodyID: BodyID
        let toolBodyID: BodyID
        let targetFaceID: FaceID
        let toolFaceID: FaceID
        let sourceSubshapes: [SubshapeID: TopologyReference]
    }
}
