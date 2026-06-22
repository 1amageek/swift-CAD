import Testing
import Foundation
import CADCore
import CADIR
@testable import CADKernel

@Suite("CADKernel")
struct CADKernelTests {
    @Test(.timeLimit(.minutes(1)))
    func parameterResolverResolvesNestedReferences() throws {
        let widthID = ParameterID()
        let heightID = ParameterID()
        let table = ParameterTable(parameters: [
            widthID: Parameter(
                id: widthID,
                name: "width",
                expression: .constant(.length(40.0, unit: .millimeter)),
                kind: .length
            ),
            heightID: Parameter(
                id: heightID,
                name: "height",
                expression: .divide(.reference(widthID), .constant(.scalar(2.0))),
                kind: .length
            )
        ])

        let resolved = try ParameterResolver().resolve(table)
        #expect(abs(try resolved.value(for: heightID).value - 0.02) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func parameterResolverRejectsInvalidUnitAddition() {
        let widthID = ParameterID()
        let table = ParameterTable(parameters: [
            widthID: Parameter(
                id: widthID,
                name: "bad",
                expression: .add(
                    .constant(.length(1.0, unit: .meter)),
                    .constant(.angle(90.0, unit: .degree))
                ),
                kind: .length
            )
        ])

        #expect(throws: UnitError.self) {
            _ = try ParameterResolver().resolve(table)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func parameterResolverRejectsParameterTableKeyMismatch() {
        let tableKey = ParameterID()
        let embeddedID = ParameterID()
        let table = ParameterTable(parameters: [
            tableKey: Parameter(
                id: embeddedID,
                name: "width",
                expression: .constant(.length(1.0, unit: .meter)),
                kind: .length
            )
        ])

        #expect(throws: ParameterError.self) {
            _ = try ParameterResolver().resolve(table)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func parameterResolverEvaluatesBoundVariables() throws {
        let value = try ParameterResolver().evaluate(
            .variable("offset", .length),
            parameters: ResolvedParameterTable(),
            variables: ["offset": .length(5.0, unit: .millimeter)]
        )

        #expect(value.kind == .length)
        #expect(abs(value.value - 0.005) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func parameterResolverRejectsInvalidVariableNames() {
        #expect(throws: ParameterError.self) {
            _ = try ParameterResolver().evaluate(
                .variable("bad name", .length),
                parameters: ResolvedParameterTable(),
                variables: ["bad name": .length(5.0, unit: .millimeter)]
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rectangleExtrudeCreatesClosedBoxBRepAndDeterministicMesh() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        try evaluated.brep.validate()
        #expect(evaluated.caches.brep?.parameterRevision == document.parameters.revision)
        #expect(evaluated.generatedNames.values.filter(\.isEdge).count == 12)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count == 36)
        #expect(mesh.positions.count == 24)
        #expect(mesh.normals[0].z < -0.9)
        let firstNormal = try firstTriangleNormal(in: mesh)
        #expect(firstNormal.dot(mesh.normals[0]) > 0.9)

        let evaluatedAgain = try DocumentEvaluator().evaluate(document)
        #expect(evaluatedAgain.meshes.values.first?.indices == mesh.indices)
    }

    @Test(.timeLimit(.minutes(1)))
    func faceLoopOffsetSplitsRectangularCapFaceWithPersistentOffsetEdges() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let offsetFeatureID = FeatureID()
        let targetFaceName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.startFace.rawValue),
        ])
        let offsetFeature = FeatureNode(
            id: offsetFeatureID,
            operation: .faceLoopOffset(
                FaceLoopOffsetFeature(
                    target: FaceLoopOffsetTargetReference(featureID: extrudeFeatureID),
                    facePersistentName: targetFaceName,
                    distance: .constant(.length(2.0, unit: .millimeter))
                )
            ),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.nodes[offsetFeatureID] = offsetFeature
        document.designGraph.order.append(offsetFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: extrudeFeatureID, target: offsetFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator().evaluate(document)
        let offsetEdgeNames = evaluated.generatedNames.filter { name, reference in
            reference.isEdge &&
                name.components.contains(.feature(offsetFeatureID)) &&
                name.components.contains(.generated("faceLoopOffset"))
        }
        let centerFaceName = PersistentName(components: [
            .feature(offsetFeatureID),
            .generated("faceLoopOffset"),
            .subshape("centerFace"),
        ])

        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.edges.count == 16)
        #expect(evaluated.brep.vertices.count == 12)
        #expect(offsetEdgeNames.count == 4)
        #expect(evaluated.generatedNames[centerFaceName] != nil)
        #expect(evaluated.generatedNames[targetFaceName] != nil)
        try evaluated.brep.validate()

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count > 36)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func faceKnifeSplitsPlanarFaceWithPersistentKnifeTopology() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let knifeFeatureID = FeatureID()
        let targetFaceName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.startFace.rawValue),
        ])
        let knifeFeature = FeatureNode(
            id: knifeFeatureID,
            operation: .faceKnife(
                FaceKnifeFeature(
                    target: FaceKnifeTargetReference(featureID: extrudeFeatureID),
                    facePersistentName: targetFaceName,
                    loop: [
                        Point3D(x: -0.01, y: -0.005, z: 0.0),
                        Point3D(x: 0.01, y: -0.005, z: 0.0),
                        Point3D(x: 0.01, y: 0.005, z: 0.0),
                        Point3D(x: -0.01, y: 0.005, z: 0.0),
                    ]
                )
            ),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.nodes[knifeFeatureID] = knifeFeature
        document.designGraph.order.append(knifeFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: extrudeFeatureID, target: knifeFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator().evaluate(document)
        let knifeEdgeNames = evaluated.generatedNames.filter { name, reference in
            reference.isEdge &&
                name.components.contains(.feature(knifeFeatureID)) &&
                name.components.contains(.generated("faceKnife")) &&
                name.components.contains(.subshape("knifeEdge"))
        }
        let faceKnifeFaceNames = evaluated.generatedNames.filter { name, reference in
            reference.isFace &&
                name.components.contains(.feature(knifeFeatureID)) &&
                name.components.contains(.generated("faceKnife"))
        }
        let centerFaceName = PersistentName(components: [
            .feature(knifeFeatureID),
            .generated("faceKnife"),
            .subshape("centerFace"),
        ])

        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.edges.count == 16)
        #expect(evaluated.brep.vertices.count == 12)
        #expect(knifeEdgeNames.count == 4)
        #expect(faceKnifeFaceNames.count == 7)
        #expect(evaluated.generatedNames[centerFaceName] != nil)
        #expect(evaluated.generatedNames[targetFaceName] != nil)
        try evaluated.brep.validate()

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count > 36)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func faceKnifeSplitsPlanarFaceWithConcaveLoop() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let knifeFeatureID = FeatureID()
        let targetFaceName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.startFace.rawValue),
        ])
        let knifeFeature = FeatureNode(
            id: knifeFeatureID,
            operation: .faceKnife(
                FaceKnifeFeature(
                    target: FaceKnifeTargetReference(featureID: extrudeFeatureID),
                    facePersistentName: targetFaceName,
                    loop: [
                        Point3D(x: -0.012, y: -0.006, z: 0.0),
                        Point3D(x: 0.012, y: -0.006, z: 0.0),
                        Point3D(x: 0.004, y: 0.0, z: 0.0),
                        Point3D(x: 0.012, y: 0.006, z: 0.0),
                        Point3D(x: -0.012, y: 0.006, z: 0.0),
                    ]
                )
            ),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.nodes[knifeFeatureID] = knifeFeature
        document.designGraph.order.append(knifeFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: extrudeFeatureID, target: knifeFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator().evaluate(document)
        let knifeEdgeNames = evaluated.generatedNames.filter { name, reference in
            reference.isEdge &&
                name.components.contains(.feature(knifeFeatureID)) &&
                name.components.contains(.generated("faceKnife")) &&
                name.components.contains(.subshape("knifeEdge"))
        }
        let faceKnifeFaceNames = evaluated.generatedNames.filter { name, reference in
            reference.isFace &&
                name.components.contains(.feature(knifeFeatureID)) &&
                name.components.contains(.generated("faceKnife"))
        }
        let centerFaceName = PersistentName(components: [
            .feature(knifeFeatureID),
            .generated("faceKnife"),
            .subshape("centerFace"),
        ])

        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.edges.count == 17)
        #expect(evaluated.brep.vertices.count == 13)
        #expect(knifeEdgeNames.count == 5)
        #expect(faceKnifeFaceNames.count == 7)
        #expect(evaluated.generatedNames[centerFaceName] != nil)
        try evaluated.brep.validate()

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count > 36)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func faceLoopOffsetRejectsNonRectangularFourEdgeFace() throws {
        var document = makeParallelogramExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let offsetFeatureID = FeatureID()
        let targetFaceName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.startFace.rawValue),
        ])
        let offsetFeature = FeatureNode(
            id: offsetFeatureID,
            operation: .faceLoopOffset(
                FaceLoopOffsetFeature(
                    target: FaceLoopOffsetTargetReference(featureID: extrudeFeatureID),
                    facePersistentName: targetFaceName,
                    distance: .constant(.length(2.0, unit: .millimeter))
                )
            ),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.nodes[offsetFeatureID] = offsetFeature
        document.designGraph.order.append(offsetFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: extrudeFeatureID, target: offsetFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        #expect(throws: FeatureEvaluationError.self) {
            _ = try DocumentEvaluator().evaluate(document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func edgeOffsetSplitsRectangularSupportFaceAndBoundaryEdges() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let offsetFeatureID = FeatureID()
        let selectedEdgeName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .index(0),
        ])
        let removedNextEdgeName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .index(1),
        ])
        let removedPreviousEdgeName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .index(3),
        ])
        let supportFaceName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.startFace.rawValue),
        ])
        let offsetFeature = FeatureNode(
            id: offsetFeatureID,
            operation: .edgeOffset(
                EdgeOffsetFeature(
                    target: EdgeOffsetTargetReference(featureID: extrudeFeatureID),
                    edgePersistentName: selectedEdgeName,
                    supportFacePersistentName: supportFaceName,
                    distance: .constant(.length(2.0, unit: .millimeter)),
                    gapFill: .linear
                )
            ),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.nodes[offsetFeatureID] = offsetFeature
        document.designGraph.order.append(offsetFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: extrudeFeatureID, target: offsetFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator().evaluate(document)
        let offsetEdgeName = PersistentName(components: [
            .feature(offsetFeatureID),
            .generated("edgeOffset"),
            .subshape("offsetEdge"),
        ])
        let remainderFaceName = PersistentName(components: [
            .feature(offsetFeatureID),
            .generated("edgeOffset"),
            .subshape("remainderFace"),
        ])

        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.edges.count == 15)
        #expect(evaluated.brep.vertices.count == 10)
        #expect(evaluated.generatedNames[selectedEdgeName]?.isEdge == true)
        #expect(evaluated.generatedNames[removedNextEdgeName] == nil)
        #expect(evaluated.generatedNames[removedPreviousEdgeName] == nil)
        #expect(evaluated.generatedNames[offsetEdgeName]?.isEdge == true)
        #expect(evaluated.generatedNames[remainderFaceName]?.isFace == true)
        try evaluated.brep.validate()

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count > 36)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepCreatesClosedPrismaticBRep() throws {
        let document = makeStraightPathSweepDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        try evaluated.brep.validate()
        #expect(evaluated.generatedNames.values.filter(\.isEdge).count == 12)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count == 36)
        #expect(mesh.positions.count == 24)
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepHonorsDistanceFractionThroughPathSampler() throws {
        let document = makeStraightPathSweepDocument(options: SweepOptions(
            distanceFraction: .constant(.scalar(0.5))
        ))
        let evaluated = try DocumentEvaluator().evaluate(document)
        let maxZ = evaluated.brep.vertices.values.map(\.point.z).max()

        #expect(abs((maxZ ?? 0.0) - 0.005) <= 1.0e-12)
        #expect(evaluated.brep.bodies.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepUnionReplacesTargetBoxWithBooleanResult() throws {
        let setup = makeBoxBooleanSweepDocument(
            targetWidth: 60.0,
            targetHeight: 30.0,
            toolWidth: 40.0,
            toolHeight: 20.0,
            operation: .union
        )
        let evaluated = try DocumentEvaluator().evaluate(setup.document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.feature(setup.targetFeatureID))
        } == false)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components == [
                .feature(setup.sweepFeatureID),
                .generated(GeneratedSubshapeRole.body.rawValue),
            ]
        })
        try evaluated.brep.validate()
        try expectBounds(
            evaluated.brep,
            minimum: Point3D(x: -0.030, y: -0.015, z: 0.0),
            maximum: Point3D(x: 0.030, y: 0.015, z: 0.010)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepUnionCanKeepTargetAndToolBodies() throws {
        let setup = makeBoxBooleanSweepDocument(
            targetWidth: 60.0,
            targetHeight: 30.0,
            toolWidth: 40.0,
            toolHeight: 20.0,
            operation: .union,
            keepTools: true
        )
        let evaluated = try DocumentEvaluator().evaluate(setup.document)

        #expect(evaluated.brep.bodies.count == 3)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.feature(setup.targetFeatureID))
        })
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.feature(setup.sweepFeatureID))
                && $0.components.contains(.subshape("tool"))
        })
        #expect(evaluated.generatedNames.keys.contains {
            $0.components == [
                .feature(setup.sweepFeatureID),
                .generated(GeneratedSubshapeRole.body.rawValue),
            ]
        })
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepBooleanResultPublishesSemanticBoxTopologyNames() throws {
        let setup = makeBoxBooleanSweepDocument(
            targetWidth: 60.0,
            targetHeight: 30.0,
            toolWidth: 40.0,
            toolHeight: 20.0,
            operation: .union
        )
        let evaluated = try DocumentEvaluator().evaluate(setup.document)
        let cornerName = PersistentName(components: [
            .feature(setup.sweepFeatureID),
            .generated(GeneratedSubshapeRole.vertex.rawValue),
            .subshape("box:0:corner:minX:minY:minZ"),
        ])
        let edgeName = PersistentName(components: [
            .feature(setup.sweepFeatureID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .subshape("box:0:zEdge:x:maxX:y:maxY"),
        ])
        let faceName = PersistentName(components: [
            .feature(setup.sweepFeatureID),
            .generated(GeneratedSubshapeRole.sideFace.rawValue),
            .subshape("box:0:face:maxX"),
        ])

        #expect(evaluated.generatedNames[cornerName]?.isVertex == true)
        #expect(evaluated.generatedNames[edgeName]?.isEdge == true)
        #expect(evaluated.generatedNames[faceName]?.isFace == true)
        #expect(evaluated.generatedNames.keys.contains { name in
            name.components.contains(.feature(setup.sweepFeatureID))
                && name.components.contains { component in
                    if case .index = component {
                        return true
                    }
                    return false
                }
        } == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepDifferenceTrimsRectangularTargetSlab() throws {
        let setup = makeBoxBooleanSweepDocument(
            targetWidth: 40.0,
            targetHeight: 20.0,
            toolWidth: 20.0,
            toolHeight: 20.0,
            toolCenterX: 10.0,
            operation: .difference
        )
        let evaluated = try DocumentEvaluator().evaluate(setup.document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        try evaluated.brep.validate()
        try expectBounds(
            evaluated.brep,
            minimum: Point3D(x: -0.020, y: -0.010, z: 0.0),
            maximum: Point3D(x: 0.0, y: 0.010, z: 0.010)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepDifferenceSplitsTargetIntoSeparatedBoxShells() throws {
        let setup = makeBoxBooleanSweepDocument(
            targetWidth: 40.0,
            targetHeight: 20.0,
            toolWidth: 20.0,
            toolHeight: 20.0,
            operation: .difference
        )
        let evaluated = try DocumentEvaluator().evaluate(setup.document)
        let body = try #require(evaluated.brep.bodies.values.first)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(body.shellIDs.count == 2)
        #expect(evaluated.brep.shells.count == 2)
        #expect(evaluated.brep.faces.count == 12)
        #expect(evaluated.brep.edges.count == 24)
        #expect(evaluated.brep.vertices.count == 16)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.feature(setup.targetFeatureID))
        } == false)
        #expect(evaluated.generatedNames.values.filter(\.isBody).count == 1)
        #expect(evaluated.generatedNames.values.filter(\.isFace).count == evaluated.brep.faces.count)
        #expect(evaluated.generatedNames.values.filter(\.isEdge).count == evaluated.brep.edges.count)
        #expect(evaluated.generatedNames.values.filter(\.isVertex).count == evaluated.brep.vertices.count)
        try evaluated.brep.validate()
        try expectBounds(
            evaluated.brep,
            minimum: Point3D(x: -0.020, y: -0.010, z: 0.0),
            maximum: Point3D(x: 0.020, y: 0.010, z: 0.010)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepDifferenceCreatesRectangularThroughHoleFrame() throws {
        let setup = makeBoxBooleanSweepDocument(
            targetWidth: 40.0,
            targetHeight: 40.0,
            toolWidth: 20.0,
            toolHeight: 20.0,
            operation: .difference
        )
        let evaluated = try DocumentEvaluator().evaluate(setup.document)
        let body = try #require(evaluated.brep.bodies.values.first)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(body.shellIDs.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 10)
        #expect(evaluated.brep.loops.count == 12)
        #expect(evaluated.brep.edges.count == 24)
        #expect(evaluated.brep.vertices.count == 16)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.feature(setup.targetFeatureID))
        } == false)
        #expect(evaluated.generatedNames.values.filter(\.isBody).count == 1)
        #expect(evaluated.generatedNames.values.filter(\.isFace).count == evaluated.brep.faces.count)
        #expect(evaluated.generatedNames.values.filter(\.isEdge).count == evaluated.brep.edges.count)
        #expect(evaluated.generatedNames.values.filter(\.isVertex).count == evaluated.brep.vertices.count)
        try evaluated.brep.validate()
        try expectBounds(
            evaluated.brep,
            minimum: Point3D(x: -0.020, y: -0.020, z: 0.0),
            maximum: Point3D(x: 0.020, y: 0.020, z: 0.010)
        )
        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.positions.count >= evaluated.brep.vertices.count)
        #expect(mesh.indices.count == 96)
        try mesh.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepBooleanFramePublishesSemanticTopologyNames() throws {
        let setup = makeBoxBooleanSweepDocument(
            targetWidth: 40.0,
            targetHeight: 40.0,
            toolWidth: 20.0,
            toolHeight: 20.0,
            operation: .difference
        )
        let evaluated = try DocumentEvaluator().evaluate(setup.document)
        let holeCornerName = PersistentName(components: [
            .feature(setup.sweepFeatureID),
            .generated(GeneratedSubshapeRole.vertex.rawValue),
            .subshape("frame:hole:corner:maxX:maxY:maxZ"),
        ])
        let holeEdgeName = PersistentName(components: [
            .feature(setup.sweepFeatureID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .subshape("frame:hole:zEdge:x:maxX:y:maxY"),
        ])
        let holeFaceName = PersistentName(components: [
            .feature(setup.sweepFeatureID),
            .generated(GeneratedSubshapeRole.sideFace.rawValue),
            .subshape("frame:holeFace:maxX"),
        ])
        let capFaceName = PersistentName(components: [
            .feature(setup.sweepFeatureID),
            .generated(GeneratedSubshapeRole.sideFace.rawValue),
            .subshape("frame:face:minZ"),
        ])

        #expect(evaluated.generatedNames[holeCornerName]?.isVertex == true)
        #expect(evaluated.generatedNames[holeEdgeName]?.isEdge == true)
        #expect(evaluated.generatedNames[holeFaceName]?.isFace == true)
        #expect(evaluated.generatedNames[capFaceName]?.isFace == true)
        #expect(evaluated.generatedNames.keys.contains { name in
            name.components.contains(.feature(setup.sweepFeatureID))
                && name.components.contains { component in
                    if case .index = component {
                        return true
                    }
                    return false
                }
        } == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepDifferenceCreatesConnectedNonRectangularCellUnion() throws {
        let setup = makeBoxBooleanSweepDocument(
            targetWidth: 40.0,
            targetHeight: 40.0,
            toolWidth: 30.0,
            toolHeight: 30.0,
            toolCenterX: 10.0,
            toolCenterY: 10.0,
            operation: .difference
        )
        let evaluated = try DocumentEvaluator().evaluate(setup.document)
        let body = try #require(evaluated.brep.bodies.values.first)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(body.shellIDs.count == 1)
        #expect(evaluated.brep.faces.count > 6)
        #expect(evaluated.brep.edges.count > 12)
        #expect(evaluated.brep.vertices.count > 8)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.feature(setup.targetFeatureID))
        } == false)
        #expect(evaluated.generatedNames.values.filter(\.isBody).count == 1)
        #expect(evaluated.generatedNames.values.filter(\.isFace).count == evaluated.brep.faces.count)
        #expect(evaluated.generatedNames.values.filter(\.isEdge).count == evaluated.brep.edges.count)
        #expect(evaluated.generatedNames.values.filter(\.isVertex).count == evaluated.brep.vertices.count)
        #expect(evaluated.generatedNames.keys.contains { name in
            name.components.contains(.feature(setup.sweepFeatureID))
                && name.components.contains(.subshape("cellUnion:component:0:face:maxX:x:maxX:y:minY-y1:z:minZ-maxZ"))
        })
        #expect(evaluated.generatedNames.keys.contains { name in
            name.components.contains(.feature(setup.sweepFeatureID))
                && name.components.contains(.subshape("cellUnion:component:0:zEdge:x:x1:y:y1:z:minZ-maxZ"))
        })
        #expect(evaluated.generatedNames.keys.contains { name in
            name.components.contains(.feature(setup.sweepFeatureID))
                && name.components.contains { component in
                    if case .index = component {
                        return true
                    }
                    return false
                }
        } == false)
        try evaluated.brep.validate()
        try expectBounds(
            evaluated.brep,
            minimum: Point3D(x: -0.020, y: -0.020, z: 0.0),
            maximum: Point3D(x: 0.020, y: 0.020, z: 0.010)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepSliceSplitsRectangularTargetIntoBoxShells() throws {
        let setup = makeBoxBooleanSweepDocument(
            targetWidth: 40.0,
            targetHeight: 20.0,
            toolWidth: 20.0,
            toolHeight: 20.0,
            operation: .slice
        )
        let evaluated = try DocumentEvaluator().evaluate(setup.document)
        let body = try #require(evaluated.brep.bodies.values.first)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(body.shellIDs.count == 3)
        #expect(evaluated.brep.shells.count == 3)
        #expect(evaluated.brep.faces.count == 18)
        #expect(evaluated.brep.edges.count == 36)
        #expect(evaluated.brep.vertices.count == 24)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.feature(setup.targetFeatureID))
        } == false)
        #expect(evaluated.generatedNames.values.filter(\.isBody).count == 1)
        #expect(evaluated.generatedNames.values.filter(\.isFace).count == evaluated.brep.faces.count)
        #expect(evaluated.generatedNames.values.filter(\.isEdge).count == evaluated.brep.edges.count)
        #expect(evaluated.generatedNames.values.filter(\.isVertex).count == evaluated.brep.vertices.count)
        try evaluated.brep.validate()
        try expectBounds(
            evaluated.brep,
            minimum: Point3D(x: -0.020, y: -0.010, z: 0.0),
            maximum: Point3D(x: 0.020, y: 0.010, z: 0.010)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func sweepPathSamplerBuildsMovingFramesForCurvedPath() throws {
        let points = [
            Point3D(x: 1.0, y: 0.0, z: 0.0),
            Point3D(x: 0.707_106_781_186_547_6, y: 0.707_106_781_186_547_5, z: 0.0),
            Point3D(x: 0.0, y: 1.0, z: 0.0),
        ]
        let curve = EvaluatedSketchCurve(
            sourceFeatureID: FeatureID(),
            entityID: SketchEntityID(),
            kind: .arc,
            points: points
        )
        let sampler = SweepPathSampler(tolerance: ModelingTolerance(distance: 1.0e-9, angle: 1.0e-9))
        let frames = try sampler.frames(
            for: curve,
            distanceFraction: 1.0,
            preferredNormal: .unitZ
        )

        #expect(frames.count == 3)
        let straightPath = try sampler.straightPath(from: frames)
        #expect(straightPath == nil)
        for frame in frames {
            try frame.validate(tolerance: ModelingTolerance(distance: 1.0e-9, angle: 1.0e-9))
            #expect(abs(frame.tangent.dot(frame.normal)) <= 1.0e-9)
            #expect(abs(frame.tangent.dot(frame.binormal)) <= 1.0e-9)
            #expect(abs(frame.normal.dot(frame.binormal)) <= 1.0e-9)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedPathSweepCreatesPolygonalSweptBRep() throws {
        let document = makeCurvedPathSweepDocument(radius: 60.0)
        let evaluated = try DocumentEvaluator().evaluate(document)
        let profileVertexCount = 4
        #expect(evaluated.brep.vertices.count % profileVertexCount == 0)
        let pathFrameCount = evaluated.brep.vertices.count / profileVertexCount
        let pathSpanCount = pathFrameCount - 1

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(pathFrameCount > 2)
        #expect(evaluated.brep.vertices.count == pathFrameCount * profileVertexCount)
        #expect(evaluated.brep.edges.count == (
            pathFrameCount * profileVertexCount
                + pathSpanCount * profileVertexCount
                + pathSpanCount * profileVertexCount
        ))
        #expect(evaluated.brep.faces.count == 2 + pathSpanCount * profileVertexCount * 2)
        try evaluated.brep.validate()
        #expect(evaluated.generatedNames.values.filter(\.isBody).count == evaluated.brep.bodies.count)
        #expect(evaluated.generatedNames.values.filter(\.isFace).count == evaluated.brep.faces.count)
        #expect(evaluated.generatedNames.values.filter(\.isEdge).count == evaluated.brep.edges.count)
        #expect(evaluated.generatedNames.values.filter(\.isVertex).count == evaluated.brep.vertices.count)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.positions.count > 0)
        #expect(mesh.indices.count > 0)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedPathSweepPublishesSemanticGeneratedTopologyNames() throws {
        let document = makeCurvedPathSweepDocument(radius: 60.0)
        let sweepFeatureID = try #require(document.designGraph.order.last)
        let evaluated = try DocumentEvaluator().evaluate(document)
        let ringVertexName = PersistentName(components: [
            .feature(sweepFeatureID),
            .generated(GeneratedSubshapeRole.vertex.rawValue),
            .subshape("ringVertex:frame:0:profile:0"),
        ])
        let ringEdgeName = PersistentName(components: [
            .feature(sweepFeatureID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .subshape("ringEdge:frame:0:profile:0"),
        ])
        let railEdgeName = PersistentName(components: [
            .feature(sweepFeatureID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .subshape("railEdge:span:0:profile:0"),
        ])
        let diagonalEdgeName = PersistentName(components: [
            .feature(sweepFeatureID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .subshape("diagonalEdge:span:0:profile:0"),
        ])
        let firstSideTriangleName = PersistentName(components: [
            .feature(sweepFeatureID),
            .generated(GeneratedSubshapeRole.sideFace.rawValue),
            .subshape("sideTriangle:span:0:profile:0:triangle:0"),
        ])
        let secondSideTriangleName = PersistentName(components: [
            .feature(sweepFeatureID),
            .generated(GeneratedSubshapeRole.sideFace.rawValue),
            .subshape("sideTriangle:span:0:profile:0:triangle:1"),
        ])

        #expect(evaluated.generatedNames[ringVertexName]?.isVertex == true)
        #expect(evaluated.generatedNames[ringEdgeName]?.isEdge == true)
        #expect(evaluated.generatedNames[railEdgeName]?.isEdge == true)
        #expect(evaluated.generatedNames[diagonalEdgeName]?.isEdge == true)
        #expect(evaluated.generatedNames[firstSideTriangleName]?.isFace == true)
        #expect(evaluated.generatedNames[secondSideTriangleName]?.isFace == true)
        #expect(evaluated.generatedNames.keys.contains { name in
            name.components.contains(.feature(sweepFeatureID))
                && name.components.contains { component in
                    if case .index = component {
                        return true
                    }
                    return false
                }
                && name.components.contains { component in
                    switch component {
                    case .generated(let role):
                        return [
                            GeneratedSubshapeRole.vertex.rawValue,
                            GeneratedSubshapeRole.edge.rawValue,
                            GeneratedSubshapeRole.sideFace.rawValue,
                        ].contains(role)
                    default:
                        return false
                    }
                }
        } == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedPathSweepRejectsDegenerateInnerRadiusBeforeProducingBody() throws {
        let document = makeCurvedPathSweepDocument(radius: 10.0)

        do {
            _ = try DocumentEvaluator().evaluate(document)
            Issue.record("Expected degenerate curved sweep to be rejected.")
        } catch FeatureEvaluationError.unsupportedOperation(let message) {
            #expect(message.contains("degenerate swept topology"))
        } catch {
            Issue.record("Expected unsupportedOperation for degenerate curved sweep, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepAppliesEndScaleThroughPolygonalBRep() throws {
        let document = makeStraightPathSweepDocument(
            options: SweepOptions(endScale: .constant(.scalar(0.5)))
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let maxEndX = endVertices.map { abs($0.x) }.max() ?? 0.0
        let maxEndY = endVertices.map { abs($0.y) }.max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.faces.count == 10)
        #expect(endVertices.count == 4)
        #expect(abs(maxEndX - 0.010) <= 1.0e-12)
        #expect(abs(maxEndY - 0.005) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepAppliesTwistThroughPolygonalBRep() throws {
        let document = makeStraightPathSweepDocument(
            options: SweepOptions(twistAngle: .constant(.angle(90.0, unit: .degree)))
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let maxEndX = endVertices.map { abs($0.x) }.max() ?? 0.0
        let maxEndY = endVertices.map { abs($0.y) }.max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.faces.count == 10)
        #expect(endVertices.count == 4)
        #expect(abs(maxEndX - 0.010) <= 1.0e-12)
        #expect(abs(maxEndY - 0.020) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func sweepEvaluationRejectsUnsupportedOptionSemantics() throws {
        let unsupportedCases: [(options: SweepOptions, expectedMessageFragment: String)] = [
            (SweepOptions(alignment: .parallel), "parallel alignment"),
            (SweepOptions(cornerStyle: .round), "round sweep corners"),
            (SweepOptions(simplify: true), "simplify"),
        ]

        for unsupportedCase in unsupportedCases {
            let document = makeStraightPathSweepDocument(options: unsupportedCase.options)
            do {
                _ = try DocumentEvaluator().evaluate(document)
                Issue.record("Sweep evaluator must reject unsupported option semantics.")
            } catch FeatureEvaluationError.unsupportedOperation(let message) {
                #expect(message.contains(unsupportedCase.expectedMessageFragment))
            } catch {
                Issue.record("Expected unsupportedOperation for unsupported sweep options, got \(error).")
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepSheetCreatesOpenSheetBodyWithoutCaps() throws {
        let document = makeStraightPathSweepDocument(
            options: SweepOptions(resultKind: .sheet)
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let body = try #require(evaluated.brep.bodies.values.first)

        #expect(body.kind == .sheet)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.faces.count == 4)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.generated(GeneratedSubshapeRole.startFace.rawValue))
        } == false)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.generated(GeneratedSubshapeRole.endFace.rawValue))
        } == false)
        #expect(evaluated.meshes.values.first?.positions.isEmpty == false)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathCircleSweepSheetCreatesExactCylindricalSheetWithoutCaps() throws {
        let document = makeCircleProfileStraightPathSweepDocument(
            options: SweepOptions(resultKind: .sheet)
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let body = try #require(evaluated.brep.bodies.values.first)
        let quarterSegmentCount = Int(ceil((Double.pi / 2.0) / TessellationOptions.standard.angularTolerance))
        let expectedMeshPositionCount = (quarterSegmentCount + 1) * 2 * 4
        let expectedMeshIndexCount = quarterSegmentCount * 2 * 3 * 4

        #expect(body.kind == .sheet)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 4)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.geometry.curves.values.filter(\.isCircle).count == 8)
        #expect(evaluated.brep.geometry.surfaces.values.filter(\.isCylinder).count == 4)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.generated(GeneratedSubshapeRole.startFace.rawValue))
        } == false)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.generated(GeneratedSubshapeRole.endFace.rawValue))
        } == false)
        try evaluated.brep.validate()

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.positions.count == expectedMeshPositionCount)
        #expect(mesh.indices.count == expectedMeshIndexCount)
    }

    @Test(.timeLimit(.minutes(1)))
    func pointGuidedStraightPathSweepScalesSectionToGuide() throws {
        let document = makeGuidedStraightPathSweepDocument(
            guideEndOffset: 20.0,
            guideMethod: .point
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let maxEndX = endVertices.map { abs($0.x) }.max() ?? 0.0
        let maxEndY = endVertices.map { abs($0.y) }.max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(endVertices.count == 4)
        #expect(abs(maxEndX - 0.040) <= 1.0e-12)
        #expect(abs(maxEndY - 0.020) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func pointGuidedStraightPathSweepAcceptsMillimeterScaleContact() throws {
        let document = makeGuidedStraightPathSweepDocument(
            width: 4.0,
            height: 2.0,
            pathLength: 20.0,
            guideStartOffset: 1.0,
            guideEndOffset: 2.0,
            guideMethod: .point
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.020) <= 1.0e-12
        }
        let maxEndX = endVertices.map { abs($0.x) }.max() ?? 0.0
        let maxEndY = endVertices.map { abs($0.y) }.max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(endVertices.count == 4)
        #expect(abs(maxEndX - 0.004) <= 1.0e-12)
        #expect(abs(maxEndY - 0.002) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func chordGuidedStraightPathSweepRotatesWithoutScalingSection() throws {
        let document = makeGuidedStraightPathSweepDocument(
            guideEndOffset: 20.0,
            guideMethod: .chord
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let maxEndX = endVertices.map { abs($0.x) }.max() ?? 0.0
        let maxEndY = endVertices.map { abs($0.y) }.max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(endVertices.count == 4)
        #expect(abs(maxEndX - 0.020) <= 1.0e-12)
        #expect(abs(maxEndY - 0.010) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func multiplePointGuidedStraightPathSweepSolvesCompatibleSectionConstraints() throws {
        let document = makeMultiGuidedStraightPathSweepDocument(
            topGuideEndOffset: 20.0,
            rightGuideEndOffset: 40.0,
            guideMethod: .point
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let maxEndX = endVertices.map { abs($0.x) }.max() ?? 0.0
        let maxEndY = endVertices.map { abs($0.y) }.max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(endVertices.count == 4)
        #expect(abs(maxEndX - 0.040) <= 1.0e-12)
        #expect(abs(maxEndY - 0.020) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func multiplePointGuidedStraightPathSweepAppliesNonUniformRailDeformation() throws {
        let document = makeMultiGuidedStraightPathSweepDocument(
            topGuideEndOffset: 20.0,
            rightGuideEndOffset: 30.0,
            guideMethod: .point
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let maxEndX = endVertices.map { abs($0.x) }.max() ?? 0.0
        let maxEndY = endVertices.map { abs($0.y) }.max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(endVertices.count == 4)
        #expect(abs(maxEndX - 0.030) <= 1.0e-12)
        #expect(abs(maxEndY - 0.020) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func pointGuidedStraightPathSweepRejectsOverconstrainedRailDeformation() throws {
        let document = makeOverconstrainedRailGuidedStraightPathSweepDocument()

        do {
            _ = try DocumentEvaluator().evaluate(document)
            Issue.record("Expected overconstrained rail guide sweep to be rejected.")
        } catch FeatureEvaluationError.unsupportedOperation(let message) {
            #expect(message.contains("rail deformation") || message.contains("overconstrain"))
        } catch {
            Issue.record("Expected unsupportedOperation for overconstrained rail guide sweep, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func curveGuidedStraightPathSweepAllowsSlidingProfileContact() throws {
        let document = makeCurveGuidedStraightPathSweepDocument(
            guideEndOffset: 10.0,
            guideMethod: .curve
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let minEndX = endVertices.map(\.x).min() ?? 0.0
        let maxEndX = endVertices.map(\.x).max() ?? 0.0
        let minEndY = endVertices.map(\.y).min() ?? 0.0
        let maxEndY = endVertices.map(\.y).max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(endVertices.count == 4)
        #expect(abs(minEndX) <= 1.0e-12)
        #expect(abs(maxEndX - 0.020) <= 1.0e-12)
        #expect(abs(minEndY) <= 1.0e-12)
        #expect(abs(maxEndY - 0.020) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func circleProfileExtrudeCreatesExactCylindricalBRepAndDeterministicMesh() throws {
        let document = makeCircleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        let quarterSegmentCount = Int(ceil((Double.pi / 2.0) / TessellationOptions.standard.angularTolerance))
        let fullSegmentCount = quarterSegmentCount * 4
        let expectedMeshPositionCount = (fullSegmentCount + 1) * 2 + (quarterSegmentCount + 1) * 2 * 4
        let expectedMeshIndexCount = fullSegmentCount * 3 * 2 + quarterSegmentCount * 2 * 3 * 4

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.geometry.curves.values.filter(\.isCircle).count == 8)
        #expect(evaluated.brep.geometry.surfaces.values.filter(\.isCylinder).count == 4)
        try evaluated.brep.validate()
        try expectBalancedEdgeOrientations(in: evaluated.brep)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count == expectedMeshIndexCount)
        #expect(mesh.positions.count == expectedMeshPositionCount)

        let evaluatedAgain = try DocumentEvaluator().evaluate(document)
        #expect(evaluatedAgain.meshes.values.first?.indices == mesh.indices)
    }

    @Test(.timeLimit(.minutes(1)))
    func circleProfileExtractionReportsMultipleCirclesAsUnsupported() throws {
        var sketch = circleSketch(radius: .constant(.length(10.0, unit: .millimeter)))
        sketch.entities[SketchEntityID()] = .circle(SketchCircle(
            center: SketchPoint(
                x: .constant(.length(20.0, unit: .millimeter)),
                y: .constant(.length(0.0, unit: .millimeter))
            ),
            radius: .constant(.length(5.0, unit: .millimeter))
        ))

        do {
            _ = try SketchProfileExtractor().extractProfiles(
                from: sketch,
                sourceFeatureID: FeatureID(),
                parameters: ResolvedParameterTable()
            )
            Issue.record("Expected multiple circle profiles to be rejected.")
        } catch SketchError.unsupportedProfile(let message) {
            #expect(message.contains("Multiple circle"))
        } catch {
            Issue.record("Expected unsupportedProfile for multiple circles, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func circleProfileExtractionRejectsUnstableTinyPolygonization() {
        let document = makeCircleExtrudeDocument(
            radius: 2.0e-6,
            unit: .meter,
            documentUnits: .meters
        )

        #expect(throws: SketchError.self) {
            _ = try DocumentEvaluator().evaluate(document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func profileExtractionAllowsCollinearSplitVertices() throws {
        func point(_ x: Double, _ y: Double) -> SketchPoint {
            SketchPoint(
                x: .constant(.length(x, unit: .meter)),
                y: .constant(.length(y, unit: .meter))
            )
        }

        let bottomOuterID = SketchEntityID()
        let bottomCornerID = SketchEntityID()
        let rightCornerID = SketchEntityID()
        let rightOuterID = SketchEntityID()
        let topID = SketchEntityID()
        let leftID = SketchEntityID()
        let bottomLeft = point(0.0, 0.0)
        let bottomSplit = point(0.008, 0.0)
        let bottomRight = point(0.010, 0.0)
        let rightSplit = point(0.010, 0.002)
        let topRight = point(0.010, 0.006)
        let topLeft = point(0.0, 0.006)
        let sketch = Sketch(
            plane: .xy,
            entities: [
                bottomOuterID: .line(SketchLine(start: bottomLeft, end: bottomSplit)),
                bottomCornerID: .line(SketchLine(start: bottomSplit, end: bottomRight)),
                rightCornerID: .line(SketchLine(start: bottomRight, end: rightSplit)),
                rightOuterID: .line(SketchLine(start: rightSplit, end: topRight)),
                topID: .line(SketchLine(start: topRight, end: topLeft)),
                leftID: .line(SketchLine(start: topLeft, end: bottomLeft)),
            ]
        )

        let profiles = try SketchProfileExtractor().extractProfiles(
            from: sketch,
            sourceFeatureID: FeatureID(),
            parameters: ResolvedParameterTable()
        )
        let profile = try #require(profiles.first)

        #expect(profiles.count == 1)
        #expect(profile.vertices.count == 6)
        #expect(profile.boundarySegments.count == 6)
        #expect(profile.boundarySegments.allSatisfy { segment in
            if case .line = segment {
                return true
            }
            return false
        })
        #expect(abs(polygonArea(profile.vertices) - 0.000_060) < 1.0e-12)

        let sketchFeatureID = FeatureID()
        let extrudeFeatureID = FeatureID()
        let document = CADDocument(
            units: .meters,
            parameters: ParameterTable(parameters: [:]),
            designGraph: DesignGraph(
                nodes: [
                    sketchFeatureID: FeatureNode(
                        id: sketchFeatureID,
                        operation: .sketch(sketch),
                        outputs: [FeatureOutput(role: .profile)]
                    ),
                    extrudeFeatureID: FeatureNode(
                        id: extrudeFeatureID,
                        operation: .extrude(ExtrudeFeature(
                            profile: ProfileReference(featureID: sketchFeatureID),
                            distance: .constant(.length(0.002, unit: .meter)),
                            direction: .normal
                        )),
                        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
                        outputs: [FeatureOutput(role: .body)]
                    ),
                ],
                order: [sketchFeatureID, extrudeFeatureID],
                dependencies: [DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID)],
                revision: DocumentRevision(2)
            )
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let mesh = try #require(evaluated.meshes.values.first)

        #expect(evaluated.brep.faces.count == 8)
        #expect(mesh.indices.count > 0)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func arcProfileExtractionPreservesClosedCurveLoopArea() throws {
        let sketch = roundedCornerSketch()
        let profiles = try SketchProfileExtractor(
            tolerance: ModelingTolerance(distance: 1.0e-3, angle: 1.0e-9)
        ).extractProfiles(
            from: sketch,
            sourceFeatureID: FeatureID(),
            parameters: ResolvedParameterTable()
        )
        let profile = try #require(profiles.first)
        let area = polygonArea(profile.vertices)

        #expect(profiles.count == 1)
        #expect(profile.vertices.count > 4)
        #expect(profile.boundarySegments.count == 5)
        #expect(profile.boundarySegments.contains { segment in
            if case .circularArc(let arc) = segment {
                return abs(arc.center.x - 1.0) <= 1.0e-12
                    && abs(arc.center.y - 1.0) <= 1.0e-12
                    && abs(arc.radius - 1.0) <= 1.0e-12
                    && abs(arc.sweepAngle - Double.pi / 2.0) <= 1.0e-12
            }
            return false
        })
        #expect(abs(area - (3.0 + Double.pi / 4.0)) < 0.01)
    }

    @Test(.timeLimit(.minutes(1)))
    func closedSplineProfileExtractionTessellatesCurveLoop() throws {
        let sketch = closedBezierCircleSplineSketch(radius: 10.0, unit: .millimeter)
        let profiles = try SketchProfileExtractor(
            tolerance: ModelingTolerance(distance: 1.0e-5, angle: 1.0e-9)
        ).extractProfiles(
            from: sketch,
            sourceFeatureID: FeatureID(),
            parameters: ResolvedParameterTable()
        )
        let profile = try #require(profiles.first)
        let area = polygonArea(profile.vertices)
        let expectedArea = Double.pi * 0.01 * 0.01

        #expect(profiles.count == 1)
        #expect(profile.vertices.count > 16)
        #expect(profile.boundarySegments.count == profile.vertices.count)
        #expect(profile.boundarySegments.allSatisfy { segment in
            if case .line = segment {
                return true
            }
            return false
        })
        #expect(abs(area - expectedArea) < 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func closedSplineProfileExtrudeCreatesTessellatedBRep() throws {
        let document = makeClosedSplineExtrudeDocument(
            radius: 10.0,
            depth: 5.0,
            unit: .millimeter,
            documentUnits: .millimeters
        )
        let evaluated = try DocumentEvaluator().evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count > 6)
        #expect(evaluated.brep.geometry.surfaces.values.allSatisfy { surface in
            if case .plane = surface {
                return true
            }
            return false
        })
        try evaluated.brep.validate()
        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.positions.count > 24)
        #expect(mesh.indices.count > 36)
    }

    @Test(.timeLimit(.minutes(1)))
    func obliqueVectorExtrudeKeepsCapFacesParallelToSketchPlane() throws {
        let document = makeRectangleExtrudeDocument(
            direction: .vector(Vector3D(x: 0.25, y: 0.5, z: 1.0))
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let startFaceID = try #require(generatedFaceID(
            .startFace,
            featureID: extrudeFeatureID,
            in: evaluated
        ))
        let endFaceID = try #require(generatedFaceID(
            .endFace,
            featureID: extrudeFeatureID,
            in: evaluated
        ))
        let startNormal = try planeNormal(for: startFaceID, in: evaluated.brep)
        let endNormal = try planeNormal(for: endFaceID, in: evaluated.brep)

        try evaluated.brep.validate()
        #expect(startNormal.z < -0.9)
        #expect(endNormal.z > 0.9)
    }

    @Test(.timeLimit(.minutes(1)))
    func vectorExtrudeRejectsDirectionParallelToSketchPlane() {
        let document = makeRectangleExtrudeDocument(
            direction: .vector(Vector3D(x: 1.0, y: 1.0, z: 0.0))
        )

        #expect(throws: FeatureEvaluationError.self) {
            _ = try DocumentEvaluator().evaluate(document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func clockwiseProfileExtrudeNormalizesOutwardNormalsAndBalancedEdgeUses() throws {
        let document = makeRectangleExtrudeDocument(clockwiseProfile: true)
        let evaluated = try DocumentEvaluator().evaluate(document)

        try evaluated.brep.validate()
        try expectBalancedEdgeOrientations(in: evaluated.brep)
        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.normals[0].z < -0.9)
        let firstNormal = try firstTriangleNormal(in: mesh)
        #expect(firstNormal.dot(mesh.normals[0]) > 0.9)
    }

    @Test(.timeLimit(.minutes(1)))
    func meshTessellatorAppliesShellAndFaceOrientationToNormals() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let bodyID = try #require(evaluated.meshes.keys.first)
        let originalMesh = try #require(evaluated.meshes[bodyID])
        let originalNormal = try #require(originalMesh.normals.first)

        var shellReversedModel = evaluated.brep
        let shellID = try #require(shellReversedModel.shells.keys.first)
        shellReversedModel.shells[shellID]?.orientation = .reversed
        let shellReversedMesh = try #require(MeshTessellator().tessellate(model: shellReversedModel)[bodyID])
        let shellReversedNormal = try #require(shellReversedMesh.normals.first)
        let shellReversedTriangleNormal = try firstTriangleNormal(in: shellReversedMesh)

        var faceReversedModel = evaluated.brep
        let faceID = try #require(faceReversedModel.shells[shellID]?.faceIDs.first)
        faceReversedModel.faces[faceID]?.orientation = .reversed
        let faceReversedMesh = try #require(MeshTessellator().tessellate(model: faceReversedModel)[bodyID])
        let faceReversedNormal = try #require(faceReversedMesh.normals.first)
        let faceReversedTriangleNormal = try firstTriangleNormal(in: faceReversedMesh)

        #expect(shellReversedNormal.dot(originalNormal) < -0.9)
        #expect(shellReversedTriangleNormal.dot(shellReversedNormal) > 0.9)
        #expect(faceReversedNormal.dot(originalNormal) < -0.9)
        #expect(faceReversedTriangleNormal.dot(faceReversedNormal) > 0.9)
    }

    @Test(.timeLimit(.minutes(1)))
    func concaveProfileExtrudesAndTessellatesPlanarCaps() throws {
        let document = makeConcaveExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        let mesh = try #require(evaluated.meshes.values.first)
        let firstNormal = try #require(mesh.normals.first)
        let firstTriangleNormal = try firstTriangleNormal(in: mesh)

        try evaluated.validate()
        try expectBalancedEdgeOrientations(in: evaluated.brep)
        #expect(evaluated.brep.vertices.count == 10)
        #expect(evaluated.brep.edges.count == 15)
        #expect(evaluated.brep.faces.count == 7)
        #expect(mesh.indices.count == 48)
        #expect(mesh.indices.count % 3 == 0)
        #expect(firstTriangleNormal.dot(firstNormal) > 0.9)
    }

    @Test(.timeLimit(.minutes(1)))
    func profileExtractionRejectsUnsupportedEntitiesInsteadOfIgnoringThem() throws {
        var document = makeRectangleExtrudeDocument()
        let sketchFeatureID = try #require(document.designGraph.order.first)
        var sketchFeature = try #require(document.designGraph.nodes[sketchFeatureID])
        guard case var .sketch(sketch) = sketchFeature.operation else {
            Issue.record("Expected first feature to be a sketch.")
            return
        }
        let circleID = SketchEntityID()
        sketch.entities[circleID] = .circle(SketchCircle(
            center: SketchPoint(
                x: .constant(.length(0.0, unit: .millimeter)),
                y: .constant(.length(0.0, unit: .millimeter))
            ),
            radius: .constant(.length(1.0, unit: .millimeter))
        ))
        sketchFeature.operation = .sketch(sketch)
        document.designGraph.nodes[sketchFeatureID] = sketchFeature

        #expect(throws: SketchError.self) {
            _ = try DocumentEvaluator().evaluate(document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsMissingCurveReference() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edge = try #require(model.edges.values.first)
        model.geometry.curves.removeValue(forKey: edge.curveID)

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedCachesValidateFreshnessAgainstSourceDocument() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)

        try evaluated.caches.validateFreshness(for: document)
        try evaluated.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsEmptyCachesForBodyProducingDocument() throws {
        let document = makeRectangleExtrudeDocument()

        #expect(throws: CacheValidationError.self) {
            try DocumentCaches().validateFreshness(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentValidationRejectsTopLevelMeshesThatDoNotMatchBRep() throws {
        var evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let bodyID = try #require(evaluated.meshes.keys.first)
        evaluated.meshes[bodyID]?.positions[0].x += 0.25

        #expect(throws: CacheValidationError.self) {
            try evaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentValidationRejectsTopLevelBRepThatDoesNotMatchCache() throws {
        var evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let bodyID = try #require(evaluated.brep.bodies.keys.first)
        evaluated.brep.bodies[bodyID]?.name = "stale-body"

        #expect(throws: CacheValidationError.self) {
            try evaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentValidationRejectsPersistentNameCacheMismatch() throws {
        var evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        evaluated.caches.brep?.persistentNames = PersistentNameMap()

        #expect(throws: CacheValidationError.self) {
            try evaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsBRepCacheContentNotEqualToSourceEvaluationEvenWhenMeshesMatch() throws {
        let document = makeRectangleExtrudeDocument()
        var staleCaches = try DocumentEvaluator().evaluate(document).caches
        let bodyID = try #require(staleCaches.brep?.model.bodies.keys.first)
        staleCaches.brep?.model.bodies[bodyID]?.name = "stale-body"

        #expect(throws: CacheValidationError.self) {
            try staleCaches.validateFreshness(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentValidationRejectsInvalidGeneratedNames() throws {
        var invalidNameEvaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let bodyID = try #require(invalidNameEvaluated.brep.bodies.keys.first)
        invalidNameEvaluated.generatedNames[PersistentName(components: [])] = .body(bodyID)
        invalidNameEvaluated.caches.brep?.persistentNames = PersistentNameMap(invalidNameEvaluated.generatedNames)

        var danglingReferenceEvaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let extrudeFeatureID = try #require(danglingReferenceEvaluated.document.designGraph.order.last)
        let danglingName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.body.rawValue)
        ])
        danglingReferenceEvaluated.generatedNames[danglingName] = .body(BodyID())
        danglingReferenceEvaluated.caches.brep?.persistentNames = PersistentNameMap(
            danglingReferenceEvaluated.generatedNames
        )

        #expect(throws: FeatureEvaluationError.self) {
            try invalidNameEvaluated.validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try danglingReferenceEvaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentValidationRequiresGeneratedNamesToCoverTopology() throws {
        var evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let edgeName = try #require(evaluated.generatedNames.first { _, reference in
            reference.isEdge
        }?.key)
        evaluated.generatedNames.removeValue(forKey: edgeName)
        evaluated.caches.brep?.persistentNames = PersistentNameMap(evaluated.generatedNames)

        #expect(throws: FeatureEvaluationError.self) {
            try evaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluationReportRecordsFailedAndBlockedFeatures() throws {
        let sketchID = FeatureID()
        let extrudeID = FeatureID()
        let lineID = SketchEntityID()
        let openSketch = Sketch(
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
        )
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(openSketch),
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
                dependencies: [DependencyEdge(source: sketchID, target: extrudeID)]
            )
        )

        let report = DocumentEvaluator().evaluateReport(document)

        #expect(report.evaluatedDocument == nil)
        guard case let .failed(failure) = report.featureStates[sketchID] else {
            Issue.record("Sketch feature should be marked as failed.")
            return
        }
        #expect(failure.featureID == sketchID)
        #expect(failure.invalidatedFeatureIDs == [extrudeID])
        #expect(report.featureStates[extrudeID] == .blocked(upstreamFeatureID: sketchID))
        #expect(report.failure != nil)
        try report.failure?.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluationReportRecordsDocumentLevelFailureAfterFeatureEvaluation() throws {
        let report = DocumentEvaluator(tessellator: EmptyTessellator()).evaluateReport(makeRectangleExtrudeDocument())

        #expect(report.evaluatedDocument == nil)
        #expect(report.isComplete == false)
        #expect(report.featureStates.values.allSatisfy { $0 == .evaluated })
        #expect(report.failure != nil)
        try report.failure?.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluationReportReturnsFailureForDuplicateFeatureOrder() throws {
        let featureID = FeatureID()
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    featureID: FeatureNode(
                        id: featureID,
                        operation: .sketch(Sketch(plane: .xy)),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [featureID, featureID]
            )
        )

        let report = DocumentEvaluator().evaluateReport(document)

        #expect(report.evaluatedDocument == nil)
        #expect(report.isComplete == false)
        #expect(report.featureStates[featureID] == .unevaluated)
        #expect(report.failure != nil)
        try report.failure?.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsStaleBRepAndMeshMetadata() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)

        var staleBRepCaches = evaluated.caches
        staleBRepCaches.brep?.parameterRevision = document.parameters.revision.advanced()

        var staleMeshCaches = evaluated.caches
        let bodyID = try #require(staleMeshCaches.meshes.keys.first)
        staleMeshCaches.meshes[bodyID]?.tessellationOptions = TessellationOptions(
            linearTolerance: 1.0e-3,
            angularTolerance: 1.0e-3
        )

        #expect(throws: CacheValidationError.self) {
            try staleBRepCaches.validateFreshness(for: document)
        }
        #expect(throws: CacheValidationError.self) {
            try staleMeshCaches.validateFreshness(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsInvalidSourceDocumentAndKernelVersion() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        var invalidDocument = document
        invalidDocument.schemaVersion = SchemaVersion(major: 1, minor: 0, patch: -1)
        let invalidKernelVersion = SchemaVersion(major: 1, minor: 0, patch: -1)
        var invalidKernelCaches = evaluated.caches
        invalidKernelCaches.brep?.kernelVersion = invalidKernelVersion
        for bodyID in invalidKernelCaches.meshes.keys {
            invalidKernelCaches.meshes[bodyID]?.kernelVersion = invalidKernelVersion
        }

        #expect(throws: SchemaError.self) {
            try evaluated.caches.validateFreshness(for: invalidDocument)
        }
        #expect(throws: SchemaError.self) {
            try invalidKernelCaches.validateFreshness(
                for: document,
                kernelVersion: invalidKernelVersion
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsMeshContentThatDoesNotMatchBRep() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        var staleCaches = evaluated.caches
        let bodyID = try #require(staleCaches.meshes.keys.first)
        var staleMeshCache = try #require(staleCaches.meshes[bodyID])
        for index in staleMeshCache.mesh.positions.indices {
            staleMeshCache.mesh.positions[index].x += 0.25
        }
        staleCaches.meshes[bodyID] = staleMeshCache

        #expect(throws: CacheValidationError.self) {
            try staleCaches.validateFreshness(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsBRepContentFromDifferentSourceEvenWhenMetadataMatches() throws {
        let document = makeRectangleExtrudeDocument(width: 40.0)
        let otherDocument = makeRectangleExtrudeDocument(width: 80.0)
        var staleCaches = try DocumentEvaluator().evaluate(otherDocument).caches
        let sourceFingerprint = try document.sourceFingerprint()
        staleCaches.brep?.designRevision = document.designGraph.revision
        staleCaches.brep?.parameterRevision = document.parameters.revision
        staleCaches.brep?.sourceFingerprint = sourceFingerprint
        for bodyID in staleCaches.meshes.keys {
            staleCaches.meshes[bodyID]?.designRevision = document.designGraph.revision
            staleCaches.meshes[bodyID]?.parameterRevision = document.parameters.revision
            staleCaches.meshes[bodyID]?.sourceFingerprint = sourceFingerprint
        }

        #expect(throws: CacheValidationError.self) {
            try staleCaches.validateFreshness(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsSourceGraphMutationWithoutRevisionAdvance() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        var mutatedDocument = document
        let extrudeFeatureID = try #require(mutatedDocument.designGraph.order.last)
        mutatedDocument.designGraph.nodes[extrudeFeatureID]?.isSuppressed = true
        try mutatedDocument.validate()

        #expect(throws: CacheValidationError.self) {
            try evaluated.caches.validateFreshness(for: mutatedDocument)
        }

        var staleEvaluated = evaluated
        staleEvaluated.document = mutatedDocument
        #expect(throws: CacheValidationError.self) {
            try staleEvaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsParameterMutationWithoutRevisionAdvance() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        var mutatedDocument = document
        let widthID = try #require(mutatedDocument.parameters.parameters.values.first { $0.name == "width" }?.id)
        mutatedDocument.parameters.parameters[widthID]?.expression = .constant(.length(80.0, unit: .millimeter))
        try mutatedDocument.validate()

        #expect(throws: CacheValidationError.self) {
            try evaluated.caches.validateFreshness(for: mutatedDocument)
        }

        var staleEvaluated = evaluated
        staleEvaluated.document = mutatedDocument
        #expect(throws: CacheValidationError.self) {
            try staleEvaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsMeshCacheTableKeyMismatch() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        var staleCaches = evaluated.caches
        let bodyID = try #require(staleCaches.meshes.keys.first)
        staleCaches.meshes[bodyID]?.bodyID = BodyID()

        #expect(throws: CacheValidationError.self) {
            try staleCaches.validateFreshness(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sourceFingerprintIsIndependentOfDictionaryInsertionOrder() throws {
        var document = makeDocumentWithManyIndependentParameters(reverseInsertionOrder: false)
        var reorderedDocument = makeDocumentWithManyIndependentParameters(reverseInsertionOrder: true)
        document.id = fixedDocumentID()
        reorderedDocument.id = document.id

        #expect(try document.sourceFingerprint() == reorderedDocument.sourceFingerprint())
    }

    @Test(.timeLimit(.minutes(1)))
    func documentEvaluatorRejectsInvalidModelingTolerance() {
        let evaluator = DocumentEvaluator(tolerance: ModelingTolerance(distance: .nan, angle: 1.0e-9))

        #expect(throws: GeometryError.self) {
            _ = try evaluator.evaluate(makeRectangleExtrudeDocument())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentEvaluatorRejectsEmptyEvaluationResults() {
        let emptyDocument = CADDocument(units: .meters)
        let suppressedSketchID = FeatureID()
        let suppressedDocument = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    suppressedSketchID: FeatureNode(
                        id: suppressedSketchID,
                        operation: .sketch(Sketch(plane: .xy)),
                        outputs: [FeatureOutput(role: .profile)],
                        isSuppressed: true
                    )
                ],
                order: [suppressedSketchID]
            )
        )

        #expect(throws: FeatureEvaluationError.self) {
            _ = try DocumentEvaluator().evaluate(emptyDocument)
        }
        #expect(throws: FeatureEvaluationError.self) {
            _ = try DocumentEvaluator().evaluate(suppressedDocument)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentEvaluatorRejectsIncompleteGeneratedPersistentNames() {
        let evaluator = DocumentEvaluator(featureEvaluator: IncompleteGeneratedNameFeatureEvaluator())

        #expect(throws: FeatureEvaluationError.self) {
            _ = try evaluator.evaluate(makeRectangleExtrudeDocument())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentEvaluatorPropagatesCustomToleranceToDefaultKernelStages() throws {
        let tolerance = ModelingTolerance(distance: 1.0e-9, angle: 1.0e-9)
        let document = makeRectangleExtrudeDocument(
            width: 1.0e-7,
            height: 1.0e-7,
            depth: 1.0e-7,
            unit: .meter,
            documentUnits: .meters
        )

        let evaluated = try DocumentEvaluator(tolerance: tolerance).evaluate(document)
        let mesh = try #require(evaluated.meshes.values.first)

        try evaluated.brep.validate(tolerance: tolerance)
        try mesh.validate(tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func documentEvaluatorPropagatesCustomToleranceToSourceValidation() throws {
        let tolerance = ModelingTolerance(distance: 1.0e-3, angle: 1.0e-3)
        let document = makeRectangleExtrudeDocument(
            width: 4.0,
            height: 2.0,
            depth: 1.0,
            unit: .meter,
            documentUnits: .meters,
            sketchPlane: .plane(Plane3D(
                origin: Point3D(x: 0.0, y: 0.0, z: 0.0),
                normal: Vector3D(x: 0.0, y: 0.0, z: 1.0001)
            ))
        )

        #expect(throws: GeometryError.self) {
            try document.validate()
        }
        let evaluated = try DocumentEvaluator(tolerance: tolerance).evaluate(document)

        try evaluated.validate()
        try evaluated.caches.validateFreshness(for: document, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func meshTessellatorRejectsNonFiniteTessellationOptions() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let options = TessellationOptions(linearTolerance: .infinity, angularTolerance: 1.0e-3)

        #expect(throws: TessellationError.self) {
            _ = try MeshTessellator().tessellate(model: evaluated.brep, options: options)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsEdgeTrimEndpointMismatch() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edgeID = try #require(model.edges.keys.first)
        model.edges[edgeID]?.trim = CurveTrim(startParameter: 0.0, endParameter: 0.5)

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsDegenerateEdgeGeometry() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edge = try #require(model.edges.values.first)
        let startPoint = try #require(model.vertices[edge.startVertexID]?.point)
        model.vertices[edge.endVertexID]?.point = startPoint

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsFullPeriodCircleTrimAsSingleEdge() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edge = try #require(model.edges.values.first)
        let curveID = edge.curveID
        let circlePoint = Point3D(x: 1.0, y: 0.0, z: 0.0)
        model.geometry.curves[curveID] = .circle(Circle3D(center: .origin, normal: .unitZ, radius: 1.0))
        model.vertices[edge.startVertexID]?.point = circlePoint
        model.vertices[edge.endVertexID]?.point = circlePoint
        model.edges[edge.id]?.trim = CurveTrim(startParameter: 0.0, endParameter: Double.pi * 2.0)

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsCircleTrimSpanningMoreThanOnePeriod() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edge = try #require(model.edges.values.first)
        let curveID = edge.curveID
        let endParameter = Double.pi * 4.0 + 0.25
        model.geometry.curves[curveID] = .circle(Circle3D(center: .origin, normal: .unitZ, radius: 1.0))
        model.vertices[edge.startVertexID]?.point = Point3D(x: 1.0, y: 0.0, z: 0.0)
        model.vertices[edge.endVertexID]?.point = Point3D(x: cos(0.25), y: sin(0.25), z: 0.0)
        model.edges[edge.id]?.trim = CurveTrim(startParameter: 0.0, endParameter: endParameter)

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplineQuadMeshCreatesBSplineSheetTopology() throws {
        let document = makePolySplineQuadDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        let body = try #require(evaluated.brep.bodies.values.first)
        #expect(body.kind == .sheet)
        #expect(evaluated.brep.faces.count == 1)
        #expect(evaluated.brep.edges.count == 4)
        #expect(evaluated.brep.vertices.count == 4)
        let face = try #require(evaluated.brep.faces.values.first)
        let surface = try #require(evaluated.brep.geometry.surfaces[face.surfaceID])
        guard case let .bSpline(bSpline) = surface else {
            Issue.record("Expected PolySpline to create a B-spline surface.")
            return
        }
        #expect(bSpline.uDegree == 3)
        #expect(bSpline.vDegree == 3)
        #expect(bSpline.uControlPointCount == 4)
        #expect(bSpline.vControlPointCount == 4)
        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.positions.count > 4)
        #expect(mesh.indices.count > 6)
        let generatedReferences = Array(evaluated.generatedNames.values)
        #expect(generatedReferences.contains { $0.isBody })
        #expect(generatedReferences.contains { $0.isFace })
        #expect(generatedReferences.filter { $0.isEdge }.count == 4)
        #expect(generatedReferences.filter { $0.isVertex }.count == 4)
        let generatedNameStrings = evaluated.generatedNames.keys.map(persistentNameString)
        #expect(generatedNameStrings.contains { $0.contains("generated:polySpline/subshape:patch:0:face") })
        #expect(generatedNameStrings.contains { $0.contains("subshape:patch:0:edge:uMax") })
        #expect(generatedNameStrings.contains { $0.contains("subshape:patch:0:vertex:uMax:vMax") })
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplinePlanarPatchNetworkCreatesMultiPatchBSplineSheetTopology() throws {
        let document = makePolySplinePatchNetworkDocument(
            centerZ: 0.0,
            options: PolySplineOptions(mergePatches: false)
        )
        let evaluated = try DocumentEvaluator().evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        let body = try #require(evaluated.brep.bodies.values.first)
        #expect(body.kind == .sheet)
        #expect(evaluated.brep.faces.count == 2)
        #expect(evaluated.brep.edges.count == 7)
        #expect(evaluated.brep.vertices.count == 6)
        #expect(evaluated.brep.geometry.surfaces.count == 2)
        #expect(evaluated.meshes.values.first?.positions.count ?? 0 > 18)
        let generatedReferences = Array(evaluated.generatedNames.values)
        #expect(generatedReferences.contains { $0.isBody })
        #expect(generatedReferences.filter { $0.isFace }.count == 2)
        #expect(generatedReferences.filter { $0.isEdge }.count == 8)
        #expect(generatedReferences.filter { $0.isVertex }.count == 8)
        let generatedNameStrings = evaluated.generatedNames.keys.map(persistentNameString)
        #expect(generatedNameStrings.contains { $0.contains("generated:polySpline/subshape:patch:0:face") })
        #expect(generatedNameStrings.contains { $0.contains("generated:polySpline/subshape:patch:2:face") })
        #expect(generatedNameStrings.contains { $0.contains("subshape:patch:0:edge:uMax") })
        #expect(generatedNameStrings.contains { $0.contains("subshape:patch:2:edge:uMin") })
        let patch0RightEdge = try #require(evaluated.generatedNames.first { name, _ in
            persistentNameString(name).contains("subshape:patch:0:edge:uMax")
        }?.value)
        let patch2LeftEdge = try #require(evaluated.generatedNames.first { name, _ in
            persistentNameString(name).contains("subshape:patch:2:edge:uMin")
        }?.value)
        #expect(patch0RightEdge == patch2LeftEdge)
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplineQuadMeshPreservesMeshBoundaryWinding() throws {
        let forward = try DocumentEvaluator().evaluate(makePolySplineQuadDocument())
        let reversed = try DocumentEvaluator().evaluate(makePolySplineQuadDocument(indices: [0, 2, 1, 0, 3, 2]))
        let forwardSurface = try polySplineSurface(from: forward)
        let reversedSurface = try polySplineSurface(from: reversed)

        let forwardNormal = try forwardSurface.normal(u: 0.5, v: 0.5)
        let reversedNormal = try reversedSurface.normal(u: 0.5, v: 0.5)

        #expect(forwardNormal.z > 0.0)
        #expect(reversedNormal.z < 0.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplineMeshAnalysisReportsSingleQuadSupport() throws {
        let analysis = PolySplineMeshAnalyzer().analyze(mesh: makePolySplineQuadMesh())

        #expect(analysis.result.isSupported)
        #expect(analysis.result.candidateKind == .singleQuad)
        #expect(analysis.result.vertexCount == 4)
        #expect(analysis.result.usedVertexCount == 4)
        #expect(analysis.result.triangleCount == 2)
        #expect(analysis.result.boundaryEdgeCount == 4)
        #expect(analysis.result.internalEdgeCount == 1)
        #expect(analysis.result.connectedComponentCount == 1)
        #expect(analysis.result.supportedPatchCount == 1)
        #expect(analysis.result.candidatePatchCount == 1)
        #expect(analysis.orderedBoundaryPoints?.count == 4)
        #expect(analysis.result.diagnostics.contains { $0.code == .singleQuadPatchSupported })
        let patchGraph = try #require(analysis.result.patchGraph)
        #expect(patchGraph.triangleCount == 2)
        #expect(patchGraph.candidates.count == 1)
        #expect(patchGraph.selectedAdjacencies.isEmpty)
        #expect(patchGraph.unpairedTriangleIndices.isEmpty)
        #expect(patchGraph.ambiguousTriangleIndices.isEmpty)
        let partition = try #require(patchGraph.partition)
        #expect(partition.isComplete)
        #expect(partition.selectedCandidateIDs == [0])
        #expect(partition.rejectedCandidateIDs.isEmpty)
        #expect(partition.coveredTriangleIndices == [0, 1])
        #expect(partition.uncoveredTriangleIndices.isEmpty)
        let candidate = try #require(patchGraph.candidates.first)
        #expect(candidate.id == 0)
        #expect(candidate.triangleIndices == [0, 1])
        #expect(candidate.boundaryVertexIndices.count == 4)
        #expect(candidate.splitEdge == PolySplinePatchGraph.VertexPair(firstVertexIndex: 0, secondVertexIndex: 2))
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplineMeshAnalysisRejectsRoundedCornerOptionWithoutLosingPatchCandidate() throws {
        let analysis = PolySplineMeshAnalyzer().analyze(
            mesh: makePolySplineQuadMesh(),
            options: PolySplineOptions(roundedCorners: true)
        )

        #expect(!analysis.result.isSupported)
        #expect(analysis.result.candidateKind == .singleQuad)
        #expect(analysis.result.supportedPatchCount == 1)
        #expect(analysis.result.candidatePatchCount == 1)
        #expect(analysis.result.patchGraph?.candidates.count == 1)
        #expect(analysis.result.patchGraph?.partition?.selectedCandidateIDs == [0])
        #expect(analysis.orderedBoundaryPoints?.count == 4)
        #expect(analysis.result.errors.contains { $0.code == .unsupportedRoundedCorners })
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplineMeshAnalysisReportsPatchGraphBeforeMultiPatchEvaluation() throws {
        let analysis = PolySplineMeshAnalyzer().analyze(mesh: makePolySplinePatchNetworkMesh())

        #expect(!analysis.result.isSupported)
        #expect(analysis.result.candidateKind == .quadPatchGraph)
        #expect(analysis.result.vertexCount == 6)
        #expect(analysis.result.usedVertexCount == 6)
        #expect(analysis.result.triangleCount == 4)
        #expect(analysis.result.boundaryEdgeCount == 6)
        #expect(analysis.result.internalEdgeCount == 3)
        #expect(analysis.result.connectedComponentCount == 1)
        #expect(analysis.result.supportedPatchCount == 0)
        #expect(analysis.result.candidatePatchCount == 3)
        #expect(analysis.result.diagnostics.contains { $0.code == .patchGraphIdentified })
        #expect(analysis.result.diagnostics.contains { $0.code == .patchGraphPartitioned })
        #expect(analysis.result.diagnostics.contains { $0.code == .patchAdjacencyIdentified })
        #expect(analysis.result.diagnostics.contains { $0.code == .patchTangentPlaneDiscontinuity })
        #expect(analysis.result.diagnostics.contains { $0.code == .patchCurvatureContinuityUnresolved })
        #expect(analysis.result.errors.contains { $0.code == .unsupportedPatchNetwork })
        #expect(analysis.orderedBoundaryPoints == nil)
        let patchGraph = try #require(analysis.result.patchGraph)
        #expect(patchGraph.triangleCount == 4)
        #expect(patchGraph.candidates.count == 3)
        let adjacency = try #require(patchGraph.selectedAdjacencies.first)
        #expect(patchGraph.selectedAdjacencies.count == 1)
        #expect(adjacency.firstCandidateID == 0)
        #expect(adjacency.secondCandidateID == 2)
        #expect(adjacency.sharedEdge == PolySplinePatchGraph.VertexPair(firstVertexIndex: 1, secondVertexIndex: 4))
        #expect(adjacency.sharedVertexIndices == [1, 4])
        #expect(adjacency.continuityLevel == .positional)
        #expect(adjacency.normalAngleRadians > ModelingTolerance.standard.angle)
        #expect(adjacency.requiresCurvatureContinuitySolve)
        #expect(patchGraph.unpairedTriangleIndices.isEmpty)
        #expect(patchGraph.ambiguousTriangleIndices == [0, 3])
        let partition = try #require(patchGraph.partition)
        #expect(partition.isComplete)
        #expect(partition.selectedCandidateIDs == [0, 2])
        #expect(partition.rejectedCandidateIDs == [1])
        #expect(partition.coveredTriangleIndices == [0, 1, 2, 3])
        #expect(partition.uncoveredTriangleIndices.isEmpty)
        #expect(patchGraph.relationships.contains {
            $0.kind == .competesForTriangle && $0.triangleIndices == [0]
        })
        #expect(patchGraph.relationships.contains {
            $0.kind == .competesForTriangle && $0.triangleIndices == [3]
        })
        #expect(patchGraph.relationships.contains {
            $0.kind == .sharesBoundaryEdge && $0.vertexIndices == [1, 4]
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplineMeshAnalysisClassifiesCoplanarSelectedPatchAdjacencyAsTangentPlane() throws {
        let analysis = PolySplineMeshAnalyzer().analyze(
            mesh: makePolySplinePatchNetworkMesh(centerZ: 0.0),
            options: PolySplineOptions(mergePatches: false)
        )

        #expect(analysis.result.isSupported)
        #expect(analysis.result.supportedPatchCount == 2)
        #expect(analysis.supportedPatches.map(\.candidateID) == [0, 2])
        #expect(analysis.result.diagnostics.contains { $0.code == .patchAdjacencyIdentified })
        #expect(!analysis.result.diagnostics.contains { $0.code == .patchTangentPlaneDiscontinuity })
        #expect(!analysis.result.diagnostics.contains { $0.code == .patchCurvatureContinuityUnresolved })
        #expect(analysis.result.diagnostics.contains { $0.code == .planarPatchNetworkSupported })
        #expect(!analysis.result.errors.contains { $0.code == .unsupportedPatchNetwork })
        let adjacency = try #require(analysis.result.patchGraph?.selectedAdjacencies.first)
        #expect(analysis.result.patchGraph?.selectedAdjacencies.count == 1)
        #expect(adjacency.continuityLevel == .tangentPlane)
        #expect(adjacency.normalAngleRadians <= ModelingTolerance.standard.angle)
        #expect(!adjacency.requiresCurvatureContinuitySolve)
    }
}

private extension TopologyReference {
    var isBody: Bool {
        if case .body = self {
            return true
        }
        return false
    }

    var isFace: Bool {
        if case .face = self {
            return true
        }
        return false
    }

    var isEdge: Bool {
        if case .edge = self {
            return true
        }
        return false
    }

    var isVertex: Bool {
        if case .vertex = self {
            return true
        }
        return false
    }
}

private func persistentNameString(_ name: PersistentName) -> String {
    name.components.map { component in
        switch component {
        case .feature(let featureID):
            return "feature:\(featureID.description)"
        case .generated(let value):
            return "generated:\(value)"
        case .subshape(let value):
            return "subshape:\(value)"
        case .index(let index):
            return "index:\(index)"
        }
    }
    .joined(separator: "/")
}

private struct IncompleteGeneratedNameFeatureEvaluator: FeatureEvaluating {
    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        var result = try PlanarExtrudeFeatureEvaluator().evaluate(feature: feature, context: context)
        if let name = result.generatedNames.first?.key {
            result.generatedNames.removeValue(forKey: name)
        }
        return result
    }
}

private struct EmptyTessellator: Tessellating {
    func tessellate(model: BRepModel, options: TessellationOptions) throws -> [BodyID: Mesh] {
        [:]
    }
}

private func makePolySplineQuadDocument(indices: [UInt32] = [0, 1, 2, 0, 2, 3]) -> CADDocument {
    let featureID = FeatureID()
    let feature = FeatureNode(
        id: featureID,
        name: "Quad PolySpline",
        operation: .polySpline(PolySplineFeature(sourceMesh: makePolySplineQuadMesh(indices: indices))),
        outputs: [FeatureOutput(role: .sheet)]
    )
    return CADDocument(
        units: .meters,
        designGraph: DesignGraph(
            nodes: [featureID: feature],
            order: [featureID],
            revision: DocumentRevision(1)
        )
    )
}

private func makePolySplinePatchNetworkDocument(
    centerZ: Double = 0.1,
    options: PolySplineOptions = PolySplineOptions()
) -> CADDocument {
    let featureID = FeatureID()
    let feature = FeatureNode(
        id: featureID,
        name: "Patch Network PolySpline",
        operation: .polySpline(
            PolySplineFeature(
                sourceMesh: makePolySplinePatchNetworkMesh(centerZ: centerZ),
                options: options
            )
        ),
        outputs: [FeatureOutput(role: .sheet)]
    )
    return CADDocument(
        units: .meters,
        designGraph: DesignGraph(
            nodes: [featureID: feature],
            order: [featureID],
            revision: DocumentRevision(1)
        )
    )
}

private func makePolySplineQuadMesh(indices: [UInt32] = [0, 1, 2, 0, 2, 3]) -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 2.0, y: 0.0, z: 0.1),
            Point3D(x: 2.0, y: 1.5, z: 0.4),
            Point3D(x: 0.0, y: 1.5, z: 0.0),
        ],
        indices: indices
    )
}

private func makePolySplinePatchNetworkMesh(centerZ: Double = 0.1) -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 0.0, z: 0.0),
            Point3D(x: 2.0, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 1.0, z: 0.0),
            Point3D(x: 1.0, y: 1.0, z: centerZ),
            Point3D(x: 2.0, y: 1.0, z: 0.0),
        ],
        indices: [
            0, 1, 4,
            0, 4, 3,
            1, 2, 5,
            1, 5, 4,
        ]
    )
}

private func polySplineSurface(from document: EvaluatedDocument) throws -> BSplineSurface3D {
    let face = try #require(document.brep.faces.values.first)
    let surface = try #require(document.brep.geometry.surfaces[face.surfaceID])
    guard case let .bSpline(bSpline) = surface else {
        Issue.record("Expected a B-spline surface.")
        throw FeatureEvaluationError.unsupportedOperation("Expected a B-spline surface.")
    }
    return bSpline
}

private func makeRectangleExtrudeDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    depth: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters,
    clockwiseProfile: Bool = false,
    sketchPlane: SketchPlane = .xy,
    direction: ExtrudeDirection = .normal
) -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let depthID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        ),
        depthID: Parameter(
            id: depthID,
            name: "depth",
            expression: .constant(.length(depth, unit: unit)),
            kind: .length
        )
    ])

    let sketch = rectangleSketch(
        widthID: widthID,
        heightID: heightID,
        plane: sketchPlane,
        clockwise: clockwiseProfile
    )
    let sketchFeatureID = FeatureID()
    let extrudeFeatureID = FeatureID()
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(sketch),
        outputs: [FeatureOutput(role: .profile)]
    )
    let extrudeFeature = FeatureNode(
        id: extrudeFeatureID,
        operation: .extrude(
            ExtrudeFeature(
                profile: ProfileReference(featureID: sketchFeatureID),
                distance: .reference(depthID),
                direction: direction
            )
        ),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            sketchFeatureID: sketchFeature,
            extrudeFeatureID: extrudeFeature
        ],
        order: [sketchFeatureID, extrudeFeatureID],
        dependencies: [DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID)],
        revision: DocumentRevision(2)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeParallelogramExtrudeDocument(
    depth: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters
) -> CADDocument {
    let depthID = ParameterID()
    let parameters = ParameterTable(parameters: [
        depthID: Parameter(
            id: depthID,
            name: "depth",
            expression: .constant(.length(depth, unit: unit)),
            kind: .length
        )
    ])
    let sketchFeatureID = FeatureID()
    let extrudeFeatureID = FeatureID()
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(parallelogramSketch(unit: unit)),
        outputs: [FeatureOutput(role: .profile)]
    )
    let extrudeFeature = FeatureNode(
        id: extrudeFeatureID,
        operation: .extrude(
            ExtrudeFeature(
                profile: ProfileReference(featureID: sketchFeatureID),
                distance: .reference(depthID),
                direction: .normal
            )
        ),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            sketchFeatureID: sketchFeature,
            extrudeFeatureID: extrudeFeature,
        ],
        order: [sketchFeatureID, extrudeFeatureID],
        dependencies: [DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID)],
        revision: DocumentRevision(2)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeStraightPathSweepDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    pathLength: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters,
    options: SweepOptions = SweepOptions()
) -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        )
    ])

    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(rectangleSketch(widthID: widthID, heightID: heightID, plane: .xy)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(straightLinePathSketch(length: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            profiles: [ProfileReference(featureID: profileFeatureID)],
            path: SweepPathReference(featureID: pathFeatureID),
            options: options
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
        ],
        outputs: [FeatureOutput(role: sweepOutputRole(for: options.resultKind))]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [profileFeatureID, pathFeatureID, sweepFeatureID],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(3)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeBoxBooleanSweepDocument(
    targetWidth: Double,
    targetHeight: Double,
    toolWidth: Double,
    toolHeight: Double,
    toolCenterX: Double = 0.0,
    toolCenterY: Double = 0.0,
    depth: Double = 10.0,
    operation: SweepBooleanOperation,
    keepTools: Bool = false,
    unit: LengthUnit = .millimeter
) -> (document: CADDocument, targetFeatureID: FeatureID, sweepFeatureID: FeatureID) {
    let targetProfileFeatureID = FeatureID()
    let targetFeatureID = FeatureID()
    let toolProfileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let targetProfileFeature = FeatureNode(
        id: targetProfileFeatureID,
        operation: .sketch(offsetRectangleSketch(
            width: targetWidth,
            height: targetHeight,
            centerX: 0.0,
            centerY: 0.0,
            unit: unit
        )),
        outputs: [FeatureOutput(role: .profile)]
    )
    let targetFeature = FeatureNode(
        id: targetFeatureID,
        operation: .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: targetProfileFeatureID),
            distance: .constant(.length(depth, unit: unit))
        )),
        inputs: [FeatureInput(featureID: targetProfileFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    let toolProfileFeature = FeatureNode(
        id: toolProfileFeatureID,
        operation: .sketch(offsetRectangleSketch(
            width: toolWidth,
            height: toolHeight,
            centerX: toolCenterX,
            centerY: toolCenterY,
            unit: unit
        )),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(straightLinePathSketch(length: depth, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            profiles: [ProfileReference(featureID: toolProfileFeatureID)],
            path: SweepPathReference(featureID: pathFeatureID),
            targets: [SweepTargetReference(featureID: targetFeatureID)],
            options: SweepOptions(booleanOperation: operation, keepTools: keepTools)
        )),
        inputs: [
            FeatureInput(featureID: toolProfileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
            FeatureInput(featureID: targetFeatureID, role: .target),
        ],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            targetProfileFeatureID: targetProfileFeature,
            targetFeatureID: targetFeature,
            toolProfileFeatureID: toolProfileFeature,
            pathFeatureID: pathFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [
            targetProfileFeatureID,
            targetFeatureID,
            toolProfileFeatureID,
            pathFeatureID,
            sweepFeatureID,
        ],
        dependencies: [
            DependencyEdge(source: targetProfileFeatureID, target: targetFeatureID),
            DependencyEdge(source: toolProfileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
            DependencyEdge(source: targetFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(5)
    )
    return (
        document: CADDocument(units: .millimeters, designGraph: designGraph),
        targetFeatureID: targetFeatureID,
        sweepFeatureID: sweepFeatureID
    )
}

private func makeCircleProfileStraightPathSweepDocument(
    radius: Double = 12.0,
    pathLength: Double = 20.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters,
    options: SweepOptions = SweepOptions()
) -> CADDocument {
    let radiusID = ParameterID()
    let parameters = ParameterTable(parameters: [
        radiusID: Parameter(
            id: radiusID,
            name: "radius",
            expression: .constant(.length(radius, unit: unit)),
            kind: .length
        )
    ])

    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(circleSketch(radius: .reference(radiusID), unit: unit, plane: .xy)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(straightLinePathSketch(length: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            profiles: [ProfileReference(featureID: profileFeatureID)],
            path: SweepPathReference(featureID: pathFeatureID),
            options: options
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
        ],
        outputs: [FeatureOutput(role: sweepOutputRole(for: options.resultKind))]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [profileFeatureID, pathFeatureID, sweepFeatureID],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(3)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeGuidedStraightPathSweepDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    pathLength: Double = 10.0,
    guideStartOffset: Double = 10.0,
    guideEndOffset: Double = 20.0,
    guideMethod: SweepGuideMethod,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters
) -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        )
    ])

    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let guideFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(rectangleSketch(widthID: widthID, heightID: heightID, plane: .xy)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(straightLinePathSketch(length: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let guideFeature = FeatureNode(
        id: guideFeatureID,
        operation: .sketch(straightLinePathSketch(
            startOffset: guideStartOffset,
            endOffset: guideEndOffset,
            length: pathLength,
            unit: unit
        )),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            profiles: [ProfileReference(featureID: profileFeatureID)],
            path: SweepPathReference(featureID: pathFeatureID),
            guides: [SweepGuideReference(featureID: guideFeatureID)],
            options: SweepOptions(guideMethod: guideMethod)
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
            FeatureInput(featureID: guideFeatureID, role: .guide),
        ],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            guideFeatureID: guideFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [profileFeatureID, pathFeatureID, guideFeatureID, sweepFeatureID],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
            DependencyEdge(source: guideFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(4)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeMultiGuidedStraightPathSweepDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    pathLength: Double = 10.0,
    topGuideStartOffset: Double = 10.0,
    topGuideEndOffset: Double,
    rightGuideStartOffset: Double = 20.0,
    rightGuideEndOffset: Double,
    guideMethod: SweepGuideMethod,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters
) -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        )
    ])

    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let topGuideFeatureID = FeatureID()
    let rightGuideFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(rectangleSketch(widthID: widthID, heightID: heightID, plane: .xy)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(straightLinePathSketch(length: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let topGuideFeature = FeatureNode(
        id: topGuideFeatureID,
        operation: .sketch(straightLinePathSketch(
            startOffset: topGuideStartOffset,
            endOffset: topGuideEndOffset,
            length: pathLength,
            unit: unit
        )),
        outputs: [FeatureOutput(role: .curve)]
    )
    let rightGuideFeature = FeatureNode(
        id: rightGuideFeatureID,
        operation: .sketch(straightLineXOffsetPathSketch(
            startOffset: rightGuideStartOffset,
            endOffset: rightGuideEndOffset,
            length: pathLength,
            unit: unit
        )),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            profiles: [ProfileReference(featureID: profileFeatureID)],
            path: SweepPathReference(featureID: pathFeatureID),
            guides: [
                SweepGuideReference(featureID: topGuideFeatureID),
                SweepGuideReference(featureID: rightGuideFeatureID),
            ],
            options: SweepOptions(guideMethod: guideMethod)
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
            FeatureInput(featureID: topGuideFeatureID, role: .guide),
            FeatureInput(featureID: rightGuideFeatureID, role: .guide),
        ],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            topGuideFeatureID: topGuideFeature,
            rightGuideFeatureID: rightGuideFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [
            profileFeatureID,
            pathFeatureID,
            topGuideFeatureID,
            rightGuideFeatureID,
            sweepFeatureID,
        ],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
            DependencyEdge(source: topGuideFeatureID, target: sweepFeatureID),
            DependencyEdge(source: rightGuideFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(5)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeOverconstrainedRailGuidedStraightPathSweepDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    pathLength: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters
) -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        )
    ])

    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let topGuideFeatureID = FeatureID()
    let rightGuideFeatureID = FeatureID()
    let bottomGuideFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(rectangleSketch(widthID: widthID, heightID: heightID, plane: .xy)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(straightLinePathSketch(length: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let topGuideFeature = FeatureNode(
        id: topGuideFeatureID,
        operation: .sketch(straightLinePathSketch(
            startOffset: height / 2.0,
            endOffset: height,
            length: pathLength,
            unit: unit
        )),
        outputs: [FeatureOutput(role: .curve)]
    )
    let rightGuideFeature = FeatureNode(
        id: rightGuideFeatureID,
        operation: .sketch(straightLineXOffsetPathSketch(
            startOffset: width / 2.0,
            endOffset: width * 0.75,
            length: pathLength,
            unit: unit
        )),
        outputs: [FeatureOutput(role: .curve)]
    )
    let bottomGuideFeature = FeatureNode(
        id: bottomGuideFeatureID,
        operation: .sketch(straightLinePathSketch(
            startOffset: -height / 2.0,
            endOffset: -height / 2.0,
            length: pathLength,
            unit: unit
        )),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            profiles: [ProfileReference(featureID: profileFeatureID)],
            path: SweepPathReference(featureID: pathFeatureID),
            guides: [
                SweepGuideReference(featureID: topGuideFeatureID),
                SweepGuideReference(featureID: rightGuideFeatureID),
                SweepGuideReference(featureID: bottomGuideFeatureID),
            ],
            options: SweepOptions(guideMethod: .point)
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
            FeatureInput(featureID: topGuideFeatureID, role: .guide),
            FeatureInput(featureID: rightGuideFeatureID, role: .guide),
            FeatureInput(featureID: bottomGuideFeatureID, role: .guide),
        ],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            topGuideFeatureID: topGuideFeature,
            rightGuideFeatureID: rightGuideFeature,
            bottomGuideFeatureID: bottomGuideFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [
            profileFeatureID,
            pathFeatureID,
            topGuideFeatureID,
            rightGuideFeatureID,
            bottomGuideFeatureID,
            sweepFeatureID,
        ],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
            DependencyEdge(source: topGuideFeatureID, target: sweepFeatureID),
            DependencyEdge(source: rightGuideFeatureID, target: sweepFeatureID),
            DependencyEdge(source: bottomGuideFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(6)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeCurveGuidedStraightPathSweepDocument(
    width: Double = 20.0,
    height: Double = 20.0,
    pathLength: Double = 10.0,
    guideStartOffset: Double = 20.0,
    guideEndOffset: Double,
    guideMethod: SweepGuideMethod,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters
) -> CADDocument {
    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let guideFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(originCornerRectangleSketch(width: width, height: height, unit: unit)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(straightLinePathSketch(length: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let guideFeature = FeatureNode(
        id: guideFeatureID,
        operation: .sketch(straightLineXOffsetPathSketch(
            startOffset: guideStartOffset,
            endOffset: guideEndOffset,
            length: pathLength,
            unit: unit
        )),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            profiles: [ProfileReference(featureID: profileFeatureID)],
            path: SweepPathReference(featureID: pathFeatureID),
            guides: [SweepGuideReference(featureID: guideFeatureID)],
            options: SweepOptions(guideMethod: guideMethod)
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
            FeatureInput(featureID: guideFeatureID, role: .guide),
        ],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            guideFeatureID: guideFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [profileFeatureID, pathFeatureID, guideFeatureID, sweepFeatureID],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
            DependencyEdge(source: guideFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(4)
    )
    return CADDocument(units: documentUnits, designGraph: designGraph)
}

private func makeCurvedPathSweepDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    radius: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters
) -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        )
    ])

    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(rectangleSketch(widthID: widthID, heightID: heightID, plane: .xy)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(curvedArcPathSketch(radius: radius, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            profiles: [ProfileReference(featureID: profileFeatureID)],
            path: SweepPathReference(featureID: pathFeatureID)
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
        ],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [profileFeatureID, pathFeatureID, sweepFeatureID],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(3)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func straightLinePathSketch(
    startOffset: Double = 0.0,
    endOffset: Double = 0.0,
    length: Double,
    unit: LengthUnit
) -> Sketch {
    Sketch(
        plane: .yz,
        entities: [
            SketchEntityID(): .line(SketchLine(
                start: SketchPoint(
                    x: .constant(.length(startOffset, unit: unit)),
                    y: .constant(.length(0.0, unit: unit))
                ),
                end: SketchPoint(
                    x: .constant(.length(endOffset, unit: unit)),
                    y: .constant(.length(length, unit: unit))
                )
            ))
        ]
    )
}

private func straightLineXOffsetPathSketch(
    startOffset: Double,
    endOffset: Double,
    length: Double,
    unit: LengthUnit
) -> Sketch {
    Sketch(
        plane: .zx,
        entities: [
            SketchEntityID(): .line(SketchLine(
                start: SketchPoint(
                    x: .constant(.length(0.0, unit: unit)),
                    y: .constant(.length(startOffset, unit: unit))
                ),
                end: SketchPoint(
                    x: .constant(.length(length, unit: unit)),
                    y: .constant(.length(endOffset, unit: unit))
                )
            ))
        ]
    )
}

private func curvedArcPathSketch(radius: Double, unit: LengthUnit) -> Sketch {
    Sketch(
        plane: .yz,
        entities: [
            SketchEntityID(): .arc(SketchArc(
                center: SketchPoint(
                    x: .constant(.length(0.0, unit: unit)),
                    y: .constant(.length(0.0, unit: unit))
                ),
                radius: .constant(.length(radius, unit: unit)),
                startAngle: .constant(.angle(0.0, unit: .degree)),
                endAngle: .constant(.angle(90.0, unit: .degree))
            ))
        ]
    )
}

private func makeCircleExtrudeDocument(
    radius: Double = 12.0,
    depth: Double = 20.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters,
    sketchPlane: SketchPlane = .xy,
    direction: ExtrudeDirection = .normal
) -> CADDocument {
    let radiusID = ParameterID()
    let depthID = ParameterID()
    let parameters = ParameterTable(parameters: [
        radiusID: Parameter(
            id: radiusID,
            name: "radius",
            expression: .constant(.length(radius, unit: unit)),
            kind: .length
        ),
        depthID: Parameter(
            id: depthID,
            name: "depth",
            expression: .constant(.length(depth, unit: unit)),
            kind: .length
        )
    ])

    let sketchFeatureID = FeatureID()
    let extrudeFeatureID = FeatureID()
    let sketch = circleSketch(
        radius: .reference(radiusID),
        unit: unit,
        plane: sketchPlane
    )
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(sketch),
        outputs: [FeatureOutput(role: .profile)]
    )
    let extrudeFeature = FeatureNode(
        id: extrudeFeatureID,
        operation: .extrude(
            ExtrudeFeature(
                profile: ProfileReference(featureID: sketchFeatureID),
                distance: .reference(depthID),
                direction: direction
            )
        ),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            sketchFeatureID: sketchFeature,
            extrudeFeatureID: extrudeFeature
        ],
        order: [sketchFeatureID, extrudeFeatureID],
        dependencies: [DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID)],
        revision: DocumentRevision(2)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func circleSketch(
    radius: CADExpression,
    unit: LengthUnit = .millimeter,
    plane: SketchPlane = .xy
) -> Sketch {
    Sketch(
        plane: plane,
        entities: [
            SketchEntityID(): .circle(SketchCircle(
                center: SketchPoint(
                    x: .constant(.length(0.0, unit: unit)),
                    y: .constant(.length(0.0, unit: unit))
                ),
                radius: radius
            ))
        ]
    )
}

private func closedBezierCircleSplineSketch(
    radius: Double,
    unit: LengthUnit,
    plane: SketchPlane = .xy
) -> Sketch {
    let kappa = 0.552_284_749_830_793_6
    func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x * radius, unit: unit)),
            y: .constant(.length(y * radius, unit: unit))
        )
    }
    return Sketch(
        plane: plane,
        entities: [
            SketchEntityID(): .spline(SketchSpline(
                controlPoints: [
                    point(1.0, 0.0),
                    point(1.0, kappa),
                    point(kappa, 1.0),
                    point(0.0, 1.0),
                    point(-kappa, 1.0),
                    point(-1.0, kappa),
                    point(-1.0, 0.0),
                    point(-1.0, -kappa),
                    point(-kappa, -1.0),
                    point(0.0, -1.0),
                    point(kappa, -1.0),
                    point(1.0, -kappa),
                    point(1.0, 0.0),
                ],
                isClosed: true
            ))
        ]
    )
}

private func makeClosedSplineExtrudeDocument(
    radius: Double,
    depth: Double,
    unit: LengthUnit,
    documentUnits: UnitSystem
) -> CADDocument {
    let sketchFeatureID = FeatureID()
    let extrudeFeatureID = FeatureID()
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(closedBezierCircleSplineSketch(radius: radius, unit: unit)),
        outputs: [FeatureOutput(role: .profile)]
    )
    let extrudeFeature = FeatureNode(
        id: extrudeFeatureID,
        operation: .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: .constant(.length(depth, unit: unit))
        )),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    return CADDocument(
        units: documentUnits,
        designGraph: DesignGraph(
            nodes: [
                sketchFeatureID: sketchFeature,
                extrudeFeatureID: extrudeFeature,
            ],
            order: [sketchFeatureID, extrudeFeatureID],
            dependencies: [DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID)]
        )
    )
}

private func roundedCornerSketch() -> Sketch {
    let bottomID = SketchEntityID()
    let arcID = SketchEntityID()
    let rightID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()

    let bottomLeft = SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter)))
    let arcStart = SketchPoint(x: .constant(.length(1.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter)))
    let arcEnd = SketchPoint(x: .constant(.length(2.0, unit: .meter)), y: .constant(.length(1.0, unit: .meter)))
    let topRight = SketchPoint(x: .constant(.length(2.0, unit: .meter)), y: .constant(.length(2.0, unit: .meter)))
    let topLeft = SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(2.0, unit: .meter)))

    return Sketch(
        plane: .xy,
        entities: [
            bottomID: .line(SketchLine(start: bottomLeft, end: arcStart)),
            arcID: .arc(SketchArc(
                center: SketchPoint(
                    x: .constant(.length(1.0, unit: .meter)),
                    y: .constant(.length(1.0, unit: .meter))
                ),
                radius: .constant(.length(1.0, unit: .meter)),
                startAngle: .constant(.angle(-90.0, unit: .degree)),
                endAngle: .constant(.angle(0.0, unit: .degree))
            )),
            rightID: .line(SketchLine(start: arcEnd, end: topRight)),
            topID: .line(SketchLine(start: topRight, end: topLeft)),
            leftID: .line(SketchLine(start: topLeft, end: bottomLeft)),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .arcStart(arcID)),
            .coincident(.arcEnd(arcID), .lineStart(rightID)),
            .coincident(.lineEnd(rightID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .lineStart(bottomID)),
        ]
    )
}

private func polygonArea(_ points: [Point3D]) -> Double {
    var twiceArea = 0.0
    for index in points.indices {
        let current = points[index]
        let next = points[(index + 1) % points.count]
        twiceArea += current.x * next.y - next.x * current.y
    }
    return abs(twiceArea / 2.0)
}

private extension Curve3D {
    var isCircle: Bool {
        if case .circle = self {
            return true
        }
        return false
    }
}

private extension Surface3D {
    var isCylinder: Bool {
        if case .cylinder = self {
            return true
        }
        return false
    }
}

private func makeDocumentWithManyIndependentParameters(reverseInsertionOrder: Bool) -> CADDocument {
    let parameterIDs = (0..<32).map { index in
        fixedParameterID(index + 1)
    }
    let pairs = parameterIDs.enumerated().map { index, parameterID in
        return (
            parameterID,
            Parameter(
                id: parameterID,
                name: "p\(index)",
                expression: .constant(.length(Double(index + 1), unit: .millimeter)),
                kind: .length
            )
        )
    }
    let orderedPairs = reverseInsertionOrder ? Array(pairs.reversed()) : pairs
    return CADDocument(
        id: fixedDocumentID(),
        units: .millimeters,
        parameters: ParameterTable(parameters: Dictionary(uniqueKeysWithValues: orderedPairs)),
        designGraph: DesignGraph()
    )
}

private func fixedDocumentID() -> DocumentID {
    DocumentID(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)))
}

private func fixedParameterID(_ index: Int) -> ParameterID {
    ParameterID(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, UInt8(index))))
}

private func sweepOutputRole(for resultKind: SweepResultKind) -> FeaturePort {
    switch resultKind {
    case .solid:
        .body
    case .sheet:
        .sheet
    }
}

private func rectangleSketch(
    widthID: ParameterID,
    heightID: ParameterID,
    plane: SketchPlane = .xy,
    clockwise: Bool = false
) -> Sketch {
    let two = CADExpression.constant(.scalar(2.0))
    let minusOne = CADExpression.constant(.scalar(-1.0))
    let halfWidth = CADExpression.divide(.reference(widthID), two)
    let halfHeight = CADExpression.divide(.reference(heightID), two)
    let negativeHalfWidth = CADExpression.multiply(minusOne, halfWidth)
    let negativeHalfHeight = CADExpression.multiply(minusOne, halfHeight)
    let bottomLeft = SketchPoint(x: negativeHalfWidth, y: negativeHalfHeight)
    let bottomRight = SketchPoint(x: halfWidth, y: negativeHalfHeight)
    let topRight = SketchPoint(x: halfWidth, y: halfHeight)
    let topLeft = SketchPoint(x: negativeHalfWidth, y: halfHeight)
    let bottomID = SketchEntityID()
    let rightID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()

    let entities: [SketchEntityID: SketchEntity]
    let constraints: [SketchConstraint]
    if clockwise {
        entities = [
            leftID: .line(SketchLine(start: bottomLeft, end: topLeft)),
            topID: .line(SketchLine(start: topLeft, end: topRight)),
            rightID: .line(SketchLine(start: topRight, end: bottomRight)),
            bottomID: .line(SketchLine(start: bottomRight, end: bottomLeft))
        ]
        constraints = [
            .coincident(.lineEnd(leftID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(rightID)),
            .coincident(.lineEnd(rightID), .lineStart(bottomID)),
            .coincident(.lineEnd(bottomID), .lineStart(leftID))
        ]
    } else {
        entities = [
            bottomID: .line(SketchLine(start: bottomLeft, end: bottomRight)),
            rightID: .line(SketchLine(start: bottomRight, end: topRight)),
            topID: .line(SketchLine(start: topRight, end: topLeft)),
            leftID: .line(SketchLine(start: topLeft, end: bottomLeft))
        ]
        constraints = [
            .coincident(.lineEnd(bottomID), .lineStart(rightID)),
            .coincident(.lineEnd(rightID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .lineStart(bottomID))
        ]
    }
    return Sketch(plane: plane, entities: entities, constraints: constraints, dimensions: [])
}

private func parallelogramSketch(unit: LengthUnit) -> Sketch {
    func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: unit)),
            y: .constant(.length(y, unit: unit))
        )
    }
    let bottomLeft = point(-20.0, -10.0)
    let bottomRight = point(20.0, -10.0)
    let topRight = point(25.0, 10.0)
    let topLeft = point(-15.0, 10.0)
    let bottomID = SketchEntityID()
    let rightID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            bottomID: .line(SketchLine(start: bottomLeft, end: bottomRight)),
            rightID: .line(SketchLine(start: bottomRight, end: topRight)),
            topID: .line(SketchLine(start: topRight, end: topLeft)),
            leftID: .line(SketchLine(start: topLeft, end: bottomLeft)),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .lineStart(rightID)),
            .coincident(.lineEnd(rightID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .lineStart(bottomID)),
        ],
        dimensions: []
    )
}

private func offsetRectangleSketch(
    width: Double,
    height: Double,
    centerX: Double,
    centerY: Double,
    unit: LengthUnit
) -> Sketch {
    let halfWidth = width / 2.0
    let halfHeight = height / 2.0
    let bottomLeft = SketchPoint(
        x: .constant(.length(centerX - halfWidth, unit: unit)),
        y: .constant(.length(centerY - halfHeight, unit: unit))
    )
    let bottomRight = SketchPoint(
        x: .constant(.length(centerX + halfWidth, unit: unit)),
        y: .constant(.length(centerY - halfHeight, unit: unit))
    )
    let topRight = SketchPoint(
        x: .constant(.length(centerX + halfWidth, unit: unit)),
        y: .constant(.length(centerY + halfHeight, unit: unit))
    )
    let topLeft = SketchPoint(
        x: .constant(.length(centerX - halfWidth, unit: unit)),
        y: .constant(.length(centerY + halfHeight, unit: unit))
    )
    let bottomID = SketchEntityID()
    let rightID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            bottomID: .line(SketchLine(start: bottomLeft, end: bottomRight)),
            rightID: .line(SketchLine(start: bottomRight, end: topRight)),
            topID: .line(SketchLine(start: topRight, end: topLeft)),
            leftID: .line(SketchLine(start: topLeft, end: bottomLeft)),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .lineStart(rightID)),
            .coincident(.lineEnd(rightID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .lineStart(bottomID)),
        ],
        dimensions: []
    )
}

private func originCornerRectangleSketch(
    width: Double,
    height: Double,
    unit: LengthUnit
) -> Sketch {
    let bottomLeft = SketchPoint(
        x: .constant(.length(0.0, unit: unit)),
        y: .constant(.length(0.0, unit: unit))
    )
    let bottomRight = SketchPoint(
        x: .constant(.length(width, unit: unit)),
        y: .constant(.length(0.0, unit: unit))
    )
    let topRight = SketchPoint(
        x: .constant(.length(width, unit: unit)),
        y: .constant(.length(height, unit: unit))
    )
    let topLeft = SketchPoint(
        x: .constant(.length(0.0, unit: unit)),
        y: .constant(.length(height, unit: unit))
    )
    let bottomID = SketchEntityID()
    let rightID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            bottomID: .line(SketchLine(start: bottomLeft, end: bottomRight)),
            rightID: .line(SketchLine(start: bottomRight, end: topRight)),
            topID: .line(SketchLine(start: topRight, end: topLeft)),
            leftID: .line(SketchLine(start: topLeft, end: bottomLeft)),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .lineStart(rightID)),
            .coincident(.lineEnd(rightID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .lineStart(bottomID)),
        ],
        dimensions: []
    )
}

private func firstTriangleNormal(in mesh: Mesh) throws -> Vector3D {
    let first = mesh.positions[Int(mesh.indices[0])]
    let second = mesh.positions[Int(mesh.indices[1])]
    let third = mesh.positions[Int(mesh.indices[2])]
    return try (second - first).cross(third - first).normalized(tolerance: ModelingTolerance.standard.distance)
}

private func expectBounds(
    _ model: BRepModel,
    minimum: Point3D,
    maximum: Point3D,
    tolerance: Double = 1.0e-12
) throws {
    let points = model.vertices.values.map(\.point)
    let actualMinimum = Point3D(
        x: try #require(points.map(\.x).min()),
        y: try #require(points.map(\.y).min()),
        z: try #require(points.map(\.z).min())
    )
    let actualMaximum = Point3D(
        x: try #require(points.map(\.x).max()),
        y: try #require(points.map(\.y).max()),
        z: try #require(points.map(\.z).max())
    )
    #expect(actualMinimum.isApproximatelyEqual(to: minimum, tolerance: tolerance))
    #expect(actualMaximum.isApproximatelyEqual(to: maximum, tolerance: tolerance))
}

private func generatedFaceID(
    _ role: GeneratedSubshapeRole,
    featureID: FeatureID,
    in evaluated: EvaluatedDocument
) -> FaceID? {
    let name = PersistentName(components: [
        .feature(featureID),
        .generated(role.rawValue)
    ])
    guard case let .face(faceID) = evaluated.generatedNames[name] else {
        return nil
    }
    return faceID
}

private func planeNormal(for faceID: FaceID, in model: BRepModel) throws -> Vector3D {
    let face = try #require(model.faces[faceID])
    let surface = try #require(model.geometry.surfaces[face.surfaceID])
    guard case let .plane(plane) = surface else {
        Issue.record("Expected a planar generated face.")
        return .zero
    }
    return try plane.normal.normalized(tolerance: ModelingTolerance.standard.distance)
}

private func makeConcaveExtrudeDocument() -> CADDocument {
    let sketchFeatureID = FeatureID()
    let extrudeFeatureID = FeatureID()
    let points = [
        SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
        SketchPoint(x: .constant(.length(2.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
        SketchPoint(x: .constant(.length(1.0, unit: .meter)), y: .constant(.length(1.0, unit: .meter))),
        SketchPoint(x: .constant(.length(2.0, unit: .meter)), y: .constant(.length(2.0, unit: .meter))),
        SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(2.0, unit: .meter)))
    ]
    var entities: [SketchEntityID: SketchEntity] = [:]
    for index in points.indices {
        entities[SketchEntityID()] = .line(SketchLine(
            start: points[index],
            end: points[(index + 1) % points.count]
        ))
    }
    let sketch = Sketch(plane: .xy, entities: entities)
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(sketch),
        outputs: [FeatureOutput(role: .profile)]
    )
    let extrudeFeature = FeatureNode(
        id: extrudeFeatureID,
        operation: .extrude(
            ExtrudeFeature(
                profile: ProfileReference(featureID: sketchFeatureID),
                distance: .constant(.length(1.0, unit: .meter))
            )
        ),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    return CADDocument(
        units: .meters,
        designGraph: DesignGraph(
            nodes: [
                sketchFeatureID: sketchFeature,
                extrudeFeatureID: extrudeFeature
            ],
            order: [sketchFeatureID, extrudeFeatureID],
            dependencies: [DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID)]
        )
    )
}

private func expectBalancedEdgeOrientations(in model: BRepModel) throws {
    for edgeID in model.edges.keys {
        var forward = 0
        var reversed = 0
        for loop in model.loops.values {
            for orientedEdge in loop.edges where orientedEdge.edgeID == edgeID {
                switch orientedEdge.orientation {
                case .forward:
                    forward += 1
                case .reversed:
                    reversed += 1
                }
            }
        }
        #expect(forward == 1)
        #expect(reversed == 1)
    }
}
