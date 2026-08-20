import CADCore
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel
import Testing

@Suite("Whole-body exact Boolean materialization")
struct WholeBodyBooleanFacePatchMaterializerTests {
    @Test(.timeLimit(.minutes(1)))
    func containedBoxDifferenceAssignsTheVoidShellToItsOwningOuterShell() throws {
        let target = try evaluatedBox(
            origin: .origin,
            width: 3.0,
            depth: 3.0,
            height: 3.0
        )
        let tool = try evaluatedBox(
            origin: Point3D(x: 1.0, y: 1.0, z: 1.0),
            width: 1.0,
            depth: 1.0,
            height: 1.0
        )
        let fixture = try fixture(target: target, tool: tool)

        let result = try evaluate(.difference, fixture: fixture)

        try result.brep.validate(level: .volumetric, tolerance: .standard)
        let body = try #require(result.brep.bodies.values.first)
        guard case let .solid(components) = body.topology else {
            Issue.record("A contained box difference must remain a solid body.")
            return
        }
        #expect(components.count == 1)
        let component = try #require(components.first)
        #expect(component.outerShellID == body.shellIDs.first)
        #expect(component.voidShellIDs.count == 1)
        let voidShellID = try #require(component.voidShellIDs.first)
        #expect(result.brep.shells[voidShellID]?.orientation == .reversed)
        #expect(abs(try result.brep.volume(tolerance: .standard) - 26.0) <= 1.0e-10)
    }

    @Test(.timeLimit(.minutes(1)))
    func containedSphereDifferenceCreatesValidatedReversedCavityShell() throws {
        let fixture = try fixture(
            targetCenter: .origin,
            targetRadius: 3.0,
            toolCenter: .origin,
            toolRadius: 1.0
        )
        let result = try evaluate(.difference, fixture: fixture)

        try result.brep.validate(level: .exact, tolerance: .standard)
        let body = try #require(result.brep.bodies.values.first)
        let orientations = try body.shellIDs.map { shellID in
            try #require(result.brep.shells[shellID]).orientation
        }
        #expect(result.brep.bodies.count == 1)
        #expect(body.shellIDs.count == 2)
        #expect(orientations.count { $0 == .forward } == 1)
        #expect(orientations.count { $0 == .reversed } == 1)
        let expected = 4.0 * Double.pi * (27.0 - 1.0) / 3.0
        #expect(abs(try result.brep.volume(tolerance: .standard) - expected) <= 1.0e-8)
        #expect(result.lineage.values.contains { !$0.parents.isEmpty })
    }

    @Test(.timeLimit(.minutes(1)))
    func containedSphereIntersectionCarriesExactInnerBody() throws {
        let fixture = try fixture(
            targetCenter: .origin,
            targetRadius: 3.0,
            toolCenter: .origin,
            toolRadius: 1.0
        )
        let result = try evaluate(.intersect, fixture: fixture)

        try result.brep.validate(level: .exact, tolerance: .standard)
        let expected = 4.0 * Double.pi / 3.0
        #expect(result.brep.bodies.count == 1)
        #expect(abs(try result.brep.volume(tolerance: .standard) - expected) <= 1.0e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func disjointSphereDifferenceCarriesTargetAndIntersectionIsTypedEmpty() throws {
        let fixture = try fixture(
            targetCenter: .origin,
            targetRadius: 1.0,
            toolCenter: Point3D(x: 4.0, y: 0.0, z: 0.0),
            toolRadius: 1.0
        )
        let difference = try evaluate(.difference, fixture: fixture)
        try difference.brep.validate(level: .exact, tolerance: .standard)
        #expect(abs(
            try difference.brep.volume(tolerance: .standard) - 4.0 * Double.pi / 3.0
        ) <= 1.0e-9)

        do {
            _ = try evaluate(.intersect, fixture: fixture)
            Issue.record("Disjoint exact solids must not produce a successful intersection body.")
        } catch let error as KernelError {
            #expect(error.code == .emptyResult)
            #expect(error.phase == .classification)
        }
    }

    private func evaluate(
        _ operation: BooleanOperation,
        fixture: Fixture
    ) throws -> EvaluationResult {
        try BooleanPipeline(evaluator: ExactBRepBooleanEvaluator()).evaluate(
            operation: operation,
            targetBodyIDs: [fixture.targetBodyID],
            toolBodyID: fixture.toolBodyID,
            keepTools: false,
            featureID: FeatureID(),
            model: fixture.model,
            subshapes: fixture.target.subshapes.entries,
            toolSubshapes: fixture.tool.subshapes.entries,
            inputLineage: fixture.target.lineage.merging(fixture.tool.lineage) {
                current, _ in current
            },
            tolerance: .standard
        )
    }

    private func fixture(
        targetCenter: Point3D,
        targetRadius: Double,
        toolCenter: Point3D,
        toolRadius: Double
    ) throws -> Fixture {
        let target = try evaluatedSphere(center: targetCenter, radius: targetRadius)
        let tool = try evaluatedSphere(center: toolCenter, radius: toolRadius)
        return try fixture(target: target, tool: tool)
    }

    private func fixture(
        target: EvaluatedDocument,
        tool: EvaluatedDocument
    ) throws -> Fixture {
        let targetBodyID = try #require(target.brep.bodies.keys.first)
        let toolBodyID = try #require(tool.brep.bodies.keys.first)
        let model = try BRepModelCombiner().combined([target.brep, tool.brep])
        try model.validate(level: .exact, tolerance: .standard)
        return Fixture(
            target: target,
            tool: tool,
            model: model,
            targetBodyID: targetBodyID,
            toolBodyID: toolBodyID
        )
    }

    private func evaluatedBox(
        origin: Point3D,
        width: Double,
        depth: Double,
        height: Double
    ) throws -> EvaluatedDocument {
        try evaluatedPrimitive(.box(BoxPrimitive(
            placement: PrimitivePlacement(
                origin: origin,
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            width: .constant(.length(width, unit: .meter)),
            depth: .constant(.length(depth, unit: .meter)),
            height: .constant(.length(height, unit: .meter))
        )))
    }

    private func evaluatedSphere(
        center: Point3D,
        radius: Double
    ) throws -> EvaluatedDocument {
        try evaluatedPrimitive(.sphere(SpherePrimitive(
                placement: PrimitivePlacement(
                    origin: center,
                    axis: .unitZ,
                    referenceDirection: .unitX
                ),
                radius: .constant(.length(radius, unit: .meter))
            )))
    }

    private func evaluatedPrimitive(
        _ definition: PrimitiveDefinition
    ) throws -> EvaluatedDocument {
        let featureID = FeatureID()
        let operation = FeatureOperation.primitive(PrimitiveFeature(definition: definition))
        var document = CADDocument(units: .meters)
        let node = try FeatureNodeFactory.make(
            operation: operation,
            id: featureID,
            name: nil,
            in: document,
            tolerance: .standard
        )
        document.designGraph.nodes[featureID] = node
        document.designGraph.order = [featureID]
        document.designGraph.revision = document.designGraph.revision.advanced()
        return try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(document)
    }

    private struct Fixture {
        let target: EvaluatedDocument
        let tool: EvaluatedDocument
        let model: BRepModel
        let targetBodyID: BodyID
        let toolBodyID: BodyID
    }
}
