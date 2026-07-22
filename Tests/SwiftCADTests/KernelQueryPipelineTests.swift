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
    func allKernelResultsRoundTripThroughTheSharedTransportContract() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sketch = try builder.sketch(on: .xy) { sketch in
            _ = sketch.line(from: point(0.0, 0.0), to: point(10.0, 0.0))
            _ = sketch.line(from: point(0.0, 0.0), to: point(0.0, 10.0))
        }
        let boxID = try builder.box(
            width: .constant(.length(0.020, unit: .meter)),
            depth: .constant(.length(0.016, unit: .meter)),
            height: .constant(.length(0.012, unit: .meter))
        )
        let firstStableVertex = try builder.stableSubshape(SubshapeID(
            featureID: boxID,
            role: GeneratedSubshapeRole.vertex.rawValue,
            ordinal: 0
        ))
        let secondStableVertex = try builder.stableSubshape(SubshapeID(
            featureID: boxID,
            role: GeneratedSubshapeRole.vertex.rawValue,
            ordinal: 1
        ))
        let dimensionID = try builder.distanceDimension(
            from: .subshape(firstStableVertex),
            to: .subshape(secondStableVertex),
            target: .constant(.length(0.020, unit: .meter))
        )
        let document = try builder.build()
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let vertexEntry = try #require(evaluated.subshapes.entries.first { subshapeID, reference in
            if case .vertex = reference, subshapeID.featureID == boxID {
                return true
            }
            return false
        })
        let secondVertexEntry = try #require(evaluated.subshapes.entries.first { subshapeID, reference in
            if case .vertex = reference,
               subshapeID.featureID == boxID,
               subshapeID != vertexEntry.key {
                return true
            }
            return false
        })
        let edgeEntry = try #require(evaluated.subshapes.entries.first { subshapeID, reference in
            if case .edge = reference, subshapeID.featureID == boxID {
                return true
            }
            return false
        })
        let faceEntry = try #require(evaluated.subshapes.entries.first { subshapeID, reference in
            if case .face = reference, subshapeID.featureID == boxID {
                return true
            }
            return false
        })
        guard case let .vertex(vertexID) = vertexEntry.value,
              let vertex = evaluated.brep.vertices[vertexID],
              case let .edge(edgeID) = edgeEntry.value,
              let edge = evaluated.brep.edges[edgeID],
              let edgeStart = evaluated.brep.vertices[edge.startVertexID]?.point,
              let edgeEnd = evaluated.brep.vertices[edge.endVertexID]?.point,
              case let .face(faceID) = faceEntry.value,
              let face = evaluated.brep.faces[faceID],
              case let .plane(plane)? = evaluated.brep.geometry.surfaces[face.surfaceID] else {
            Issue.record("Expected exact box vertex, edge, and planar face topology.")
            return
        }
        let vertexSelection = SelectionReference.subshape(
            try evaluated.stableSubshapeReference(for: vertexEntry.key)
        )
        let secondVertexSelection = SelectionReference.subshape(
            try evaluated.stableSubshapeReference(for: secondVertexEntry.key)
        )
        let edgeReference = EdgeReference(
            subshape: try evaluated.stableSubshapeReference(for: edgeEntry.key)
        )
        let faceReference = SurfaceReference(
            subshape: try evaluated.stableSubshapeReference(for: faceEntry.key)
        )
        let horizontalCurve = CurveOutputReference(featureID: sketch.featureID, curveIndex: 0)
        let verticalCurve = CurveOutputReference(featureID: sketch.featureID, curveIndex: 1)
        let horizontalSelection = SelectionReference.curve(.parameter(CurveParameterReference(
            curve: horizontalCurve,
            parameter: 0.005
        )))
        let verticalSelection = SelectionReference.curve(.parameter(CurveParameterReference(
            curve: verticalCurve,
            parameter: 0.005
        )))
        let curveSource = Point3D(x: 0.005, y: 0.002, z: 0.0)
        let edgeMidpoint = edgeStart + (edgeEnd - edgeStart) * 0.5
        let edgeTangent = try (edgeEnd - edgeStart).normalized(tolerance: 1.0e-12)
        let edgeOffsetCandidate = edgeTangent.cross(.unitZ)
        let edgeOffset = edgeOffsetCandidate.length > 1.0e-12
            ? try edgeOffsetCandidate.normalized(tolerance: 1.0e-12)
            : try edgeTangent.cross(.unitY).normalized(tolerance: 1.0e-12)
        let edgeSource = edgeMidpoint + edgeOffset * 0.001
        let surfaceSource = plane.origin + plane.normal * 0.001
        let results: [KernelQueryResult] = [
            try pipeline.execute(.evaluatedDocument, on: document),
            try pipeline.execute(.lineage(vertexEntry.key), on: document),
            try pipeline.execute(.diagnostics, on: document),
            try pipeline.execute(
                .snap(SnapQueryRequest(
                    point: vertex.point,
                    options: SnapQueryOptions(maximumDistance: 0.001)
                )),
                on: document
            ),
            try pipeline.execute(
                .measurement(MeasurementQuery(kind: .point, first: vertexSelection)),
                on: document
            ),
            try pipeline.execute(
                .measurement(MeasurementQuery(
                    kind: .distance,
                    first: vertexSelection,
                    second: secondVertexSelection
                )),
                on: document
            ),
            try pipeline.execute(
                .measurement(MeasurementQuery(
                    kind: .angle,
                    first: horizontalSelection,
                    second: verticalSelection
                )),
                on: document
            ),
            try pipeline.execute(
                .selectionDimensionEvaluation(SelectionDimensionEvaluationQuery(
                    dimensionID: dimensionID
                )),
                on: document
            ),
            try pipeline.execute(
                .projection(ProjectionQuery(
                    point: curveSource,
                    target: .curve(horizontalCurve)
                )),
                on: document
            ),
            try pipeline.execute(
                .projection(ProjectionQuery(
                    point: curveSource,
                    target: .curve(horizontalCurve),
                    mode: .directional(direction: -.unitY, range: .ray)
                )),
                on: document
            ),
            try pipeline.execute(
                .projection(ProjectionQuery(
                    point: edgeSource,
                    target: .edge(edgeReference)
                )),
                on: document
            ),
            try pipeline.execute(
                .projection(ProjectionQuery(
                    point: edgeSource,
                    target: .edge(edgeReference),
                    mode: .directional(direction: -edgeOffset, range: .ray)
                )),
                on: document
            ),
            try pipeline.execute(
                .projection(ProjectionQuery(
                    point: surfaceSource,
                    target: .surface(faceReference)
                )),
                on: document
            ),
            try pipeline.execute(
                .projection(ProjectionQuery(
                    point: surfaceSource,
                    target: .surface(faceReference),
                    mode: .directional(direction: -plane.normal, range: .ray)
                )),
                on: document
            ),
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var decodedResults: [KernelQueryResult] = []
        for result in results {
            let encoded = try encoder.encode(result)
            let decoded = try JSONDecoder().decode(KernelQueryResult.self, from: encoded)
            try decoded.validate()
            _ = try encoder.encode(decoded)
            decodedResults.append(decoded)
        }
        guard case let .evaluatedDocument(decodedDocument) = decodedResults[0],
              case let .lineage(decodedLineage) = decodedResults[1],
              case let .diagnostics(decodedReport) = decodedResults[2],
              case let .snap(decodedSnap) = decodedResults[3],
              case let .measurement(.point(decodedPoint)) = decodedResults[4],
              case let .measurement(.distance(decodedDistance)) = decodedResults[5],
              case let .measurement(.angle(decodedAngle)) = decodedResults[6],
              case let .selectionDimensionEvaluation(decodedDimensions) = decodedResults[7],
              case let .projection(.curveClosest(decodedCurveClosest)) = decodedResults[8],
              case let .projection(.curveDirectional(decodedCurveDirectional)) = decodedResults[9],
              case let .projection(.edgeClosest(decodedEdgeClosest)) = decodedResults[10],
              case let .projection(.edgeDirectional(decodedEdgeDirectional)) = decodedResults[11],
              case let .projection(.surfaceClosest(decodedSurfaceClosest)) = decodedResults[12],
              case let .projection(.surfaceDirectional(decodedSurfaceDirectional)) = decodedResults[13] else {
            Issue.record("Kernel query result kind changed during transport round-trip.")
            return
        }
        try decodedDocument.validate()
        #expect(decodedLineage?.isStructurallyValid == true)
        #expect(decodedReport.isComplete)
        #expect(decodedSnap.candidates.isEmpty == false)
        #expect(decodedPoint.point == vertex.point)
        #expect(decodedDistance.distance > 0.0)
        #expect(abs(decodedAngle.angleRadians - Double.pi * 0.5) <= 1.0e-12)
        #expect(decodedDimensions.measurements.count == 1)
        #expect(decodedCurveClosest.distance <= 0.002 + 1.0e-12)
        #expect(decodedCurveDirectional.lineDistance <= 1.0e-12)
        #expect(decodedEdgeClosest.distance <= 0.001 + 1.0e-12)
        #expect(decodedEdgeDirectional.lineDistance <= 1.0e-12)
        #expect(decodedSurfaceClosest.distance <= 0.001 + 1.0e-12)
        #expect(decodedSurfaceDirectional.lineDistance <= 1.0e-12)
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
