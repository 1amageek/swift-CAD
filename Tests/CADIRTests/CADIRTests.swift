import Foundation
import Testing
import CADCore
@testable import CADIR

@Suite("CADIR")
struct CADIRTests {
    @Test(.timeLimit(.minutes(1)))
    func documentMetadataDefaultTimestampsAreConsistent() throws {
        let metadata = DocumentMetadata()

        #expect(metadata.createdAt == metadata.updatedAt)
        try metadata.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsMissingOrderedFeature() throws {
        let missingID = FeatureID()
        let graph = DesignGraph(nodes: [:], order: [missingID], dependencies: [])

        #expect(throws: FeatureEvaluationError.self) {
            try graph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsUnorderedExistingNode() {
        let featureID = FeatureID()
        let graph = DesignGraph(
            nodes: [featureID: FeatureNode(
                id: featureID,
                operation: .sketch(Sketch(plane: .xy)),
                outputs: [FeatureOutput(role: .profile)]
            )],
            order: [],
            dependencies: []
        )

        #expect(throws: FeatureEvaluationError.self) {
            try graph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchCurveChainResolverOrdersConnectedOpenLineArcChain() throws {
        let lineID = SketchEntityID()
        let arcID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                lineID: .line(SketchLine(
                    start: sketchPoint(x: 0.0, y: 0.0),
                    end: sketchPoint(x: 0.01, y: 0.0)
                )),
                arcID: .arc(SketchArc(
                    center: sketchPoint(x: 0.01, y: 0.005),
                    radius: .constant(.length(0.005, unit: .meter)),
                    startAngle: .constant(.angle(-90.0, unit: .degree)),
                    endAngle: .constant(.angle(0.0, unit: .degree))
                )),
            ],
            constraints: [
                .coincident(.lineEnd(lineID), .arcStart(arcID)),
            ]
        )

        let chain = try SketchCurveChainResolver().resolveOpenChain(
            in: sketch,
            selectedEntityID: lineID
        )

        #expect(chain.segments == [
            SketchCurveChainSegment(
                entityID: lineID,
                startReference: .lineStart(lineID),
                endReference: .lineEnd(lineID)
            ),
            SketchCurveChainSegment(
                entityID: arcID,
                startReference: .arcStart(arcID),
                endReference: .arcEnd(arcID)
            ),
        ])
        #expect(chain.vertices.count == 3)
        #expect(Set(chain.vertices[1].connectedEndpointReferences) == Set([
            .lineEnd(lineID),
            .arcStart(arcID),
        ]))
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchCurveChainResolverRejectsBranchedLineChain() throws {
        let firstID = SketchEntityID()
        let secondID = SketchEntityID()
        let thirdID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                firstID: .line(SketchLine(
                    start: sketchPoint(x: 0.0, y: 0.0),
                    end: sketchPoint(x: 0.01, y: 0.0)
                )),
                secondID: .line(SketchLine(
                    start: sketchPoint(x: 0.01, y: 0.0),
                    end: sketchPoint(x: 0.02, y: 0.0)
                )),
                thirdID: .line(SketchLine(
                    start: sketchPoint(x: 0.01, y: 0.0),
                    end: sketchPoint(x: 0.01, y: 0.01)
                )),
            ],
            constraints: [
                .coincident(.lineEnd(firstID), .lineStart(secondID)),
                .coincident(.lineEnd(firstID), .lineStart(thirdID)),
            ]
        )

        do {
            _ = try SketchCurveChainResolver(supportedKinds: [.line]).resolveOpenChain(
                in: sketch,
                selectedEntityID: firstID
            )
            Issue.record("Branched sketch curve chains must be rejected.")
        } catch let error as SketchCurveChainResolutionError {
            #expect(error == .branched)
        } catch {
            Issue.record("Expected SketchCurveChainResolutionError, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchCurveChainResolverRejectsClosedLineChain() throws {
        let firstID = SketchEntityID()
        let secondID = SketchEntityID()
        let thirdID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                firstID: .line(SketchLine(
                    start: sketchPoint(x: 0.0, y: 0.0),
                    end: sketchPoint(x: 0.01, y: 0.0)
                )),
                secondID: .line(SketchLine(
                    start: sketchPoint(x: 0.01, y: 0.0),
                    end: sketchPoint(x: 0.01, y: 0.01)
                )),
                thirdID: .line(SketchLine(
                    start: sketchPoint(x: 0.01, y: 0.01),
                    end: sketchPoint(x: 0.0, y: 0.0)
                )),
            ],
            constraints: [
                .coincident(.lineEnd(firstID), .lineStart(secondID)),
                .coincident(.lineEnd(secondID), .lineStart(thirdID)),
                .coincident(.lineEnd(thirdID), .lineStart(firstID)),
            ]
        )

        do {
            _ = try SketchCurveChainResolver(supportedKinds: [.line]).resolveOpenChain(
                in: sketch,
                selectedEntityID: firstID
            )
            Issue.record("Closed sketch curve chains must be rejected by open-chain resolution.")
        } catch let error as SketchCurveChainResolutionError {
            #expect(error == .closed)
        } catch {
            Issue.record("Expected SketchCurveChainResolutionError, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsInvalidPersistentOutputNames() {
        let emptyNameFeatureID = FeatureID()
        let negativeIndexFeatureID = FeatureID()
        let emptyNameGraph = DesignGraph(
            nodes: [emptyNameFeatureID: FeatureNode(
                id: emptyNameFeatureID,
                operation: .sketch(Sketch(plane: .xy)),
                outputs: [
                    FeatureOutput(
                        role: .profile,
                        persistentName: PersistentName(components: [])
                    )
                ]
            )],
            order: [emptyNameFeatureID]
        )
        let negativeIndexGraph = DesignGraph(
            nodes: [negativeIndexFeatureID: FeatureNode(
                id: negativeIndexFeatureID,
                operation: .sketch(Sketch(plane: .xy)),
                outputs: [
                    FeatureOutput(
                        role: .profile,
                        persistentName: PersistentName(components: [
                            .feature(negativeIndexFeatureID),
                            .generated(GeneratedSubshapeRole.body.rawValue),
                            .index(-1)
                        ])
                    )
                ]
            )],
            order: [negativeIndexFeatureID]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try emptyNameGraph.validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try negativeIndexGraph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphReportsDeterministicInvalidatedFeatures() throws {
        let sketchID = FeatureID()
        let firstExtrudeID = FeatureID()
        let secondExtrudeID = FeatureID()
        let graph = DesignGraph(
            nodes: [
                sketchID: FeatureNode(
                    id: sketchID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                firstExtrudeID: FeatureNode(
                    id: firstExtrudeID,
                    operation: .extrude(ExtrudeFeature(
                        profile: ProfileReference(featureID: sketchID),
                        distance: .constant(.length(1.0, unit: .meter))
                    )),
                    inputs: [FeatureInput(featureID: sketchID, role: .profile)],
                    outputs: [FeatureOutput(role: .body)]
                ),
                secondExtrudeID: FeatureNode(
                    id: secondExtrudeID,
                    operation: .extrude(ExtrudeFeature(
                        profile: ProfileReference(featureID: sketchID),
                        distance: .constant(.length(1.0, unit: .meter))
                    )),
                    inputs: [FeatureInput(featureID: sketchID, role: .profile)],
                    outputs: [FeatureOutput(role: .body)]
                )
            ],
            order: [sketchID, firstExtrudeID, secondExtrudeID],
            dependencies: [
                DependencyEdge(source: sketchID, target: firstExtrudeID),
                DependencyEdge(source: sketchID, target: secondExtrudeID)
            ]
        )

        #expect(try graph.invalidatedFeatureIDs(after: sketchID) == [firstExtrudeID, secondExtrudeID])
        #expect(try graph.invalidatedFeatureIDs(after: firstExtrudeID).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsDependencyCyclesAndOrderViolations() {
        let firstID = FeatureID()
        let secondID = FeatureID()
        let nodes = [
            firstID: FeatureNode(
                id: firstID,
                operation: .sketch(Sketch(plane: .xy)),
                outputs: [FeatureOutput(role: .profile)]
            ),
            secondID: FeatureNode(
                id: secondID,
                operation: .sketch(Sketch(plane: .xy)),
                outputs: [FeatureOutput(role: .profile)]
            )
        ]
        let cyclicGraph = DesignGraph(
            nodes: nodes,
            order: [firstID, secondID],
            dependencies: [
                DependencyEdge(source: firstID, target: secondID),
                DependencyEdge(source: secondID, target: firstID)
            ]
        )
        let wrongOrderGraph = DesignGraph(
            nodes: nodes,
            order: [secondID, firstID],
            dependencies: [DependencyEdge(source: firstID, target: secondID)]
        )
        let duplicateDependencyGraph = DesignGraph(
            nodes: nodes,
            order: [firstID, secondID],
            dependencies: [
                DependencyEdge(source: firstID, target: secondID),
                DependencyEdge(source: firstID, target: secondID)
            ]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try cyclicGraph.validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try wrongOrderGraph.validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try duplicateDependencyGraph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsInvalidFeatureInputs() {
        let firstID = FeatureID()
        let secondID = FeatureID()
        let missingID = FeatureID()
        let missingInputNodes = [
            firstID: FeatureNode(
                id: firstID,
                operation: .extrude(ExtrudeFeature(
                    profile: ProfileReference(featureID: missingID),
                    distance: .constant(.length(1.0, unit: .meter))
                )),
                inputs: [FeatureInput(featureID: missingID, role: .profile)],
                outputs: [FeatureOutput(role: .body)]
            )
        ]
        let wrongOrderNodes = [
            firstID: FeatureNode(
                id: firstID,
                operation: .sketch(Sketch(plane: .xy)),
                outputs: [FeatureOutput(role: .profile)]
            ),
            secondID: FeatureNode(
                id: secondID,
                operation: .extrude(ExtrudeFeature(
                    profile: ProfileReference(featureID: firstID),
                    distance: .constant(.length(1.0, unit: .meter))
                )),
                inputs: [FeatureInput(featureID: firstID, role: .profile)],
                outputs: [FeatureOutput(role: .body)]
            )
        ]
        let missingInputGraph = DesignGraph(
            nodes: missingInputNodes,
            order: [firstID],
            dependencies: []
        )
        let wrongInputOrderGraph = DesignGraph(
            nodes: wrongOrderNodes,
            order: [secondID, firstID],
            dependencies: []
        )

        #expect(throws: FeatureEvaluationError.self) {
            try missingInputGraph.validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try wrongInputOrderGraph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsOperationContractViolations() {
        let sketchID = FeatureID()
        let extrudeID = FeatureID()
        let sketchWithoutOutput = DesignGraph(
            nodes: [
                sketchID: FeatureNode(id: sketchID, operation: .sketch(Sketch(plane: .xy)))
            ],
            order: [sketchID]
        )
        let extrudeWithoutBodyOutput = DesignGraph(
            nodes: [
                sketchID: FeatureNode(
                    id: sketchID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                extrudeID: FeatureNode(
                    id: extrudeID,
                    operation: .extrude(ExtrudeFeature(
                        profile: ProfileReference(featureID: sketchID),
                        distance: .constant(.length(1.0, unit: .meter))
                    )),
                    inputs: [FeatureInput(featureID: sketchID, role: .profile)]
                )
            ],
            order: [sketchID, extrudeID],
            dependencies: [DependencyEdge(source: sketchID, target: extrudeID)]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try sketchWithoutOutput.validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try extrudeWithoutBodyOutput.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphAcceptsSweepWithProfilePathAndGuides() throws {
        let profileID = FeatureID()
        let pathID = FeatureID()
        let guideID = FeatureID()
        let sweepID = FeatureID()
        let graph = DesignGraph(
            nodes: [
                profileID: FeatureNode(
                    id: profileID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                pathID: FeatureNode(
                    id: pathID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .curve)]
                ),
                guideID: FeatureNode(
                    id: guideID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .curve)]
                ),
                sweepID: FeatureNode(
                    id: sweepID,
                    operation: .sweep(
                        SweepFeature(
                            profiles: [ProfileReference(featureID: profileID)],
                            path: SweepPathReference(featureID: pathID),
                            guides: [SweepGuideReference(featureID: guideID)],
                            options: SweepOptions(
                                twistAngle: .constant(.angle(30.0, unit: .degree)),
                                endScale: .constant(.scalar(1.25)),
                                alignment: .parallel,
                                distanceFraction: .constant(.scalar(0.75)),
                                cornerStyle: .round,
                                guideMethod: .chord,
                                booleanOperation: .newBody,
                                keepTools: false,
                                simplify: true,
                                resultKind: .solid
                            )
                        )
                    ),
                    inputs: [
                        FeatureInput(featureID: profileID, role: .profile),
                        FeatureInput(featureID: pathID, role: .path),
                        FeatureInput(featureID: guideID, role: .guide),
                    ],
                    outputs: [FeatureOutput(role: .body)]
                ),
            ],
            order: [profileID, pathID, guideID, sweepID],
            dependencies: [
                DependencyEdge(source: profileID, target: sweepID),
                DependencyEdge(source: pathID, target: sweepID),
                DependencyEdge(source: guideID, target: sweepID),
            ]
        )

        try graph.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphAcceptsBridgeCurveFeatureOutput() throws {
        let bridgeID = FeatureID()
        let graph = DesignGraph(
            nodes: [
                bridgeID: FeatureNode(
                    id: bridgeID,
                    operation: .bridgeCurve(makeBridgeCurveFeature()),
                    outputs: [FeatureOutput(role: .curve)]
                )
            ],
            order: [bridgeID]
        )

        try graph.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsBridgeCurveFeatureWithNonCurveOutput() throws {
        let bridgeID = FeatureID()
        let graph = DesignGraph(
            nodes: [
                bridgeID: FeatureNode(
                    id: bridgeID,
                    operation: .bridgeCurve(makeBridgeCurveFeature()),
                    outputs: [FeatureOutput(role: .body)]
                )
            ],
            order: [bridgeID]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try graph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsBridgeCurveFeatureWithInputs() throws {
        let sourceID = FeatureID()
        let bridgeID = FeatureID()
        let graph = DesignGraph(
            nodes: [
                sourceID: FeatureNode(
                    id: sourceID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .curve)]
                ),
                bridgeID: FeatureNode(
                    id: bridgeID,
                    operation: .bridgeCurve(makeBridgeCurveFeature()),
                    inputs: [FeatureInput(featureID: sourceID, role: .curve)],
                    outputs: [FeatureOutput(role: .curve)]
                ),
            ],
            order: [sourceID, bridgeID],
            dependencies: [DependencyEdge(source: sourceID, target: bridgeID)]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try graph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphAcceptsCurveEditFeatureOutput() throws {
        let sourceID = FeatureID()
        let editID = FeatureID()
        let source = CurveOutputReference(featureID: sourceID)
        let graph = DesignGraph(
            nodes: [
                sourceID: FeatureNode(
                    id: sourceID,
                    operation: .bridgeCurve(makeBridgeCurveFeature()),
                    outputs: [FeatureOutput(role: .curve)]
                ),
                editID: FeatureNode(
                    id: editID,
                    operation: .curveEdit(CurveEditFeature(
                        source: source,
                        edits: [
                            .setControlPoint(CurveControlPointEdit(
                                target: CurveControlPointReference(curve: source, controlPointIndex: 1),
                                point: Point3D(x: 0.0, y: 1.0, z: 0.0)
                            ))
                        ]
                    )),
                    inputs: [FeatureInput(featureID: sourceID, role: .curve)],
                    outputs: [FeatureOutput(role: .curve)]
                ),
            ],
            order: [sourceID, editID],
            dependencies: [DependencyEdge(source: sourceID, target: editID)]
        )

        try graph.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsCurveEditFeatureWithNonCurveSource() throws {
        let sourceID = FeatureID()
        let editID = FeatureID()
        let source = CurveOutputReference(featureID: sourceID)
        let graph = DesignGraph(
            nodes: [
                sourceID: FeatureNode(
                    id: sourceID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                editID: FeatureNode(
                    id: editID,
                    operation: .curveEdit(CurveEditFeature(
                        source: source,
                        edits: [
                            .setKnot(CurveKnotEdit(
                                target: CurveKnotReference(curve: source, knotIndex: 3),
                                value: 0.5
                            ))
                        ]
                    )),
                    inputs: [FeatureInput(featureID: sourceID, role: .curve)],
                    outputs: [FeatureOutput(role: .curve)]
                ),
            ],
            order: [sourceID, editID],
            dependencies: [DependencyEdge(source: sourceID, target: editID)]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try graph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func selectionReferenceRoundTripsEdgeParameterReference() throws {
        let edgeName = PersistentName(components: [
            .feature(FeatureID()),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .index(2),
        ])
        let reference = SelectionReference.edge(.parameter(EdgeParameterReference(
            edge: EdgeReference(edgeName: edgeName),
            parameter: 0.25
        )))

        try reference.validate()
        let data = try JSONEncoder().encode(reference)
        let decoded = try JSONDecoder().decode(SelectionReference.self, from: data)

        #expect(decoded == reference)
    }

    @Test(.timeLimit(.minutes(1)))
    func selectionReferenceRoundTripsCurveControlPointReference() throws {
        let featureID = FeatureID()
        let reference = SelectionReference.curve(.controlPoint(CurveControlPointReference(
            curve: CurveOutputReference(featureID: featureID, curveIndex: 1),
            controlPointIndex: 3
        )))

        try reference.validate()
        let data = try JSONEncoder().encode(reference)
        let decoded = try JSONDecoder().decode(SelectionReference.self, from: data)

        #expect(decoded == reference)
    }

    @Test(.timeLimit(.minutes(1)))
    func selectionReferenceRejectsNegativeCurveSubobjectIndexes() throws {
        let featureID = FeatureID()

        #expect(throws: FeatureEvaluationError.self) {
            try CurveOutputReference(featureID: featureID, curveIndex: -1).validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try CurveSpanReference(
                curve: CurveOutputReference(featureID: featureID),
                spanIndex: -1
            ).validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try CurveControlPointReference(
                curve: CurveOutputReference(featureID: featureID),
                controlPointIndex: -1
            ).validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try CurveKnotReference(
                curve: CurveOutputReference(featureID: featureID),
                knotIndex: -1
            ).validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func selectionReferenceRoundTripsSurfaceControlPointReference() throws {
        let faceName = PersistentName(components: [
            .feature(FeatureID()),
            .generated("polySpline"),
            .subshape("patch:0:face"),
        ])
        let reference = SelectionReference.surface(.controlPoint(SurfaceControlPointReference(
            surface: SurfaceReference(faceName: faceName),
            uIndex: 2,
            vIndex: 3
        )))

        try reference.validate()
        let data = try JSONEncoder().encode(reference)
        let decoded = try JSONDecoder().decode(SelectionReference.self, from: data)

        #expect(decoded == reference)
    }

    @Test(.timeLimit(.minutes(1)))
    func selectionReferenceRoundTripsSurfaceTrimReference() throws {
        let faceName = PersistentName(components: [
            .feature(FeatureID()),
            .generated("polySpline"),
            .subshape("patch:0:face"),
        ])
        let reference = SelectionReference.surface(.trim(SurfaceTrimReference(
            surface: SurfaceReference(faceName: faceName),
            loopIndex: 0,
            edgeIndex: 2
        )))

        try reference.validate()
        let data = try JSONEncoder().encode(reference)
        let decoded = try JSONDecoder().decode(SelectionReference.self, from: data)

        #expect(decoded == reference)
    }

    @Test(.timeLimit(.minutes(1)))
    func selectionReferenceRejectsNegativeSurfaceSubobjectIndexes() throws {
        let faceName = PersistentName(components: [
            .feature(FeatureID()),
            .generated("surface"),
        ])
        let surface = SurfaceReference(faceName: faceName)

        #expect(throws: FeatureEvaluationError.self) {
            try SurfaceSpanReference(surface: surface, direction: .u, spanIndex: -1).validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try SurfaceControlPointReference(surface: surface, uIndex: -1, vIndex: 0).validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try SurfaceControlPointReference(surface: surface, uIndex: 0, vIndex: -1).validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try SurfaceKnotReference(surface: surface, direction: .v, knotIndex: -1).validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try SurfaceTrimReference(surface: surface, loopIndex: -1, edgeIndex: 0).validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try SurfaceTrimReference(surface: surface, loopIndex: 0, edgeIndex: -1).validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentSelectionDimensionsValidateAndAffectSourceFingerprint() throws {
        let featureID = FeatureID()
        let lineID = SketchEntityID()
        let dimensionID = SelectionDimensionID()
        let curve = CurveOutputReference(featureID: featureID)
        let dimension = SelectionDimension(
            id: dimensionID,
            kind: .distance,
            first: .curve(.parameter(CurveParameterReference(curve: curve, parameter: 0.0))),
            second: .curve(.parameter(CurveParameterReference(curve: curve, parameter: 1.0))),
            target: .constant(.length(1.0, unit: .meter))
        )
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    featureID: FeatureNode(
                        id: featureID,
                        operation: .sketch(Sketch(
                            plane: .xy,
                            entities: [
                                lineID: .line(SketchLine(
                                    start: SketchPoint(
                                        x: .constant(.length(0.0, unit: .meter)),
                                        y: .constant(.length(0.0, unit: .meter))
                                    ),
                                    end: SketchPoint(
                                        x: .constant(.length(1.0, unit: .meter)),
                                        y: .constant(.length(0.0, unit: .meter))
                                    )
                                ))
                            ]
                        )),
                        outputs: [
                            FeatureOutput(role: .profile),
                            FeatureOutput(role: .curve),
                        ]
                    )
                ],
                order: [featureID]
            ),
            selectionDimensions: [dimension]
        )
        var retargetedDocument = document
        retargetedDocument.selectionDimensions[0].target = .constant(.length(2.0, unit: .meter))
        let duplicateDimensionDocument = CADDocument(
            units: .meters,
            designGraph: document.designGraph,
            selectionDimensions: [dimension, dimension]
        )
        var wrongQuantityDocument = document
        wrongQuantityDocument.selectionDimensions[0].target = .constant(.angle(90.0, unit: .degree))

        try document.validate()
        try retargetedDocument.validate()
        #expect(try document.sourceFingerprint() != retargetedDocument.sourceFingerprint())
        #expect(throws: FeatureEvaluationError.self) {
            try duplicateDimensionDocument.validate()
        }
        #expect(throws: UnitError.self) {
            try wrongQuantityDocument.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cadDocumentAddsSelectionDimensionsThroughValidatedMutation() throws {
        let featureID = FeatureID()
        let lineID = SketchEntityID()
        let curve = CurveOutputReference(featureID: featureID)
        var document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    featureID: FeatureNode(
                        id: featureID,
                        operation: .sketch(Sketch(
                            plane: .xy,
                            entities: [
                                lineID: .line(SketchLine(
                                    start: SketchPoint(
                                        x: .constant(.length(0.0, unit: .meter)),
                                        y: .constant(.length(0.0, unit: .meter))
                                    ),
                                    end: SketchPoint(
                                        x: .constant(.length(1.0, unit: .meter)),
                                        y: .constant(.length(0.0, unit: .meter))
                                    )
                                ))
                            ]
                        )),
                        outputs: [
                            FeatureOutput(role: .profile),
                            FeatureOutput(role: .curve),
                        ]
                    )
                ],
                order: [featureID]
            )
        )

        let dimensionID = try document.addSelectionDimension(
            name: "Line length",
            kind: .distance,
            first: .curve(.parameter(CurveParameterReference(curve: curve, parameter: 0.0))),
            second: .curve(.parameter(CurveParameterReference(curve: curve, parameter: 1.0))),
            target: .constant(.length(1.0, unit: .meter))
        )

        #expect(document.selectionDimensions.count == 1)
        #expect(document.selectionDimensions[0].id == dimensionID)
        #expect(document.selectionDimensions[0].name == "Line length")

        var duplicateDocument = document
        let duplicateDimension = try #require(document.selectionDimensions.first)
        #expect(throws: FeatureEvaluationError.self) {
            try duplicateDocument.addSelectionDimension(duplicateDimension)
        }
        #expect(duplicateDocument.selectionDimensions == document.selectionDimensions)

        var invalidDocument = document
        #expect(throws: UnitError.self) {
            try invalidDocument.addSelectionDimension(
                kind: .distance,
                first: .curve(.parameter(CurveParameterReference(curve: curve, parameter: 0.0))),
                second: .curve(.parameter(CurveParameterReference(curve: curve, parameter: 1.0))),
                target: .constant(.angle(90.0, unit: .degree))
            )
        }
        #expect(invalidDocument.selectionDimensions == document.selectionDimensions)
    }

    @Test(.timeLimit(.minutes(1)))
    func cadDocumentUpsertsAndDeletesParametersThroughCentralMutation() throws {
        var document = CADDocument(units: .meters)

        let widthID = document.upsertParameter(
            name: "width",
            expression: .constant(.length(1.0, unit: .meter)),
            kind: .length
        )
        let updatedWidthID = document.upsertParameter(
            name: "width",
            expression: .constant(.length(2.0, unit: .meter)),
            kind: .length
        )

        #expect(widthID == updatedWidthID)
        #expect(document.parameterID(named: "width") == widthID)
        #expect(document.parameters.parameters.count == 1)
        #expect(document.parameters.revision.value == 2)

        let deletedID = try document.deleteParameter(named: "width")
        #expect(deletedID == widthID)
        #expect(document.parameters.parameters.isEmpty)
        #expect(document.parameters.revision.value == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func cadDocumentRejectsReferencedParameterDeleteWithoutMutation() throws {
        var document = CADDocument(units: .meters)
        let widthID = document.upsertParameter(
            name: "width",
            expression: .constant(.length(1.0, unit: .meter)),
            kind: .length
        )
        document.upsertParameter(
            name: "height",
            expression: .multiply(
                .reference(widthID),
                .constant(.scalar(2.0))
            ),
            kind: .length
        )
        let before = document.parameters

        #expect(throws: ParameterError.self) {
            try document.deleteParameter(named: "width")
        }
        #expect(document.parameters.parameters.keys.sorted { $0.description < $1.description } ==
            before.parameters.keys.sorted { $0.description < $1.description })
        #expect(document.parameters.revision == before.revision)
        #expect(document.parameterID(named: "width") == widthID)
    }

    @Test(.timeLimit(.minutes(1)))
    func cadDocumentAppendsFeaturesWithDerivedDependenciesThroughCentralMutation() throws {
        var document = CADDocument(units: .meters)
        let sketchID = FeatureID()
        let sketchFeature = FeatureNode(
            id: sketchID,
            operation: .sketch(Sketch(plane: .xy)),
            outputs: [FeatureOutput(role: .profile)]
        )

        let appendedSketchID = try document.appendFeature(sketchFeature)
        #expect(appendedSketchID == sketchID)
        #expect(document.designGraph.order == [sketchID])
        #expect(document.designGraph.dependencies.isEmpty)
        #expect(document.designGraph.revision.value == 1)

        let extrudeID = FeatureID()
        let extrudeFeature = FeatureNode(
            id: extrudeID,
            operation: .extrude(ExtrudeFeature(
                profile: ProfileReference(featureID: sketchID),
                distance: .constant(.length(1.0, unit: .meter))
            )),
            inputs: [FeatureInput(featureID: sketchID, role: .profile)],
            outputs: [FeatureOutput(role: .body)]
        )

        let appendedExtrudeID = try document.appendFeature(extrudeFeature)
        #expect(appendedExtrudeID == extrudeID)
        #expect(document.designGraph.order == [sketchID, extrudeID])
        #expect(document.designGraph.dependencies == [
            DependencyEdge(source: sketchID, target: extrudeID),
        ])
        #expect(document.designGraph.revision.value == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func cadDocumentRejectsInvalidFeatureAppendWithoutMutation() throws {
        var document = CADDocument(units: .meters)
        let missingProfileID = FeatureID()
        let extrudeFeature = FeatureNode(
            operation: .extrude(ExtrudeFeature(
                profile: ProfileReference(featureID: missingProfileID),
                distance: .constant(.length(1.0, unit: .meter))
            )),
            inputs: [FeatureInput(featureID: missingProfileID, role: .profile)],
            outputs: [FeatureOutput(role: .body)]
        )
        let before = document.designGraph

        #expect(throws: FeatureEvaluationError.self) {
            try document.appendFeature(extrudeFeature)
        }
        #expect(document.designGraph.nodes.keys.sorted { $0.description < $1.description } ==
            before.nodes.keys.sorted { $0.description < $1.description })
        #expect(document.designGraph.order == before.order)
        #expect(document.designGraph.dependencies == before.dependencies)
        #expect(document.designGraph.revision == before.revision)
    }

    @Test(.timeLimit(.minutes(1)))
    func cadDocumentReplacesFeatureThroughCentralMutation() throws {
        var document = CADDocument(units: .meters)
        let sketchID = try document.appendFeature(FeatureNode(
            operation: .sketch(Sketch(plane: .xy)),
            outputs: [FeatureOutput(role: .profile)]
        ))
        let extrudeID = FeatureID()
        try document.appendFeature(FeatureNode(
            id: extrudeID,
            operation: .extrude(ExtrudeFeature(
                profile: ProfileReference(featureID: sketchID),
                distance: .constant(.length(1.0, unit: .meter))
            )),
            inputs: [FeatureInput(featureID: sketchID, role: .profile)],
            outputs: [FeatureOutput(role: .body)]
        ))

        var replacement = try #require(document.designGraph.nodes[extrudeID])
        replacement.name = "Updated Extrude"
        replacement.operation = .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: sketchID),
            distance: .constant(.length(2.0, unit: .meter))
        ))

        let replacedID = try document.replaceFeature(replacement)
        let replacedFeature = try #require(document.designGraph.nodes[extrudeID])

        #expect(replacedID == extrudeID)
        #expect(replacedFeature.name == "Updated Extrude")
        #expect(document.designGraph.order == [sketchID, extrudeID])
        #expect(document.designGraph.dependencies == [
            DependencyEdge(source: sketchID, target: extrudeID),
        ])
        #expect(document.designGraph.revision.value == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func cadDocumentReplacesMultipleFeaturesWithSingleRevision() throws {
        var document = CADDocument(units: .meters)
        let sketchID = try document.appendFeature(FeatureNode(
            operation: .sketch(Sketch(plane: .xy)),
            outputs: [FeatureOutput(role: .profile)]
        ))
        let extrudeID = try document.appendFeature(FeatureNode(
            operation: .extrude(ExtrudeFeature(
                profile: ProfileReference(featureID: sketchID),
                distance: .constant(.length(1.0, unit: .meter))
            )),
            inputs: [FeatureInput(featureID: sketchID, role: .profile)],
            outputs: [FeatureOutput(role: .body)]
        ))

        var sketchReplacement = try #require(document.designGraph.nodes[sketchID])
        sketchReplacement.name = "Updated Sketch"
        var extrudeReplacement = try #require(document.designGraph.nodes[extrudeID])
        extrudeReplacement.name = "Updated Body"

        let replacedIDs = try document.replaceFeatures([sketchReplacement, extrudeReplacement])

        #expect(replacedIDs == [sketchID, extrudeID])
        #expect(document.designGraph.nodes[sketchID]?.name == "Updated Sketch")
        #expect(document.designGraph.nodes[extrudeID]?.name == "Updated Body")
        #expect(document.designGraph.dependencies == [
            DependencyEdge(source: sketchID, target: extrudeID),
        ])
        #expect(document.designGraph.revision.value == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func cadDocumentRejectsInvalidFeatureReplacementWithoutMutation() throws {
        var document = CADDocument(units: .meters)
        let sketchID = try document.appendFeature(FeatureNode(
            operation: .sketch(Sketch(plane: .xy)),
            outputs: [FeatureOutput(role: .profile)]
        ))
        let before = document.designGraph
        let missingFeature = FeatureNode(
            operation: .extrude(ExtrudeFeature(
                profile: ProfileReference(featureID: sketchID),
                distance: .constant(.length(1.0, unit: .meter))
            )),
            inputs: [FeatureInput(featureID: sketchID, role: .profile)],
            outputs: [FeatureOutput(role: .body)]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try document.replaceFeature(missingFeature)
        }
        #expect(document.designGraph.nodes.keys.sorted { $0.description < $1.description } ==
            before.nodes.keys.sorted { $0.description < $1.description })
        #expect(document.designGraph.order == before.order)
        #expect(document.designGraph.dependencies == before.dependencies)
        #expect(document.designGraph.revision == before.revision)
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphAcceptsSweepBooleanWithTargetBodyInput() throws {
        let targetProfileID = FeatureID()
        let targetBodyID = FeatureID()
        let profileID = FeatureID()
        let pathID = FeatureID()
        let sweepID = FeatureID()
        let graph = DesignGraph(
            nodes: [
                targetProfileID: FeatureNode(
                    id: targetProfileID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                targetBodyID: FeatureNode(
                    id: targetBodyID,
                    operation: .extrude(ExtrudeFeature(
                        profile: ProfileReference(featureID: targetProfileID),
                        distance: .constant(.length(10.0, unit: .millimeter))
                    )),
                    inputs: [FeatureInput(featureID: targetProfileID, role: .profile)],
                    outputs: [FeatureOutput(role: .body)]
                ),
                profileID: FeatureNode(
                    id: profileID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                pathID: FeatureNode(
                    id: pathID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .curve)]
                ),
                sweepID: FeatureNode(
                    id: sweepID,
                    operation: .sweep(
                        SweepFeature(
                            profiles: [ProfileReference(featureID: profileID)],
                            path: SweepPathReference(featureID: pathID),
                            targets: [SweepTargetReference(featureID: targetBodyID)],
                            options: SweepOptions(booleanOperation: .union)
                        )
                    ),
                    inputs: [
                        FeatureInput(featureID: profileID, role: .profile),
                        FeatureInput(featureID: pathID, role: .path),
                        FeatureInput(featureID: targetBodyID, role: .target),
                    ],
                    outputs: [FeatureOutput(role: .body)]
                ),
            ],
            order: [targetProfileID, targetBodyID, profileID, pathID, sweepID],
            dependencies: [
                DependencyEdge(source: targetProfileID, target: targetBodyID),
                DependencyEdge(source: profileID, target: sweepID),
                DependencyEdge(source: pathID, target: sweepID),
                DependencyEdge(source: targetBodyID, target: sweepID),
            ]
        )

        try graph.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsInvalidSweepContracts() {
        let profileID = FeatureID()
        let pathID = FeatureID()
        let sweepID = FeatureID()
        let sourceNodes = [
            profileID: FeatureNode(
                id: profileID,
                operation: .sketch(Sketch(plane: .xy)),
                outputs: [FeatureOutput(role: .profile)]
            ),
            pathID: FeatureNode(
                id: pathID,
                operation: .sketch(Sketch(plane: .xy)),
                outputs: [FeatureOutput(role: .curve)]
            ),
        ]
        let sweep = SweepFeature(
            profiles: [ProfileReference(featureID: profileID)],
            path: SweepPathReference(featureID: pathID)
        )
        let missingPathInput = DesignGraph(
            nodes: sourceNodes.merging([
                sweepID: FeatureNode(
                    id: sweepID,
                    operation: .sweep(sweep),
                    inputs: [FeatureInput(featureID: profileID, role: .profile)],
                    outputs: [FeatureOutput(role: .body)]
                ),
            ]) { current, _ in current },
            order: [profileID, pathID, sweepID],
            dependencies: [DependencyEdge(source: profileID, target: sweepID)]
        )
        let wrongOutput = DesignGraph(
            nodes: sourceNodes.merging([
                sweepID: FeatureNode(
                    id: sweepID,
                    operation: .sweep(sweep),
                    inputs: [
                        FeatureInput(featureID: profileID, role: .profile),
                        FeatureInput(featureID: pathID, role: .path),
                    ],
                    outputs: [FeatureOutput(role: .sheet)]
                ),
            ]) { current, _ in current },
            order: [profileID, pathID, sweepID],
            dependencies: [
                DependencyEdge(source: profileID, target: sweepID),
                DependencyEdge(source: pathID, target: sweepID),
            ]
        )
        let booleanWithoutTarget = DesignGraph(
            nodes: sourceNodes.merging([
                sweepID: FeatureNode(
                    id: sweepID,
                    operation: .sweep(SweepFeature(
                        profiles: [ProfileReference(featureID: profileID)],
                        path: SweepPathReference(featureID: pathID),
                        options: SweepOptions(booleanOperation: .union)
                    )),
                    inputs: [
                        FeatureInput(featureID: profileID, role: .profile),
                        FeatureInput(featureID: pathID, role: .path),
                    ],
                    outputs: [FeatureOutput(role: .body)]
                ),
            ]) { current, _ in current },
            order: [profileID, pathID, sweepID],
            dependencies: [
                DependencyEdge(source: profileID, target: sweepID),
                DependencyEdge(source: pathID, target: sweepID),
            ]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try missingPathInput.validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try wrongOutput.validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try booleanWithoutTarget.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsInputsWithoutDependencyEdges() {
        let sketchID = FeatureID()
        let extrudeID = FeatureID()
        let graph = DesignGraph(
            nodes: [
                sketchID: FeatureNode(
                    id: sketchID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                extrudeID: FeatureNode(
                    id: extrudeID,
                    operation: .extrude(ExtrudeFeature(
                        profile: ProfileReference(featureID: sketchID),
                        distance: .constant(.length(1.0, unit: .meter))
                    )),
                    inputs: [FeatureInput(featureID: sketchID, role: .profile)],
                    outputs: [FeatureOutput(role: .body)]
                )
            ],
            order: [sketchID, extrudeID],
            dependencies: []
        )

        #expect(throws: FeatureEvaluationError.self) {
            try graph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsDependencyEdgesWithoutFeatureInputs() {
        let firstID = FeatureID()
        let secondID = FeatureID()
        let graph = DesignGraph(
            nodes: [
                firstID: FeatureNode(
                    id: firstID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                secondID: FeatureNode(
                    id: secondID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                )
            ],
            order: [firstID, secondID],
            dependencies: [DependencyEdge(source: firstID, target: secondID)]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try graph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsActiveFeaturesDependingOnSuppressedSources() {
        let sketchID = FeatureID()
        let extrudeID = FeatureID()
        let graph = DesignGraph(
            nodes: [
                sketchID: FeatureNode(
                    id: sketchID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)],
                    isSuppressed: true
                ),
                extrudeID: FeatureNode(
                    id: extrudeID,
                    operation: .extrude(ExtrudeFeature(
                        profile: ProfileReference(featureID: sketchID),
                        distance: .constant(.length(1.0, unit: .meter))
                    )),
                    inputs: [FeatureInput(featureID: sketchID, role: .profile)],
                    outputs: [FeatureOutput(role: .body)]
                )
            ],
            order: [sketchID, extrudeID],
            dependencies: [DependencyEdge(source: sketchID, target: extrudeID)]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try graph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchValidationRejectsInvalidReferences() {
        let circleID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                circleID: .circle(SketchCircle(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .constant(.length(1.0, unit: .meter))
                ))
            ],
            constraints: [.horizontal(circleID)],
            dimensions: []
        )

        #expect(throws: SketchError.self) {
            try sketch.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchValidationChecksArcExpressionKinds() throws {
        let arcID = SketchEntityID()
        let invalidSketch = Sketch(
            plane: .xy,
            entities: [
                arcID: .arc(SketchArc(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .constant(.length(1.0, unit: .meter)),
                    startAngle: .constant(.scalar(0.0)),
                    endAngle: .constant(.angle(90.0, unit: .degree))
                ))
            ],
            dimensions: [.radius(entity: arcID, value: .constant(.length(1.0, unit: .meter)))]
        )

        try invalidSketch.validate()
        let graph = try invalidSketch.constraintGraph()
        #expect(graph.nodes.contains(SketchConstraintNode(reference: .arcRadius(arcID), degreeOfFreedom: .radius)))
        #expect(throws: UnitError.self) {
            try invalidSketch.validateExpressions(using: ParameterTable())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchBuildsSolverReadyConstraintGraph() throws {
        let lineID = SketchEntityID()
        let circleID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                lineID: .line(SketchLine(
                    start: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    end: SketchPoint(
                        x: .constant(.length(1.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    )
                )),
                circleID: .circle(SketchCircle(
                    center: SketchPoint(
                        x: .constant(.length(0.5, unit: .meter)),
                        y: .constant(.length(0.5, unit: .meter))
                    ),
                    radius: .constant(.length(0.25, unit: .meter))
                ))
            ],
            constraints: [
                .horizontal(lineID),
                .coincident(.lineStart(lineID), .circleCenter(circleID))
            ],
            dimensions: [
                .radius(entity: circleID, value: .constant(.length(0.25, unit: .meter)))
            ]
        )

        let graph = try sketch.constraintGraph()

        #expect(graph.equations.map(\.kind) == [.horizontal, .coincident, .radius])
        #expect(graph.nodes.contains(SketchConstraintNode(reference: .entity(lineID), degreeOfFreedom: .angle)))
        #expect(graph.nodes.contains(SketchConstraintNode(reference: .circleRadius(circleID), degreeOfFreedom: .radius)))
        let radiusEquation = try #require(graph.equations.first { $0.kind == .radius })
        #expect(radiusEquation.target == .constant(.length(0.25, unit: .meter)))
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchConstraintGraphValidatesDimensionTargets() {
        let reference = SketchReference.circleRadius(SketchEntityID())
        let node = SketchConstraintNode(reference: reference, degreeOfFreedom: .radius)

        #expect(throws: SketchError.self) {
            try SketchConstraintGraph(
                nodes: [node],
                equations: [SketchConstraintEquation(kind: .radius, nodes: [node])]
            ).validate()
        }

        #expect(throws: SketchError.self) {
            try SketchConstraintGraph(
                nodes: [node],
                equations: [
                    SketchConstraintEquation(
                        kind: .fixed,
                        nodes: [node],
                        target: .constant(.length(0.25, unit: .meter))
                    )
                ]
            ).validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchDimensionEvaluatorReportsDistanceResiduals() throws {
        let firstID = SketchEntityID()
        let secondID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                firstID: .point(SketchPoint(
                    x: .constant(.length(0.0, unit: .meter)),
                    y: .constant(.length(0.0, unit: .meter))
                )),
                secondID: .point(SketchPoint(
                    x: .constant(.length(3.0, unit: .meter)),
                    y: .constant(.length(4.0, unit: .meter))
                ))
            ],
            dimensions: [
                .distance(
                    from: .entity(firstID),
                    to: .entity(secondID),
                    value: .constant(.length(6.0, unit: .meter))
                )
            ]
        )

        let evaluation = try SketchDimensionEvaluator().evaluate(sketch)
        let measurement = try #require(evaluation.measurements.first)

        #expect(measurement.measured == .length(5.0, unit: .meter))
        #expect(measurement.target == .length(6.0, unit: .meter))
        #expect(measurement.residual == .length(-1.0, unit: .meter))
        #expect(try evaluation.isSatisfied() == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchDimensionEvaluatorResolvesParameterizedTargets() throws {
        let radiusID = ParameterID()
        let circleID = SketchEntityID()
        let parameters = ParameterTable(parameters: [
            radiusID: Parameter(
                id: radiusID,
                name: "radius",
                expression: .constant(.length(0.25, unit: .meter)),
                kind: .length
            )
        ])
        let sketch = Sketch(
            plane: .xy,
            entities: [
                circleID: .circle(SketchCircle(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .constant(.length(0.25, unit: .meter))
                ))
            ],
            dimensions: [
                .radius(entity: circleID, value: .reference(radiusID))
            ]
        )

        let evaluation = try SketchDimensionEvaluator(parameters: parameters).evaluate(sketch)
        let measurement = try #require(evaluation.measurements.first)

        #expect(measurement.measured == .length(0.25, unit: .meter))
        #expect(measurement.target == .length(0.25, unit: .meter))
        #expect(measurement.residual == .length(0.0, unit: .meter))
        #expect(try evaluation.isSatisfied())
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchDimensionEvaluatorMeasuresLineOrientationAngles() throws {
        let lineID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                lineID: .line(SketchLine(
                    start: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    end: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(1.0, unit: .meter))
                    )
                ))
            ],
            dimensions: [
                .angle(
                    from: .lineStart(lineID),
                    to: .lineEnd(lineID),
                    value: .constant(.angle(90.0, unit: .degree))
                )
            ]
        )

        let evaluation = try SketchDimensionEvaluator().evaluate(sketch)
        let measurement = try #require(evaluation.measurements.first)

        #expect(abs(measurement.measured.value - Double.pi / 2.0) <= 1.0e-12)
        #expect(measurement.measured.kind == .angle)
        #expect(abs(measurement.residual.value) <= 1.0e-12)
        #expect(try evaluation.isSatisfied())
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchDimensionEvaluatorMeasuresArcSpanAngles() throws {
        let arcID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                arcID: .arc(SketchArc(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .constant(.length(1.0, unit: .meter)),
                    startAngle: .constant(.angle(0.0, unit: .degree)),
                    endAngle: .constant(.angle(90.0, unit: .degree))
                ))
            ],
            dimensions: [
                .angle(
                    from: .arcStart(arcID),
                    to: .arcEnd(arcID),
                    value: .constant(.angle(90.0, unit: .degree))
                )
            ]
        )

        let evaluation = try SketchDimensionEvaluator().evaluate(sketch)
        let measurement = try #require(evaluation.measurements.first)

        #expect(abs(measurement.measured.value - Double.pi / 2.0) <= 1.0e-12)
        #expect(measurement.measured.kind == .angle)
        #expect(abs(measurement.residual.value) <= 1.0e-12)
        #expect(try evaluation.isSatisfied())
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchDimensionSolverAppliesLineLengthDimensions() throws {
        let lineID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                lineID: .line(SketchLine(
                    start: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    end: SketchPoint(
                        x: .constant(.length(1.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    )
                ))
            ],
            dimensions: [
                .distance(
                    from: .lineStart(lineID),
                    to: .lineEnd(lineID),
                    value: .constant(.length(2.0, unit: .meter))
                )
            ]
        )

        let result = try SketchDimensionSolver().solve(sketch)

        #expect(result.steps.map(\.status) == [.applied])
        #expect(try result.after.isSatisfied())
        guard case let .line(line) = result.sketch.entities[lineID] else {
            Issue.record("Expected solved sketch to keep a line entity.")
            return
        }
        let x = try ParameterTable().resolvedValue(for: line.end.x)
        let y = try ParameterTable().resolvedValue(for: line.end.y)
        #expect(abs(x.value - 2.0) <= 1.0e-12)
        #expect(abs(y.value) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchDimensionSolverAppliesLineOrientationDimensions() throws {
        let lineID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                lineID: .line(SketchLine(
                    start: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    end: SketchPoint(
                        x: .constant(.length(1.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    )
                ))
            ],
            dimensions: [
                .angle(
                    from: .lineStart(lineID),
                    to: .lineEnd(lineID),
                    value: .constant(.angle(90.0, unit: .degree))
                )
            ]
        )

        let result = try SketchDimensionSolver().solve(sketch)

        #expect(result.steps.map(\.status) == [.applied])
        #expect(try result.after.isSatisfied())
        guard case let .line(line) = result.sketch.entities[lineID] else {
            Issue.record("Expected solved sketch to keep a line entity.")
            return
        }
        let x = try ParameterTable().resolvedValue(for: line.end.x)
        let y = try ParameterTable().resolvedValue(for: line.end.y)
        #expect(abs(x.value) <= 1.0e-12)
        #expect(abs(y.value - 1.0) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchDimensionSolverAppliesCircularDimensions() throws {
        let radiusID = ParameterID()
        let circleID = SketchEntityID()
        let parameters = ParameterTable(parameters: [
            radiusID: Parameter(
                id: radiusID,
                name: "radius",
                expression: .constant(.length(0.25, unit: .meter)),
                kind: .length
            )
        ])
        let sketch = Sketch(
            plane: .xy,
            entities: [
                circleID: .circle(SketchCircle(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .constant(.length(0.1, unit: .meter))
                ))
            ],
            dimensions: [
                .radius(entity: circleID, value: .reference(radiusID))
            ]
        )

        let result = try SketchDimensionSolver(parameters: parameters).solve(sketch)

        #expect(result.steps.map(\.status) == [.applied])
        #expect(try result.after.isSatisfied())
        guard case let .circle(circle) = result.sketch.entities[circleID] else {
            Issue.record("Expected solved sketch to keep a circle entity.")
            return
        }
        #expect(circle.radius == .reference(radiusID))
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchDimensionSolverAppliesArcSpanDimensions() throws {
        let arcID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                arcID: .arc(SketchArc(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .constant(.length(1.0, unit: .meter)),
                    startAngle: .constant(.angle(0.0, unit: .degree)),
                    endAngle: .constant(.angle(30.0, unit: .degree))
                ))
            ],
            dimensions: [
                .angle(
                    from: .arcStart(arcID),
                    to: .arcEnd(arcID),
                    value: .constant(.angle(90.0, unit: .degree))
                )
            ]
        )

        let result = try SketchDimensionSolver().solve(sketch)

        #expect(result.steps.map(\.status) == [.applied])
        #expect(try result.after.isSatisfied())
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchDimensionSolverAppliesPointDistanceDimensions() throws {
        let firstID = SketchEntityID()
        let secondID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                firstID: .point(SketchPoint(
                    x: .constant(.length(0.0, unit: .meter)),
                    y: .constant(.length(0.0, unit: .meter))
                )),
                secondID: .point(SketchPoint(
                    x: .constant(.length(1.0, unit: .meter)),
                    y: .constant(.length(0.0, unit: .meter))
                ))
            ],
            dimensions: [
                .distance(
                    from: .entity(firstID),
                    to: .entity(secondID),
                    value: .constant(.length(2.0, unit: .meter))
                )
            ]
        )

        let result = try SketchDimensionSolver().solve(sketch)

        #expect(result.steps.map(\.status) == [.applied])
        #expect(try result.after.isSatisfied())
        guard case let .point(point) = result.sketch.entities[secondID] else {
            Issue.record("Expected solved sketch to keep the target point entity.")
            return
        }
        let x = try ParameterTable().resolvedValue(for: point.x)
        let y = try ParameterTable().resolvedValue(for: point.y)
        #expect(abs(x.value - 2.0) <= 1.0e-12)
        #expect(abs(y.value) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchDimensionSolverReportsUnsupportedDerivedPointDistanceTargets() throws {
        let lineID = SketchEntityID()
        let arcID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                lineID: .line(SketchLine(
                    start: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    end: SketchPoint(
                        x: .constant(.length(1.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    )
                )),
                arcID: .arc(SketchArc(
                    center: SketchPoint(
                        x: .constant(.length(1.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .constant(.length(1.0, unit: .meter)),
                    startAngle: .constant(.angle(0.0, unit: .degree)),
                    endAngle: .constant(.angle(90.0, unit: .degree))
                ))
            ],
            dimensions: [
                .distance(
                    from: .lineStart(lineID),
                    to: .arcStart(arcID),
                    value: .constant(.length(3.0, unit: .meter))
                )
            ]
        )

        let result = try SketchDimensionSolver().solve(sketch)

        #expect(result.steps.map(\.status) == [.unsupported])
        #expect(try result.after.isSatisfied() == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchConstraintGraphIncludesEqualLengthEquations() throws {
        let firstLineID = SketchEntityID()
        let secondLineID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                firstLineID: .line(SketchLine(
                    start: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    end: SketchPoint(
                        x: .constant(.length(1.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    )
                )),
                secondLineID: .line(SketchLine(
                    start: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(1.0, unit: .meter))
                    ),
                    end: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(2.0, unit: .meter))
                    )
                )),
            ],
            constraints: [
                .equalLength(firstLineID, secondLineID),
            ]
        )

        let graph = try sketch.constraintGraph()

        #expect(graph.equations.map(\.kind) == [.equalLength])
        #expect(graph.nodes.contains(SketchConstraintNode(reference: .entity(firstLineID), degreeOfFreedom: .length)))
        #expect(graph.nodes.contains(SketchConstraintNode(reference: .entity(secondLineID), degreeOfFreedom: .length)))
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchConstraintGraphIncludesTangentEquations() throws {
        let lineID = SketchEntityID()
        let circleID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                lineID: .line(SketchLine(
                    start: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    end: SketchPoint(
                        x: .constant(.length(1.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    )
                )),
                circleID: .circle(SketchCircle(
                    center: SketchPoint(
                        x: .constant(.length(0.5, unit: .meter)),
                        y: .constant(.length(0.5, unit: .meter))
                    ),
                    radius: .constant(.length(0.25, unit: .meter))
                )),
            ],
            constraints: [
                .tangent(lineID, circleID),
            ]
        )

        let graph = try sketch.constraintGraph()

        #expect(graph.equations.map(\.kind) == [.tangent])
        #expect(graph.nodes.contains(SketchConstraintNode(reference: .entity(lineID), degreeOfFreedom: .angle)))
        #expect(graph.nodes.contains(SketchConstraintNode(reference: .circleCenter(circleID), degreeOfFreedom: .x)))
        #expect(graph.nodes.contains(SketchConstraintNode(reference: .circleCenter(circleID), degreeOfFreedom: .y)))
        #expect(graph.nodes.contains(SketchConstraintNode(reference: .circleRadius(circleID), degreeOfFreedom: .radius)))
    }

    @Test(.timeLimit(.minutes(1)))
    func tangentConstraintRejectsUnsupportedEntityPairs() throws {
        let firstLineID = SketchEntityID()
        let secondLineID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                firstLineID: .line(SketchLine(
                    start: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    end: SketchPoint(
                        x: .constant(.length(1.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    )
                )),
                secondLineID: .line(SketchLine(
                    start: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(1.0, unit: .meter))
                    ),
                    end: SketchPoint(
                        x: .constant(.length(1.0, unit: .meter)),
                        y: .constant(.length(1.0, unit: .meter))
                    )
                )),
            ],
            constraints: [
                .tangent(firstLineID, secondLineID),
            ]
        )

        #expect(throws: SketchError.self) {
            try sketch.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchConstraintGraphIncludesConcentricAndEqualRadiusEquations() throws {
        let circleID = SketchEntityID()
        let arcID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                circleID: .circle(SketchCircle(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .constant(.length(1.0, unit: .meter))
                )),
                arcID: .arc(SketchArc(
                    center: SketchPoint(
                        x: .constant(.length(0.5, unit: .meter)),
                        y: .constant(.length(0.5, unit: .meter))
                    ),
                    radius: .constant(.length(0.25, unit: .meter)),
                    startAngle: .constant(.angle(0.0, unit: .radian)),
                    endAngle: .constant(.angle(1.0, unit: .radian))
                )),
            ],
            constraints: [
                .concentric(circleID, arcID),
                .equalRadius(circleID, arcID),
            ]
        )

        let graph = try sketch.constraintGraph()

        #expect(graph.equations.map(\.kind) == [.concentric, .equalRadius])
        #expect(graph.nodes.contains(SketchConstraintNode(reference: .circleCenter(circleID), degreeOfFreedom: .x)))
        #expect(graph.nodes.contains(SketchConstraintNode(reference: .circleCenter(circleID), degreeOfFreedom: .y)))
        #expect(graph.nodes.contains(SketchConstraintNode(reference: .arcCenter(arcID), degreeOfFreedom: .x)))
        #expect(graph.nodes.contains(SketchConstraintNode(reference: .arcCenter(arcID), degreeOfFreedom: .y)))
        #expect(graph.nodes.contains(SketchConstraintNode(reference: .circleRadius(circleID), degreeOfFreedom: .radius)))
        #expect(graph.nodes.contains(SketchConstraintNode(reference: .arcRadius(arcID), degreeOfFreedom: .radius)))
    }

    @Test(.timeLimit(.minutes(1)))
    func circularConstraintsRejectUnsupportedEntityPairs() throws {
        let lineID = SketchEntityID()
        let circleID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                lineID: .line(SketchLine(
                    start: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    end: SketchPoint(
                        x: .constant(.length(1.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    )
                )),
                circleID: .circle(SketchCircle(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .constant(.length(1.0, unit: .meter))
                )),
            ],
            constraints: [
                .concentric(lineID, circleID),
            ]
        )

        #expect(throws: SketchError.self) {
            try sketch.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func curveAndSurfaceDomainsAreExplicitAndValidated() throws {
        let line = Curve3D.line(Line3D(origin: Point3D(x: 0.0, y: 0.0, z: 0.0), direction: .unitX))
        let circle = Curve3D.circle(Circle3D(center: Point3D(x: 0.0, y: 0.0, z: 0.0), normal: .unitZ, radius: 1.0))
        let bSpline = Curve3D.bSpline(makeQuarterCircleNURBSCurve())
        let plane = Surface3D.plane(Plane3D(origin: Point3D(x: 0.0, y: 0.0, z: 0.0), normal: .unitZ))
        let cylinder = Surface3D.cylinder(Cylinder3D(origin: .origin, axis: .unitZ, radius: 1.0))

        #expect(line.parameterDomain == .unbounded)
        #expect(circle.parameterDomain == .periodic(period: Double.pi * 2.0))
        #expect(bSpline.parameterDomain == .closed(0.0, 1.0))
        #expect(plane.uDomain == .unbounded)
        #expect(plane.vDomain == .unbounded)
        #expect(cylinder.uDomain == .periodic(period: Double.pi * 2.0))
        #expect(cylinder.vDomain == .unbounded)
        #expect(try circle.parameterDomain.containsSpan(from: -Double.pi, to: Double.pi))
        try bSpline.validate()
        try cylinder.validate()
        #expect(throws: GeometryError.self) {
            try ParameterDomain.closed(1.0, 1.0).validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalBSplineCurveRepresentsExactQuarterCircle() throws {
        let curve = makeQuarterCircleNURBSCurve()

        let start = try curve.point(at: 0.0)
        let middle = try curve.point(at: 0.5)
        let end = try curve.point(at: 1.0)
        let middleGeometry = try curve.differentialGeometry(at: 0.5)
        let radial = try Vector3D(x: middle.x, y: middle.y, z: middle.z)
            .normalized(tolerance: ModelingTolerance.standard.distance)

        #expect(curve.order == 3)
        #expect(curve.isRational == true)
        #expect(abs(start.x - 1.0) <= 1.0e-12)
        #expect(abs(start.y) <= 1.0e-12)
        #expect(abs(middle.x - sqrt(0.5)) <= 1.0e-12)
        #expect(abs(middle.y - sqrt(0.5)) <= 1.0e-12)
        #expect(abs(end.x) <= 1.0e-12)
        #expect(abs(end.y - 1.0) <= 1.0e-12)
        #expect(abs(middleGeometry.tangent.dot(radial)) <= 1.0e-12)
        #expect(abs(middleGeometry.curvature - 1.0) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalBSplineCurveRejectsInvalidWeights() {
        let curve = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 1.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0),
            ],
            weights: [1.0, 0.0, 1.0]
        )

        #expect(throws: GeometryError.self) {
            try curve.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func curve3DCommonDifferentialGeometryEvaluatesAnalyticCurves() throws {
        let line = Curve3D.line(Line3D(origin: .origin, direction: .unitX))
        let circle = Curve3D.circle(Circle3D(center: .origin, normal: .unitZ, radius: 2.0))

        let lineGeometry = try line.differentialGeometry(at: 3.0)
        let circleGeometry = try circle.differentialGeometry(at: 0.0)

        #expect(abs(lineGeometry.position.x - 3.0) <= 1.0e-12)
        #expect(abs(lineGeometry.tangent.x - 1.0) <= 1.0e-12)
        #expect(abs(lineGeometry.curvature) <= 1.0e-12)
        #expect(abs(circleGeometry.position.x - 2.0) <= 1.0e-12)
        #expect(abs(circleGeometry.position.y) <= 1.0e-12)
        #expect(abs(circleGeometry.tangent.x) <= 1.0e-12)
        #expect(abs(circleGeometry.tangent.y - 1.0) <= 1.0e-12)
        #expect(abs(circleGeometry.curvatureVector.x + 0.5) <= 1.0e-12)
        #expect(abs(circleGeometry.curvatureVector.y) <= 1.0e-12)
        #expect(abs(circleGeometry.curvature - 0.5) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func curveContinuityEvaluatorReportsCurvatureContinuityForAlignedLines() throws {
        let first = Curve3D.line(Line3D(origin: .origin, direction: .unitX))
        let second = Curve3D.line(Line3D(origin: .origin, direction: -Vector3D.unitX))
        let request = CurveContinuityRequest(
            first: CurveContinuityTarget(curve: first, parameter: 0.0),
            second: CurveContinuityTarget(curve: second, parameter: 0.0, orientation: .reversed),
            requiredLevel: .curvature
        )

        let result = try CurveContinuityEvaluator().evaluate(request)

        #expect(result.achievedLevel == .curvature)
        #expect(result.isSatisfied)
        #expect(abs(result.deviation.positionDistance) <= 1.0e-12)
        #expect(abs(result.deviation.tangentAngle) <= 1.0e-12)
        #expect(abs(result.deviation.curvatureVectorDistance) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func curveContinuityEvaluatorReportsOnlyPositionForTangentMismatch() throws {
        let first = Curve3D.line(Line3D(origin: .origin, direction: .unitX))
        let second = Curve3D.line(Line3D(origin: .origin, direction: .unitY))
        let request = CurveContinuityRequest(
            first: CurveContinuityTarget(curve: first, parameter: 0.0),
            second: CurveContinuityTarget(curve: second, parameter: 0.0),
            requiredLevel: .tangent
        )

        let result = try CurveContinuityEvaluator().evaluate(request)

        #expect(result.achievedLevel == .positional)
        #expect(!result.isSatisfied)
        #expect(abs(result.deviation.positionDistance) <= 1.0e-12)
        #expect(abs(result.deviation.tangentAngle - Double.pi / 2.0) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func curveContinuityEvaluatorReportsTangentForCurvatureMismatch() throws {
        let line = Curve3D.line(Line3D(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            direction: .unitY
        ))
        let quarterCircle = Curve3D.bSpline(makeQuarterCircleNURBSCurve())
        let request = CurveContinuityRequest(
            first: CurveContinuityTarget(curve: line, parameter: 0.0),
            second: CurveContinuityTarget(curve: quarterCircle, parameter: 0.0),
            requiredLevel: .curvature
        )

        let result = try CurveContinuityEvaluator().evaluate(request)

        #expect(result.achievedLevel == .tangent)
        #expect(!result.isSatisfied)
        #expect(abs(result.deviation.positionDistance) <= 1.0e-12)
        #expect(abs(result.deviation.tangentAngle) <= 1.0e-12)
        #expect(result.deviation.curvatureVectorDistance > 0.9)
    }

    @Test(.timeLimit(.minutes(1)))
    func bSplineSurfaceDifferentialGeometryReportsPlanarCurvature() throws {
        let surface = BSplineSurface3D.cubicBezierPatch(
            bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
            bottomRight: Point3D(x: 1.0, y: 0.0, z: 0.0),
            topRight: Point3D(x: 1.0, y: 1.0, z: 0.0),
            topLeft: Point3D(x: 0.0, y: 1.0, z: 0.0)
        )

        let geometry = try surface.differentialGeometry(atU: 0.5, v: 0.5)

        #expect(abs(geometry.position.x - 0.5) <= 1.0e-12)
        #expect(abs(geometry.position.y - 0.5) <= 1.0e-12)
        #expect(abs(geometry.position.z) <= 1.0e-12)
        #expect(abs(geometry.normal.x) <= 1.0e-12)
        #expect(abs(geometry.normal.y) <= 1.0e-12)
        #expect(abs(geometry.normal.z - 1.0) <= 1.0e-12)
        #expect(abs(geometry.normalCurvatureU) <= 1.0e-12)
        #expect(abs(geometry.normalCurvatureV) <= 1.0e-12)
        #expect(abs(geometry.meanCurvature) <= 1.0e-12)
        #expect(abs(geometry.gaussianCurvature) <= 1.0e-12)
        #expect(abs(geometry.minimumPrincipalCurvature) <= 1.0e-12)
        #expect(abs(geometry.maximumPrincipalCurvature) <= 1.0e-12)
        #expect(abs(geometry.minimumPrincipalDirection.x - 1.0) <= 1.0e-12)
        #expect(abs(geometry.minimumPrincipalDirection.y) <= 1.0e-12)
        #expect(abs(geometry.minimumPrincipalDirection.z) <= 1.0e-12)
        #expect(abs(geometry.maximumPrincipalDirection.x) <= 1.0e-12)
        #expect(abs(geometry.maximumPrincipalDirection.y - 1.0) <= 1.0e-12)
        #expect(abs(geometry.maximumPrincipalDirection.z) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func bSplineSurfaceDifferentialGeometryHandlesClosedDomainEndpoints() throws {
        let surface = BSplineSurface3D.cubicBezierPatch(
            bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
            bottomRight: Point3D(x: 1.0, y: 0.0, z: 0.0),
            topRight: Point3D(x: 1.0, y: 1.0, z: 0.0),
            topLeft: Point3D(x: 0.0, y: 1.0, z: 0.0)
        )

        for parameter in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)] {
            let geometry = try surface.differentialGeometry(atU: parameter.0, v: parameter.1)

            #expect(abs(geometry.tangentU.length - 1.0) <= 1.0e-12)
            #expect(abs(geometry.tangentV.length - 1.0) <= 1.0e-12)
            #expect(abs(geometry.normal.z - 1.0) <= 1.0e-12)
            #expect(abs(geometry.minimumPrincipalDirection.length - 1.0) <= 1.0e-12)
            #expect(abs(geometry.maximumPrincipalDirection.length - 1.0) <= 1.0e-12)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func bSplineSurfaceReportsOrderAndRationalState() throws {
        let polynomialSurface = BSplineSurface3D.cubicBezierPatch(
            bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
            bottomRight: Point3D(x: 1.0, y: 0.0, z: 0.0),
            topRight: Point3D(x: 1.0, y: 1.0, z: 0.0),
            topLeft: Point3D(x: 0.0, y: 1.0, z: 0.0)
        )
        let rationalSurface = makeWeightedBilinearSurface()

        #expect(polynomialSurface.uOrder == 4)
        #expect(polynomialSurface.vOrder == 4)
        #expect(polynomialSurface.isRational == false)
        #expect(rationalSurface.uOrder == 2)
        #expect(rationalSurface.vOrder == 2)
        #expect(rationalSurface.isRational == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalBSplineSurfaceEvaluatesWeightedPointAndDerivatives() throws {
        let surface = makeWeightedBilinearSurface()

        let point = try surface.point(u: 0.5, v: 0.5)
        let geometry = try surface.differentialGeometry(atU: 0.5, v: 0.5)

        #expect(abs(point.x - 4.0 / 7.0) <= 1.0e-12)
        #expect(abs(point.y - 4.0 / 7.0) <= 1.0e-12)
        #expect(abs(point.z) <= 1.0e-12)
        #expect(abs(geometry.position.x - point.x) <= 1.0e-12)
        #expect(abs(geometry.position.y - point.y) <= 1.0e-12)
        #expect(abs(geometry.tangentU.x - 80.0 / 49.0) <= 1.0e-12)
        #expect(abs(geometry.tangentU.y - 24.0 / 49.0) <= 1.0e-12)
        #expect(abs(geometry.tangentV.x - 24.0 / 49.0) <= 1.0e-12)
        #expect(abs(geometry.tangentV.y - 80.0 / 49.0) <= 1.0e-12)
        #expect(abs(geometry.normal.z - 1.0) <= 1.0e-12)
        #expect(abs(geometry.normal.length - 1.0) <= 1.0e-12)
        #expect(abs(geometry.gaussianCurvature) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalBSplineSurfaceRejectsInvalidWeights() {
        let missingWeightRow = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [Point3D(x: 0.0, y: 0.0, z: 0.0), Point3D(x: 1.0, y: 0.0, z: 0.0)],
                [Point3D(x: 0.0, y: 1.0, z: 0.0), Point3D(x: 1.0, y: 1.0, z: 0.0)],
            ],
            weights: [[1.0, 1.0]]
        )
        let negativeWeight = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [Point3D(x: 0.0, y: 0.0, z: 0.0), Point3D(x: 1.0, y: 0.0, z: 0.0)],
                [Point3D(x: 0.0, y: 1.0, z: 0.0), Point3D(x: 1.0, y: 1.0, z: 0.0)],
            ],
            weights: [[1.0, -1.0], [1.0, 1.0]]
        )

        #expect(throws: GeometryError.self) {
            try missingWeightRow.validate()
        }
        #expect(throws: GeometryError.self) {
            try negativeWeight.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func surface3DCommonDifferentialGeometryEvaluatesAnalyticSurfaces() throws {
        let plane = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let cylinder = Surface3D.cylinder(Cylinder3D(origin: .origin, axis: .unitZ, radius: 2.0))

        let planeGeometry = try plane.differentialGeometry(atU: 2.0, v: 3.0)
        let cylinderGeometry = try cylinder.differentialGeometry(atU: 0.0, v: 3.0)

        #expect(abs(planeGeometry.position.x - 2.0) <= 1.0e-12)
        #expect(abs(planeGeometry.position.y - 3.0) <= 1.0e-12)
        #expect(abs(planeGeometry.normal.z - 1.0) <= 1.0e-12)
        #expect(abs(planeGeometry.minimumPrincipalCurvature) <= 1.0e-12)
        #expect(abs(planeGeometry.maximumPrincipalCurvature) <= 1.0e-12)
        #expect(abs(cylinderGeometry.position.x - 2.0) <= 1.0e-12)
        #expect(abs(cylinderGeometry.position.y) <= 1.0e-12)
        #expect(abs(cylinderGeometry.position.z - 3.0) <= 1.0e-12)
        #expect(abs(cylinderGeometry.normal.x - 1.0) <= 1.0e-12)
        #expect(abs(cylinderGeometry.minimumPrincipalCurvature + 0.5) <= 1.0e-12)
        #expect(abs(cylinderGeometry.maximumPrincipalCurvature) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceContinuityEvaluatorReportsCurvatureContinuityForOppositePlaneNormals() throws {
        let first = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let second = Surface3D.plane(Plane3D(origin: .origin, normal: -Vector3D.unitZ))
        let request = SurfaceContinuityRequest(
            samplePairs: [
                SurfaceContinuitySamplePair(
                    first: SurfaceContinuityTarget(surface: first, u: 0.0, v: 0.0),
                    second: SurfaceContinuityTarget(
                        surface: second,
                        u: 0.0,
                        v: 0.0,
                        orientation: .reversed
                    )
                ),
            ],
            requiredLevel: .curvature
        )

        let result = try SurfaceContinuityEvaluator().evaluate(request)

        #expect(result.achievedLevel == .curvature)
        #expect(result.isSatisfied)
        #expect(result.deviation.sampleCount == 1)
        #expect(abs(result.deviation.maximumPositionDistance) <= 1.0e-12)
        #expect(abs(result.deviation.maximumNormalAngle) <= 1.0e-12)
        #expect(abs(result.deviation.maximumPrincipalCurvatureDistance) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceContinuityEvaluatorReportsOnlyPositionForNormalMismatch() throws {
        let first = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let second = Surface3D.plane(Plane3D(origin: .origin, normal: .unitY))
        let request = SurfaceContinuityRequest(
            samplePairs: [
                SurfaceContinuitySamplePair(
                    first: SurfaceContinuityTarget(surface: first, u: 0.0, v: 0.0),
                    second: SurfaceContinuityTarget(surface: second, u: 0.0, v: 0.0)
                ),
            ],
            requiredLevel: .tangentPlane
        )

        let result = try SurfaceContinuityEvaluator().evaluate(request)

        #expect(result.achievedLevel == .positional)
        #expect(!result.isSatisfied)
        #expect(abs(result.deviation.maximumPositionDistance) <= 1.0e-12)
        #expect(abs(result.deviation.maximumNormalAngle - Double.pi / 2.0) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceContinuityEvaluatorReportsTangentPlaneForCurvatureMismatch() throws {
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))
        let cylinder = Surface3D.cylinder(Cylinder3D(origin: .origin, axis: .unitZ, radius: 1.0))
        let request = SurfaceContinuityRequest(
            samplePairs: [
                SurfaceContinuitySamplePair(
                    first: SurfaceContinuityTarget(surface: plane, u: 0.0, v: 0.0),
                    second: SurfaceContinuityTarget(surface: cylinder, u: 0.0, v: 0.0)
                ),
            ],
            requiredLevel: .curvature
        )

        let result = try SurfaceContinuityEvaluator().evaluate(request)

        #expect(result.achievedLevel == .tangentPlane)
        #expect(!result.isSatisfied)
        #expect(abs(result.deviation.maximumPositionDistance) <= 1.0e-12)
        #expect(abs(result.deviation.maximumNormalAngle) <= 1.0e-12)
        #expect(result.deviation.maximumPrincipalCurvatureDistance > 0.9)
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceContinuitySamplerCreatesBoundaryRequestForAdjacentPatches() throws {
        let first = Surface3D.bSpline(BSplineSurface3D.cubicBezierPatch(
            bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
            bottomRight: Point3D(x: 1.0, y: 0.0, z: 0.0),
            topRight: Point3D(x: 1.0, y: 1.0, z: 0.0),
            topLeft: Point3D(x: 0.0, y: 1.0, z: 0.0)
        ))
        let second = Surface3D.bSpline(BSplineSurface3D.cubicBezierPatch(
            bottomLeft: Point3D(x: 1.0, y: 0.0, z: 0.0),
            bottomRight: Point3D(x: 2.0, y: 0.0, z: 0.0),
            topRight: Point3D(x: 2.0, y: 1.0, z: 0.0),
            topLeft: Point3D(x: 1.0, y: 1.0, z: 0.0)
        ))
        let request = try SurfaceContinuitySampler().request(
            first: SurfaceContinuitySamplingSide(
                surface: first,
                parameterCurve: try SurfaceParameterCurve.boundary(.uUpper, on: first)
            ),
            second: SurfaceContinuitySamplingSide(
                surface: second,
                parameterCurve: try SurfaceParameterCurve.boundary(.uLower, on: second)
            ),
            requiredLevel: .curvature,
            options: SurfaceContinuitySamplingOptions(sampleCount: 5)
        )

        let result = try SurfaceContinuityEvaluator().evaluate(request)

        #expect(request.samplePairs.count == 5)
        #expect(request.samplePairs.first?.first.u == 1.0)
        #expect(request.samplePairs.first?.second.u == 0.0)
        #expect(request.samplePairs.last?.first.v == 1.0)
        #expect(request.samplePairs.last?.second.v == 1.0)
        #expect(result.achievedLevel == .curvature)
        #expect(result.isSatisfied)
        #expect(abs(result.deviation.maximumPositionDistance) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceContinuitySamplerSupportsPolylineTrimCurvesAndDirectionReversal() throws {
        let surface = Surface3D.bSpline(BSplineSurface3D.cubicBezierPatch(
            bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
            bottomRight: Point3D(x: 1.0, y: 0.0, z: 0.0),
            topRight: Point3D(x: 1.0, y: 1.0, z: 0.0),
            topLeft: Point3D(x: 0.0, y: 1.0, z: 0.0)
        ))
        let forwardTrim = SurfaceParameterCurve.polyline([
            SurfaceParameter(u: 0.0, v: 0.0),
            SurfaceParameter(u: 0.5, v: 0.5),
            SurfaceParameter(u: 1.0, v: 1.0),
        ])
        let reversedTrim = SurfaceParameterCurve.polyline([
            SurfaceParameter(u: 1.0, v: 1.0),
            SurfaceParameter(u: 0.5, v: 0.5),
            SurfaceParameter(u: 0.0, v: 0.0),
        ])
        let request = try SurfaceContinuitySampler().request(
            first: SurfaceContinuitySamplingSide(surface: surface, parameterCurve: forwardTrim),
            second: SurfaceContinuitySamplingSide(
                surface: surface,
                parameterCurve: reversedTrim,
                parameterDirection: .reversed
            ),
            requiredLevel: .curvature,
            options: SurfaceContinuitySamplingOptions(sampleCount: 3)
        )

        let result = try SurfaceContinuityEvaluator().evaluate(request)

        #expect(request.samplePairs.count == 3)
        #expect(abs(request.samplePairs[1].first.u - 0.5) <= 1.0e-12)
        #expect(abs(request.samplePairs[1].first.v - 0.5) <= 1.0e-12)
        #expect(abs(request.samplePairs[1].second.u - 0.5) <= 1.0e-12)
        #expect(abs(request.samplePairs[1].second.v - 0.5) <= 1.0e-12)
        #expect(result.achievedLevel == .curvature)
        #expect(result.isSatisfied)
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceParameterCurveSupportsRationalBSplineTrimCurves() throws {
        let surface = Surface3D.bSpline(BSplineSurface3D.cubicBezierPatch(
            bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
            bottomRight: Point3D(x: 1.0, y: 0.0, z: 0.0),
            topRight: Point3D(x: 1.0, y: 1.0, z: 0.0),
            topLeft: Point3D(x: 0.0, y: 1.0, z: 0.0)
        ))
        let middleWeight = sqrt(0.5)
        let curve = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 1.0, y: 0.0),
                Point2D(x: 1.0, y: 1.0),
                Point2D(x: 0.0, y: 1.0),
            ],
            weights: [1.0, middleWeight, 1.0]
        )
        let trimCurve = SurfaceParameterCurve.bSpline(curve)

        try trimCurve.validate(on: surface)
        let middle = try trimCurve.parameter(atNormalizedFraction: 0.5)
        let data = try JSONEncoder().encode(trimCurve)
        let decoded = try JSONDecoder().decode(SurfaceParameterCurve.self, from: data)
        let request = try SurfaceContinuitySampler().request(
            first: SurfaceContinuitySamplingSide(surface: surface, parameterCurve: trimCurve),
            second: SurfaceContinuitySamplingSide(surface: surface, parameterCurve: decoded),
            requiredLevel: .curvature,
            options: SurfaceContinuitySamplingOptions(sampleCount: 3)
        )
        let result = try SurfaceContinuityEvaluator().evaluate(request)

        #expect(abs(middle.u - middleWeight) <= 1.0e-12)
        #expect(abs(middle.v - middleWeight) <= 1.0e-12)
        #expect(decoded == trimCurve)
        #expect(request.samplePairs.count == 3)
        #expect(result.achievedLevel == .curvature)
        #expect(result.isSatisfied)
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceContinuitySamplerRejectsInvalidSamplingInputs() {
        let surface = Surface3D.bSpline(BSplineSurface3D.cubicBezierPatch(
            bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
            bottomRight: Point3D(x: 1.0, y: 0.0, z: 0.0),
            topRight: Point3D(x: 1.0, y: 1.0, z: 0.0),
            topLeft: Point3D(x: 0.0, y: 1.0, z: 0.0)
        ))
        let edge = SurfaceParameterCurve.constantU(u: 0.0, vStart: 0.0, vEnd: 1.0)

        #expect(throws: GeometryError.self) {
            _ = try SurfaceContinuitySampler().request(
                first: SurfaceContinuitySamplingSide(surface: surface, parameterCurve: edge),
                second: SurfaceContinuitySamplingSide(surface: surface, parameterCurve: edge),
                requiredLevel: .positional,
                options: SurfaceContinuitySamplingOptions(sampleCount: 1)
            )
        }
        #expect(throws: GeometryError.self) {
            _ = try SurfaceParameterCurve.boundary(.uLower, on: Surface3D.plane(Plane3D(
                origin: .origin,
                normal: .unitZ
            )))
        }
        #expect(throws: GeometryError.self) {
            try SurfaceParameterCurve.bSpline(BSplineCurve2D(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point2D(x: 1.0, y: 0.0),
                    Point2D(x: 1.0, y: 1.0),
                    Point2D(x: 0.0, y: 1.0),
                ],
                weights: [1.0, 0.0, 1.0]
            )).validate(on: surface)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func bSplineSurfaceDifferentialGeometryReportsNonPlanarCurvature() throws {
        let surface = BSplineSurface3D.cubicBezierPatch(
            bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
            bottomRight: Point3D(x: 1.0, y: 0.0, z: 0.0),
            topRight: Point3D(x: 1.0, y: 1.0, z: 0.25),
            topLeft: Point3D(x: 0.0, y: 1.0, z: 0.0)
        )

        let geometry = try surface.differentialGeometry(atU: 0.5, v: 0.5)

        #expect(geometry.gaussianCurvature < 0.0)
        #expect(geometry.minimumPrincipalCurvature < 0.0)
        #expect(geometry.maximumPrincipalCurvature > 0.0)
        #expect(abs(geometry.normal.length - 1.0) <= 1.0e-12)
        #expect(abs(geometry.normalCurvatureU) <= 1.0e-12)
        #expect(abs(geometry.normalCurvatureV) <= 1.0e-12)
        #expect(abs(geometry.gaussianCurvature) > 1.0e-3)
        #expect(abs(geometry.minimumPrincipalDirection.length - 1.0) <= 1.0e-12)
        #expect(abs(geometry.maximumPrincipalDirection.length - 1.0) <= 1.0e-12)
        #expect(abs(geometry.minimumPrincipalDirection.dot(geometry.maximumPrincipalDirection)) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsNonLengthSketchDimensionExpressions() {
        let circleID = SketchEntityID()
        let sketchID = FeatureID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                circleID: .circle(SketchCircle(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .constant(.length(1.0, unit: .meter))
                ))
            ],
            dimensions: [.radius(entity: circleID, value: .constant(.scalar(1.0)))]
        )
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(sketch),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [sketchID]
            )
        )

        #expect(throws: UnitError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsNonAngleSketchDimensionExpressions() {
        let arcID = SketchEntityID()
        let sketchID = FeatureID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                arcID: .arc(SketchArc(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .constant(.length(1.0, unit: .meter)),
                    startAngle: .constant(.angle(0.0, unit: .radian)),
                    endAngle: .constant(.angle(Double.pi / 2.0, unit: .radian))
                ))
            ],
            dimensions: [
                .angle(
                    from: .arcStart(arcID),
                    to: .arcEnd(arcID),
                    value: .constant(.length(1.0, unit: .meter))
                ),
            ]
        )
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(sketch),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [sketchID]
            )
        )

        #expect(throws: UnitError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func lineAngleSketchDimensionAllowsZeroOrientationAndBuildsGraphEquation() throws {
        let lineID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                lineID: .line(SketchLine(
                    start: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    end: SketchPoint(
                        x: .constant(.length(1.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    )
                ))
            ],
            dimensions: [
                .angle(
                    from: .lineStart(lineID),
                    to: .lineEnd(lineID),
                    value: .constant(.angle(0.0, unit: .radian))
                ),
            ]
        )

        try sketch.validate()
        let graph = try sketch.constraintGraph()

        #expect(graph.equations.contains { equation in
            equation.kind == .angle
                && equation.nodes.contains(SketchConstraintNode(reference: .lineStart(lineID), degreeOfFreedom: .angle))
                && equation.nodes.contains(SketchConstraintNode(reference: .lineEnd(lineID), degreeOfFreedom: .angle))
                && equation.target == .constant(.angle(0.0, unit: .radian))
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsNonResolvableSourceExpressions() {
        let pointID = SketchEntityID()
        let sketchID = FeatureID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                pointID: .point(SketchPoint(
                    x: .divide(.constant(.length(1.0, unit: .meter)), .constant(.scalar(0.0))),
                    y: .constant(.length(0.0, unit: .meter))
                ))
            ]
        )
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(sketch),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [sketchID]
            )
        )

        #expect(throws: UnitError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsNonPositiveResolvedDimensions() {
        let radiusID = ParameterID()
        let circleID = SketchEntityID()
        let sketchID = FeatureID()
        let invalidCircleSketch = Sketch(
            plane: .xy,
            entities: [
                circleID: .circle(SketchCircle(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .reference(radiusID)
                ))
            ],
            dimensions: [.diameter(entity: circleID, value: .constant(.length(0.0, unit: .meter)))]
        )
        let invalidCircleDocument = CADDocument(
            units: .meters,
            parameters: ParameterTable(parameters: [
                radiusID: Parameter(
                    id: radiusID,
                    name: "radius",
                    expression: .constant(.length(-1.0, unit: .meter)),
                    kind: .length
                )
            ]),
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(invalidCircleSketch),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [sketchID]
            )
        )

        #expect(throws: GeometryError.self) {
            try invalidCircleDocument.validate()
        }

        let validCircleID = SketchEntityID()
        let invalidDimensionSketchID = FeatureID()
        let invalidDimensionSketch = Sketch(
            plane: .xy,
            entities: [
                validCircleID: .circle(SketchCircle(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .constant(.length(1.0, unit: .meter))
                ))
            ],
            dimensions: [.diameter(entity: validCircleID, value: .constant(.length(0.0, unit: .meter)))]
        )
        let invalidDimensionDocument = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    invalidDimensionSketchID: FeatureNode(
                        id: invalidDimensionSketchID,
                        operation: .sketch(invalidDimensionSketch),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [invalidDimensionSketchID]
            )
        )

        #expect(throws: GeometryError.self) {
            try invalidDimensionDocument.validate()
        }

        let validArcID = SketchEntityID()
        let invalidAngleDimensionSketchID = FeatureID()
        let invalidAngleDimensionSketch = Sketch(
            plane: .xy,
            entities: [
                validArcID: .arc(SketchArc(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .constant(.length(1.0, unit: .meter)),
                    startAngle: .constant(.angle(0.0, unit: .radian)),
                    endAngle: .constant(.angle(Double.pi / 2.0, unit: .radian))
                ))
            ],
            dimensions: [
                .angle(
                    from: .arcStart(validArcID),
                    to: .arcEnd(validArcID),
                    value: .constant(.angle(0.0, unit: .radian))
                ),
            ]
        )
        let invalidAngleDimensionDocument = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    invalidAngleDimensionSketchID: FeatureNode(
                        id: invalidAngleDimensionSketchID,
                        operation: .sketch(invalidAngleDimensionSketch),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [invalidAngleDimensionSketchID]
            )
        )

        #expect(throws: GeometryError.self) {
            try invalidAngleDimensionDocument.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsNonPositiveExtrudeDistance() {
        let sketchID = FeatureID()
        let extrudeID = FeatureID()
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(Sketch(plane: .xy)),
                        outputs: [FeatureOutput(role: .profile)]
                    ),
                    extrudeID: FeatureNode(
                        id: extrudeID,
                        operation: .extrude(ExtrudeFeature(
                            profile: ProfileReference(featureID: sketchID),
                            distance: .constant(.length(0.0, unit: .meter))
                        )),
                        inputs: [FeatureInput(featureID: sketchID, role: .profile)],
                        outputs: [FeatureOutput(role: .body)]
                    )
                ],
                order: [sketchID, extrudeID],
                dependencies: [DependencyEdge(source: sketchID, target: extrudeID)]
            )
        )

        #expect(throws: FeatureEvaluationError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func featureOperationUsesStableKindDiscriminator() throws {
        let sketch = Sketch(plane: .xy)
        let operation = FeatureOperation.sketch(sketch)
        let data = try JSONEncoder().encode(operation)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"kind\":\"sketch\""))
    }

    @Test(.timeLimit(.minutes(1)))
    func featureOperationRoundTripsSweep() throws {
        let profileID = FeatureID()
        let pathID = FeatureID()
        let targetID = FeatureID()
        let operation = FeatureOperation.sweep(
            SweepFeature(
                profiles: [ProfileReference(featureID: profileID)],
                path: SweepPathReference(featureID: pathID),
                targets: [SweepTargetReference(featureID: targetID)],
                options: SweepOptions(
                    twistAngle: .constant(.angle(15.0, unit: .degree)),
                    endScale: .constant(.scalar(0.8)),
                    alignment: .normal,
                    distanceFraction: .constant(.scalar(1.0)),
                    cornerStyle: .mitre,
                    guideMethod: .curve,
                    booleanOperation: .union,
                    keepTools: false,
                    simplify: true,
                    resultKind: .solid
                )
            )
        )

        let data = try JSONEncoder().encode(operation)
        let decoded = try JSONDecoder().decode(FeatureOperation.self, from: data)

        guard case .sweep(let sweep) = decoded else {
            Issue.record("Sweep operation must round-trip with its discriminator.")
            return
        }
        #expect(sweep.profiles == [ProfileReference(featureID: profileID)])
        #expect(sweep.path == SweepPathReference(featureID: pathID))
        #expect(sweep.targets == [SweepTargetReference(featureID: targetID)])
        #expect(sweep.options.alignment == .normal)
        #expect(sweep.options.guideMethod == .curve)
        #expect(sweep.options.booleanOperation == .union)
        #expect(sweep.options.simplify)
    }

    @Test(.timeLimit(.minutes(1)))
    func featureOperationRoundTripsFaceLoopOffset() throws {
        let targetID = FeatureID()
        let faceName = PersistentName(components: [
            .feature(targetID),
            .generated(GeneratedSubshapeRole.startFace.rawValue),
        ])
        let operation = FeatureOperation.faceLoopOffset(
            FaceLoopOffsetFeature(
                target: FaceLoopOffsetTargetReference(featureID: targetID),
                facePersistentName: faceName,
                distance: .constant(.length(2.0, unit: .millimeter)),
                gapFill: .linear
            )
        )

        let data = try JSONEncoder().encode(operation)
        let decoded = try JSONDecoder().decode(FeatureOperation.self, from: data)

        guard case .faceLoopOffset(let offset) = decoded else {
            Issue.record("Face loop offset operation must round-trip with its discriminator.")
            return
        }
        #expect(offset.target == FaceLoopOffsetTargetReference(featureID: targetID))
        #expect(offset.facePersistentName == faceName)
        #expect(offset.gapFill == .linear)
    }

    @Test(.timeLimit(.minutes(1)))
    func featureOperationRoundTripsEdgeOffset() throws {
        let targetID = FeatureID()
        let edgeName = PersistentName(components: [
            .feature(targetID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .index(0),
        ])
        let supportFaceName = PersistentName(components: [
            .feature(targetID),
            .generated(GeneratedSubshapeRole.startFace.rawValue),
        ])
        let operation = FeatureOperation.edgeOffset(
            EdgeOffsetFeature(
                target: EdgeOffsetTargetReference(featureID: targetID),
                edgePersistentName: edgeName,
                supportFacePersistentName: supportFaceName,
                distance: .constant(.length(2.0, unit: .millimeter)),
                isSymmetric: true,
                gapFill: .natural
            )
        )

        let data = try JSONEncoder().encode(operation)
        let decoded = try JSONDecoder().decode(FeatureOperation.self, from: data)

        guard case .edgeOffset(let offset) = decoded else {
            Issue.record("Edge offset operation must round-trip with its discriminator.")
            return
        }
        #expect(offset.target == EdgeOffsetTargetReference(featureID: targetID))
        #expect(offset.edgePersistentName == edgeName)
        #expect(offset.supportFacePersistentName == supportFaceName)
        #expect(offset.isSymmetric)
        #expect(offset.gapFill == .natural)
    }

    @Test(.timeLimit(.minutes(1)))
    func featureOperationRoundTripsCurveEdit() throws {
        let sourceID = FeatureID()
        let source = CurveOutputReference(featureID: sourceID, curveIndex: 1)
        let operation = FeatureOperation.curveEdit(CurveEditFeature(
            source: source,
            edits: [
                .setControlPoint(CurveControlPointEdit(
                    target: CurveControlPointReference(curve: source, controlPointIndex: 2),
                    point: Point3D(x: 1.0, y: 2.0, z: 3.0)
                )),
                .setKnot(CurveKnotEdit(
                    target: CurveKnotReference(curve: source, knotIndex: 4),
                    value: 0.25
                )),
                .setWeight(CurveWeightEdit(
                    target: CurveControlPointReference(curve: source, controlPointIndex: 2),
                    value: 0.75
                )),
            ],
            sampleCount: 17
        ))

        let data = try JSONEncoder().encode(operation)
        let decoded = try JSONDecoder().decode(FeatureOperation.self, from: data)

        guard case .curveEdit(let curveEdit) = decoded else {
            Issue.record("Curve edit operation must round-trip with its discriminator.")
            return
        }
        #expect(curveEdit.source == source)
        #expect(curveEdit.edits.count == 3)
        #expect(curveEdit.sampleCount == 17)
    }

    @Test(.timeLimit(.minutes(1)))
    func featureOperationRoundTripsCurveOffset() throws {
        let source = CurveOutputReference(featureID: FeatureID(), curveIndex: 2)
        let operation = FeatureOperation.curveOffset(CurveOffsetFeature(
            source: source,
            distance: .constant(.length(1.25, unit: .millimeter)),
            planeNormal: .unitZ,
            side: .right,
            sampleCount: 19
        ))

        let data = try JSONEncoder().encode(operation)
        let decoded = try JSONDecoder().decode(FeatureOperation.self, from: data)

        guard case .curveOffset(let curveOffset) = decoded else {
            Issue.record("Curve offset operation must round-trip with its discriminator.")
            return
        }
        #expect(curveOffset.source == source)
        #expect(curveOffset.side == .right)
        #expect(curveOffset.sampleCount == 19)
    }

    @Test(.timeLimit(.minutes(1)))
    func featureOperationRoundTripsCurveTrim() throws {
        let source = CurveOutputReference(featureID: FeatureID(), curveIndex: 1)
        let operation = FeatureOperation.curveTrim(CurveTrimFeature(
            source: source,
            domain: .closed(0.25, 0.75),
            sampleCount: 11
        ))

        let data = try JSONEncoder().encode(operation)
        let decoded = try JSONDecoder().decode(FeatureOperation.self, from: data)

        guard case .curveTrim(let curveTrim) = decoded else {
            Issue.record("Curve trim operation must round-trip with its discriminator.")
            return
        }
        #expect(curveTrim.source == source)
        #expect(curveTrim.domain == .closed(0.25, 0.75))
        #expect(curveTrim.sampleCount == 11)
    }

    @Test(.timeLimit(.minutes(1)))
    func unionDecodersRejectInactivePayloadKeys() throws {
        let point = SketchPoint(
            x: .constant(.length(0.0, unit: .meter)),
            y: .constant(.length(0.0, unit: .meter))
        )

        var operationObject = try jsonObject(from: JSONEncoder().encode(FeatureOperation.sketch(Sketch(plane: .xy))))
        operationObject["extrude"] = try jsonObject(from: JSONEncoder().encode(ExtrudeFeature(
            profile: ProfileReference(featureID: FeatureID()),
            distance: .constant(.length(1.0, unit: .meter))
        )))
        operationObject["sweep"] = try jsonObject(from: JSONEncoder().encode(SweepFeature(
            profiles: [ProfileReference(featureID: FeatureID())],
            path: SweepPathReference(featureID: FeatureID())
        )))
        operationObject["faceLoopOffset"] = try jsonObject(from: JSONEncoder().encode(FaceLoopOffsetFeature(
            target: FaceLoopOffsetTargetReference(featureID: FeatureID()),
            facePersistentName: PersistentName(components: [
                .feature(FeatureID()),
                .generated(GeneratedSubshapeRole.startFace.rawValue),
            ]),
            distance: .constant(.length(1.0, unit: .millimeter))
        )))
        operationObject["edgeOffset"] = try jsonObject(from: JSONEncoder().encode(EdgeOffsetFeature(
            target: EdgeOffsetTargetReference(featureID: FeatureID()),
            edgePersistentName: PersistentName(components: [
                .feature(FeatureID()),
                .generated(GeneratedSubshapeRole.edge.rawValue),
                .index(0),
            ]),
            supportFacePersistentName: PersistentName(components: [
                .feature(FeatureID()),
                .generated(GeneratedSubshapeRole.startFace.rawValue),
            ]),
            distance: .constant(.length(1.0, unit: .millimeter))
        )))
        operationObject["curveOffset"] = try jsonObject(from: JSONEncoder().encode(CurveOffsetFeature(
            source: CurveOutputReference(featureID: FeatureID()),
            distance: .constant(.length(1.0, unit: .millimeter)),
            planeNormal: .unitZ
        )))
        operationObject["curveTrim"] = try jsonObject(from: JSONEncoder().encode(CurveTrimFeature(
            source: CurveOutputReference(featureID: FeatureID()),
            domain: .closed(0.0, 1.0)
        )))
        try expectDecodingFailure(FeatureOperation.self, from: operationObject)

        let lineObject = try jsonObject(from: JSONEncoder().encode(SketchEntity.line(SketchLine(start: point, end: point))))
        var entityObject = try jsonObject(from: JSONEncoder().encode(SketchEntity.point(point)))
        entityObject["line"] = lineObject["line"]
        try expectDecodingFailure(SketchEntity.self, from: entityObject)

        var directionObject = try jsonObject(from: JSONEncoder().encode(ExtrudeDirection.normal))
        directionObject["vector"] = try jsonObject(from: JSONEncoder().encode(Vector3D.unitZ))
        try expectDecodingFailure(ExtrudeDirection.self, from: directionObject)

        var planeObject = try jsonObject(from: JSONEncoder().encode(SketchPlane.xy))
        planeObject["plane"] = try jsonObject(from: JSONEncoder().encode(Plane3D(origin: .origin, normal: .unitZ)))
        try expectDecodingFailure(SketchPlane.self, from: planeObject)

        var nameComponentObject = try jsonObject(from: JSONEncoder().encode(NameComponent.feature(FeatureID())))
        nameComponentObject["value"] = "inactive"
        try expectDecodingFailure(NameComponent.self, from: nameComponentObject)

        var sketchReferenceObject = try jsonObject(from: JSONEncoder().encode(SketchReference.entity(SketchEntityID())))
        sketchReferenceObject["inactive"] = "payload"
        try expectDecodingFailure(SketchReference.self, from: sketchReferenceObject)
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchSplineRoundTripsAndValidatesControlPoints() throws {
        let spline = SketchSpline(controlPoints: [
            SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
            SketchPoint(x: .constant(.length(0.2, unit: .meter)), y: .constant(.length(0.4, unit: .meter))),
            SketchPoint(x: .constant(.length(0.8, unit: .meter)), y: .constant(.length(0.4, unit: .meter))),
            SketchPoint(x: .constant(.length(1.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
        ])
        let entity = SketchEntity.spline(spline)
        let decoded = try JSONDecoder().decode(SketchEntity.self, from: JSONEncoder().encode(entity))

        #expect(decoded == entity)
        try Sketch(
            plane: .xy,
            entities: [SketchEntityID(): entity]
        ).validate()

        #expect(throws: SketchError.self) {
            try Sketch(
                plane: .xy,
                entities: [
                    SketchEntityID(): .spline(SketchSpline(controlPoints: Array(spline.controlPoints.prefix(3)))),
                ]
            ).validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchSplineControlPointReferenceRoundTripsAndValidates() throws {
        let splineID = SketchEntityID()
        let reference = SketchReference.splineControlPoint(entity: splineID, index: 3)
        let decoded = try JSONDecoder().decode(SketchReference.self, from: JSONEncoder().encode(reference))
        let spline = SketchSpline(controlPoints: [
            SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
            SketchPoint(x: .constant(.length(0.2, unit: .meter)), y: .constant(.length(0.4, unit: .meter))),
            SketchPoint(x: .constant(.length(0.8, unit: .meter)), y: .constant(.length(0.4, unit: .meter))),
            SketchPoint(x: .constant(.length(1.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
        ])
        let sketch = Sketch(
            plane: .xy,
            entities: [splineID: .spline(spline)],
            constraints: [.fixed(reference)],
            dimensions: [
                .distance(
                    from: .splineControlPoint(entity: splineID, index: 0),
                    to: reference,
                    value: .constant(.length(1.0, unit: .meter))
                ),
            ]
        )

        #expect(decoded == reference)
        try sketch.validate()
        let graph = try sketch.constraintGraph()
        #expect(graph.nodes.contains(SketchConstraintNode(reference: reference, degreeOfFreedom: .x)))
        #expect(graph.nodes.contains(SketchConstraintNode(reference: reference, degreeOfFreedom: .y)))
        let distanceEquation = try #require(graph.equations.first { $0.kind == .distance })
        #expect(distanceEquation.target == .constant(.length(1.0, unit: .meter)))

        #expect(throws: SketchError.self) {
            try Sketch(
                plane: .xy,
                entities: [splineID: .spline(spline)],
                constraints: [.fixed(.splineControlPoint(entity: splineID, index: -1))]
            ).validate()
        }
        #expect(throws: SketchError.self) {
            try Sketch(
                plane: .xy,
                entities: [splineID: .spline(spline)],
                constraints: [.fixed(.splineControlPoint(entity: splineID, index: 4))]
            ).validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchSmoothSplineControlPointConstraintRoundTripsAndValidates() throws {
        let splineID = SketchEntityID()
        let constraint = SketchConstraint.smoothSplineControlPoint(entity: splineID, index: 3)
        let decoded = try JSONDecoder().decode(SketchConstraint.self, from: JSONEncoder().encode(constraint))
        let spline = SketchSpline(controlPoints: [
            SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
            SketchPoint(x: .constant(.length(0.1, unit: .meter)), y: .constant(.length(0.2, unit: .meter))),
            SketchPoint(x: .constant(.length(0.3, unit: .meter)), y: .constant(.length(0.2, unit: .meter))),
            SketchPoint(x: .constant(.length(0.4, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
            SketchPoint(x: .constant(.length(0.5, unit: .meter)), y: .constant(.length(-0.2, unit: .meter))),
            SketchPoint(x: .constant(.length(0.7, unit: .meter)), y: .constant(.length(-0.2, unit: .meter))),
            SketchPoint(x: .constant(.length(0.8, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
        ])
        let sketch = Sketch(
            plane: .xy,
            entities: [splineID: .spline(spline)],
            constraints: [constraint]
        )

        #expect(decoded == constraint)
        try sketch.validate()
        let graph = try sketch.constraintGraph()
        #expect(graph.equations.map(\.kind) == [.smoothSplineControlPoint])
        #expect(graph.nodes.contains(SketchConstraintNode(
            reference: .splineControlPoint(entity: splineID, index: 2),
            degreeOfFreedom: .x
        )))
        #expect(graph.nodes.contains(SketchConstraintNode(
            reference: .splineControlPoint(entity: splineID, index: 3),
            degreeOfFreedom: .y
        )))
        #expect(graph.nodes.contains(SketchConstraintNode(
            reference: .splineControlPoint(entity: splineID, index: 4),
            degreeOfFreedom: .x
        )))

        #expect(throws: SketchError.self) {
            try Sketch(
                plane: .xy,
                entities: [splineID: .spline(spline)],
                constraints: [.smoothSplineControlPoint(entity: splineID, index: 0)]
            ).validate()
        }
        #expect(throws: SketchError.self) {
            try Sketch(
                plane: .xy,
                entities: [splineID: .spline(spline)],
                constraints: [.smoothSplineControlPoint(entity: splineID, index: 2)]
            ).validate()
        }
        #expect(throws: SketchError.self) {
            try Sketch(
                plane: .xy,
                entities: [splineID: .spline(spline)],
                constraints: [.smoothSplineControlPoint(entity: splineID, index: 6)]
            ).validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchSplineEndpointTangentConstraintRoundTripsAndValidates() throws {
        let splineID = SketchEntityID()
        let lineID = SketchEntityID()
        let constraint = SketchConstraint.splineEndpointTangent(
            spline: splineID,
            endpoint: .start,
            line: lineID
        )
        let decoded = try JSONDecoder().decode(SketchConstraint.self, from: JSONEncoder().encode(constraint))
        let spline = SketchSpline(controlPoints: [
            SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
            SketchPoint(x: .constant(.length(0.1, unit: .meter)), y: .constant(.length(0.2, unit: .meter))),
            SketchPoint(x: .constant(.length(0.3, unit: .meter)), y: .constant(.length(0.2, unit: .meter))),
            SketchPoint(x: .constant(.length(0.4, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
        ])
        let line = SketchLine(
            start: SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
            end: SketchPoint(x: .constant(.length(1.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter)))
        )
        let sketch = Sketch(
            plane: .xy,
            entities: [
                splineID: .spline(spline),
                lineID: .line(line),
            ],
            constraints: [constraint]
        )

        #expect(decoded == constraint)
        try sketch.validate()
        let graph = try sketch.constraintGraph()
        #expect(graph.equations.map(\.kind) == [.splineEndpointTangent])
        #expect(graph.nodes.contains(SketchConstraintNode(
            reference: .splineControlPoint(entity: splineID, index: 0),
            degreeOfFreedom: .x
        )))
        #expect(graph.nodes.contains(SketchConstraintNode(
            reference: .splineControlPoint(entity: splineID, index: 1),
            degreeOfFreedom: .y
        )))
        #expect(graph.nodes.contains(SketchConstraintNode(
            reference: .entity(lineID),
            degreeOfFreedom: .angle
        )))

        #expect(throws: SketchError.self) {
            try Sketch(
                plane: .xy,
                entities: [lineID: .line(line)],
                constraints: [constraint]
            ).validate()
        }
        #expect(throws: SketchError.self) {
            try Sketch(
                plane: .xy,
                entities: [splineID: .spline(spline)],
                constraints: [constraint]
            ).validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func tangentSplineEndpointsConstraintRoundTripsAndValidates() throws {
        let firstSplineID = SketchEntityID()
        let secondSplineID = SketchEntityID()
        let firstReference = SketchSplineEndpointReference(splineID: firstSplineID, endpoint: .end)
        let secondReference = SketchSplineEndpointReference(splineID: secondSplineID, endpoint: .start)
        let constraint = SketchConstraint.tangentSplineEndpoints(
            first: firstReference,
            second: secondReference
        )
        let decoded = try JSONDecoder().decode(SketchConstraint.self, from: JSONEncoder().encode(constraint))
        let firstSpline = SketchSpline(controlPoints: [
            SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
            SketchPoint(x: .constant(.length(0.2, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
            SketchPoint(x: .constant(.length(0.4, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
            SketchPoint(x: .constant(.length(0.6, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
        ])
        let secondSpline = SketchSpline(controlPoints: [
            SketchPoint(x: .constant(.length(0.6, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
            SketchPoint(x: .constant(.length(0.8, unit: .meter)), y: .constant(.length(0.1, unit: .meter))),
            SketchPoint(x: .constant(.length(1.0, unit: .meter)), y: .constant(.length(0.1, unit: .meter))),
            SketchPoint(x: .constant(.length(1.2, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
        ])
        let sketch = Sketch(
            plane: .xy,
            entities: [
                firstSplineID: .spline(firstSpline),
                secondSplineID: .spline(secondSpline),
            ],
            constraints: [constraint]
        )

        #expect(decoded == constraint)
        try sketch.validate()
        let graph = try sketch.constraintGraph()
        #expect(graph.equations.map(\.kind) == [.tangentSplineEndpoints])
        #expect(graph.nodes.contains(SketchConstraintNode(
            reference: .splineControlPoint(entity: firstSplineID, index: 2),
            degreeOfFreedom: .x
        )))
        #expect(graph.nodes.contains(SketchConstraintNode(
            reference: .splineControlPoint(entity: firstSplineID, index: 3),
            degreeOfFreedom: .y
        )))
        #expect(graph.nodes.contains(SketchConstraintNode(
            reference: .splineControlPoint(entity: secondSplineID, index: 0),
            degreeOfFreedom: .x
        )))
        #expect(graph.nodes.contains(SketchConstraintNode(
            reference: .splineControlPoint(entity: secondSplineID, index: 1),
            degreeOfFreedom: .y
        )))

        #expect(throws: SketchError.self) {
            try Sketch(
                plane: .xy,
                entities: [firstSplineID: .spline(firstSpline)],
                constraints: [constraint]
            ).validate()
        }
        #expect(throws: SketchError.self) {
            try Sketch(
                plane: .xy,
                entities: [firstSplineID: .spline(firstSpline)],
                constraints: [
                    .tangentSplineEndpoints(first: firstReference, second: firstReference),
                ]
            ).validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func smoothSplineEndpointsConstraintRoundTripsAndValidates() throws {
        let firstSplineID = SketchEntityID()
        let secondSplineID = SketchEntityID()
        let firstReference = SketchSplineEndpointReference(splineID: firstSplineID, endpoint: .end)
        let secondReference = SketchSplineEndpointReference(splineID: secondSplineID, endpoint: .start)
        let constraint = SketchConstraint.smoothSplineEndpoints(
            first: firstReference,
            second: secondReference
        )
        let decoded = try JSONDecoder().decode(SketchConstraint.self, from: JSONEncoder().encode(constraint))
        let firstSpline = SketchSpline(controlPoints: [
            SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
            SketchPoint(x: .constant(.length(0.2, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
            SketchPoint(x: .constant(.length(0.4, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
            SketchPoint(x: .constant(.length(0.6, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
        ])
        let secondSpline = SketchSpline(controlPoints: [
            SketchPoint(x: .constant(.length(0.6, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
            SketchPoint(x: .constant(.length(0.8, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
            SketchPoint(x: .constant(.length(1.0, unit: .meter)), y: .constant(.length(0.1, unit: .meter))),
            SketchPoint(x: .constant(.length(1.2, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
        ])
        let sketch = Sketch(
            plane: .xy,
            entities: [
                firstSplineID: .spline(firstSpline),
                secondSplineID: .spline(secondSpline),
            ],
            constraints: [constraint]
        )

        #expect(decoded == constraint)
        try sketch.validate()
        let graph = try sketch.constraintGraph()
        #expect(graph.equations.map(\.kind) == [.smoothSplineEndpoints])
        #expect(graph.nodes.contains(SketchConstraintNode(
            reference: .splineControlPoint(entity: firstSplineID, index: 2),
            degreeOfFreedom: .x
        )))
        #expect(graph.nodes.contains(SketchConstraintNode(
            reference: .splineControlPoint(entity: firstSplineID, index: 3),
            degreeOfFreedom: .y
        )))
        #expect(graph.nodes.contains(SketchConstraintNode(
            reference: .splineControlPoint(entity: secondSplineID, index: 0),
            degreeOfFreedom: .x
        )))
        #expect(graph.nodes.contains(SketchConstraintNode(
            reference: .splineControlPoint(entity: secondSplineID, index: 1),
            degreeOfFreedom: .y
        )))

        #expect(throws: SketchError.self) {
            try Sketch(
                plane: .xy,
                entities: [firstSplineID: .spline(firstSpline)],
                constraints: [constraint]
            ).validate()
        }
        #expect(throws: SketchError.self) {
            try Sketch(
                plane: .xy,
                entities: [firstSplineID: .spline(firstSpline)],
                constraints: [
                    .smoothSplineEndpoints(first: firstReference, second: firstReference),
                ]
            ).validate()
        }
    }

    private func expectDecodingFailure<T: Decodable>(_ type: T.Type, from object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(type, from: data)
        }
    }

    private func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SchemaError.invalidPackage("Expected JSON object fixture.")
        }
        return object
    }

    @Test(.timeLimit(.minutes(1)))
    func meshValidationRejectsInvalidIndices() {
        let mesh = Mesh(
            positions: [Point3D.origin],
            normals: [],
            indices: [0, 1, 2]
        )

        #expect(throws: ExportError.self) {
            try mesh.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshValidationRejectsUnreferencedPositions() {
        let mesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0),
                Point3D(x: 10.0, y: 10.0, z: 10.0)
            ],
            normals: [],
            indices: [0, 1, 2]
        )

        #expect(throws: ExportError.self) {
            try mesh.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshValidationRejectsNonFiniteCoordinates() {
        let badPositionMesh = Mesh(
            positions: [
                Point3D(x: .nan, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2]
        )
        let badNormalMesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [
                Vector3D(x: .infinity, y: 0.0, z: 1.0),
                Vector3D(x: 0.0, y: 0.0, z: 1.0),
                Vector3D(x: 0.0, y: 0.0, z: 1.0)
            ],
            indices: [0, 1, 2]
        )

        #expect(throws: ExportError.self) {
            try badPositionMesh.validate()
        }
        #expect(throws: ExportError.self) {
            try badNormalMesh.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshValidationRejectsInvalidTextureCoordinates() {
        let mismatchedTextureCoordinateMesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2],
            textureCoordinates: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 1.0, y: 0.0)
            ]
        )
        let nonFiniteTextureCoordinateMesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2],
            textureCoordinates: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: .nan, y: 0.0),
                Point2D(x: 0.0, y: 1.0)
            ]
        )

        #expect(throws: ExportError.self) {
            try mismatchedTextureCoordinateMesh.validate()
        }
        #expect(throws: ExportError.self) {
            try nonFiniteTextureCoordinateMesh.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshValidationRejectsInvalidVertexColors() {
        let mismatchedVertexColorMesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2],
            vertexColors: [
                ColorRGBA(r: 1.0, g: 0.0, b: 0.0, a: 1.0),
                ColorRGBA(r: 0.0, g: 1.0, b: 0.0, a: 1.0)
            ]
        )
        let outOfRangeVertexColorMesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2],
            vertexColors: [
                ColorRGBA(r: 1.0, g: 0.0, b: 0.0, a: 1.0),
                ColorRGBA(r: 0.0, g: 2.0, b: 0.0, a: 1.0),
                ColorRGBA(r: 0.0, g: 0.0, b: 1.0, a: 1.0)
            ]
        )

        #expect(throws: ExportError.self) {
            try mismatchedVertexColorMesh.validate()
        }
        #expect(throws: ExportError.self) {
            try outOfRangeVertexColorMesh.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshDecodingDefaultsMissingOptionalVertexAttributesToEmpty() throws {
        let data = Data("""
        {
            "positions": [
                { "x": 0, "y": 0, "z": 0 },
                { "x": 1, "y": 0, "z": 0 },
                { "x": 0, "y": 1, "z": 0 }
            ],
            "normals": [],
            "indices": [0, 1, 2]
        }
        """.utf8)

        let mesh = try JSONDecoder().decode(Mesh.self, from: data)

        #expect(mesh.textureCoordinates == [])
        #expect(mesh.vertexColors == [])
    }

    @Test(.timeLimit(.minutes(1)))
    func meshValidationRejectsNonUnitNormals() {
        let mesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [
                Vector3D(x: 0.0, y: 0.0, z: 2.0),
                Vector3D.unitZ,
                Vector3D.unitZ
            ],
            indices: [0, 1, 2]
        )

        #expect(throws: ExportError.self) {
            try mesh.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshValidationRejectsNormalsOpposingTriangleWinding() {
        let mesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [
                -Vector3D.unitZ,
                -Vector3D.unitZ,
                -Vector3D.unitZ
            ],
            indices: [0, 1, 2]
        )

        #expect(throws: ExportError.self) {
            try mesh.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshValidationRejectsDegenerateTriangles() {
        let repeatedIndexMesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 1]
        )
        let collinearMesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 2.0, y: 0.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2]
        )

        #expect(throws: ExportError.self) {
            try repeatedIndexMesh.validate()
        }
        #expect(throws: ExportError.self) {
            try collinearMesh.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshValidationRejectsTriangleAreaOverflow() {
        let mesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0e308, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0e308, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2]
        )

        #expect(throws: ExportError.self) {
            try mesh.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func validationRejectsInvalidModelingToleranceAtIRBoundary() {
        let mesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2]
        )

        #expect(throws: GeometryError.self) {
            try mesh.validate(tolerance: ModelingTolerance(distance: -1.0, angle: 1.0e-9))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func tessellationOptionsRejectNonFiniteAndNonPositiveValues() {
        #expect(throws: TessellationError.self) {
            try TessellationOptions(linearTolerance: .infinity, angularTolerance: 1.0e-3).validate()
        }
        #expect(throws: TessellationError.self) {
            try TessellationOptions(linearTolerance: 1.0e-4, angularTolerance: 0.0).validate()
        }
        #expect(throws: TessellationError.self) {
            try TessellationOptions(
                linearTolerance: 1.0e-4,
                angularTolerance: 1.0e-3,
                maxEdgeLength: .nan
            ).validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func materialValidationRejectsOutOfRangeValues() {
        let badColor = ColorRGBA(r: 1.2, g: 0.0, b: 0.0, a: 1.0)
        let badMaterial = Material(
            name: "Invalid",
            baseColor: ColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0),
            metallic: 0.0,
            roughness: .nan,
            opacity: 1.0
        )

        #expect(throws: MaterialError.self) {
            try badColor.validate()
        }
        #expect(throws: MaterialError.self) {
            try badMaterial.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func geometryValidationRejectsNonFiniteAndNonUnitDirections() {
        let badLine = Line3D(
            origin: Point3D(x: .nan, y: 0.0, z: 0.0),
            direction: Vector3D.unitX
        )
        let nonUnitPlane = Plane3D(
            origin: .origin,
            normal: Vector3D(x: 2.0, y: 0.0, z: 0.0)
        )

        #expect(throws: GeometryError.self) {
            try badLine.validate()
        }
        #expect(throws: GeometryError.self) {
            try nonUnitPlane.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsSameDirectionEdgeUse() throws {
        let model = makeTwoFaceTriangleModelWithSameEdgeOrientations()

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsDuplicateTopologyOwnershipReferences() throws {
        try makeClosedTetrahedronModel().validate()

        var duplicateShellModel = makeClosedTetrahedronModel()
        let bodyID = try #require(duplicateShellModel.bodies.keys.first)
        let shellID = try #require(duplicateShellModel.shells.keys.first)
        duplicateShellModel.bodies[bodyID]?.shellIDs.append(shellID)

        var duplicateFaceModel = makeClosedTetrahedronModel()
        let duplicateFaceShellID = try #require(duplicateFaceModel.shells.keys.first)
        let faceID = try #require(duplicateFaceModel.faces.keys.first)
        duplicateFaceModel.shells[duplicateFaceShellID]?.faceIDs.append(faceID)

        var duplicateLoopModel = makeClosedTetrahedronModel()
        let duplicateLoopFaceID = try #require(duplicateLoopModel.faces.keys.first)
        let loopID = try #require(duplicateLoopModel.loops.keys.first)
        duplicateLoopModel.faces[duplicateLoopFaceID]?.loops.append(loopID)

        var duplicateLoopEdgeModel = makeClosedTetrahedronModel()
        let duplicateEdgeLoopID = try #require(duplicateLoopEdgeModel.loops.keys.first)
        let orientedEdge = try #require(duplicateLoopEdgeModel.loops[duplicateEdgeLoopID]?.edges.first)
        duplicateLoopEdgeModel.loops[duplicateEdgeLoopID]?.edges.append(orientedEdge)

        #expect(throws: TopologyError.self) {
            try duplicateShellModel.validate()
        }
        #expect(throws: TopologyError.self) {
            try duplicateFaceModel.validate()
        }
        #expect(throws: TopologyError.self) {
            try duplicateLoopModel.validate()
        }
        #expect(throws: TopologyError.self) {
            try duplicateLoopEdgeModel.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsTopologySharingAcrossShells() throws {
        var model = makeClosedTetrahedronModel()
        let bodyID = try #require(model.bodies.keys.first)
        let originalShellID = try #require(model.shells.keys.first)
        let originalFaceIDs = try #require(model.shells[originalShellID]?.faceIDs)
        var copiedFaceIDs: [FaceID] = []
        for originalFaceID in originalFaceIDs {
            let originalFace = try #require(model.faces[originalFaceID])
            let originalLoopID = try #require(originalFace.loops.first)
            let originalLoop = try #require(model.loops[originalLoopID])
            let copiedLoopID = LoopID()
            let copiedFaceID = FaceID()
            model.loops[copiedLoopID] = Loop(
                id: copiedLoopID,
                role: originalLoop.role,
                edges: originalLoop.edges
            )
            model.faces[copiedFaceID] = Face(
                id: copiedFaceID,
                surfaceID: originalFace.surfaceID,
                loops: [copiedLoopID],
                orientation: originalFace.orientation
            )
            copiedFaceIDs.append(copiedFaceID)
        }
        let copiedShellID = ShellID()
        model.shells[copiedShellID] = Shell(id: copiedShellID, faceIDs: copiedFaceIDs)
        model.bodies[bodyID]?.shellIDs.append(copiedShellID)

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsUnreferencedTopologyAndInvalidVertexValues() {
        let vertexID = VertexID()
        let orphanModel = BRepModel(
            vertices: [vertexID: Vertex(id: vertexID, point: .origin)]
        )
        let invalidVertexModel = BRepModel(
            vertices: [vertexID: Vertex(id: vertexID, point: Point3D(x: .infinity, y: 0.0, z: 0.0))]
        )

        #expect(throws: TopologyError.self) {
            try orphanModel.validate()
        }
        #expect(throws: GeometryError.self) {
            try invalidVertexModel.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsFaceLoopGeometryOffSurface() throws {
        var model = makeClosedTetrahedronModel()
        let faceID = try #require(model.faces.keys.first)
        let surfaceID = try #require(model.faces[faceID]?.surfaceID)
        model.geometry.surfaces[surfaceID] = .plane(Plane3D(
            origin: Point3D(x: 0.0, y: 0.0, z: 10.0),
            normal: Vector3D.unitZ
        ))

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsLoopClosedByCoincidentDifferentVertexID() throws {
        var model = makeClosedTetrahedronModel()
        let sharedPoint = Point3D.origin
        let sharedVertexID = try #require(model.vertices.first { $0.value.point == sharedPoint }?.key)
        let splitVertexID = VertexID()
        let splitEdgeID = try #require(model.edges.first { _, edge in
            edge.startVertexID == sharedVertexID
                && model.vertices[edge.endVertexID]?.point == Point3D(x: 0.0, y: 1.0, z: 0.0)
        }?.key)
        model.vertices[splitVertexID] = Vertex(id: splitVertexID, point: sharedPoint)
        model.edges[splitEdgeID]?.startVertexID = splitVertexID

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsInvalidTrimAndLoopRoles() {
        var invalidTrimModel = makeTwoFaceTriangleModelWithSameEdgeOrientations()
        if let edgeID = invalidTrimModel.edges.keys.first {
            invalidTrimModel.edges[edgeID]?.trim = CurveTrim(startParameter: .nan, endParameter: 1.0)
        }
        var invalidLoopRoleModel = makeTwoFaceTriangleModelWithSameEdgeOrientations()
        if let loopID = invalidLoopRoleModel.loops.keys.first {
            invalidLoopRoleModel.loops[loopID]?.role = .inner
        }

        #expect(throws: TopologyError.self) {
            try invalidTrimModel.validate()
        }
        #expect(throws: TopologyError.self) {
            try invalidLoopRoleModel.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsUntrimmedCircularEdges() throws {
        var model = makeTwoFaceTriangleModelWithBalancedEdgeOrientations()
        let edgeID = try #require(model.edges.first { _, edge in
            model.vertices[edge.startVertexID]?.point == Point3D(x: 0.0, y: 0.0, z: 0.0)
                && model.vertices[edge.endVertexID]?.point == Point3D(x: 1.0, y: 0.0, z: 0.0)
        }?.key)
        let edge = try #require(model.edges[edgeID])
        let curveID = edge.curveID
        let center = Point3D(x: 0.5, y: 0.0, z: 0.0)
        model.geometry.curves[curveID] = .circle(Circle3D(center: center, normal: Vector3D.unitZ, radius: 0.5))

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsCoincidentOppositeFacesAsNonSolidShell() {
        let model = makeTwoFaceTriangleModelWithBalancedEdgeOrientations()

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationAllowsOpenBoundaryEdgesOnlyForSheetBodies() throws {
        let sheetModel = makeSingleFaceQuadModel(kind: .sheet)
        let solidModel = makeSingleFaceQuadModel(kind: .solid)

        try sheetModel.validate()
        #expect(throws: TopologyError.self) {
            try solidModel.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationUsesAngularToleranceForCircularTrimSpans() throws {
        let model = try makeTwoFaceTriangleModelWithCircularEdge(
            radius: 10_000_000.0,
            span: 1.0e-7
        )

        try model.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsDegenerateLineTrimSpans() throws {
        var model = makeTwoFaceTriangleModelWithBalancedEdgeOrientations()
        let edgeID = try #require(model.edges.keys.first)
        model.edges[edgeID]?.trim = CurveTrim(
            startParameter: 0.0,
            endParameter: ModelingTolerance.standard.distance / 2.0
        )

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsLineOnlyLoopsWithoutArea() {
        let model = makeTwoFaceLineSegmentModelWithoutLoopArea()

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsInvalidParameterReferences() {
        let missingID = ParameterID()
        let badID = ParameterID()
        let document = CADDocument(
            units: .millimeters,
            parameters: ParameterTable(parameters: [
                badID: Parameter(
                    id: badID,
                    name: "bad",
                    expression: .reference(missingID),
                    kind: .length
                )
            ])
        )

        #expect(throws: ParameterError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsNonResolvableParameterValues() {
        let zeroID = ParameterID()
        let dividedID = ParameterID()
        let zeroDivisionDocument = CADDocument(
            units: .meters,
            parameters: ParameterTable(parameters: [
                zeroID: Parameter(
                    id: zeroID,
                    name: "zero",
                    expression: .constant(.scalar(0.0)),
                    kind: .scalar
                ),
                dividedID: Parameter(
                    id: dividedID,
                    name: "divided",
                    expression: .divide(.constant(.length(1.0, unit: .meter)), .reference(zeroID)),
                    kind: .length
                )
            ])
        )

        let hugeID = ParameterID()
        let overflowID = ParameterID()
        let overflowDocument = CADDocument(
            units: .meters,
            parameters: ParameterTable(parameters: [
                hugeID: Parameter(
                    id: hugeID,
                    name: "huge",
                    expression: .constant(.scalar(Double.greatestFiniteMagnitude)),
                    kind: .scalar
                ),
                overflowID: Parameter(
                    id: overflowID,
                    name: "overflow",
                    expression: .multiply(.reference(hugeID), .constant(.scalar(2.0))),
                    kind: .scalar
                )
            ])
        )

        #expect(throws: UnitError.self) {
            try zeroDivisionDocument.validate()
        }
        #expect(throws: UnitError.self) {
            try overflowDocument.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsInvalidParameterNames() {
        let badID = ParameterID()
        let document = CADDocument(
            units: .millimeters,
            parameters: ParameterTable(parameters: [
                badID: Parameter(
                    id: badID,
                    name: "bad name",
                    expression: .constant(.length(1.0, unit: .meter)),
                    kind: .length
                )
            ])
        )

        #expect(throws: ParameterError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsUnboundVariablesInSourceExpressions() {
        let pointID = SketchEntityID()
        let sketchID = FeatureID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                pointID: .point(SketchPoint(
                    x: .variable("externalX", .length),
                    y: .constant(.length(0.0, unit: .meter))
                ))
            ]
        )
        let document = CADDocument(
            units: .millimeters,
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(sketch),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [sketchID]
            )
        )

        #expect(throws: ParameterError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsUnboundVariablesInParameters() {
        let badID = ParameterID()
        let document = CADDocument(
            units: .millimeters,
            parameters: ParameterTable(parameters: [
                badID: Parameter(
                    id: badID,
                    name: "width",
                    expression: .variable("externalWidth", .length),
                    kind: .length
                )
            ])
        )

        #expect(throws: ParameterError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsNonFiniteParameterValues() {
        let badID = ParameterID()
        let document = CADDocument(
            units: .millimeters,
            parameters: ParameterTable(parameters: [
                badID: Parameter(
                    id: badID,
                    name: "bad",
                    expression: .constant(.length(.nan, unit: .meter)),
                    kind: .length
                )
            ])
        )

        #expect(throws: UnitError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsParameterTableKeyMismatch() {
        let tableKey = ParameterID()
        let embeddedID = ParameterID()
        let document = CADDocument(
            units: .millimeters,
            parameters: ParameterTable(parameters: [
                tableKey: Parameter(
                    id: embeddedID,
                    name: "width",
                    expression: .constant(.length(1.0, unit: .meter)),
                    kind: .length
                )
            ])
        )

        #expect(throws: ParameterError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsNegativeRevisions() {
        let parameterRevisionDocument = CADDocument(
            units: .meters,
            parameters: ParameterTable(revision: DocumentRevision(-1))
        )
        let designRevisionDocument = CADDocument(
            units: .meters,
            designGraph: DesignGraph(revision: DocumentRevision(-1))
        )

        #expect(throws: SchemaError.self) {
            try parameterRevisionDocument.validate()
        }
        #expect(throws: SchemaError.self) {
            try designRevisionDocument.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsInvalidMetadataTimestamps() {
        let createdAt = Date(timeIntervalSinceReferenceDate: 100.0)
        let earlierUpdatedAt = Date(timeIntervalSinceReferenceDate: 99.0)
        let nonFiniteCreatedAt = Date(timeIntervalSinceReferenceDate: .nan)
        let orderedDocument = CADDocument(
            units: .meters,
            metadata: DocumentMetadata(createdAt: createdAt, updatedAt: earlierUpdatedAt)
        )
        let nonFiniteDocument = CADDocument(
            units: .meters,
            metadata: DocumentMetadata(createdAt: nonFiniteCreatedAt, updatedAt: createdAt)
        )

        #expect(throws: SchemaError.self) {
            try orderedDocument.validate()
        }
        #expect(throws: SchemaError.self) {
            try nonFiniteDocument.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsFutureSchemaVersion() {
        let document = CADDocument(
            schemaVersion: SchemaVersion(major: 1, minor: 1, patch: 0),
            units: .millimeters
        )

        #expect(throws: SchemaError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsNegativeSchemaVersion() {
        let document = CADDocument(
            schemaVersion: SchemaVersion(major: 1, minor: -1, patch: 0),
            units: .millimeters
        )

        #expect(throws: SchemaError.self) {
            try document.validate()
        }
    }
}

private func makeClosedTetrahedronModel() -> BRepModel {
    let firstVertexID = VertexID()
    let secondVertexID = VertexID()
    let thirdVertexID = VertexID()
    let fourthVertexID = VertexID()
    let firstPoint = Point3D(x: 0.0, y: 0.0, z: 0.0)
    let secondPoint = Point3D(x: 1.0, y: 0.0, z: 0.0)
    let thirdPoint = Point3D(x: 0.0, y: 1.0, z: 0.0)
    let fourthPoint = Point3D(x: 0.0, y: 0.0, z: 1.0)

    let firstCurveID = CurveID()
    let secondCurveID = CurveID()
    let thirdCurveID = CurveID()
    let fourthCurveID = CurveID()
    let fifthCurveID = CurveID()
    let sixthCurveID = CurveID()
    let firstEdgeID = EdgeID()
    let secondEdgeID = EdgeID()
    let thirdEdgeID = EdgeID()
    let fourthEdgeID = EdgeID()
    let fifthEdgeID = EdgeID()
    let sixthEdgeID = EdgeID()
    let firstSurfaceID = SurfaceID()
    let secondSurfaceID = SurfaceID()
    let thirdSurfaceID = SurfaceID()
    let fourthSurfaceID = SurfaceID()
    let firstLoopID = LoopID()
    let secondLoopID = LoopID()
    let thirdLoopID = LoopID()
    let fourthLoopID = LoopID()
    let firstFaceID = FaceID()
    let secondFaceID = FaceID()
    let thirdFaceID = FaceID()
    let fourthFaceID = FaceID()
    let shellID = ShellID()
    let bodyID = BodyID()

    let diagonal = sqrt(2.0)
    let triDiagonal = sqrt(3.0)
    return BRepModel(
        geometry: GeometryStore(
            curves: [
                firstCurveID: .line(Line3D(origin: firstPoint, direction: Vector3D.unitX)),
                secondCurveID: .line(Line3D(origin: firstPoint, direction: Vector3D.unitY)),
                thirdCurveID: .line(Line3D(origin: firstPoint, direction: Vector3D.unitZ)),
                fourthCurveID: .line(Line3D(
                    origin: secondPoint,
                    direction: Vector3D(x: -1.0 / diagonal, y: 1.0 / diagonal, z: 0.0)
                )),
                fifthCurveID: .line(Line3D(
                    origin: secondPoint,
                    direction: Vector3D(x: -1.0 / diagonal, y: 0.0, z: 1.0 / diagonal)
                )),
                sixthCurveID: .line(Line3D(
                    origin: thirdPoint,
                    direction: Vector3D(x: 0.0, y: -1.0 / diagonal, z: 1.0 / diagonal)
                ))
            ],
            surfaces: [
                firstSurfaceID: .plane(Plane3D(origin: firstPoint, normal: Vector3D.unitZ)),
                secondSurfaceID: .plane(Plane3D(origin: firstPoint, normal: -Vector3D.unitY)),
                thirdSurfaceID: .plane(Plane3D(origin: firstPoint, normal: Vector3D.unitX)),
                fourthSurfaceID: .plane(Plane3D(
                    origin: secondPoint,
                    normal: Vector3D(x: 1.0 / triDiagonal, y: 1.0 / triDiagonal, z: 1.0 / triDiagonal)
                ))
            ]
        ),
        bodies: [bodyID: Body(id: bodyID, shellIDs: [shellID])],
        shells: [shellID: Shell(id: shellID, faceIDs: [firstFaceID, secondFaceID, thirdFaceID, fourthFaceID])],
        faces: [
            firstFaceID: Face(id: firstFaceID, surfaceID: firstSurfaceID, loops: [firstLoopID]),
            secondFaceID: Face(id: secondFaceID, surfaceID: secondSurfaceID, loops: [secondLoopID]),
            thirdFaceID: Face(id: thirdFaceID, surfaceID: thirdSurfaceID, loops: [thirdLoopID]),
            fourthFaceID: Face(id: fourthFaceID, surfaceID: fourthSurfaceID, loops: [fourthLoopID])
        ],
        loops: [
            firstLoopID: Loop(id: firstLoopID, edges: [
                OrientedEdge(edgeID: firstEdgeID, orientation: .forward),
                OrientedEdge(edgeID: fourthEdgeID, orientation: .forward),
                OrientedEdge(edgeID: secondEdgeID, orientation: .reversed)
            ]),
            secondLoopID: Loop(id: secondLoopID, edges: [
                OrientedEdge(edgeID: thirdEdgeID, orientation: .forward),
                OrientedEdge(edgeID: fifthEdgeID, orientation: .reversed),
                OrientedEdge(edgeID: firstEdgeID, orientation: .reversed)
            ]),
            thirdLoopID: Loop(id: thirdLoopID, edges: [
                OrientedEdge(edgeID: secondEdgeID, orientation: .forward),
                OrientedEdge(edgeID: sixthEdgeID, orientation: .forward),
                OrientedEdge(edgeID: thirdEdgeID, orientation: .reversed)
            ]),
            fourthLoopID: Loop(id: fourthLoopID, edges: [
                OrientedEdge(edgeID: fifthEdgeID, orientation: .forward),
                OrientedEdge(edgeID: sixthEdgeID, orientation: .reversed),
                OrientedEdge(edgeID: fourthEdgeID, orientation: .reversed)
            ])
        ],
        edges: [
            firstEdgeID: Edge(
                id: firstEdgeID,
                curveID: firstCurveID,
                startVertexID: firstVertexID,
                endVertexID: secondVertexID
            ),
            secondEdgeID: Edge(
                id: secondEdgeID,
                curveID: secondCurveID,
                startVertexID: firstVertexID,
                endVertexID: thirdVertexID
            ),
            thirdEdgeID: Edge(
                id: thirdEdgeID,
                curveID: thirdCurveID,
                startVertexID: firstVertexID,
                endVertexID: fourthVertexID
            ),
            fourthEdgeID: Edge(
                id: fourthEdgeID,
                curveID: fourthCurveID,
                startVertexID: secondVertexID,
                endVertexID: thirdVertexID
            ),
            fifthEdgeID: Edge(
                id: fifthEdgeID,
                curveID: fifthCurveID,
                startVertexID: secondVertexID,
                endVertexID: fourthVertexID
            ),
            sixthEdgeID: Edge(
                id: sixthEdgeID,
                curveID: sixthCurveID,
                startVertexID: thirdVertexID,
                endVertexID: fourthVertexID
            )
        ],
        vertices: [
            firstVertexID: Vertex(id: firstVertexID, point: firstPoint),
            secondVertexID: Vertex(id: secondVertexID, point: secondPoint),
            thirdVertexID: Vertex(id: thirdVertexID, point: thirdPoint),
            fourthVertexID: Vertex(id: fourthVertexID, point: fourthPoint)
        ]
    )
}

private func makeTwoFaceTriangleModelWithSameEdgeOrientations() -> BRepModel {
    let firstVertexID = VertexID()
    let secondVertexID = VertexID()
    let thirdVertexID = VertexID()
    let firstPoint = Point3D(x: 0.0, y: 0.0, z: 0.0)
    let secondPoint = Point3D(x: 1.0, y: 0.0, z: 0.0)
    let thirdPoint = Point3D(x: 0.0, y: 1.0, z: 0.0)
    let firstCurveID = CurveID()
    let secondCurveID = CurveID()
    let thirdCurveID = CurveID()
    let firstEdgeID = EdgeID()
    let secondEdgeID = EdgeID()
    let thirdEdgeID = EdgeID()
    let surfaceID = SurfaceID()
    let firstLoopID = LoopID()
    let secondLoopID = LoopID()
    let firstFaceID = FaceID()
    let secondFaceID = FaceID()
    let shellID = ShellID()
    let bodyID = BodyID()

    let diagonalLength = sqrt(2.0)
    return BRepModel(
        geometry: GeometryStore(
            curves: [
                firstCurveID: .line(Line3D(origin: firstPoint, direction: Vector3D.unitX)),
                secondCurveID: .line(Line3D(
                    origin: secondPoint,
                    direction: Vector3D(x: -1.0 / diagonalLength, y: 1.0 / diagonalLength, z: 0.0)
                )),
                thirdCurveID: .line(Line3D(origin: thirdPoint, direction: -Vector3D.unitY))
            ],
            surfaces: [surfaceID: .plane(Plane3D(origin: firstPoint, normal: Vector3D.unitZ))]
        ),
        bodies: [bodyID: Body(id: bodyID, shellIDs: [shellID])],
        shells: [shellID: Shell(id: shellID, faceIDs: [firstFaceID, secondFaceID])],
        faces: [
            firstFaceID: Face(id: firstFaceID, surfaceID: surfaceID, loops: [firstLoopID]),
            secondFaceID: Face(id: secondFaceID, surfaceID: surfaceID, loops: [secondLoopID])
        ],
        loops: [
            firstLoopID: Loop(id: firstLoopID, edges: [
                OrientedEdge(edgeID: firstEdgeID, orientation: .forward),
                OrientedEdge(edgeID: secondEdgeID, orientation: .forward),
                OrientedEdge(edgeID: thirdEdgeID, orientation: .forward)
            ]),
            secondLoopID: Loop(id: secondLoopID, edges: [
                OrientedEdge(edgeID: firstEdgeID, orientation: .forward),
                OrientedEdge(edgeID: secondEdgeID, orientation: .forward),
                OrientedEdge(edgeID: thirdEdgeID, orientation: .forward)
            ])
        ],
        edges: [
            firstEdgeID: Edge(
                id: firstEdgeID,
                curveID: firstCurveID,
                startVertexID: firstVertexID,
                endVertexID: secondVertexID
            ),
            secondEdgeID: Edge(
                id: secondEdgeID,
                curveID: secondCurveID,
                startVertexID: secondVertexID,
                endVertexID: thirdVertexID
            ),
            thirdEdgeID: Edge(
                id: thirdEdgeID,
                curveID: thirdCurveID,
                startVertexID: thirdVertexID,
                endVertexID: firstVertexID
            )
        ],
        vertices: [
            firstVertexID: Vertex(id: firstVertexID, point: firstPoint),
            secondVertexID: Vertex(id: secondVertexID, point: secondPoint),
            thirdVertexID: Vertex(id: thirdVertexID, point: thirdPoint)
        ]
    )
}

private func makeTwoFaceTriangleModelWithBalancedEdgeOrientations() -> BRepModel {
    var model = makeTwoFaceTriangleModelWithSameEdgeOrientations()
    let loopIDs = model.loops.keys.sorted { $0.description < $1.description }
    guard loopIDs.count == 2,
          let firstLoop = model.loops[loopIDs[0]] else {
        return model
    }
    model.loops[loopIDs[1]]?.edges = firstLoop.edges.reversed().map { edge in
        OrientedEdge(edgeID: edge.edgeID, orientation: .reversed)
    }
    return model
}

private func makeTwoFaceTriangleModelWithCircularEdge(radius: Double, span: Double) throws -> BRepModel {
    let firstVertexID = VertexID()
    let secondVertexID = VertexID()
    let thirdVertexID = VertexID()
    let firstPoint = Point3D(x: radius, y: 0.0, z: 0.0)
    let secondPoint = Point3D(x: radius * cos(span), y: radius * sin(span), z: 0.0)
    let thirdPoint = Point3D(x: radius + 1.0, y: 0.5, z: 0.0)
    let firstCurveID = CurveID()
    let secondCurveID = CurveID()
    let thirdCurveID = CurveID()
    let firstEdgeID = EdgeID()
    let secondEdgeID = EdgeID()
    let thirdEdgeID = EdgeID()
    let surfaceID = SurfaceID()
    let firstLoopID = LoopID()
    let secondLoopID = LoopID()
    let firstFaceID = FaceID()
    let secondFaceID = FaceID()
    let shellID = ShellID()
    let bodyID = BodyID()
    let secondDelta = thirdPoint - secondPoint
    let thirdDelta = firstPoint - thirdPoint

    return BRepModel(
        geometry: GeometryStore(
            curves: [
                firstCurveID: .circle(Circle3D(center: .origin, normal: Vector3D.unitZ, radius: radius)),
                secondCurveID: .line(Line3D(
                    origin: secondPoint,
                    direction: try secondDelta.normalized(tolerance: ModelingTolerance.standard.distance)
                )),
                thirdCurveID: .line(Line3D(
                    origin: thirdPoint,
                    direction: try thirdDelta.normalized(tolerance: ModelingTolerance.standard.distance)
                ))
            ],
            surfaces: [surfaceID: .plane(Plane3D(origin: .origin, normal: Vector3D.unitZ))]
        ),
        bodies: [bodyID: Body(id: bodyID, shellIDs: [shellID])],
        shells: [shellID: Shell(id: shellID, faceIDs: [firstFaceID, secondFaceID])],
        faces: [
            firstFaceID: Face(id: firstFaceID, surfaceID: surfaceID, loops: [firstLoopID]),
            secondFaceID: Face(id: secondFaceID, surfaceID: surfaceID, loops: [secondLoopID])
        ],
        loops: [
            firstLoopID: Loop(id: firstLoopID, edges: [
                OrientedEdge(edgeID: firstEdgeID, orientation: .forward),
                OrientedEdge(edgeID: secondEdgeID, orientation: .forward),
                OrientedEdge(edgeID: thirdEdgeID, orientation: .forward)
            ]),
            secondLoopID: Loop(id: secondLoopID, edges: [
                OrientedEdge(edgeID: thirdEdgeID, orientation: .reversed),
                OrientedEdge(edgeID: secondEdgeID, orientation: .reversed),
                OrientedEdge(edgeID: firstEdgeID, orientation: .reversed)
            ])
        ],
        edges: [
            firstEdgeID: Edge(
                id: firstEdgeID,
                curveID: firstCurveID,
                startVertexID: firstVertexID,
                endVertexID: secondVertexID,
                trim: CurveTrim(startParameter: 0.0, endParameter: span)
            ),
            secondEdgeID: Edge(
                id: secondEdgeID,
                curveID: secondCurveID,
                startVertexID: secondVertexID,
                endVertexID: thirdVertexID,
                trim: CurveTrim(startParameter: 0.0, endParameter: secondDelta.length)
            ),
            thirdEdgeID: Edge(
                id: thirdEdgeID,
                curveID: thirdCurveID,
                startVertexID: thirdVertexID,
                endVertexID: firstVertexID,
                trim: CurveTrim(startParameter: 0.0, endParameter: thirdDelta.length)
            )
        ],
        vertices: [
            firstVertexID: Vertex(id: firstVertexID, point: firstPoint),
            secondVertexID: Vertex(id: secondVertexID, point: secondPoint),
            thirdVertexID: Vertex(id: thirdVertexID, point: thirdPoint)
        ]
    )
}

private func makeSingleFaceQuadModel(kind: BodyKind) -> BRepModel {
    let firstVertexID = VertexID()
    let secondVertexID = VertexID()
    let thirdVertexID = VertexID()
    let fourthVertexID = VertexID()
    let firstPoint = Point3D(x: 0.0, y: 0.0, z: 0.0)
    let secondPoint = Point3D(x: 1.0, y: 0.0, z: 0.0)
    let thirdPoint = Point3D(x: 1.0, y: 1.0, z: 0.0)
    let fourthPoint = Point3D(x: 0.0, y: 1.0, z: 0.0)
    let firstCurveID = CurveID()
    let secondCurveID = CurveID()
    let thirdCurveID = CurveID()
    let fourthCurveID = CurveID()
    let firstEdgeID = EdgeID()
    let secondEdgeID = EdgeID()
    let thirdEdgeID = EdgeID()
    let fourthEdgeID = EdgeID()
    let surfaceID = SurfaceID()
    let loopID = LoopID()
    let faceID = FaceID()
    let shellID = ShellID()
    let bodyID = BodyID()

    return BRepModel(
        geometry: GeometryStore(
            curves: [
                firstCurveID: .line(Line3D(origin: firstPoint, direction: Vector3D.unitX)),
                secondCurveID: .line(Line3D(origin: secondPoint, direction: Vector3D.unitY)),
                thirdCurveID: .line(Line3D(origin: thirdPoint, direction: -Vector3D.unitX)),
                fourthCurveID: .line(Line3D(origin: fourthPoint, direction: -Vector3D.unitY))
            ],
            surfaces: [surfaceID: .plane(Plane3D(origin: firstPoint, normal: Vector3D.unitZ))]
        ),
        bodies: [bodyID: Body(id: bodyID, shellIDs: [shellID], kind: kind)],
        shells: [shellID: Shell(id: shellID, faceIDs: [faceID])],
        faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: [loopID])],
        loops: [
            loopID: Loop(id: loopID, edges: [
                OrientedEdge(edgeID: firstEdgeID, orientation: .forward),
                OrientedEdge(edgeID: secondEdgeID, orientation: .forward),
                OrientedEdge(edgeID: thirdEdgeID, orientation: .forward),
                OrientedEdge(edgeID: fourthEdgeID, orientation: .forward)
            ])
        ],
        edges: [
            firstEdgeID: Edge(
                id: firstEdgeID,
                curveID: firstCurveID,
                startVertexID: firstVertexID,
                endVertexID: secondVertexID
            ),
            secondEdgeID: Edge(
                id: secondEdgeID,
                curveID: secondCurveID,
                startVertexID: secondVertexID,
                endVertexID: thirdVertexID
            ),
            thirdEdgeID: Edge(
                id: thirdEdgeID,
                curveID: thirdCurveID,
                startVertexID: thirdVertexID,
                endVertexID: fourthVertexID
            ),
            fourthEdgeID: Edge(
                id: fourthEdgeID,
                curveID: fourthCurveID,
                startVertexID: fourthVertexID,
                endVertexID: firstVertexID
            )
        ],
        vertices: [
            firstVertexID: Vertex(id: firstVertexID, point: firstPoint),
            secondVertexID: Vertex(id: secondVertexID, point: secondPoint),
            thirdVertexID: Vertex(id: thirdVertexID, point: thirdPoint),
            fourthVertexID: Vertex(id: fourthVertexID, point: fourthPoint)
        ]
    )
}

private func makeTwoFaceLineSegmentModelWithoutLoopArea() -> BRepModel {
    let firstVertexID = VertexID()
    let secondVertexID = VertexID()
    let firstPoint = Point3D(x: 0.0, y: 0.0, z: 0.0)
    let secondPoint = Point3D(x: 1.0, y: 0.0, z: 0.0)
    let firstCurveID = CurveID()
    let secondCurveID = CurveID()
    let firstEdgeID = EdgeID()
    let secondEdgeID = EdgeID()
    let surfaceID = SurfaceID()
    let firstLoopID = LoopID()
    let secondLoopID = LoopID()
    let firstFaceID = FaceID()
    let secondFaceID = FaceID()
    let shellID = ShellID()
    let bodyID = BodyID()

    return BRepModel(
        geometry: GeometryStore(
            curves: [
                firstCurveID: .line(Line3D(origin: firstPoint, direction: Vector3D.unitX)),
                secondCurveID: .line(Line3D(origin: secondPoint, direction: -Vector3D.unitX))
            ],
            surfaces: [surfaceID: .plane(Plane3D(origin: firstPoint, normal: Vector3D.unitZ))]
        ),
        bodies: [bodyID: Body(id: bodyID, shellIDs: [shellID])],
        shells: [shellID: Shell(id: shellID, faceIDs: [firstFaceID, secondFaceID])],
        faces: [
            firstFaceID: Face(id: firstFaceID, surfaceID: surfaceID, loops: [firstLoopID]),
            secondFaceID: Face(id: secondFaceID, surfaceID: surfaceID, loops: [secondLoopID])
        ],
        loops: [
            firstLoopID: Loop(id: firstLoopID, edges: [
                OrientedEdge(edgeID: firstEdgeID, orientation: .forward),
                OrientedEdge(edgeID: secondEdgeID, orientation: .forward)
            ]),
            secondLoopID: Loop(id: secondLoopID, edges: [
                OrientedEdge(edgeID: secondEdgeID, orientation: .reversed),
                OrientedEdge(edgeID: firstEdgeID, orientation: .reversed)
            ])
        ],
        edges: [
            firstEdgeID: Edge(
                id: firstEdgeID,
                curveID: firstCurveID,
                startVertexID: firstVertexID,
                endVertexID: secondVertexID
            ),
            secondEdgeID: Edge(
                id: secondEdgeID,
                curveID: secondCurveID,
                startVertexID: secondVertexID,
                endVertexID: firstVertexID
            )
        ],
        vertices: [
            firstVertexID: Vertex(id: firstVertexID, point: firstPoint),
            secondVertexID: Vertex(id: secondVertexID, point: secondPoint)
        ]
    )
}

private func makeWeightedBilinearSurface() -> BSplineSurface3D {
    BSplineSurface3D(
        uDegree: 1,
        vDegree: 1,
        uKnots: [0.0, 0.0, 1.0, 1.0],
        vKnots: [0.0, 0.0, 1.0, 1.0],
        controlPoints: [
            [Point3D(x: 0.0, y: 0.0, z: 0.0), Point3D(x: 2.0, y: 0.0, z: 0.0)],
            [Point3D(x: 0.0, y: 2.0, z: 0.0), Point3D(x: 2.0, y: 2.0, z: 0.0)],
        ],
        weights: [[4.0, 1.0], [1.0, 1.0]]
    )
}

private func makeQuarterCircleNURBSCurve() -> BSplineCurve3D {
    BSplineCurve3D(
        degree: 2,
        knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
        controlPoints: [
            Point3D(x: 1.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 1.0, z: 0.0),
            Point3D(x: 0.0, y: 1.0, z: 0.0),
        ],
        weights: [1.0, sqrt(0.5), 1.0]
    )
}

private func makeBridgeCurveFeature() -> BridgeCurveFeature {
    BridgeCurveFeature(
        start: BridgeCurveEndpointTarget(
            curve: .line(Line3D(origin: .origin, direction: .unitX)),
            parameter: 0.0,
            requiredLevel: .tangent
        ),
        end: BridgeCurveEndpointTarget(
            curve: .line(Line3D(
                origin: Point3D(x: 0.0, y: 0.0, z: 0.01),
                direction: .unitX
            )),
            parameter: 0.0,
            requiredLevel: .tangent
        )
    )
}

private func sketchPoint(x: Double, y: Double) -> SketchPoint {
    SketchPoint(
        x: .constant(.length(x, unit: .meter)),
        y: .constant(.length(y, unit: .meter))
    )
}
