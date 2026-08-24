import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive sphere Boolean integration")
struct PrimitiveSphereBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func offsetSphereIntersectionProducesValidatedExactLens() throws {
        let result = try evaluate(operation: .intersect)
        try assertExactResult(
            result,
            expectedVolume: 56.0 * Double.pi / 3.0
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func offsetSphereDifferenceProducesValidatedExactRemainder() throws {
        let result = try evaluate(operation: .difference)
        try assertExactResult(
            result,
            expectedVolume: 52.0 * Double.pi / 3.0
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func offsetSphereUnionProducesValidatedExactMergedBody() throws {
        let result = try evaluate(operation: .union)
        try assertExactResult(
            result,
            expectedVolume: 160.0 * Double.pi / 3.0
        )
    }

    @Test(.timeLimit(.minutes(2)))
    func offsetSphereSliceProducesExactComplementaryComponents() throws {
        let result = try evaluate(operation: .slice)

        try result.document.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.document.brep.bodies.count == 1)
        #expect(result.document.brep.shells.count == 2)
        let volume = try result.document.brep.volume(tolerance: .standard)
        let expectedTargetVolume = 36.0 * Double.pi
        #expect(abs(volume - expectedTargetVolume) <= 1.0e-8)
        let booleanLineage = result.document.lineage.values.filter {
            $0.output.featureID == result.featureID
        }
        #expect(booleanLineage.isEmpty == false)
        #expect(booleanLineage.contains { $0.relation == .split })
    }

    @Test(.timeLimit(.minutes(2)))
    func offsetSphereSlicePreflightUsesGeneralExactResult() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let firstSphereID = try builder.sphere(
            radius: length(3.0),
            named: "First sphere"
        )
        let secondSphereID = try builder.sphere(
            placement: PrimitivePlacement(
                origin: Point3D(x: 2.0, y: 0.0, z: 0.0),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            radius: length(3.0),
            named: "Second sphere"
        )

        let plan = try BooleanEvaluationPlanService().plan(
            document: builder.build(name: "Sphere slice preflight"),
            targets: [BooleanTargetReference(featureID: firstSphereID)],
            tool: BooleanToolReference(featureID: secondSphereID),
            operation: .slice,
            keepTools: false,
            tolerance: .standard
        )

        #expect(plan.status == .supported)
        #expect(plan.operandKind == .generalExactBRepSolids)
        #expect(plan.outputTopologyKind == .generalExactBRepResult)
        #expect(plan.resultTopologyCounts?.bodyCount == 1)
        #expect(plan.resultTopologyCounts?.shellCount == 2)
        #expect(plan.unsupportedCode == nil)
        #expect(plan.checks.allSatisfy { $0.status == .passed })
    }

    @Test(.timeLimit(.minutes(2)))
    func separatedSphereSliceCarriesTheUncutTargetComponent() throws {
        let result = try evaluateSlice(
            toolOrigin: Point3D(x: 8.0, y: 0.0, z: 0.0),
            toolRadius: 3.0
        )

        try result.document.brep.validate(level: .exact, tolerance: .standard)
        let body = try #require(result.document.brep.bodies.values.first)
        #expect(result.document.brep.bodies.count == 1)
        #expect(body.solidComponents?.count == 1)
        #expect(result.document.brep.shells.count == 1)
        #expect(abs(
            try result.document.brep.volume(tolerance: .standard) - 36.0 * Double.pi
        ) <= 1.0e-8)
    }

    @Test(.timeLimit(.minutes(2)))
    func containedSphereSliceProducesCavityAndContainedComponent() throws {
        let result = try evaluateSlice(
            toolOrigin: .origin,
            toolRadius: 1.0
        )

        try result.document.brep.validate(level: .exact, tolerance: .standard)
        let body = try #require(result.document.brep.bodies.values.first)
        let components = try #require(body.solidComponents)
        #expect(result.document.brep.bodies.count == 1)
        #expect(components.count == 2)
        #expect(components.map(\.voidShellIDs.count).sorted() == [0, 1])
        #expect(result.document.brep.shells.count == 3)
        #expect(abs(
            try result.document.brep.volume(tolerance: .standard) - 36.0 * Double.pi
        ) <= 1.0e-8)
    }

    @Test(.timeLimit(.minutes(1)))
    func separatedSphereUnionProducesExactTwoComponentBody() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let firstSphereID = try builder.sphere(
            radius: length(3.0),
            named: "First sphere"
        )
        let secondSphereID = try builder.sphere(
            placement: PrimitivePlacement(
                origin: Point3D(x: 8.0, y: 0.0, z: 0.0),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            radius: length(3.0),
            named: "Second sphere"
        )
        let booleanID = try builder.boolean(
            targets: [firstSphereID],
            tool: secondSphereID,
            operation: .union,
            named: "Separated sphere union"
        )
        let evaluated = try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(builder.build(name: "Separated sphere Boolean"))

        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 2)
        #expect(abs(
            try evaluated.brep.volume(tolerance: .standard) - 72.0 * Double.pi
        ) <= 1.0e-8)
        let lineage = evaluated.lineage.values.filter {
            $0.output.featureID == booleanID
        }
        #expect(lineage.isEmpty == false)
        #expect(Set(lineage.flatMap(\.parents).map(\.featureID)) == Set([
            firstSphereID,
            secondSphereID,
        ]))
    }

    private func evaluate(
        operation: BooleanOperation
    ) throws -> (document: EvaluatedDocument, featureID: FeatureID) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let firstSphereID = try builder.sphere(
            radius: length(3.0),
            named: "First sphere"
        )
        let secondSphereID = try builder.sphere(
            placement: PrimitivePlacement(
                origin: Point3D(x: 2.0, y: 0.0, z: 0.0),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            radius: length(3.0),
            named: "Second sphere"
        )
        let booleanID = try builder.boolean(
            targets: [firstSphereID],
            tool: secondSphereID,
            operation: operation,
            named: "Exact sphere Boolean"
        )
        let document = try builder.build(name: "Sphere Boolean")
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)

        return (evaluated, booleanID)
    }

    private func evaluateSlice(
        toolOrigin: Point3D,
        toolRadius: Double
    ) throws -> (document: EvaluatedDocument, featureID: FeatureID) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let targetID = try builder.sphere(
            radius: length(3.0),
            named: "Target sphere"
        )
        let toolID = try builder.sphere(
            placement: PrimitivePlacement(
                origin: toolOrigin,
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            radius: length(toolRadius),
            named: "Tool sphere"
        )
        let booleanID = try builder.boolean(
            targets: [targetID],
            tool: toolID,
            operation: .slice,
            named: "Exact sphere slice"
        )
        let document = try builder.build(name: "Sphere slice")
        let evaluated = try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(document)
        return (evaluated, booleanID)
    }

    private func assertExactResult(
        _ result: (document: EvaluatedDocument, featureID: FeatureID),
        expectedVolume: Double
    ) throws {
        try result.document.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.document.brep.bodies.count == 1)
        let volume = try result.document.brep.volume(tolerance: .standard)
        let volumeTolerance = ModelingTolerance.standard.distance * 3.0 * 3.0 * 16.0
        #expect(abs(volume - expectedVolume) <= volumeTolerance)
        let booleanLineage = result.document.lineage.values.filter {
            $0.output.featureID == result.featureID
        }
        #expect(booleanLineage.isEmpty == false)
        #expect(booleanLineage.contains { $0.parents.isEmpty == false })
    }

    private func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }
}
