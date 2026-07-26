import CADCore
import CADIR
import Foundation
import Testing

struct CADCommandTests {
    @Test
    func sharedCommandRoundTripsWithStrictDiscriminator() throws {
        let command = CADCommand.suppressFeature(featureID: FeatureID(), suppressed: true)
        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(CADCommand.self, from: data)
        #expect(decoded == command)
    }

    @Test
    func parameterCommandRoundTripsWithStrictDiscriminator() throws {
        let parameter = Parameter(
            name: "width",
            expression: .constant(.length(10.0, unit: .millimeter)),
            kind: .length
        )
        let command = CADCommand.upsertParameter(parameter)
        let decoded = try JSONDecoder().decode(
            CADCommand.self,
            from: JSONEncoder().encode(command)
        )
        #expect(decoded == command)
    }

    @Test
    func featureRequestCarriesStableIdentityAndOperation() throws {
        let featureID = FeatureID()
        let request = FeatureRequest(
            id: featureID,
            name: "Development feature",
            operation: .polySpline(PolySplineFeature(
                sourceMesh: Mesh(
                    positions: [
                        Point3D(x: 0.0, y: 0.0, z: 0.0),
                        Point3D(x: 1.0, y: 0.0, z: 0.0),
                        Point3D(x: 0.0, y: 1.0, z: 0.0),
                    ],
                    normals: [],
                    indices: [0, 1, 2]
                )
            ))
        )
        let command = CADCommand.appendFeature(request)
        let decoded = try JSONDecoder().decode(
            CADCommand.self,
            from: JSONEncoder().encode(command)
        )
        #expect(decoded == command)
    }

    @Test
    func featureReplacementRoundTripsThroughSharedCommand() throws {
        let request = FeatureRequest(
            id: FeatureID(),
            name: "Solved sketch",
            operation: .sketch(Sketch(plane: .xy))
        )
        let command = CADCommand.replaceFeature(request)

        let decoded = try JSONDecoder().decode(
            CADCommand.self,
            from: JSONEncoder().encode(command)
        )

        #expect(decoded == command)
    }

    @Test
    func chamferRequestRoundTripsThroughSharedCommand() throws {
        let targetID = FeatureID()
        let selectedEdge = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: targetID, role: "edge", ordinal: 0),
            geometrySignature: try .lineEdge(
                startPoint: .origin,
                endPoint: Point3D(x: 1.0, y: 0.0, z: 0.0)
            )
        )
        let request = FeatureRequest(
            operation: .chamfer(ChamferFeature(
                target: ChamferTargetReference(featureID: targetID),
                edges: [selectedEdge],
                distance: .constant(.length(2.0, unit: .millimeter))
            ))
        )
        let command = CADCommand.appendFeature(request)

        let decoded = try JSONDecoder().decode(
            CADCommand.self,
            from: JSONEncoder().encode(command)
        )

        #expect(decoded == command)
    }

    @Test
    func filletRequestRoundTripsThroughSharedCommand() throws {
        let targetID = FeatureID()
        let selectedEdge = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: targetID, role: "edge", ordinal: 0),
            geometrySignature: try .lineEdge(
                startPoint: .origin,
                endPoint: Point3D(x: 1.0, y: 0.0, z: 0.0)
            )
        )
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .fillet(FilletFeature(
                target: FilletTargetReference(featureID: targetID),
                edges: [selectedEdge],
                radius: .constant(.length(2.0, unit: .millimeter))
            ))
        ))

        let decoded = try JSONDecoder().decode(
            CADCommand.self,
            from: JSONEncoder().encode(command)
        )

        #expect(decoded == command)
    }

    @Test
    func g2BlendRequestRoundTripsThroughSharedCommand() throws {
        let targetID = FeatureID()
        let selectedEdge = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: targetID, role: "edge", ordinal: 0),
            geometrySignature: try .lineEdge(
                startPoint: .origin,
                endPoint: Point3D(x: 1.0, y: 0.0, z: 0.0)
            )
        )
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .g2Blend(G2BlendFeature(
                target: G2BlendTargetReference(featureID: targetID),
                edges: [selectedEdge],
                distance: .constant(.length(2.0, unit: .millimeter))
            ))
        ))

        let decoded = try JSONDecoder().decode(
            CADCommand.self,
            from: JSONEncoder().encode(command)
        )

        #expect(decoded == command)
    }

    @Test
    func setbackCornerRequestRoundTripsThroughSharedCommand() throws {
        let targetID = FeatureID()
        let vertex = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: targetID, role: "vertex", ordinal: 0),
            geometrySignature: .vertex(point: .origin)
        )
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .setbackCorner(SetbackCornerFeature(
                target: SetbackCornerTargetReference(featureID: targetID),
                vertex: vertex,
                radius: .constant(.length(2.0, unit: .millimeter))
            ))
        ))

        let decoded = try JSONDecoder().decode(
            CADCommand.self,
            from: JSONEncoder().encode(command)
        )

        #expect(decoded == command)
    }

    @Test
    func shellRequestRoundTripsThroughSharedCommand() throws {
        let targetID = FeatureID()
        let face = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: targetID, role: "face", ordinal: 0),
            geometrySignature: .untrimmedPlane(origin: .origin)
        )
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .shell(ShellFeature(
                target: ShellTargetReference(featureID: targetID),
                removedFaces: [face],
                thickness: .constant(.length(2.0, unit: .millimeter))
            ))
        ))

        let decoded = try JSONDecoder().decode(
            CADCommand.self,
            from: JSONEncoder().encode(command)
        )

        #expect(decoded == command)
    }

    @Test
    func thickenRequestRoundTripsThroughSharedCommand() throws {
        let targetID = FeatureID()
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .thicken(ThickenFeature(
                target: ThickenTargetReference(featureID: targetID),
                thickness: .constant(.length(2.0, unit: .millimeter)),
                side: .positive
            ))
        ))

        let decoded = try JSONDecoder().decode(
            CADCommand.self,
            from: JSONEncoder().encode(command)
        )

        #expect(decoded == command)
    }

    @Test
    func faceMoveRequestRoundTripsThroughSharedCommand() throws {
        let targetID = FeatureID()
        let face = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: targetID, role: "face", ordinal: 0),
            geometrySignature: .untrimmedPlane(origin: .origin)
        )
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .faceMove(FaceMoveFeature(
                target: FaceMoveTargetReference(featureID: targetID),
                face: face,
                translation: DirectMoveVector(
                    direction: .unitX,
                    distance: .constant(.length(2.0, unit: .millimeter))
                )
            ))
        ))
        let decoded = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }

    @Test
    func faceOffsetRequestRoundTripsThroughSharedCommand() throws {
        let targetID = FeatureID()
        let face = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: targetID, role: "face", ordinal: 0),
            geometrySignature: .untrimmedPlane(origin: .origin)
        )
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .faceOffset(FaceOffsetFeature(
                target: FaceOffsetTargetReference(featureID: targetID),
                face: face,
                distance: .constant(.length(2.0, unit: .millimeter))
            ))
        ))
        let decoded = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }

    @Test
    func edgeMoveRequestRoundTripsThroughSharedCommand() throws {
        let targetID = FeatureID()
        let edge = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: targetID, role: "edge", ordinal: 0),
            geometrySignature: try .lineEdge(
                startPoint: .origin,
                endPoint: Point3D(x: 0.0, y: 0.0, z: 1.0)
            )
        )
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .edgeMove(EdgeMoveFeature(
                target: EdgeMoveTargetReference(featureID: targetID),
                edge: edge,
                translation: DirectMoveVector(
                    direction: .unitX,
                    distance: .constant(.length(2.0, unit: .millimeter))
                )
            ))
        ))
        let decoded = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }

    @Test
    func vertexMoveRequestRoundTripsThroughSharedCommand() throws {
        let targetID = FeatureID()
        let vertex = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: targetID, role: "vertex", ordinal: 0),
            geometrySignature: .vertex(point: .origin)
        )
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .vertexMove(VertexMoveFeature(
                target: VertexMoveTargetReference(featureID: targetID),
                vertex: vertex,
                translation: DirectMoveVector(
                    direction: .unitZ,
                    distance: .constant(.length(2.0, unit: .millimeter))
                )
            ))
        ))
        let decoded = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }

    @Test
    func linearPatternRequestRoundTripsThroughSharedCommand() throws {
        let targetID = FeatureID()
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .linearPattern(LinearPatternFeature(
                target: PatternTargetReference(featureID: targetID),
                direction: .unitX,
                spacing: .constant(.length(60.0, unit: .millimeter)),
                count: 3
            ))
        ))
        let decoded = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }

    @Test
    func radialPatternRequestRoundTripsThroughSharedCommand() throws {
        let targetID = FeatureID()
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .radialPattern(RadialPatternFeature(
                target: PatternTargetReference(featureID: targetID),
                axisOrigin: .origin,
                axisDirection: .unitZ,
                angularSpacing: .constant(.angle(.pi / 3.0, unit: .radian)),
                count: 6
            ))
        ))
        let decoded = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }

    @Test
    func gridPatternRequestRoundTripsThroughSharedCommand() throws {
        let targetID = FeatureID()
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .gridPattern(GridPatternFeature(
                target: PatternTargetReference(featureID: targetID),
                firstDirection: .unitX,
                firstSpacing: .constant(.length(60.0, unit: .millimeter)),
                firstCount: 2,
                secondDirection: .unitY,
                secondSpacing: .constant(.length(40.0, unit: .millimeter)),
                secondCount: 3
            ))
        ))
        let decoded = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }

    @Test
    func curveDrivenPatternRequestRoundTripsThroughSharedCommand() throws {
        let targetID = FeatureID()
        let pathID = FeatureID()
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .curveDrivenPattern(CurveDrivenPatternFeature(
                target: PatternTargetReference(featureID: targetID),
                path: CurveDrivenPatternPathReference(featureID: pathID),
                anchor: .origin,
                referenceDirection: .unitX,
                count: 5
            ))
        ))
        let decoded = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }

    @Test
    func curveOffsetRequestRoundTripsThroughSharedCommand() throws {
        let sourceID = FeatureID()
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .curveOffset(CurveOffsetFeature(
                source: CurveOutputReference(featureID: sourceID),
                distance: .constant(.length(2.0, unit: .millimeter)),
                planeNormal: .unitZ,
                side: .right
            ))
        ))
        let decoded = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }

    @Test
    func curveTrimRequestRoundTripsThroughSharedCommand() throws {
        let sourceID = FeatureID()
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .curveTrim(CurveTrimFeature(
                source: CurveOutputReference(featureID: sourceID),
                domain: .closed(0.1, 0.9)
            ))
        ))
        let decoded = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }

    @Test
    func curveExtendRequestRoundTripsThroughSharedCommand() throws {
        let sourceID = FeatureID()
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .curveExtend(CurveExtendFeature(
                source: CurveOutputReference(featureID: sourceID),
                end: .both,
                distance: .constant(.length(5.0, unit: .millimeter))
            ))
        ))
        let decoded = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }

    @Test
    func curveMatchRequestRoundTripsThroughSharedCommand() throws {
        let sourceID = FeatureID()
        let targetID = FeatureID()
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .curveMatch(CurveMatchFeature(
                source: CurveOutputReference(featureID: sourceID),
                sourceEnd: .end,
                target: CurveOutputReference(featureID: targetID),
                targetEnd: .start,
                targetOrientation: .forward,
                continuity: .curvature
            ))
        ))
        let decoded = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }

    @Test
    func surfaceOffsetRequestRoundTripsThroughSharedCommand() throws {
        let targetID = FeatureID()
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .surfaceOffset(SurfaceOffsetFeature(
                target: surfaceOperationTargetReference(featureID: targetID),
                distance: .constant(.length(-2.0, unit: .millimeter))
            ))
        ))
        let decoded = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }

    @Test
    func surfaceTrimRequestRoundTripsThroughSharedCommand() throws {
        let targetID = FeatureID()
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .surfaceTrim(SurfaceTrimFeature(
                target: surfaceOperationTargetReference(featureID: targetID),
                loops: [SurfaceTrimLoop(
                    role: .outer,
                    parameterCurves: [
                        .constantV(v: 0.2, uStart: 0.1, uEnd: 0.9),
                        .constantU(u: 0.9, vStart: 0.2, vEnd: 0.8),
                        .constantV(v: 0.8, uStart: 0.9, uEnd: 0.1),
                        .constantU(u: 0.1, vStart: 0.8, vEnd: 0.2),
                    ]
                )]
            ))
        ))
        let decoded = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }

    @Test
    func surfaceExtendRequestRoundTripsThroughSharedCommand() throws {
        let targetID = FeatureID()
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .surfaceExtend(SurfaceExtendFeature(
                target: surfaceOperationTargetReference(featureID: targetID),
                uDomain: .closed(-0.1, 1.1),
                vDomain: .closed(-0.2, 1.2)
            ))
        ))
        let decoded = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }

    @Test
    func surfaceMatchRequestRoundTripsThroughSharedCommand() throws {
        let sourceID = FeatureID()
        let targetID = FeatureID()
        let command = CADCommand.appendFeature(FeatureRequest(
            operation: .surfaceMatch(SurfaceMatchFeature(
                source: surfaceOperationTargetReference(featureID: sourceID),
                target: surfaceOperationTargetReference(featureID: targetID),
                sourceParameter: SurfaceParameter(u: 0.1, v: 0.2),
                targetParameter: SurfaceParameter(u: 0.3, v: 0.4),
                normalAlignment: .opposed,
                continuity: .curvature
            ))
        ))
        let decoded = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }

    @Test
    func topologyLineageRequiresValidOutputIdentity() {
        let output = SubshapeID(featureID: FeatureID(), role: "face", ordinal: 0)
        let lineage = TopologyLineage(output: output, relation: .generated)
        #expect(lineage.isStructurallyValid)
    }

    @Test
    func subshapeSelectionRoundTripsByIdentity() throws {
        let selection = SelectionReference.subshape(
            StableSubshapeReference(
                subshapeID: SubshapeID(featureID: FeatureID(), role: "face", ordinal: 2),
                geometrySignature: .untrimmedPlane(origin: .origin)
            )
        )
        let data = try JSONEncoder().encode(selection)
        let decoded = try JSONDecoder().decode(SelectionReference.self, from: data)
        #expect(decoded == selection)
    }
}
