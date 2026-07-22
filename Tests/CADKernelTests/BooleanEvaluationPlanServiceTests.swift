import CADCore
import CADIR
import CADKernel
import Foundation
import Testing

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPlanReportsRotatedConvexPlanarIntersection() throws {
    let setup = booleanPlanRotatedConvexIntersectionDocument()

    let result = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .intersect,
        keepTools: false,
        tolerance: .standard
    )

    #expect(result.status == .supported)
    #expect(result.operandKind == .convexPlanarSolids)
    #expect(result.outputTopologyKind == .convexPlanarIntersection)
    #expect(result.topologyNameSchemes == [.body, .exactPlanarBoundaryTopology])
    #expect(result.resultPrimitiveCount == 1)
    #expect(result.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 6,
        loopCount: 6,
        edgeCount: 12,
        vertexCount: 8
    ))
    #expect(result.unsupportedCode == nil)
    #expect(result.checks.allSatisfy { $0.status == .passed })
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesDeterministicRotatedConvexPlanarIntersection() throws {
    let setup = booleanPlanRotatedConvexIntersectionDocument()
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .intersect,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .intersect,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    #expect(evaluated.brep.faces.count == 6)
    #expect(evaluated.brep.edges.count == 12)
    #expect(evaluated.brep.vertices.count == 8)
    #expect(evaluated.lineage.values.contains { lineage in
        lineage.parents.contains { $0.featureID == setup.targetFeatureID }
    })
    #expect(evaluated.lineage.values.contains { lineage in
        lineage.parents.contains { $0.featureID == setup.toolFeatureID }
    })
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.016 * 0.008 * 0.010) <= 1.0e-12)
    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.012, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesRotatedConvexPlanarUnionAndDifference() throws {
    let setup = booleanPlanRotatedConvexIntersectionDocument()
    let classifier = DefaultBRepSolidPointClassifier()
    for operation in [BooleanOperation.union, .difference] {
        let booleanID = FeatureID()
        let plan = try BooleanEvaluationPlanService().plan(
            document: setup.document,
            targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
            tool: BooleanToolReference(featureID: setup.toolFeatureID),
            operation: operation,
            keepTools: false,
            tolerance: .standard
        )
        let document = booleanPlanDocument(
            setup: setup,
            booleanID: booleanID,
            operation: operation,
            keepTools: false
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let bodyID = try #require(evaluated.brep.bodies.keys.first)

        #expect(plan.status == .supported)
        #expect(plan.operandKind == .convexPlanarSolids)
        #expect(plan.outputTopologyKind == (operation == .union
            ? .convexPlanarUnion
            : .convexPlanarDifference))
        expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
        #expect(evaluated.brep == repeated.brep)
        #expect(evaluated.lineage == repeated.lineage)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let expectedVolume = operation == .union
            ? 0.020 * 0.020 * 0.010
            : (0.020 * 0.020 - 0.016 * 0.008) * 0.010
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)
        let centerClassification = try classifier.classify(
            Point3D(x: 0.0, y: 0.0, z: 0.005),
            in: bodyID,
            model: evaluated.brep,
            tolerance: .standard
        )
        #expect(centerClassification == (operation == .union ? .inside : .outside))
        #expect(evaluated.lineage.values.contains { lineage in
            lineage.parents.contains { $0.featureID == setup.targetFeatureID }
        })
        if operation == .difference {
            #expect(evaluated.lineage.values.contains { lineage in
                lineage.parents.contains { $0.featureID == setup.toolFeatureID }
            })
        }
    }
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesSeparatedRotatedConvexPlanarUnionShells() throws {
    let setup = booleanPlanRotatedConvexIntersectionDocument(toolCenterX: 40.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .union,
        keepTools: false
    )
    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .convexPlanarUnion)
    #expect(evaluated.brep.bodies.count == 1)
    #expect(evaluated.brep.shells.count == 2)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - (0.020 * 0.020 + 0.016 * 0.008) * 0.010) <= 1.0e-12)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPreservesVolumeIdentityForPartiallyOverlappingRotatedSolids() throws {
    let setup = booleanPlanRotatedConvexIntersectionDocument(toolCenterX: 8.0)
    var volumes: [BooleanOperation: Double] = [:]
    for operation in [BooleanOperation.union, .difference, .intersect] {
        let booleanID = FeatureID()
        let document = booleanPlanDocument(
            setup: setup,
            booleanID: booleanID,
            operation: operation,
            keepTools: false
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        volumes[operation] = try evaluated.brep.volume(tolerance: .standard)
    }

    let unionVolume = try #require(volumes[.union])
    let differenceVolume = try #require(volumes[.difference])
    let intersectionVolume = try #require(volumes[.intersect])
    let targetVolume = 0.020 * 0.020 * 0.010
    let toolVolume = 0.016 * 0.008 * 0.010
    #expect(intersectionVolume > 0.0)
    #expect(intersectionVolume < toolVolume)
    #expect(abs((unionVolume + intersectionVolume) - (targetVolume + toolVolume)) <= 1.0e-12)
    #expect(abs((differenceVolume + intersectionVolume) - targetVolume) <= 1.0e-12)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPlanReportsExactBoxFrameDifference() throws {
    let setup = booleanPlanBoxDocument(
        targetWidth: 40.0,
        targetHeight: 40.0,
        toolWidth: 20.0,
        toolHeight: 20.0
    )

    let result = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )

    #expect(result.status == .supported)
    #expect(result.operation == .difference)
    #expect(result.keepTools == false)
    #expect(result.targetCount == 1)
    #expect(result.targetCellCount == 1)
    #expect(result.toolCellCount == 1)
    #expect(result.resultPrimitiveCount == 1)
    #expect(result.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 10,
        loopCount: 12,
        edgeCount: 24,
        vertexCount: 16
    ))
    #expect(result.operandKind == .axisAlignedBoxSolids)
    #expect(result.outputTopologyKind == .zThroughFrame)
    #expect(result.topologyNameSchemes == [
        .body,
        .orthogonalBoundaryTopology,
    ])
    #expect(result.topologySlots.count == 51)
    #expect(result.topologySlots.first == BooleanEvaluationTopologySlot(role: .body))
    #expect(result.topologySlots.contains { slot in
        slot.role == .vertex && slot.subshape?.hasPrefix("orthogonal:component:0:") == true
    })
    #expect(result.topologySlots.contains { slot in
        slot.role == .edge && slot.subshape?.hasPrefix("orthogonal:component:0:") == true
    })
    #expect(result.topologySlots.contains { slot in
        slot.role == .sideFace
            && slot.subshape?.contains(":face:minimumZ:") == true
    })
    #expect(result.unsupportedCode == nil)
    #expect(result.checks.map(\.kind) == [.requestContract, .sourceBodies, .operandTopology, .capabilityDecision])
    #expect(result.checks.allSatisfy { $0.status == .passed })
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPlanTopologySlotsResolveGeneratedFrameNames() throws {
    let setup = booleanPlanBoxDocument(
        targetWidth: 40.0,
        targetHeight: 40.0,
        toolWidth: 20.0,
        toolHeight: 20.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )
    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    ))

    #expect(plan.outputTopologyKind == .zThroughFrame)
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPlanTopologySlotsResolveGeneratedCellUnionNames() throws {
    let setup = booleanPlanBoxDocument(
        targetWidth: 40.0,
        targetHeight: 40.0,
        toolWidth: 30.0,
        toolHeight: 30.0,
        toolCenterX: 10.0,
        toolCenterY: 10.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )
    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    ))

    #expect(plan.outputTopologyKind == .orthogonalCellUnion)
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPlanReportsContainedCylindricalUnionBeforeMutation() throws {
    let setup = booleanPlanCylinderToolDocument()

    let result = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: true,
        tolerance: .standard
    )

    #expect(result.status == .supported)
    #expect(result.operation == .union)
    #expect(result.keepTools == true)
    #expect(result.operandKind == .planarAndRevolvedSolids)
    #expect(result.outputTopologyKind == .revolvedUnion)
    #expect(result.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 6,
        loopCount: 6,
        edgeCount: 12,
        vertexCount: 8
    ))
    #expect(result.topologyNameSchemes == [.body, .curvedBoundaryTopology])
    #expect(result.topologySlots.isEmpty == false)
    #expect(result.unsupportedCode == nil)
    #expect(result.message == "Boolean can evaluate as revolvedUnion.")
    #expect(result.checks.map(\.kind) == [
        .requestContract,
        .sourceBodies,
        .operandTopology,
        .capabilityDecision,
    ])
    #expect(result.checks.allSatisfy { $0.status == .passed })
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPlanReportsExactRevolvedThroughHole() throws {
    let setup = booleanPlanCylinderToolDocument()

    let result = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )

    #expect(result.status == .supported)
    #expect(result.operandKind == .planarAndRevolvedSolids)
    #expect(result.outputTopologyKind == .revolvedThroughHole)
    #expect(result.topologyNameSchemes == [.body, .curvedBoundaryTopology])
    #expect(result.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 10,
        loopCount: 12,
        edgeCount: 24,
        vertexCount: 16
    ))
    #expect(result.topologySlots.count == 51)
    #expect(result.unsupportedCode == nil)
    #expect(result.checks.allSatisfy { $0.status == .passed })
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactCylindricalThroughHole() throws {
    let setup = booleanPlanCylinderToolDocument()
    let source = try DocumentEvaluator(tolerance: .standard).evaluate(setup.document)
    let sourceToolCylinderID = try #require(source.subshapes.entries.first { subshapeID, reference in
        guard subshapeID.featureID == setup.toolFeatureID,
              case let .face(faceID) = reference,
              let face = source.brep.faces[faceID],
              let surface = source.brep.geometry.surfaces[face.surfaceID],
              case .cylinder = surface else {
            return false
        }
        return true
    }?.key)
    let sourceToolCylinderSelection = try source.stableSubshapeReference(for: sourceToolCylinderID)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)
    let classifier = DefaultBRepSolidPointClassifier()
    let resolvedToolCylinderReference = try evaluated.topologyReference(
        for: sourceToolCylinderSelection
    )

    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    guard case let .face(resolvedToolCylinderFaceID) = resolvedToolCylinderReference,
          let resolvedToolCylinderFace = evaluated.brep.faces[resolvedToolCylinderFaceID],
          let resolvedToolCylinderSurface = evaluated.brep.geometry.surfaces[resolvedToolCylinderFace.surfaceID],
          case .cylinder = resolvedToolCylinderSurface else {
        Issue.record("Stable tool-face selection did not resolve to the Boolean cylindrical wall.")
        return
    }
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.brep.bodies.count == 1)
    #expect(evaluated.brep.shells.count == 1)
    #expect(evaluated.brep.faces.count == 10)
    #expect(evaluated.brep.loops.count == 12)
    #expect(evaluated.brep.edges.count == 24)
    #expect(evaluated.brep.vertices.count == 16)
    let cylindricalFaceIDs = Set(evaluated.brep.faces.values.compactMap { face -> FaceID? in
        guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
              case .cylinder = surface else {
            return nil
        }
        return face.orientation == .reversed ? face.id : nil
    })
    #expect(cylindricalFaceIDs.count == 4)
    let cylindricalLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case let .face(faceID) = reference,
              cylindricalFaceIDs.contains(faceID) else {
            return nil
        }
        return evaluated.lineage[subshapeID]
    }
    #expect(cylindricalLineage.count == 4)
    #expect(cylindricalLineage.allSatisfy { lineage in
        lineage.parents.count == 1
            && lineage.parents[0].featureID == setup.toolFeatureID
            && lineage.relation == .preserved
    })
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let expectedVolume = 0.024 * 0.024 * 0.010
        - Double.pi * 0.006 * 0.006 * 0.010
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
    #expect(try classifier.classify(
        Point3D(x: 0.010, y: 0.010, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesTiltedCylindricalThroughHole() throws {
    let setup = booleanPlanTiltedCylinderToolDocument()
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

    #expect(plan.status == .supported)
    #expect(plan.operandKind == .planarAndRevolvedSolids)
    #expect(plan.outputTopologyKind == .revolvedThroughHole)
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let expectedVolume = 0.024 * 0.024 * 0.010
        - Double.pi * 0.006 * 0.006 * 0.010
    let actualVolume = try evaluated.brep.volume(tolerance: .standard)
    #expect(
        abs(actualVolume - expectedVolume) <= 1.0e-12,
        "Tilted through-hole volume residual: \(actualVolume - expectedVolume)"
    )
    let cylinderFaces = evaluated.brep.faces.values.filter { face in
        guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
        if case .cylinder = surface { return true }
        return false
    }
    #expect(cylinderFaces.count == 4)
    #expect(cylinderFaces.allSatisfy { $0.orientation == .reversed })
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactConicalThroughHole() throws {
    let setup = booleanPlanConicalToolDocument()
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.operandKind == .planarAndRevolvedSolids)
    #expect(plan.outputTopologyKind == .revolvedThroughHole)
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)

    let lowerRadius = 0.0056
    let upperRadius = 0.0036
    let height = 0.010
    let removedVolume = Double.pi * height
        * (lowerRadius * lowerRadius + lowerRadius * upperRadius + upperRadius * upperRadius)
        / 3.0
    let expectedVolume = 0.024 * 0.024 * height - removedVolume
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)

    let conicalFaceIDs = Set(evaluated.brep.faces.values.compactMap { face -> FaceID? in
        guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
              case .analytic(.cone) = surface,
              face.orientation == .reversed else {
            return nil
        }
        return face.id
    })
    #expect(conicalFaceIDs.count == 4)
    let conicalLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case let .face(faceID) = reference,
              conicalFaceIDs.contains(faceID) else {
            return nil
        }
        return evaluated.lineage[subshapeID]
    }
    #expect(conicalLineage.count == 4)
    #expect(conicalLineage.allSatisfy { lineage in
        lineage.parents.count == 1
            && lineage.parents[0].featureID == setup.toolFeatureID
            && lineage.relation == .preserved
    })
    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.005, z: 0.0),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
    #expect(try classifier.classify(
        Point3D(x: 0.010, y: 0.005, z: 0.010),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactCylindricalIntersection() throws {
    let setup = booleanPlanCylinderToolDocument()
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .intersect,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .intersect,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.operandKind == .planarAndRevolvedSolids)
    #expect(plan.outputTopologyKind == .revolvedIntersection)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 6,
        loopCount: 6,
        edgeCount: 12,
        vertexCount: 8
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - Double.pi * 0.006 * 0.006 * 0.010) <= 1.0e-12)

    let cylinderFaces = evaluated.brep.faces.values.filter { face in
        guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
              case .cylinder = surface else {
            return false
        }
        return face.orientation == .forward
    }
    #expect(cylinderFaces.count == 4)
    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.010, y: 0.010, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactConicalIntersection() throws {
    let setup = booleanPlanConicalToolDocument()
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .intersect,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .intersect,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.operandKind == .planarAndRevolvedSolids)
    #expect(plan.outputTopologyKind == .revolvedIntersection)
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)

    let lowerRadius = 0.0056
    let upperRadius = 0.0036
    let height = 0.010
    let expectedVolume = Double.pi * height
        * (lowerRadius * lowerRadius + lowerRadius * upperRadius + upperRadius * upperRadius)
        / 3.0
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)

    let conicalFaceIDs = Set(evaluated.brep.faces.values.compactMap { face -> FaceID? in
        guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
              case .analytic(.cone) = surface,
              face.orientation == .forward else {
            return nil
        }
        return face.id
    })
    #expect(conicalFaceIDs.count == 4)
    let wallLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case let .face(faceID) = reference,
              conicalFaceIDs.contains(faceID) else {
            return nil
        }
        return evaluated.lineage[subshapeID]
    }
    #expect(wallLineage.count == 4)
    #expect(wallLineage.allSatisfy { lineage in
        lineage.parents.count == 1
            && lineage.parents[0].featureID == setup.toolFeatureID
            && lineage.relation == .preserved
    })
    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.005, z: 0.0),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.010, y: 0.005, z: 0.010),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPreservesContainedCylinderForIntersection() throws {
    let setup = booleanPlanCylinderToolDocument(toolDepth: 6.0, toolStart: 2.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .intersect,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .intersect,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.operandKind == .planarAndRevolvedSolids)
    #expect(plan.outputTopologyKind == .revolvedIntersection)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 6,
        loopCount: 6,
        edgeCount: 12,
        vertexCount: 8
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    #expect(abs(
        try evaluated.brep.volume(tolerance: .standard) - Double.pi * 0.006 * 0.006 * 0.006
    ) <= 1.0e-12)

    let boundaryLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case .body = reference else {
            return evaluated.lineage[subshapeID]
        }
        return nil
    }
    #expect(boundaryLineage.count == 26)
    #expect(boundaryLineage.allSatisfy { lineage in
        lineage.parents.count == 1
            && lineage.parents[0].featureID == setup.toolFeatureID
            && lineage.relation == .preserved
    })

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.001),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
    #expect(try classifier.classify(
        Point3D(x: 0.007, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCarriesRevolvedToolForTargetContainedUnion() throws {
    let setup = booleanPlanCylinderToolDocument(
        targetWidth: 8.0,
        targetHeight: 8.0,
        toolDepth: 14.0,
        toolStart: -2.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .union,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.operandKind == .planarAndRevolvedSolids)
    #expect(plan.outputTopologyKind == .carriedOperand)
    #expect(plan.topologyNameSchemes == [.body, .copiedSourceTopology])
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 6,
        loopCount: 6,
        edgeCount: 12,
        vertexCount: 8
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    #expect(abs(
        try evaluated.brep.volume(tolerance: .standard) - Double.pi * 0.006 * 0.006 * 0.014
    ) <= 1.0e-12)

    let boundaryLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case .body = reference else {
            return evaluated.lineage[subshapeID]
        }
        return nil
    }
    #expect(boundaryLineage.count == 26)
    #expect(boundaryLineage.allSatisfy { lineage in
        lineage.parents.count == 1
            && lineage.parents[0].featureID == setup.toolFeatureID
            && lineage.relation == .preserved
    })

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: -0.001),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.007, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCarriesPlanarTargetForTargetContainedIntersection() throws {
    let setup = booleanPlanCylinderToolDocument(
        targetWidth: 8.0,
        targetHeight: 8.0,
        toolDepth: 14.0,
        toolStart: -2.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .intersect,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .intersect,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .carriedOperand)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 6,
        loopCount: 6,
        edgeCount: 12,
        vertexCount: 8
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.008 * 0.008 * 0.010) <= 1.0e-12)
    #expect(evaluated.brep.faces.values.allSatisfy { face in
        guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID] else {
            return false
        }
        if case .plane = surface { return true }
        return false
    })

    let boundaryLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case .body = reference else {
            return evaluated.lineage[subshapeID]
        }
        return nil
    }
    #expect(boundaryLineage.count == 26)
    #expect(boundaryLineage.allSatisfy { lineage in
        lineage.parents.count == 1
            && lineage.parents[0].featureID == setup.targetFeatureID
            && lineage.relation == .preserved
    })

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.003, y: 0.003, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.005, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationReportsEmptyDifferenceForTargetContainedByRevolvedTool() throws {
    let setup = booleanPlanCylinderToolDocument(
        targetWidth: 8.0,
        targetHeight: 8.0,
        toolDepth: 14.0,
        toolStart: -2.0
    )
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )

    #expect(plan.status == .unsupported)
    #expect(plan.unsupportedCode == .emptyResult)
    #expect(plan.outputTopologyKind == nil)
    #expect(plan.checks.last?.kind == .capabilityDecision)
    #expect(plan.checks.last?.status == .unsupported)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCarriesPlanarTargetForAxiallySeparatedDifference() throws {
    let setup = booleanPlanCylinderToolDocument(toolDepth: 10.0, toolStart: 20.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

    #expect(plan.status == .supported)
    #expect(plan.operandKind == .planarAndRevolvedSolids)
    #expect(plan.outputTopologyKind == .carriedOperand)
    #expect(plan.topologyNameSchemes == [.body, .copiedSourceTopology])
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 6,
        loopCount: 6,
        edgeCount: 12,
        vertexCount: 8
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.024 * 0.024 * 0.010) <= 1.0e-12)

    let boundaryLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case .body = reference else {
            return evaluated.lineage[subshapeID]
        }
        return nil
    }
    #expect(boundaryLineage.count == 26)
    #expect(boundaryLineage.allSatisfy { lineage in
        lineage.parents.count == 1
            && lineage.parents[0].featureID == setup.targetFeatureID
            && lineage.relation == .preserved
    })
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationReportsTypedEmptyIntersectionForAxiallySeparatedTool() throws {
    let setup = booleanPlanCylinderToolDocument(toolDepth: 10.0, toolStart: 20.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .intersect,
        keepTools: false,
        tolerance: .standard
    )

    #expect(plan.status == .unsupported)
    #expect(plan.unsupportedCode == .emptyResult)
    #expect(plan.outputTopologyKind == nil)

    do {
        _ = try DocumentEvaluator(tolerance: .standard).evaluate(booleanPlanDocument(
            setup: setup,
            booleanID: booleanID,
            operation: .intersect,
            keepTools: false
        ))
        Issue.record("Axially separated Boolean intersection must produce a typed empty result.")
    } catch let error as KernelError {
        #expect(error.code == .emptyResult)
        #expect(error.phase == .topology)
        #expect(error.featureID == booleanID)
        #expect(error.tolerance == .standard)
    }
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesAxiallySeparatedConicalUnion() throws {
    let setup = booleanPlanConicalToolDocument(
        lowerRadius: 5.0,
        lowerCoordinate: 20.0,
        upperRadius: 4.0,
        upperCoordinate: 30.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: false,
        tolerance: .standard
    )
    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .union,
        keepTools: false
    ))

    #expect(plan.status == .supported)
    #expect(plan.operandKind == .separatedSolidBodies)
    #expect(plan.outputTopologyKind == .disjointSolidUnion)
    #expect(plan.resultTopologyCounts?.bodyCount == 1)
    #expect(plan.resultTopologyCounts?.shellCount == 2)
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let targetVolume = 0.024 * 0.024 * 0.010
    let toolVolume = Double.pi * 0.010 * (0.005 * 0.005 + 0.005 * 0.004 + 0.004 * 0.004) / 3.0
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - targetVolume - toolVolume) <= 1.0e-12)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCarriesPlanarTargetForRadiallySeparatedDifference() throws {
    let setup = booleanPlanCylinderToolDocument(toolCenterX: 50.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )
    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    ))

    #expect(plan.status == .supported)
    #expect(plan.operandKind == .planarAndRevolvedSolids)
    #expect(plan.outputTopologyKind == .carriedOperand)
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.024 * 0.024 * 0.010) <= 1.0e-12)

    let boundaryLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case .body = reference else {
            return evaluated.lineage[subshapeID]
        }
        return nil
    }
    #expect(boundaryLineage.count == 26)
    #expect(boundaryLineage.allSatisfy { lineage in
        lineage.parents.count == 1
            && lineage.parents[0].featureID == setup.targetFeatureID
            && lineage.relation == .preserved
    })
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationReportsTypedEmptyIntersectionForRadiallySeparatedTool() throws {
    let setup = booleanPlanCylinderToolDocument(toolCenterX: 50.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .intersect,
        keepTools: false,
        tolerance: .standard
    )

    #expect(plan.status == .unsupported)
    #expect(plan.unsupportedCode == .emptyResult)

    do {
        _ = try DocumentEvaluator(tolerance: .standard).evaluate(booleanPlanDocument(
            setup: setup,
            booleanID: booleanID,
            operation: .intersect,
            keepTools: false
        ))
        Issue.record("Radially separated Boolean intersection must produce a typed empty result.")
    } catch let error as KernelError {
        #expect(error.code == .emptyResult)
        #expect(error.phase == .topology)
        #expect(error.featureID == booleanID)
    }
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCarriesTargetForTangentialCylindricalDifference() throws {
    let setup = booleanPlanCylinderToolDocument(toolCenterX: 18.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )
    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    ))

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .carriedOperand)
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.024 * 0.024 * 0.010) <= 1.0e-12)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationReportsTypedEmptyIntersectionForTangentialCylindricalTool() throws {
    let setup = booleanPlanCylinderToolDocument(toolCenterX: 18.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .intersect,
        keepTools: false,
        tolerance: .standard
    )

    #expect(plan.status == .unsupported)
    #expect(plan.unsupportedCode == .emptyResult)

    do {
        _ = try DocumentEvaluator(tolerance: .standard).evaluate(booleanPlanDocument(
            setup: setup,
            booleanID: booleanID,
            operation: .intersect,
            keepTools: false
        ))
        Issue.record("Tangential Boolean intersection must produce a typed empty result.")
    } catch let error as KernelError {
        #expect(error.code == .emptyResult)
        #expect(error.phase == .classification)
        #expect(error.featureID == booleanID)
        #expect((error.residual ?? .infinity) <= ModelingTolerance.standard.distance)
    }
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationRejectsTangentialCylindricalUnionAsNonManifold() throws {
    let setup = booleanPlanCylinderToolDocument(toolCenterX: 18.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: false,
        tolerance: .standard
    )

    #expect(plan.status == .unsupported)
    #expect(plan.unsupportedCode == .nonManifoldResult)
    #expect(plan.checks.last?.kind == .capabilityDecision)

    do {
        _ = try DocumentEvaluator(tolerance: .standard).evaluate(booleanPlanDocument(
            setup: setup,
            booleanID: booleanID,
            operation: .union,
            keepTools: false
        ))
        Issue.record("Tangential Boolean union must reject its non-manifold result.")
    } catch let error as KernelError {
        #expect(error.code == .nonManifoldResult)
        #expect(error.phase == .topology)
        #expect(error.featureID == booleanID)
        #expect((error.residual ?? .infinity) <= ModelingTolerance.standard.distance)
    }
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactSideCrossingCylindricalDifference() throws {
    let setup = booleanPlanCylinderToolDocument(toolCenterX: 9.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .partialCylinderDifference)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 8,
        loopCount: 8,
        edgeCount: 18,
        vertexCount: 12
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let metrics = sideCrossingCylinderVolumeMetrics()
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - metrics.difference) <= 1.0e-12)
    try expectSideCrossingLineage(evaluated, setup: setup)

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.009, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
    #expect(try classifier.classify(
        Point3D(x: -0.010, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactSideCrossingCylindricalIntersection() throws {
    let setup = booleanPlanCylinderToolDocument(toolCenterX: 9.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .intersect,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .intersect,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .partialCylinderIntersection)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 4,
        loopCount: 4,
        edgeCount: 6,
        vertexCount: 4
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let metrics = sideCrossingCylinderVolumeMetrics()
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - metrics.intersection) <= 1.0e-12)
    try expectSideCrossingLineage(evaluated, setup: setup)

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.009, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactSideCrossingCylindricalUnion() throws {
    let setup = booleanPlanCylinderToolDocument(toolCenterX: 9.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .union,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .partialCylinderUnion)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 8,
        loopCount: 8,
        edgeCount: 18,
        vertexCount: 12
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let metrics = sideCrossingCylinderVolumeMetrics()
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - metrics.union) <= 1.0e-12)
    try expectSideCrossingLineage(evaluated, setup: setup)

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.014, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.016, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactOutsideAxisCylindricalDifference() throws {
    let setup = booleanPlanCylinderToolDocument(toolCenterX: 15.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .partialCylinderDifference)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 8,
        loopCount: 8,
        edgeCount: 18,
        vertexCount: 12
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let metrics = sideCrossingCylinderVolumeMetrics(centerInsideTarget: false)
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - metrics.difference) <= 1.0e-12)
    try expectSideCrossingLineage(evaluated, setup: setup)

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.011, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactOutsideAxisCylindricalIntersection() throws {
    let setup = booleanPlanCylinderToolDocument(toolCenterX: 15.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .intersect,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .intersect,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .partialCylinderIntersection)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 4,
        loopCount: 4,
        edgeCount: 6,
        vertexCount: 4
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let metrics = sideCrossingCylinderVolumeMetrics(centerInsideTarget: false)
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - metrics.intersection) <= 1.0e-12)
    try expectSideCrossingLineage(evaluated, setup: setup)

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.011, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactOutsideAxisCylindricalUnion() throws {
    let setup = booleanPlanCylinderToolDocument(toolCenterX: 15.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .union,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .partialCylinderUnion)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 8,
        loopCount: 8,
        edgeCount: 18,
        vertexCount: 12
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let metrics = sideCrossingCylinderVolumeMetrics(centerInsideTarget: false)
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - metrics.union) <= 1.0e-12)
    try expectSideCrossingLineage(evaluated, setup: setup)

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.015, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.022, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactCornerCylindricalDifference() throws {
    let setup = booleanPlanCylinderToolDocument(
        toolCenterX: 15.0,
        toolCenterY: 15.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .partialCylinderDifference)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 7,
        loopCount: 7,
        edgeCount: 15,
        vertexCount: 10
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let metrics = cornerCrossingCylinderVolumeMetrics()
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - metrics.difference) <= 1.0e-12)
    try expectSideCrossingLineage(evaluated, setup: setup)

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.011, y: 0.011, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactCornerCylindricalIntersection() throws {
    let setup = booleanPlanCylinderToolDocument(
        toolCenterX: 15.0,
        toolCenterY: 15.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .intersect,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .intersect,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .partialCylinderIntersection)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 5,
        loopCount: 5,
        edgeCount: 9,
        vertexCount: 6
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let metrics = cornerCrossingCylinderVolumeMetrics()
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - metrics.intersection) <= 1.0e-12)
    try expectSideCrossingLineage(evaluated, setup: setup)

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.011, y: 0.011, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactCornerCylindricalUnion() throws {
    let setup = booleanPlanCylinderToolDocument(
        toolCenterX: 15.0,
        toolCenterY: 15.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .union,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .partialCylinderUnion)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 7,
        loopCount: 7,
        edgeCount: 15,
        vertexCount: 10
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let metrics = cornerCrossingCylinderVolumeMetrics()
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - metrics.union) <= 1.0e-12)
    try expectSideCrossingLineage(evaluated, setup: setup)

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.015, y: 0.015, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.022, y: 0.022, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactInsideCornerCylindricalDifference() throws {
    let setup = booleanPlanCylinderToolDocument(
        toolCenterX: 9.0,
        toolCenterY: 9.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .partialCylinderDifference)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 7,
        loopCount: 7,
        edgeCount: 15,
        vertexCount: 10
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let metrics = cornerCrossingCylinderVolumeMetrics(centerInsideTarget: true)
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - metrics.difference) <= 1.0e-12)
    try expectSideCrossingLineage(evaluated, setup: setup)

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.009, y: 0.009, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactInsideCornerCylindricalIntersection() throws {
    let setup = booleanPlanCylinderToolDocument(
        toolCenterX: 9.0,
        toolCenterY: 9.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .intersect,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .intersect,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .partialCylinderIntersection)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 5,
        loopCount: 5,
        edgeCount: 9,
        vertexCount: 6
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let metrics = cornerCrossingCylinderVolumeMetrics(centerInsideTarget: true)
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - metrics.intersection) <= 1.0e-12)
    try expectSideCrossingLineage(evaluated, setup: setup)

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.009, y: 0.009, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactInsideCornerCylindricalUnion() throws {
    let setup = booleanPlanCylinderToolDocument(
        toolCenterX: 9.0,
        toolCenterY: 9.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .union,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .partialCylinderUnion)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 7,
        loopCount: 7,
        edgeCount: 15,
        vertexCount: 10
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let metrics = cornerCrossingCylinderVolumeMetrics(centerInsideTarget: true)
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - metrics.union) <= 1.0e-12)
    try expectSideCrossingLineage(evaluated, setup: setup)

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.014, y: 0.009, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.016, y: 0.016, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesTwoShellOppositeSideCylindricalDifference() throws {
    let setup = booleanPlanCylinderToolDocument(
        targetWidth: 10.0,
        targetHeight: 24.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)
    let body = try #require(evaluated.brep.bodies[bodyID])

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .partialCylinderDifference)
    #expect(plan.resultPrimitiveCount == 2)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 2,
        faceCount: 12,
        loopCount: 12,
        edgeCount: 24,
        vertexCount: 16
    ))
    #expect(body.shellIDs.count == 2)
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let metrics = oppositeSideCrossingCylinderVolumeMetrics()
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - metrics.difference) <= 1.0e-12)
    try expectSideCrossingLineage(
        evaluated,
        setup: setup,
        expectedCylinderFaceCount: 2
    )

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.010, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesOppositeSideCylindricalIntersection() throws {
    let setup = booleanPlanCylinderToolDocument(
        targetWidth: 10.0,
        targetHeight: 24.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .intersect,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .intersect,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .partialCylinderIntersection)
    #expect(plan.resultPrimitiveCount == 1)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 6,
        loopCount: 6,
        edgeCount: 12,
        vertexCount: 8
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let metrics = oppositeSideCrossingCylinderVolumeMetrics()
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - metrics.intersection) <= 1.0e-12)
    try expectSideCrossingLineage(
        evaluated,
        setup: setup,
        expectedCylinderFaceCount: 2
    )

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.010, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesOppositeSideCylindricalUnion() throws {
    let setup = booleanPlanCylinderToolDocument(
        targetWidth: 10.0,
        targetHeight: 24.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .union,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .partialCylinderUnion)
    #expect(plan.resultPrimitiveCount == 1)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 10,
        loopCount: 10,
        edgeCount: 24,
        vertexCount: 16
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let metrics = oppositeSideCrossingCylinderVolumeMetrics()
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - metrics.union) <= 1.0e-12)
    try expectSideCrossingLineage(
        evaluated,
        setup: setup,
        expectedCylinderFaceCount: 2
    )

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0055, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.007, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactPartialConicalIntersection() throws {
    let setup = booleanPlanConicalToolDocument(
        lowerRadius: 4.8,
        lowerCoordinate: 4.0,
        upperRadius: 3.2,
        upperCoordinate: 12.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .intersect,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .intersect,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .revolvedIntersection)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 6,
        loopCount: 6,
        edgeCount: 12,
        vertexCount: 8
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let lowerRadius = 0.0048
    let upperRadius = 0.0036
    let expectedVolume = Double.pi * 0.006
        * (lowerRadius * lowerRadius + lowerRadius * upperRadius + upperRadius * upperRadius)
        / 3.0
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)

    let conicalFaceIDs = Set(evaluated.brep.faces.values.compactMap { face -> FaceID? in
        guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
              case .analytic(.cone) = surface,
              face.orientation == .forward else {
            return nil
        }
        return face.id
    })
    #expect(conicalFaceIDs.count == 4)
    let wallLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case let .face(faceID) = reference,
              conicalFaceIDs.contains(faceID) else {
            return nil
        }
        return evaluated.lineage[subshapeID]
    }
    #expect(wallLineage.count == 4)
    #expect(wallLineage.allSatisfy { lineage in
        lineage.parents.count == 1
            && lineage.parents[0].featureID == setup.toolFeatureID
            && lineage.relation == .preserved
    })

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.007, z: 0.0),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.002, z: 0.0),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
    #expect(try classifier.classify(
        Point3D(x: 0.010, y: 0.007, z: 0.0),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactCylindricalUnion() throws {
    let setup = booleanPlanCylinderToolDocument(toolDepth: 14.0, toolStart: -2.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .union,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.operandKind == .planarAndRevolvedSolids)
    #expect(plan.outputTopologyKind == .revolvedUnion)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 16,
        loopCount: 18,
        edgeCount: 36,
        vertexCount: 24
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let expectedVolume = 0.024 * 0.024 * 0.010
        + Double.pi * 0.006 * 0.006 * 0.004
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)

    let wallFaceIDs = Set(evaluated.brep.faces.values.compactMap { face -> FaceID? in
        guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
              case .cylinder = surface,
              face.orientation == .forward else {
            return nil
        }
        return face.id
    })
    #expect(wallFaceIDs.count == 8)
    let wallLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case let .face(faceID) = reference,
              wallFaceIDs.contains(faceID) else {
            return nil
        }
        return evaluated.lineage[subshapeID]
    }
    #expect(wallLineage.count == 8)
    #expect(wallLineage.allSatisfy { lineage in
        lineage.parents.count == 1
            && lineage.parents[0].featureID == setup.toolFeatureID
            && lineage.relation == .split
    })
    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: -0.001),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.010, y: 0.0, z: -0.001),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactConicalUnion() throws {
    let setup = booleanPlanConicalToolDocument()
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .union,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.operandKind == .planarAndRevolvedSolids)
    #expect(plan.outputTopologyKind == .revolvedUnion)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 16,
        loopCount: 18,
        edgeCount: 36,
        vertexCount: 24
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)

    func frustumVolume(height: Double, lowerRadius: Double, upperRadius: Double) -> Double {
        Double.pi * height
            * (lowerRadius * lowerRadius + lowerRadius * upperRadius + upperRadius * upperRadius)
            / 3.0
    }
    let expectedVolume = 0.024 * 0.024 * 0.010
        + frustumVolume(height: 0.002, lowerRadius: 0.006, upperRadius: 0.0056)
        + frustumVolume(height: 0.002, lowerRadius: 0.0036, upperRadius: 0.0032)
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)

    let wallFaceIDs = Set(evaluated.brep.faces.values.compactMap { face -> FaceID? in
        guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
              case .analytic(.cone) = surface,
              face.orientation == .forward else {
            return nil
        }
        return face.id
    })
    #expect(wallFaceIDs.count == 8)
    let wallLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case let .face(faceID) = reference,
              wallFaceIDs.contains(faceID) else {
            return nil
        }
        return evaluated.lineage[subshapeID]
    }
    #expect(wallLineage.count == 8)
    #expect(wallLineage.allSatisfy { lineage in
        lineage.parents.count == 1
            && lineage.parents[0].featureID == setup.toolFeatureID
            && lineage.relation == .split
    })
    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: -0.001, z: 0.0),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.010, y: -0.001, z: 0.0),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactUpperCylindricalUnion() throws {
    let setup = booleanPlanCylinderToolDocument(toolDepth: 7.0, toolStart: 5.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .union,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .revolvedUnion)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 11,
        loopCount: 12,
        edgeCount: 24,
        vertexCount: 16
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let expectedVolume = 0.024 * 0.024 * 0.010
        + Double.pi * 0.006 * 0.006 * 0.002
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)

    let wallFaceIDs = Set(evaluated.brep.faces.values.compactMap { face -> FaceID? in
        guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
              case .cylinder = surface,
              face.orientation == .forward else {
            return nil
        }
        return face.id
    })
    #expect(wallFaceIDs.count == 4)
    let wallLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case let .face(faceID) = reference,
              wallFaceIDs.contains(faceID) else {
            return nil
        }
        return evaluated.lineage[subshapeID]
    }
    #expect(wallLineage.count == 4)
    #expect(wallLineage.allSatisfy { lineage in
        lineage.parents.count == 1
            && lineage.parents[0].featureID == setup.toolFeatureID
            && lineage.relation == .preserved
    })
    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.011),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.010, y: 0.0, z: 0.011),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactLowerConicalUnion() throws {
    let setup = booleanPlanConicalToolDocument(
        lowerRadius: 6.0,
        lowerCoordinate: -2.0,
        upperRadius: 4.6,
        upperCoordinate: 5.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .union,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .revolvedUnion)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 11,
        loopCount: 12,
        edgeCount: 24,
        vertexCount: 16
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let lowerRadius = 0.006
    let upperRadius = 0.0056
    let addedVolume = Double.pi * 0.002
        * (lowerRadius * lowerRadius + lowerRadius * upperRadius + upperRadius * upperRadius)
        / 3.0
    let expectedVolume = 0.024 * 0.024 * 0.010 + addedVolume
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)

    let wallFaceIDs = Set(evaluated.brep.faces.values.compactMap { face -> FaceID? in
        guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
              case .analytic(.cone) = surface,
              face.orientation == .forward else {
            return nil
        }
        return face.id
    })
    #expect(wallFaceIDs.count == 4)
    let wallLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case let .face(faceID) = reference,
              wallFaceIDs.contains(faceID) else {
            return nil
        }
        return evaluated.lineage[subshapeID]
    }
    #expect(wallLineage.count == 4)
    #expect(wallLineage.allSatisfy { lineage in
        lineage.parents.count == 1
            && lineage.parents[0].featureID == setup.toolFeatureID
            && lineage.relation == .preserved
    })
    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: -0.001, z: 0.0),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.010, y: -0.001, z: 0.0),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPreservesTargetForContainedCylindricalUnion() throws {
    let setup = booleanPlanCylinderToolDocument(toolDepth: 6.0, toolStart: 2.0)
    let source = try DocumentEvaluator(tolerance: .standard).evaluate(setup.document)
    let targetBodyReference = try source.stableSubshapeReference(for: SubshapeID(
        featureID: setup.targetFeatureID,
        role: GeneratedSubshapeRole.body.rawValue,
        ordinal: 0
    ))
    let toolBodyReference = try source.stableSubshapeReference(for: SubshapeID(
        featureID: setup.toolFeatureID,
        role: GeneratedSubshapeRole.body.rawValue,
        ordinal: 0
    ))
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .union,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)
    let resultBody = TopologyReference.body(bodyID)

    #expect(plan.status == .supported)
    #expect(plan.operandKind == .planarAndRevolvedSolids)
    #expect(plan.outputTopologyKind == .revolvedUnion)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 6,
        loopCount: 6,
        edgeCount: 12,
        vertexCount: 8
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.024 * 0.024 * 0.010) <= 1.0e-12)
    #expect(evaluated.brep.faces.values.allSatisfy { face in
        guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID] else {
            return false
        }
        if case .plane = surface {
            return true
        }
        return false
    })

    let bodyLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case .body = reference else { return nil }
        return evaluated.lineage[subshapeID]
    }
    #expect(bodyLineage.count == 1)
    #expect(bodyLineage[0].relation == .merged)
    #expect(Set(bodyLineage[0].parents.map(\.featureID)) == Set([
        setup.targetFeatureID,
        setup.toolFeatureID,
    ]))
    #expect(try evaluated.topologyReference(for: targetBodyReference) == resultBody)
    #expect(try evaluated.topologyReference(for: toolBodyReference) == resultBody)
    let boundaryLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case .body = reference else {
            return evaluated.lineage[subshapeID]
        }
        return nil
    }
    #expect(boundaryLineage.count == 26)
    #expect(boundaryLineage.allSatisfy { lineage in
        lineage.parents.count == 1
            && lineage.parents[0].featureID == setup.targetFeatureID
            && lineage.relation == .preserved
    })

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.013, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Suite("Topology lineage merge resolution")
struct TopologyLineageMergeResolutionTests {
    @Test(.timeLimit(.minutes(1)))
    func resolvesBothBooleanBodyParentsToMergedResult() throws {
        let setup = booleanPlanCylinderToolDocument(toolDepth: 6.0, toolStart: 2.0)
        let source = try DocumentEvaluator(tolerance: .standard).evaluate(setup.document)
        let targetReference = try source.stableSubshapeReference(for: SubshapeID(
            featureID: setup.targetFeatureID,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        ))
        let toolReference = try source.stableSubshapeReference(for: SubshapeID(
            featureID: setup.toolFeatureID,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        ))
        let document = booleanPlanDocument(
            setup: setup,
            booleanID: FeatureID(),
            operation: .union,
            keepTools: false
        )

        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let bodyEntry = try #require(evaluated.subshapes.entries.first {
            if case .body = $0.value { true } else { false }
        })
        let lineage = try #require(evaluated.lineage[bodyEntry.key])

        #expect(lineage.relation == .merged)
        #expect(Set(lineage.parents.map(\.featureID)) == Set([
            setup.targetFeatureID,
            setup.toolFeatureID,
        ]))
        #expect(try evaluated.topologyReference(for: targetReference) == bodyEntry.value)
        #expect(try evaluated.topologyReference(for: toolReference) == bodyEntry.value)
    }
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactContainedCylindricalCavity() throws {
    let setup = booleanPlanCylinderToolDocument(toolDepth: 6.0, toolStart: 2.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)
    let body = try #require(evaluated.brep.bodies[bodyID])

    #expect(plan.status == .supported)
    #expect(plan.operandKind == .planarAndRevolvedSolids)
    #expect(plan.outputTopologyKind == .revolvedCavity)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 2,
        faceCount: 12,
        loopCount: 12,
        edgeCount: 24,
        vertexCount: 16
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    #expect(body.shellIDs.count == 2)
    let shellOrientations = body.shellIDs.compactMap {
        evaluated.brep.shells[$0]?.orientation
    }
    #expect(shellOrientations.filter { $0 == .forward }.count == 1)
    #expect(shellOrientations.filter { $0 == .reversed }.count == 1)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let expectedVolume = 0.024 * 0.024 * 0.010
        - Double.pi * 0.006 * 0.006 * 0.006
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)

    let cavityWallFaceIDs = Set(evaluated.brep.faces.values.compactMap { face -> FaceID? in
        guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
              case .cylinder = surface else {
            return nil
        }
        return face.id
    })
    #expect(cavityWallFaceIDs.count == 4)
    let cavityWallLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case let .face(faceID) = reference,
              cavityWallFaceIDs.contains(faceID) else {
            return nil
        }
        return evaluated.lineage[subshapeID]
    }
    #expect(cavityWallLineage.count == 4)
    #expect(cavityWallLineage.allSatisfy { lineage in
        lineage.parents.count == 1
            && lineage.parents[0].featureID == setup.toolFeatureID
            && lineage.relation == .preserved
    })

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
    #expect(try classifier.classify(
        Point3D(x: 0.010, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.013, y: 0.0, z: 0.005),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactContainedConicalCavity() throws {
    let setup = booleanPlanConicalToolDocument(
        lowerRadius: 4.8,
        lowerCoordinate: 2.0,
        upperRadius: 3.6,
        upperCoordinate: 8.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)
    let body = try #require(evaluated.brep.bodies[bodyID])

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .revolvedCavity)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 2,
        faceCount: 12,
        loopCount: 12,
        edgeCount: 24,
        vertexCount: 16
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    let shellOrientations = body.shellIDs.compactMap {
        evaluated.brep.shells[$0]?.orientation
    }
    #expect(shellOrientations.contains(.reversed))
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let lowerRadius = 0.0048
    let upperRadius = 0.0036
    let cavityVolume = Double.pi * 0.006
        * (lowerRadius * lowerRadius + lowerRadius * upperRadius + upperRadius * upperRadius)
        / 3.0
    let expectedVolume = 0.024 * 0.024 * 0.010 - cavityVolume
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)

    let cavityWallFaceIDs = Set(evaluated.brep.faces.values.compactMap { face -> FaceID? in
        guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
              case .analytic(.cone) = surface else {
            return nil
        }
        return face.id
    })
    #expect(cavityWallFaceIDs.count == 4)
    let cavityWallLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case let .face(faceID) = reference,
              cavityWallFaceIDs.contains(faceID) else {
            return nil
        }
        return evaluated.lineage[subshapeID]
    }
    #expect(cavityWallLineage.count == 4)
    #expect(cavityWallLineage.allSatisfy { lineage in
        lineage.parents.count == 1
            && lineage.parents[0].featureID == setup.toolFeatureID
            && lineage.relation == .preserved
    })

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.005, z: 0.0),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
    #expect(try classifier.classify(
        Point3D(x: 0.010, y: 0.005, z: 0.0),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactLowerCylindricalBlindHole() throws {
    let setup = booleanPlanCylinderToolDocument(toolDepth: 8.0, toolStart: -2.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.operandKind == .planarAndRevolvedSolids)
    #expect(plan.outputTopologyKind == .revolvedBlindHole)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 11,
        loopCount: 12,
        edgeCount: 24,
        vertexCount: 16
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let expectedVolume = 0.024 * 0.024 * 0.010
        - Double.pi * 0.006 * 0.006 * 0.006
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)

    let wallFaceIDs = Set(evaluated.brep.faces.values.compactMap { face -> FaceID? in
        guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
              case .cylinder = surface,
              face.orientation == .reversed else {
            return nil
        }
        return face.id
    })
    #expect(wallFaceIDs.count == 4)
    let wallLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case let .face(faceID) = reference,
              wallFaceIDs.contains(faceID) else {
            return nil
        }
        return evaluated.lineage[subshapeID]
    }
    #expect(wallLineage.count == 4)
    #expect(wallLineage.allSatisfy { lineage in
        lineage.parents.count == 1
            && lineage.parents[0].featureID == setup.toolFeatureID
            && lineage.relation == .preserved
    })
    let internalCapFaceIDs = Set(evaluated.brep.faces.values.compactMap { face -> FaceID? in
        guard face.orientation == .reversed,
              let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
              case let .plane(plane) = surface,
              abs(plane.origin.z - 0.006) <= ModelingTolerance.standard.distance else {
            return nil
        }
        return face.id
    })
    #expect(internalCapFaceIDs.count == 1)
    let internalCapLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case let .face(faceID) = reference,
              internalCapFaceIDs.contains(faceID) else {
            return nil
        }
        return evaluated.lineage[subshapeID]
    }
    #expect(internalCapLineage.count == 1)
    #expect(internalCapLineage[0].parents.count == 1)
    #expect(internalCapLineage[0].parents[0].featureID == setup.toolFeatureID)

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.003),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.0, z: 0.008),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.010, y: 0.0, z: 0.003),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationCreatesExactUpperConicalBlindHole() throws {
    let setup = booleanPlanConicalToolDocument(
        lowerRadius: 4.8,
        lowerCoordinate: 4.0,
        upperRadius: 3.2,
        upperCoordinate: 12.0
    )
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .difference,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
    let bodyID = try #require(evaluated.brep.bodies.keys.first)

    #expect(plan.status == .supported)
    #expect(plan.outputTopologyKind == .revolvedBlindHole)
    #expect(plan.resultTopologyCounts == BooleanEvaluationTopologyCounts(
        bodyCount: 1,
        shellCount: 1,
        faceCount: 11,
        loopCount: 12,
        edgeCount: 24,
        vertexCount: 16
    ))
    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep == repeated.brep)
    #expect(evaluated.lineage == repeated.lineage)
    try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    let lowerRadius = 0.0048
    let upperRadius = 0.0036
    let removedVolume = Double.pi * 0.006
        * (lowerRadius * lowerRadius + lowerRadius * upperRadius + upperRadius * upperRadius)
        / 3.0
    let expectedVolume = 0.024 * 0.024 * 0.010 - removedVolume
    #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)

    let wallFaceIDs = Set(evaluated.brep.faces.values.compactMap { face -> FaceID? in
        guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
              case .analytic(.cone) = surface,
              face.orientation == .reversed else {
            return nil
        }
        return face.id
    })
    #expect(wallFaceIDs.count == 4)
    let wallLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case let .face(faceID) = reference,
              wallFaceIDs.contains(faceID) else {
            return nil
        }
        return evaluated.lineage[subshapeID]
    }
    #expect(wallLineage.count == 4)
    #expect(wallLineage.allSatisfy { lineage in
        lineage.parents.count == 1
            && lineage.parents[0].featureID == setup.toolFeatureID
            && lineage.relation == .preserved
    })

    let classifier = DefaultBRepSolidPointClassifier()
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.007, z: 0.0),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .outside)
    #expect(try classifier.classify(
        Point3D(x: 0.0, y: 0.002, z: 0.0),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
    #expect(try classifier.classify(
        Point3D(x: 0.010, y: 0.007, z: 0.0),
        in: bodyID,
        model: evaluated.brep,
        tolerance: .standard
    ) == .inside)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPlanReportsSeparatedBRepUnionBeforeMutation() throws {
    let setup = booleanPlanCylinderToolDocument(toolCenterX: 50.0)

    let result = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: false,
        tolerance: .standard
    )

    #expect(result.status == .supported)
    #expect(result.operation == .union)
    #expect(result.targetCount == 1)
    #expect(result.targetCellCount == 1)
    #expect(result.toolCellCount == 1)
    #expect(result.resultPrimitiveCount == 2)
    #expect(result.operandKind == .separatedSolidBodies)
    #expect(result.outputTopologyKind == .disjointSolidUnion)
    #expect(result.topologyNameSchemes == [.body, .copiedSourceTopology])
    #expect(result.resultTopologyCounts?.bodyCount == 1)
    #expect(result.resultTopologyCounts?.shellCount == 2)
    #expect((result.resultTopologyCounts?.faceCount ?? 0) > 6)
    #expect(result.topologySlots.contains(BooleanEvaluationTopologySlot(
        role: .sideFace,
        subshape: "copy:target:0:face:0"
    )))
    #expect(result.topologySlots.contains(BooleanEvaluationTopologySlot(
        role: .sideFace,
        subshape: "copy:tool:face:0"
    )))
    #expect(result.topologySlots.contains(BooleanEvaluationTopologySlot(
        role: .edge,
        subshape: "copy:tool:edge:0"
    )))
    #expect(result.unsupportedCode == nil)
    #expect(result.checks.map(\.kind) == [.requestContract, .sourceBodies, .operandTopology, .capabilityDecision])
    #expect(result.checks.allSatisfy { $0.status == .passed })
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationEvaluatesSeparatedBRepUnionWithStableCopiedTopologyNames() throws {
    let setup = booleanPlanCylinderToolDocument(toolCenterX: 50.0)
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: setup.targetFeatureID)],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: false,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .union,
        keepTools: false
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep.bodies.count == 1)
    #expect(evaluated.brep.shells.count == 2)
    #expect(evaluated.subshapes.entries.keys.contains { $0.featureID == setup.targetFeatureID } == false)
    #expect(evaluated.subshapes.entries.keys.contains { $0.featureID == setup.toolFeatureID } == false)
    guard case .body? = evaluated.subshapes[SubshapeID(
        featureID: booleanID,
        role: GeneratedSubshapeRole.body.rawValue,
        ordinal: 0
    )] else {
        Issue.record("Separated B-rep union must publish a generated result body identity.")
        return
    }
    #expect(evaluated.subshapes[SubshapeID(
        featureID: booleanID,
        role: "sideFace.copy:target:0:face:0",
        ordinal: 0
    )] != nil)
    #expect(evaluated.subshapes[SubshapeID(
        featureID: booleanID,
        role: "sideFace.copy:tool:face:0",
        ordinal: 0
    )] != nil)
    #expect(evaluated.subshapes[SubshapeID(
        featureID: booleanID,
        role: "edge.copy:tool:edge:0",
        ordinal: 0
    )] != nil)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPlanReportsMultiTargetSeparatedBRepUnionBeforeMutation() throws {
    let setup = booleanPlanMultiTargetCylinderToolDocument()

    let result = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: setup.targetFeatureIDs.map(BooleanTargetReference.init(featureID:)),
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: true,
        tolerance: .standard
    )

    #expect(result.status == .supported)
    #expect(result.operation == .union)
    #expect(result.keepTools)
    #expect(result.targetCount == 2)
    #expect(result.targetCellCount == 2)
    #expect(result.toolCellCount == 1)
    #expect(result.resultPrimitiveCount == 3)
    #expect(result.operandKind == .separatedSolidBodies)
    #expect(result.outputTopologyKind == .disjointSolidUnion)
    #expect(result.topologyNameSchemes == [.body, .copiedSourceTopology])
    #expect(result.resultTopologyCounts?.bodyCount == 1)
    #expect(result.resultTopologyCounts?.shellCount == 3)
    #expect(result.topologySlots.contains(BooleanEvaluationTopologySlot(
        role: .sideFace,
        subshape: "copy:target:1:face:0"
    )))
    #expect(result.topologySlots.contains(BooleanEvaluationTopologySlot(
        role: .edge,
        subshape: "copy:tool:edge:0"
    )))
    #expect(result.unsupportedCode == nil)
    #expect(result.checks.map(\.kind) == [.requestContract, .sourceBodies, .operandTopology, .capabilityDecision])
    #expect(result.checks.allSatisfy { $0.status == .passed })
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationEvaluatesMultiTargetSeparatedBRepUnionKeepToolsWithStableCopiedTopologyNames() throws {
    let setup = booleanPlanMultiTargetCylinderToolDocument()
    let booleanID = FeatureID()
    let plan = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: setup.targetFeatureIDs.map(BooleanTargetReference.init(featureID:)),
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .union,
        keepTools: true,
        tolerance: .standard
    )
    let document = booleanPlanDocument(
        setup: setup,
        booleanID: booleanID,
        operation: .union,
        keepTools: true
    )

    let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

    expectPlannedTopologyNames(plan, for: booleanID, in: evaluated)
    #expect(evaluated.brep.bodies.count == 4)
    #expect(evaluated.brep.shells.count == 6)
    for targetFeatureID in setup.targetFeatureIDs {
        #expect(evaluated.subshapes[SubshapeID(
            featureID: targetFeatureID,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        )] != nil)
    }
    #expect(evaluated.subshapes[SubshapeID(
        featureID: setup.toolFeatureID,
        role: GeneratedSubshapeRole.body.rawValue,
        ordinal: 0
    )] != nil)
    #expect(evaluated.subshapes[SubshapeID(
        featureID: booleanID,
        role: "body.tool",
        ordinal: 0
    )] == nil)
    #expect(evaluated.subshapes[SubshapeID(
        featureID: booleanID,
        role: "sideFace.copy:target:1:face:0",
        ordinal: 0
    )] != nil)
    #expect(evaluated.subshapes[SubshapeID(
        featureID: booleanID,
        role: "edge.copy:tool:edge:0",
        ordinal: 0
    )] != nil)
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPlanReportsInvalidRequestAtRequestContractGate() throws {
    let setup = booleanPlanBoxDocument(
        targetWidth: 40.0,
        targetHeight: 40.0,
        toolWidth: 20.0,
        toolHeight: 20.0
    )

    let result = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [
            BooleanTargetReference(featureID: setup.targetFeatureID),
            BooleanTargetReference(featureID: setup.targetFeatureID),
        ],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )

    #expect(result.status == .unsupported)
    #expect(result.unsupportedCode == .invalidRequest)
    #expect(result.checks == [
        BooleanEvaluationPreflightCheck(
            kind: .requestContract,
            status: .unsupported,
            message: result.message
        ),
    ])
    #expect(result.message.contains("Boolean target references must be unique"))
}

@Test(.timeLimit(.minutes(1)))
func booleanEvaluationPlanReportsMissingBodyAtSourceBodyGate() throws {
    let setup = booleanPlanBoxDocument(
        targetWidth: 40.0,
        targetHeight: 40.0,
        toolWidth: 20.0,
        toolHeight: 20.0
    )

    let result = try BooleanEvaluationPlanService().plan(
        document: setup.document,
        targets: [BooleanTargetReference(featureID: FeatureID())],
        tool: BooleanToolReference(featureID: setup.toolFeatureID),
        operation: .difference,
        keepTools: false,
        tolerance: .standard
    )

    #expect(result.status == .unsupported)
    #expect(result.unsupportedCode == .missingBody)
    #expect(result.checks.map(\.kind) == [.requestContract, .sourceBodies])
    #expect(result.checks.first?.status == .passed)
    #expect(result.checks.last?.status == .unsupported)
    #expect(result.message.contains("Boolean body reference could not be resolved"))
}

private struct BooleanPlanDocumentSetup {
    var document: CADDocument
    var targetFeatureID: FeatureID
    var toolFeatureID: FeatureID
}

private struct BooleanMultiTargetPlanDocumentSetup {
    var document: CADDocument
    var targetFeatureIDs: [FeatureID]
    var toolFeatureID: FeatureID
}

private func sideCrossingCylinderVolumeMetrics(
    centerInsideTarget: Bool = true
) -> (
    difference: Double,
    intersection: Double,
    union: Double
) {
    let targetArea = 0.024 * 0.024
    let radius = 0.006
    let sideDistance = 0.003
    let outsideSegmentArea = radius * radius * acos(sideDistance / radius)
        - sideDistance * sqrt(radius * radius - sideDistance * sideDistance)
    let circleArea = Double.pi * radius * radius
    let intersectionArea = centerInsideTarget
        ? circleArea - outsideSegmentArea
        : outsideSegmentArea
    let height = 0.010
    return (
        difference: (targetArea - intersectionArea) * height,
        intersection: intersectionArea * height,
        union: (targetArea + circleArea - intersectionArea) * height
    )
}

private func cornerCrossingCylinderVolumeMetrics(
    centerInsideTarget: Bool = false
) -> (
    difference: Double,
    intersection: Double,
    union: Double
) {
    let targetArea = 0.024 * 0.024
    let radius = 0.006
    let sideDistance = 0.003
    let halfChord = sqrt(radius * radius - sideDistance * sideDistance)
    let cornerArea = 0.5 * (
        radius * radius * Double.pi / 6.0
            + 2.0 * sideDistance * sideDistance
            - 2.0 * sideDistance * halfChord
    )
    let circleArea = Double.pi * radius * radius
    let outsideSegmentArea = radius * radius * acos(sideDistance / radius)
        - sideDistance * halfChord
    let intersectionArea = centerInsideTarget
        ? circleArea - 2.0 * outsideSegmentArea + cornerArea
        : cornerArea
    let height = 0.010
    return (
        difference: (targetArea - intersectionArea) * height,
        intersection: intersectionArea * height,
        union: (targetArea + circleArea - intersectionArea) * height
    )
}

private func oppositeSideCrossingCylinderVolumeMetrics() -> (
    difference: Double,
    intersection: Double,
    union: Double
) {
    let targetArea = 0.010 * 0.024
    let radius = 0.006
    let halfWidth = 0.005
    let halfChord = sqrt(radius * radius - halfWidth * halfWidth)
    let intersectionArea = 2.0 * (
        halfWidth * halfChord
            + radius * radius * asin(halfWidth / radius)
    )
    let circleArea = Double.pi * radius * radius
    let height = 0.010
    return (
        difference: (targetArea - intersectionArea) * height,
        intersection: intersectionArea * height,
        union: (targetArea + circleArea - intersectionArea) * height
    )
}

private func expectSideCrossingLineage(
    _ evaluated: EvaluatedDocument,
    setup: BooleanPlanDocumentSetup,
    expectedCylinderFaceCount: Int = 1
) throws {
    #expect(evaluated.lineage.values.contains { lineage in
        lineage.parents.contains { $0.featureID == setup.targetFeatureID }
    })
    let cylinderFaces = Set(evaluated.brep.faces.values.compactMap { face -> FaceID? in
        guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
              case .cylinder = surface else {
            return nil
        }
        return face.id
    })
    #expect(cylinderFaces.count == expectedCylinderFaceCount)
    let cylinderLineage = evaluated.subshapes.entries.compactMap { subshapeID, reference -> TopologyLineage? in
        guard case let .face(faceID) = reference,
              cylinderFaces.contains(faceID) else {
            return nil
        }
        return evaluated.lineage[subshapeID]
    }
    #expect(cylinderLineage.count == expectedCylinderFaceCount)
    #expect(cylinderLineage.allSatisfy { lineage in
        lineage.parents.contains { $0.featureID == setup.toolFeatureID }
    })
}

private func booleanPlanBoxDocument(
    targetWidth: Double,
    targetHeight: Double,
    toolWidth: Double,
    toolHeight: Double,
    toolCenterX: Double = 0.0,
    toolCenterY: Double = 0.0,
    depth: Double = 10.0,
    unit: LengthUnit = .millimeter
) -> BooleanPlanDocumentSetup {
    let targetProfileID = FeatureID()
    let targetID = FeatureID()
    let toolProfileID = FeatureID()
    let toolID = FeatureID()
    let targetProfile = booleanPlanProfileFeature(
        id: targetProfileID,
        sketch: booleanPlanRectangleSketch(
            width: targetWidth,
            height: targetHeight,
            centerX: 0.0,
            centerY: 0.0,
            unit: unit
        )
    )
    let target = booleanPlanExtrudeFeature(
        id: targetID,
        profileID: targetProfileID,
        depth: depth,
        unit: unit
    )
    let toolProfile = booleanPlanProfileFeature(
        id: toolProfileID,
        sketch: booleanPlanRectangleSketch(
            width: toolWidth,
            height: toolHeight,
            centerX: toolCenterX,
            centerY: toolCenterY,
            unit: unit
        )
    )
    let tool = booleanPlanExtrudeFeature(
        id: toolID,
        profileID: toolProfileID,
        depth: depth,
        unit: unit
    )
    let document = booleanPlanDocument(
        nodes: [
            targetProfileID: targetProfile,
            targetID: target,
            toolProfileID: toolProfile,
            toolID: tool,
        ],
        order: [targetProfileID, targetID, toolProfileID, toolID],
        dependencies: [
            DependencyEdge(source: targetProfileID, target: targetID),
            DependencyEdge(source: toolProfileID, target: toolID),
        ]
    )
    return BooleanPlanDocumentSetup(document: document, targetFeatureID: targetID, toolFeatureID: toolID)
}

private func booleanPlanRotatedConvexIntersectionDocument(
    toolCenterX: Double = 0.0
) -> BooleanPlanDocumentSetup {
    let targetProfileID = FeatureID()
    let targetID = FeatureID()
    let toolProfileID = FeatureID()
    let toolID = FeatureID()
    let targetProfile = booleanPlanProfileFeature(
        id: targetProfileID,
        sketch: booleanPlanRectangleSketch(
            width: 20.0,
            height: 20.0,
            centerX: 0.0,
            centerY: 0.0,
            unit: .millimeter
        )
    )
    let target = booleanPlanExtrudeFeature(
        id: targetID,
        profileID: targetProfileID,
        depth: 10.0,
        unit: .millimeter
    )
    let toolProfile = booleanPlanProfileFeature(
        id: toolProfileID,
        sketch: booleanPlanRotatedRectangleSketch(
            width: 16.0,
            height: 8.0,
            angle: .pi / 6.0,
            centerX: toolCenterX,
            plane: .xy,
            unit: .millimeter
        )
    )
    let tool = booleanPlanExtrudeFeature(
        id: toolID,
        profileID: toolProfileID,
        depth: 10.0,
        unit: .millimeter
    )
    let document = booleanPlanDocument(
        nodes: [
            targetProfileID: targetProfile,
            targetID: target,
            toolProfileID: toolProfile,
            toolID: tool,
        ],
        order: [targetProfileID, targetID, toolProfileID, toolID],
        dependencies: [
            DependencyEdge(source: targetProfileID, target: targetID),
            DependencyEdge(source: toolProfileID, target: toolID),
        ]
    )
    return BooleanPlanDocumentSetup(
        document: document,
        targetFeatureID: targetID,
        toolFeatureID: toolID
    )
}

private func booleanPlanMultiTargetCylinderToolDocument(
    depth: Double = 10.0,
    unit: LengthUnit = .millimeter
) -> BooleanMultiTargetPlanDocumentSetup {
    let firstProfileID = FeatureID()
    let firstTargetID = FeatureID()
    let secondProfileID = FeatureID()
    let secondTargetID = FeatureID()
    let toolProfileID = FeatureID()
    let toolID = FeatureID()
    let firstProfile = booleanPlanProfileFeature(
        id: firstProfileID,
        sketch: booleanPlanRectangleSketch(
            width: 16.0,
            height: 16.0,
            centerX: -50.0,
            centerY: 0.0,
            unit: unit
        )
    )
    let firstTarget = booleanPlanExtrudeFeature(
        id: firstTargetID,
        profileID: firstProfileID,
        depth: depth,
        unit: unit
    )
    let secondProfile = booleanPlanProfileFeature(
        id: secondProfileID,
        sketch: booleanPlanRectangleSketch(
            width: 16.0,
            height: 16.0,
            centerX: 0.0,
            centerY: 0.0,
            unit: unit
        )
    )
    let secondTarget = booleanPlanExtrudeFeature(
        id: secondTargetID,
        profileID: secondProfileID,
        depth: depth,
        unit: unit
    )
    let toolProfile = booleanPlanProfileFeature(
        id: toolProfileID,
        sketch: booleanPlanCircleSketch(
            radius: 6.0,
            centerX: 50.0,
            centerY: 0.0,
            unit: unit
        )
    )
    let tool = booleanPlanExtrudeFeature(
        id: toolID,
        profileID: toolProfileID,
        depth: depth,
        unit: unit
    )
    let document = booleanPlanDocument(
        nodes: [
            firstProfileID: firstProfile,
            firstTargetID: firstTarget,
            secondProfileID: secondProfile,
            secondTargetID: secondTarget,
            toolProfileID: toolProfile,
            toolID: tool,
        ],
        order: [
            firstProfileID,
            firstTargetID,
            secondProfileID,
            secondTargetID,
            toolProfileID,
            toolID,
        ],
        dependencies: [
            DependencyEdge(source: firstProfileID, target: firstTargetID),
            DependencyEdge(source: secondProfileID, target: secondTargetID),
            DependencyEdge(source: toolProfileID, target: toolID),
        ]
    )
    return BooleanMultiTargetPlanDocumentSetup(
        document: document,
        targetFeatureIDs: [firstTargetID, secondTargetID],
        toolFeatureID: toolID
    )
}

private func booleanPlanCylinderToolDocument(
    toolCenterX: Double = 0.0,
    toolCenterY: Double = 0.0,
    targetWidth: Double = 24.0,
    targetHeight: Double = 24.0,
    depth: Double = 10.0,
    toolDepth: Double? = nil,
    toolStart: Double = 0.0,
    unit: LengthUnit = .millimeter
) -> BooleanPlanDocumentSetup {
    let targetProfileID = FeatureID()
    let targetID = FeatureID()
    let toolProfileID = FeatureID()
    let toolID = FeatureID()
    let targetProfile = booleanPlanProfileFeature(
        id: targetProfileID,
        sketch: booleanPlanRectangleSketch(
            width: targetWidth,
            height: targetHeight,
            centerX: 0.0,
            centerY: 0.0,
            unit: unit
        )
    )
    let target = booleanPlanExtrudeFeature(
        id: targetID,
        profileID: targetProfileID,
        depth: depth,
        unit: unit
    )
    let toolProfile = booleanPlanProfileFeature(
        id: toolProfileID,
        sketch: booleanPlanCircleSketch(
            radius: 6.0,
            centerX: toolCenterX,
            centerY: toolCenterY,
            unit: unit,
            plane: toolStart == 0.0
                ? .xy
                : .plane(Plane3D(
                    origin: Point3D(x: 0.0, y: 0.0, z: unit.toInternal(toolStart)),
                    normal: .unitZ
                ))
        )
    )
    let tool = booleanPlanExtrudeFeature(
        id: toolID,
        profileID: toolProfileID,
        depth: toolDepth ?? depth,
        unit: unit
    )
    let document = booleanPlanDocument(
        nodes: [
            targetProfileID: targetProfile,
            targetID: target,
            toolProfileID: toolProfile,
            toolID: tool,
        ],
        order: [targetProfileID, targetID, toolProfileID, toolID],
        dependencies: [
            DependencyEdge(source: targetProfileID, target: targetID),
            DependencyEdge(source: toolProfileID, target: toolID),
        ]
    )
    return BooleanPlanDocumentSetup(document: document, targetFeatureID: targetID, toolFeatureID: toolID)
}

private func booleanPlanTiltedCylinderToolDocument() -> BooleanPlanDocumentSetup {
    let inverseRootThree = 1.0 / sqrt(3.0)
    let axis = Vector3D(
        x: inverseRootThree,
        y: inverseRootThree,
        z: inverseRootThree
    )
    let targetPlane = SketchPlane.plane(Plane3D(origin: .origin, normal: axis))
    let toolPlane = SketchPlane.plane(Plane3D(
        origin: .origin + axis * -0.002,
        normal: axis
    ))
    let targetProfileID = FeatureID()
    let targetID = FeatureID()
    let toolProfileID = FeatureID()
    let toolID = FeatureID()
    let targetProfile = booleanPlanProfileFeature(
        id: targetProfileID,
        sketch: booleanPlanRectangleSketch(
            width: 24.0,
            height: 24.0,
            centerX: 0.0,
            centerY: 0.0,
            unit: .millimeter,
            plane: targetPlane
        )
    )
    let target = booleanPlanExtrudeFeature(
        id: targetID,
        profileID: targetProfileID,
        depth: 10.0,
        unit: .millimeter
    )
    let toolProfile = booleanPlanProfileFeature(
        id: toolProfileID,
        sketch: booleanPlanCircleSketch(
            radius: 6.0,
            unit: .millimeter,
            plane: toolPlane
        )
    )
    let tool = booleanPlanExtrudeFeature(
        id: toolID,
        profileID: toolProfileID,
        depth: 14.0,
        unit: .millimeter
    )
    let document = booleanPlanDocument(
        nodes: [
            targetProfileID: targetProfile,
            targetID: target,
            toolProfileID: toolProfile,
            toolID: tool,
        ],
        order: [targetProfileID, targetID, toolProfileID, toolID],
        dependencies: [
            DependencyEdge(source: targetProfileID, target: targetID),
            DependencyEdge(source: toolProfileID, target: toolID),
        ]
    )
    return BooleanPlanDocumentSetup(
        document: document,
        targetFeatureID: targetID,
        toolFeatureID: toolID
    )
}

private func booleanPlanConicalToolDocument(
    lowerRadius: Double = 6.0,
    lowerCoordinate: Double = -2.0,
    upperRadius: Double = 3.2,
    upperCoordinate: Double = 12.0
) -> BooleanPlanDocumentSetup {
    let targetProfileID = FeatureID()
    let targetID = FeatureID()
    let toolProfileID = FeatureID()
    let toolID = FeatureID()
    let targetProfile = booleanPlanProfileFeature(
        id: targetProfileID,
        sketch: booleanPlanRectangleSketch(
            width: 24.0,
            height: 24.0,
            centerX: 0.0,
            centerY: 0.0,
            unit: .millimeter,
            plane: .zx
        )
    )
    let target = booleanPlanExtrudeFeature(
        id: targetID,
        profileID: targetProfileID,
        depth: 10.0,
        unit: .millimeter
    )
    let toolProfile = booleanPlanProfileFeature(
        id: toolProfileID,
        sketch: booleanPlanConicalRevolveSketch(
            lowerRadius: lowerRadius,
            lowerCoordinate: lowerCoordinate,
            upperRadius: upperRadius,
            upperCoordinate: upperCoordinate
        )
    )
    let tool = FeatureNode(
        id: toolID,
        operation: .revolve(RevolveFeature(
            profile: ProfileReference(featureID: toolProfileID),
            axis: RevolveAxis(origin: .origin, direction: .unitY)
        )),
        inputs: [FeatureInput(featureID: toolProfileID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    let document = booleanPlanDocument(
        nodes: [
            targetProfileID: targetProfile,
            targetID: target,
            toolProfileID: toolProfile,
            toolID: tool,
        ],
        order: [targetProfileID, targetID, toolProfileID, toolID],
        dependencies: [
            DependencyEdge(source: targetProfileID, target: targetID),
            DependencyEdge(source: toolProfileID, target: toolID),
        ]
    )
    return BooleanPlanDocumentSetup(
        document: document,
        targetFeatureID: targetID,
        toolFeatureID: toolID
    )
}

private func booleanPlanConicalRevolveSketch(
    lowerRadius: Double,
    lowerCoordinate: Double,
    upperRadius: Double,
    upperCoordinate: Double
) -> Sketch {
    func point(_ radial: Double, _ axial: Double) -> SketchPoint {
        booleanPlanPoint(radial, axial, unit: .millimeter)
    }
    let axisLower = point(0.0, lowerCoordinate)
    let lowerRim = point(lowerRadius, lowerCoordinate)
    let upperRim = point(upperRadius, upperCoordinate)
    let axisUpper = point(0.0, upperCoordinate)
    let lowerID = SketchEntityID()
    let wallID = SketchEntityID()
    let upperID = SketchEntityID()
    let axisID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            lowerID: .line(SketchLine(start: axisLower, end: lowerRim)),
            wallID: .line(SketchLine(start: lowerRim, end: upperRim)),
            upperID: .line(SketchLine(start: upperRim, end: axisUpper)),
            axisID: .line(SketchLine(start: axisUpper, end: axisLower)),
        ],
        constraints: [
            .coincident(.lineEnd(lowerID), .lineStart(wallID)),
            .coincident(.lineEnd(wallID), .lineStart(upperID)),
            .coincident(.lineEnd(upperID), .lineStart(axisID)),
            .coincident(.lineEnd(axisID), .lineStart(lowerID)),
        ]
    )
}

private func booleanPlanDocument(
    nodes: [FeatureID: FeatureNode],
    order: [FeatureID],
    dependencies: [DependencyEdge]
) -> CADDocument {
    CADDocument(
        units: .millimeters,
        designGraph: DesignGraph(
            nodes: nodes,
            order: order,
            dependencies: dependencies,
            revision: DocumentRevision(1)
        )
    )
}

private func booleanPlanDocument(
    setup: BooleanPlanDocumentSetup,
    booleanID: FeatureID,
    operation: BooleanOperation,
    keepTools: Bool
) -> CADDocument {
    booleanPlanDocument(
        document: setup.document,
        booleanID: booleanID,
        targets: [setup.targetFeatureID],
        tool: setup.toolFeatureID,
        operation: operation,
        keepTools: keepTools
    )
}

private func booleanPlanDocument(
    setup: BooleanMultiTargetPlanDocumentSetup,
    booleanID: FeatureID,
    operation: BooleanOperation,
    keepTools: Bool
) -> CADDocument {
    booleanPlanDocument(
        document: setup.document,
        booleanID: booleanID,
        targets: setup.targetFeatureIDs,
        tool: setup.toolFeatureID,
        operation: operation,
        keepTools: keepTools
    )
}

private func booleanPlanDocument(
    document: CADDocument,
    booleanID: FeatureID,
    targets: [FeatureID],
    tool: FeatureID,
    operation: BooleanOperation,
    keepTools: Bool
) -> CADDocument {
    var document = document
    document.designGraph.nodes[booleanID] = FeatureNode(
        id: booleanID,
        operation: .boolean(BooleanFeature(
            targets: targets.map(BooleanTargetReference.init(featureID:)),
            tool: BooleanToolReference(featureID: tool),
            operation: operation,
            keepTools: keepTools
        )),
        inputs: targets.map { FeatureInput(featureID: $0, role: .target) }
            + [FeatureInput(featureID: tool, role: .body)],
        outputs: [FeatureOutput(role: .body)]
    )
    document.designGraph.order.append(booleanID)
    document.designGraph.dependencies.append(contentsOf: targets.map {
        DependencyEdge(source: $0, target: booleanID)
    })
    document.designGraph.dependencies.append(DependencyEdge(source: tool, target: booleanID))
    return document
}

private func expectPlannedTopologyNames(
    _ plan: BooleanEvaluationPlanResult,
    for featureID: FeatureID,
    in evaluated: EvaluatedDocument
) {
    let plannedSubshapeIDs = plan.topologySubshapeIDs(featureID: featureID)
    #expect(Set(plannedSubshapeIDs).count == plannedSubshapeIDs.count)
    for subshapeID in plannedSubshapeIDs {
        #expect(evaluated.subshapes[subshapeID] != nil)
    }
}

private func booleanPlanProfileFeature(id: FeatureID, sketch: Sketch) -> FeatureNode {
    FeatureNode(
        id: id,
        operation: .sketch(sketch),
        outputs: [FeatureOutput(role: .profile)]
    )
}

private func booleanPlanExtrudeFeature(
    id: FeatureID,
    profileID: FeatureID,
    depth: Double,
    unit: LengthUnit
) -> FeatureNode {
    FeatureNode(
        id: id,
        operation: .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: profileID),
            distance: .constant(.length(depth, unit: unit))
        )),
        inputs: [FeatureInput(featureID: profileID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
}

private func booleanPlanRectangleSketch(
    width: Double,
    height: Double,
    centerX: Double,
    centerY: Double,
    unit: LengthUnit,
    plane: SketchPlane = .xy
) -> Sketch {
    let halfWidth = width / 2.0
    let halfHeight = height / 2.0
    let bottomLeft = booleanPlanPoint(centerX - halfWidth, centerY - halfHeight, unit: unit)
    let bottomRight = booleanPlanPoint(centerX + halfWidth, centerY - halfHeight, unit: unit)
    let topRight = booleanPlanPoint(centerX + halfWidth, centerY + halfHeight, unit: unit)
    let topLeft = booleanPlanPoint(centerX - halfWidth, centerY + halfHeight, unit: unit)
    let bottomID = SketchEntityID()
    let rightID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()
    return Sketch(
        plane: plane,
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
        ]
    )
}

private func booleanPlanRotatedRectangleSketch(
    width: Double,
    height: Double,
    angle: Double,
    centerX: Double = 0.0,
    centerY: Double = 0.0,
    plane: SketchPlane,
    unit: LengthUnit
) -> Sketch {
    let cosine = cos(angle)
    let sine = sin(angle)
    let localPoints = [
        Point2D(x: -width * 0.5, y: -height * 0.5),
        Point2D(x: width * 0.5, y: -height * 0.5),
        Point2D(x: width * 0.5, y: height * 0.5),
        Point2D(x: -width * 0.5, y: height * 0.5),
    ]
    let points = localPoints.map { point in
        booleanPlanPoint(
            centerX + point.x * cosine - point.y * sine,
            centerY + point.x * sine + point.y * cosine,
            unit: unit
        )
    }
    let edgeIDs = (0..<4).map { _ in SketchEntityID() }
    var entities: [SketchEntityID: SketchEntity] = [:]
    var constraints: [SketchConstraint] = []
    for index in edgeIDs.indices {
        let next = (index + 1) % edgeIDs.count
        entities[edgeIDs[index]] = .line(SketchLine(
            start: points[index],
            end: points[next]
        ))
        constraints.append(.coincident(
            .lineEnd(edgeIDs[index]),
            .lineStart(edgeIDs[next])
        ))
    }
    return Sketch(plane: plane, entities: entities, constraints: constraints)
}

private func booleanPlanCircleSketch(
    radius: Double,
    centerX: Double = 0.0,
    centerY: Double = 0.0,
    unit: LengthUnit,
    plane: SketchPlane = .xy
) -> Sketch {
    Sketch(
        plane: plane,
        entities: [
            SketchEntityID(): .circle(SketchCircle(
                center: booleanPlanPoint(centerX, centerY, unit: unit),
                radius: .constant(.length(radius, unit: unit))
            )),
        ]
    )
}

private func booleanPlanPoint(_ x: Double, _ y: Double, unit: LengthUnit) -> SketchPoint {
    SketchPoint(
        x: .constant(.length(x, unit: unit)),
        y: .constant(.length(y, unit: unit))
    )
}
