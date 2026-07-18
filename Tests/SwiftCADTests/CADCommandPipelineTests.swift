import Foundation
import CADCore
import CADIR
import CADKernel
import SwiftCAD
import Testing

struct CADCommandPipelineTests {
    @Test
    func pipelineExposesSharedCapabilitiesAndQueries() throws {
        let pipeline = CADPipeline(tolerance: .standard)
        let catalog = pipeline.capabilities()
        try catalog.validate()
        #expect(catalog.capability(id: "API-PARITY-001") != nil)

        let curve = CurveOutputReference(featureID: FeatureID())
        let selection = SelectionReference.curve(.parameter(CurveParameterReference(
            curve: curve,
            parameter: 0.5
        )))
        let queries: [KernelQuery] = [
            .lineage(SubshapeID(featureID: FeatureID(), role: "face", ordinal: 0)),
            .snap(SnapQueryRequest(point: .origin)),
            .measurement(MeasurementQuery(kind: .point, first: selection)),
            .selectionDimensionEvaluation(SelectionDimensionEvaluationQuery()),
        ]
        for query in queries {
            let encoded = try JSONEncoder().encode(query)
            #expect(try JSONDecoder().decode(KernelQuery.self, from: encoded) == query)
        }
    }

    @Test
    func builderUsesDocumentEditorForFeatureInsertion() throws {
        let document = try CADDocument.millimeters(tolerance: .standard, named: "Command path") { builder in
            let profile = try builder.sketch(on: .xy) { sketch in
                sketch.rectangle(
                    width: .constant(.length(10.0, unit: .millimeter)),
                    height: .constant(.length(5.0, unit: .millimeter))
                )
            }
            try builder.extrude(
                profile,
                distance: .constant(.length(2.0, unit: .millimeter))
            )
        }
        #expect(document.designGraph.order.count == 2)
        #expect(document.designGraph.dependencies.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceIdenticalConicalDifference() throws {
        try assertBuilderAndCodableCommandParity(operation: .difference)
    }

    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceIdenticalConicalIntersection() throws {
        try assertBuilderAndCodableCommandParity(operation: .intersect)
    }

    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceIdenticalConicalUnion() throws {
        try assertBuilderAndCodableCommandParity(operation: .union)
    }

    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceIdenticalContainedConicalUnion() throws {
        try assertBuilderAndCodableCommandParity(
            operation: .union,
            lowerRadius: 0.0048,
            lowerCoordinate: 0.002,
            upperRadius: 0.0036,
            upperCoordinate: 0.008
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceIdenticalContainedConicalDifference() throws {
        try assertBuilderAndCodableCommandParity(
            operation: .difference,
            lowerRadius: 0.0048,
            lowerCoordinate: 0.002,
            upperRadius: 0.0036,
            upperCoordinate: 0.008
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceIdenticalUpperBlindConicalDifference() throws {
        try assertBuilderAndCodableCommandParity(
            operation: .difference,
            lowerRadius: 0.0048,
            lowerCoordinate: 0.004,
            upperRadius: 0.0032,
            upperCoordinate: 0.012
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceIdenticalPartialConicalIntersection() throws {
        try assertBuilderAndCodableCommandParity(
            operation: .intersect,
            lowerRadius: 0.0048,
            lowerCoordinate: 0.004,
            upperRadius: 0.0032,
            upperCoordinate: 0.012
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceIdenticalTargetContainedConicalUnion() throws {
        try assertBuilderAndCodableCommandParity(
            operation: .union,
            targetSize: 0.004
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceIdenticalAxiallySeparatedConicalDifference() throws {
        try assertBuilderAndCodableCommandParity(
            operation: .difference,
            lowerRadius: 0.005,
            lowerCoordinate: 0.020,
            upperRadius: 0.004,
            upperCoordinate: 0.030
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceIdenticalRadiallySeparatedConicalDifference() throws {
        try assertBuilderAndCodableCommandParity(
            operation: .difference,
            toolAxisOffsetX: 0.050
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceIdenticalTangentialRevolvedDifference() throws {
        try assertBuilderAndCodableCommandParity(
            operation: .difference,
            toolAxisOffsetX: 0.018,
            lowerRadius: 0.006,
            upperRadius: 0.006
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceIdenticalSideCrossingCylindricalDifference() throws {
        try assertBuilderAndCodableCommandParity(
            operation: .difference,
            toolAxisOffsetX: 0.009,
            lowerRadius: 0.006,
            lowerCoordinate: 0.0,
            upperRadius: 0.006,
            upperCoordinate: 0.010
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceIdenticalOutsideAxisCylindricalDifference() throws {
        try assertBuilderAndCodableCommandParity(
            operation: .difference,
            toolAxisOffsetX: 0.015,
            lowerRadius: 0.006,
            lowerCoordinate: 0.0,
            upperRadius: 0.006,
            upperCoordinate: 0.010
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceIdenticalCornerCylindricalDifference() throws {
        try assertBuilderAndCodableCommandParity(
            operation: .difference,
            toolAxisOffsetX: 0.015,
            toolAxisOffsetZ: 0.015,
            lowerRadius: 0.006,
            lowerCoordinate: 0.0,
            upperRadius: 0.006,
            upperCoordinate: 0.010
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceIdenticalInsideCornerCylindricalDifference() throws {
        try assertBuilderAndCodableCommandParity(
            operation: .difference,
            toolAxisOffsetX: 0.009,
            toolAxisOffsetZ: 0.009,
            lowerRadius: 0.006,
            lowerCoordinate: 0.0,
            upperRadius: 0.006,
            upperCoordinate: 0.010
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceIdenticalTwoShellCylindricalDifference() throws {
        try assertBuilderAndCodableCommandParity(
            operation: .difference,
            targetWidth: 0.010,
            targetHeight: 0.024,
            lowerRadius: 0.006,
            lowerCoordinate: 0.0,
            upperRadius: 0.006,
            upperCoordinate: 0.010
        )
    }

    private func assertBuilderAndCodableCommandParity(
        operation: BooleanOperation,
        targetSize: Double = 0.024,
        targetWidth: Double? = nil,
        targetHeight: Double? = nil,
        toolAxisOffsetX: Double = 0.0,
        toolAxisOffsetZ: Double = 0.0,
        lowerRadius: Double = 0.006,
        lowerCoordinate: Double = -0.002,
        upperRadius: Double = 0.0032,
        upperCoordinate: Double = 0.012
    ) throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let targetProfile = try builder.sketch(on: .zx) { sketch in
            sketch.rectangle(
                width: .constant(.length(targetWidth ?? targetSize, unit: .meter)),
                height: .constant(.length(targetHeight ?? targetSize, unit: .meter))
            )
        }
        let targetID = try builder.extrude(
            targetProfile,
            distance: .constant(.length(0.010, unit: .meter))
        )
        let toolPlane: SketchPlane = toolAxisOffsetZ == 0.0
            ? .xy
            : .plane(Plane3D(
                origin: Point3D(x: 0.0, y: 0.0, z: toolAxisOffsetZ),
                normal: .unitZ
            ))
        let toolProfile = try builder.sketch(on: toolPlane) { sketch in
            let axisLower = point(toolAxisOffsetX, lowerCoordinate)
            let lowerRim = point(toolAxisOffsetX + lowerRadius, lowerCoordinate)
            let upperRim = point(toolAxisOffsetX + upperRadius, upperCoordinate)
            let axisUpper = point(toolAxisOffsetX, upperCoordinate)
            _ = sketch.line(from: axisLower, to: lowerRim)
            _ = sketch.line(from: lowerRim, to: upperRim)
            _ = sketch.line(from: upperRim, to: axisUpper)
            _ = sketch.line(from: axisUpper, to: axisLower)
        }
        let toolID = try builder.revolve(
            toolProfile,
            axis: RevolveAxis(
                origin: Point3D(
                    x: toolAxisOffsetX,
                    y: 0.0,
                    z: toolAxisOffsetZ
                ),
                direction: .unitY
            )
        )
        _ = try builder.boolean(
            targets: [targetID],
            tool: toolID,
            operation: operation
        )
        let builderDocument = try builder.build()

        let editor = DocumentEditor()
        var commandDocument = CADDocument(units: .meters)
        for featureID in builderDocument.designGraph.order {
            let node = try #require(builderDocument.designGraph.nodes[featureID])
            let command = CADCommand.appendFeature(FeatureRequest(
                id: node.id,
                name: node.name,
                operation: node.operation
            ))
            let decoded = try JSONDecoder().decode(
                CADCommand.self,
                from: JSONEncoder().encode(command)
            )
            #expect(decoded == command)
            commandDocument = try editor.apply(
                decoded,
                to: commandDocument,
                tolerance: .standard
            )
        }

        #expect(try commandDocument.sourceFingerprint(tolerance: .standard) == builderDocument.sourceFingerprint(tolerance: .standard))
        let evaluator = DocumentEvaluator(tolerance: .standard)
        let builderResult = try evaluator.evaluate(builderDocument)
        let commandResult = try evaluator.evaluate(commandDocument)
        #expect(builderResult.brep == commandResult.brep)
        #expect(builderResult.lineage == commandResult.lineage)
        #expect(try builderResult.brep.volume(tolerance: .standard) == commandResult.brep.volume(tolerance: .standard))
    }

    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: .meter)),
            y: .constant(.length(y, unit: .meter))
        )
    }
}
