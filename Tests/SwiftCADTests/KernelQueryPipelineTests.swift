import Foundation
import CADCore
import CADIR
import CADKernel
import CADTopology
import SwiftCAD
import Testing

@Suite("Shared kernel query pipeline")
struct KernelQueryPipelineTests {
    @Test
    func allSerializableRequestsRoundTripThroughKernelQuery() throws {
        let curve = CurveOutputReference(featureID: FeatureID())
        let selection = SelectionReference.curve(.parameter(CurveParameterReference(
            curve: curve,
            parameter: 0.5
        )))
        let queries: [KernelQuery] = [
            .evaluatedDocument,
            .lineage(SubshapeID(featureID: FeatureID(), role: "face", ordinal: 0)),
            .diagnostics,
            .snap(SnapQueryRequest(point: .origin)),
            .measurement(MeasurementQuery(kind: .point, first: selection)),
            .selectionDimensionEvaluation(SelectionDimensionEvaluationQuery()),
            .projection(ProjectionQuery(
                point: .origin,
                target: .curve(curve)
            )),
        ]

        for query in queries {
            let data = try JSONEncoder().encode(query)
            #expect(try JSONDecoder().decode(KernelQuery.self, from: data) == query)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func snapAndMeasurementUseOneKernelExecutionPath() throws {
        var horizontalFeatureID: FeatureID?
        var verticalFeatureID: FeatureID?
        let document = try CADDocument.millimeters(
            tolerance: .standard,
            named: "Kernel query parity"
        ) { builder in
            let horizontal = try builder.sketch(on: .xy) { sketch in
                _ = sketch.line(from: point(0.0, 0.0), to: point(10.0, 0.0))
            }
            horizontalFeatureID = horizontal.featureID
            let vertical = try builder.sketch(on: .xy) { sketch in
                _ = sketch.line(from: point(0.0, 0.0), to: point(0.0, 10.0))
            }
            verticalFeatureID = vertical.featureID
        }
        let pipeline = CADPipeline(tolerance: .standard)
        let start = try snap(
            point: Point3D(x: 0.0001, y: 0.0, z: 0.0),
            pipeline: pipeline,
            document: document
        )
        let end = try snap(
            point: Point3D(x: 0.010, y: 0.0, z: 0.0),
            pipeline: pipeline,
            document: document
        )
        let distanceResult = try pipeline.execute(
            .measurement(MeasurementQuery(
                kind: .distance,
                first: start,
                second: end
            )),
            on: document
        )
        guard case let .measurement(.distance(distance)) = distanceResult else {
            Issue.record("Expected a distance measurement result.")
            return
        }
        let horizontal = CurveOutputReference(featureID: try #require(horizontalFeatureID))
        let vertical = CurveOutputReference(featureID: try #require(verticalFeatureID))
        let closestProjection = try pipeline.execute(
            .projection(ProjectionQuery(
                point: Point3D(x: 0.005, y: 0.002, z: 0.0),
                target: .curve(horizontal)
            )),
            on: document
        )
        guard case let .projection(.curveClosest(curveProjection)) = closestProjection else {
            Issue.record("Expected a closest curve projection result.")
            return
        }
        let directionalProjection = try pipeline.execute(
            .projection(ProjectionQuery(
                point: Point3D(x: 0.005, y: 0.002, z: 0.0),
                target: .curve(horizontal),
                mode: .directional(direction: -.unitY, range: .ray)
            )),
            on: document
        )
        guard case let .projection(.curveDirectional(curveDirectional)) = directionalProjection else {
            Issue.record("Expected a directional curve projection result.")
            return
        }
        let angleResult = try pipeline.execute(
            .measurement(MeasurementQuery(
                kind: .angle,
                first: .curve(.parameter(CurveParameterReference(
                    curve: horizontal,
                    parameter: 0.005
                ))),
                second: .curve(.parameter(CurveParameterReference(
                    curve: vertical,
                    parameter: 0.005
                )))
            )),
            on: document
        )
        guard case let .measurement(.angle(angle)) = angleResult else {
            Issue.record("Expected an angle measurement result.")
            return
        }

        #expect(abs(distance.distance - 0.010) < 1.0e-12)
        #expect(curveProjection.projectedPoint.isApproximatelyEqual(
            to: Point3D(x: 0.005, y: 0.0, z: 0.0),
            tolerance: 1.0e-12
        ))
        #expect(curveDirectional.lineDistance <= 1.0e-12)
        #expect(abs(angle.angleRadians - Double.pi / 2.0) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func edgeAndSurfaceProjectionUseOneKernelExecutionPath() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let boxID = try builder.box(
            width: .constant(.length(0.020, unit: .meter)),
            depth: .constant(.length(0.016, unit: .meter)),
            height: .constant(.length(0.012, unit: .meter))
        )
        let document = try builder.build()
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)

        let edgeSubshapeID = SubshapeID(
            featureID: boxID,
            role: GeneratedSubshapeRole.edge.rawValue,
            ordinal: 0
        )
        guard case let .edge(edgeID) = try #require(evaluated.subshapes[edgeSubshapeID]),
              let edge = evaluated.brep.edges[edgeID],
              let start = evaluated.brep.vertices[edge.startVertexID]?.point,
              let end = evaluated.brep.vertices[edge.endVertexID]?.point else {
            Issue.record("Expected an exact primitive edge.")
            return
        }
        let tangent = try (end - start).normalized(tolerance: 1.0e-12)
        let candidateOffset = tangent.cross(.unitZ)
        let offset = candidateOffset.length > 1.0e-12
            ? try candidateOffset.normalized(tolerance: 1.0e-12)
            : try tangent.cross(.unitY).normalized(tolerance: 1.0e-12)
        let edgePoint = start + (end - start) * 0.5
        let edgeSource = edgePoint + offset * 0.001
        let edgeReference = EdgeReference(
            subshape: try evaluated.stableSubshapeReference(for: edgeSubshapeID)
        )
        let edgeClosest = try pipeline.execute(
            .projection(ProjectionQuery(
                point: edgeSource,
                target: .edge(edgeReference)
            )),
            on: document
        )
        let edgeDirectional = try pipeline.execute(
            .projection(ProjectionQuery(
                point: edgeSource,
                target: .edge(edgeReference),
                mode: .directional(direction: -offset, range: .ray)
            )),
            on: document
        )

        let faceSubshapeID = SubshapeID(
            featureID: boxID,
            role: GeneratedSubshapeRole.face.rawValue,
            ordinal: 0
        )
        guard case let .face(faceID) = try #require(evaluated.subshapes[faceSubshapeID]),
              let face = evaluated.brep.faces[faceID],
              case let .plane(plane)? = evaluated.brep.geometry.surfaces[face.surfaceID] else {
            Issue.record("Expected an exact primitive planar face.")
            return
        }
        let surfaceSource = plane.origin + plane.normal * 0.001
        let surfaceReference = SurfaceReference(
            subshape: try evaluated.stableSubshapeReference(for: faceSubshapeID)
        )
        let surfaceClosest = try pipeline.execute(
            .projection(ProjectionQuery(
                point: surfaceSource,
                target: .surface(surfaceReference)
            )),
            on: document
        )
        let surfaceDirectional = try pipeline.execute(
            .projection(ProjectionQuery(
                point: surfaceSource,
                target: .surface(surfaceReference),
                mode: .directional(direction: -plane.normal, range: .ray)
            )),
            on: document
        )

        guard case let .projection(.edgeClosest(edgeClosestResult)) = edgeClosest,
              case let .projection(.edgeDirectional(edgeDirectionalResult)) = edgeDirectional,
              case let .projection(.surfaceClosest(surfaceClosestResult)) = surfaceClosest,
              case let .projection(.surfaceDirectional(surfaceDirectionalResult)) = surfaceDirectional else {
            Issue.record("Expected edge and surface projection results.")
            return
        }
        #expect(edgeClosestResult.distance <= 0.001 + 1.0e-12)
        #expect(edgeDirectionalResult.lineDistance <= 1.0e-12)
        #expect(surfaceClosestResult.distance <= 0.001 + 1.0e-12)
        #expect(surfaceDirectionalResult.lineDistance <= 1.0e-12)
    }

    private func snap(
        point: Point3D,
        pipeline: CADPipeline,
        document: CADDocument
    ) throws -> SelectionReference {
        let result = try pipeline.execute(
            .snap(SnapQueryRequest(
                point: point,
                options: SnapQueryOptions(
                    maximumDistance: 0.001,
                    intent: .curvePoint
                )
            )),
            on: document
        )
        guard case let .snap(snapResult) = result else {
            throw FeatureEvaluationError.invalidGraph("Expected a snap query result.")
        }
        return try #require(snapResult.candidates.first?.selection)
    }

    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: .millimeter)),
            y: .constant(.length(y, unit: .millimeter))
        )
    }
}
