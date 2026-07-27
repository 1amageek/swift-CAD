import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Foundation
import Testing
@testable import CADKernel

@Suite("Boolean Intersection Graph")
struct BooleanIntersectionGraphTests {
    func verifyUnequalCylinderSheetsReachBooleanIntersectionGraphWithDualPcurves() throws {
        let target = try cylinderSheet(
            stablePrefix: "target-cylinder",
            origin: .origin,
            axis: .unitZ,
            radius: 2.0,
            halfLength: 4.0
        )
        let tool = try cylinderSheet(
            stablePrefix: "tool-cylinder",
            origin: .origin,
            axis: .unitX,
            radius: 3.0,
            halfLength: 3.0
        )
        let model = try merged(target, tool)
        let targetBodyID = try #require(target.bodies.keys.first)
        let toolBodyID = try #require(tool.bodies.keys.first)
        let pipeline = BooleanPipeline(evaluator: RequiredIntersectionEvaluator())

        let graph = try pipeline.intersectionGraph(
            targetBodyIDs: [targetBodyID],
            toolBodyID: toolBodyID,
            operation: .intersect,
            model: model,
            tolerance: .standard
        )
        let repeated = try pipeline.intersectionGraph(
            targetBodyIDs: [targetBodyID],
            toolBodyID: toolBodyID,
            operation: .intersect,
            model: model,
            tolerance: .standard
        )

        #expect(graph == repeated)
        #expect(graph.facePairs.count == 1)
        #expect(graph.faceIntersections.count == 2)
        for faceIntersection in graph.faceIntersections {
            guard case let .curve(curve) = faceIntersection.geometry,
                  case .surfaceLift = curve.curve,
                  case .bSpline = curve.firstSurfaceParameterCurve,
                  case .bSpline = curve.secondSurfaceParameterCurve,
                  let targetFace = model.faces[faceIntersection.facePair.targetFaceID],
                  let toolFace = model.faces[faceIntersection.facePair.toolFaceID],
                  let targetSurface = model.geometry.surfaces[targetFace.surfaceID],
                  let toolSurface = model.geometry.surfaces[toolFace.surfaceID] else {
                Issue.record("General cylinder Boolean broad phase must retain certified surface-lift geometry with dual spline pcurves.")
                continue
            }
            #expect(curve.maximumResidual <= ModelingTolerance.standard.distance)
            try curve.firstSurfaceParameterCurve.validate(
                on: targetSurface,
                tolerance: .standard
            )
            try curve.secondSurfaceParameterCurve.validate(
                on: toolSurface,
                tolerance: .standard
            )
        }
        try graph.validate(in: model, tolerance: .standard)

        let splitGraph = try pipeline.uvSplitGraph(
            intersectionGraph: graph,
            model: model,
            tolerance: .standard
        )
        #expect(splitGraph.splits.count == 1)
        let split = try #require(splitGraph.splits.first)
        #expect(split.components.isEmpty == false)
        #expect(split.components.allSatisfy { component in
            if case .trimmedCurve = component.geometry { return true }
            return false
        })
        try splitGraph.validate(
            intersectionGraph: graph,
            model: model,
            tolerance: .standard
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func nestedBoxesProduceDeterministicVerifiedContacts() throws {
        let target = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument(
            width: 40.0,
            height: 40.0,
            depth: 10.0
        ))
        let tool = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument(
            width: 20.0,
            height: 20.0,
            depth: 10.0
        ))
        let model = try merged(target.brep, tool.brep)
        let targetBodyID = try #require(target.brep.bodies.keys.first)
        let toolBodyID = try #require(tool.brep.bodies.keys.first)
        let pipeline = BooleanPipeline(evaluator: ExactBRepBooleanEvaluator())

        let first = try pipeline.intersectionGraph(
            targetBodyIDs: [targetBodyID],
            toolBodyID: toolBodyID,
            operation: .difference,
            model: model,
            tolerance: .standard
        )
        let second = try pipeline.intersectionGraph(
            targetBodyIDs: [targetBodyID],
            toolBodyID: toolBodyID,
            operation: .difference,
            model: model,
            tolerance: .standard
        )

        #expect(first == second)
        #expect(first.facePairs.isEmpty == false)
        #expect(first.faceIntersections.isEmpty == false)
        #expect(first.faceIntersections.allSatisfy { intersection in
            switch intersection.geometry {
            case let .curve(value):
                return value.maximumResidual <= ModelingTolerance.standard.distance
            case let .point(value):
                return value.residual <= ModelingTolerance.standard.distance
            case let .coincident(value):
                return value.residual <= ModelingTolerance.standard.distance
            }
        })
        #expect(first.boundaryContacts.contains { contact in
            if case .points = contact.geometry { return true }
            return false
        })
        #expect(first.boundaryContacts.contains { contact in
            if case .coincident = contact.geometry { return true }
            return false
        })
        try first.validate(in: model, tolerance: .standard)

        let firstUV = try pipeline.uvSplitGraph(
            intersectionGraph: first,
            model: model,
            tolerance: .standard
        )
        let secondUV = try pipeline.uvSplitGraph(
            intersectionGraph: second,
            model: model,
            tolerance: .standard
        )
        #expect(firstUV == secondUV)
        #expect(firstUV.splits.contains { split in
            split.components.contains { component in
                if case .transverseSegment = component.geometry { return true }
                return false
            }
        })
        #expect(firstUV.splits.contains { split in
            split.components.contains { component in
                if case .coincident = component.geometry { return true }
                return false
            }
        })
        try firstUV.validate(intersectionGraph: first, model: model, tolerance: .standard)
        let classifications = try pipeline.classificationGraph(
            uvSplitGraph: firstUV,
            targetBodyIDs: [targetBodyID],
            toolBodyID: toolBodyID,
            model: model,
            tolerance: .standard
        )
        #expect(classifications.samples.isEmpty == false)
        #expect(classifications.samples.contains { $0.classification == .inside })
        #expect(classifications.samples.contains { $0.classification == .outside })
        try classifications.validate(uvSplitGraph: firstUV, model: model, tolerance: .standard)
        let selections = try pipeline.regionSelectionGraph(
            operation: .difference,
            classificationGraph: classifications,
            tolerance: .standard
        )
        #expect(selections.decisions.contains { $0.action == .keep })
        #expect(selections.decisions.contains { $0.action == .discard })
        #expect(selections.decisions.contains { $0.action == .keepReversed })
        try selections.validate(
            operation: .difference,
            classificationGraph: classifications,
            tolerance: .standard
        )
        if let firstDecision = selections.decisions.first {
            let wrongAction: BooleanRegionSelectionAction = firstDecision.action == .discard
                ? .keep
                : .discard
            let invalidSelections = BooleanRegionSelectionGraph(decisions: [
                BooleanRegionSelectionGraph.Decision(
                    sample: firstDecision.sample,
                    action: wrongAction
                ),
            ] + Array(selections.decisions.dropFirst()))
            #expect(throws: KernelError.self) {
                try invalidSelections.validate(
                    operation: .difference,
                    classificationGraph: classifications,
                    tolerance: .standard
                )
            }
        }
        let exactFeatureID = FeatureID()
        let exactSelection = try ExactBRepBooleanEvaluator().exactRegionSelection(
            operation: .difference,
            targetBodyIDs: [targetBodyID],
            toolBodyID: toolBodyID,
            featureID: exactFeatureID,
            model: model,
            subshapes: [:],
            uvSplitGraph: firstUV,
            regionSelectionGraph: selections,
            tolerance: .standard
        )
        try exactSelection.validate(
            operation: .difference,
            featureID: exactFeatureID,
            classificationGraph: classifications,
            tolerance: .standard
        )
        #expect(exactSelection.sewingRequest.shells.isEmpty == false)
        #expect(exactSelection.sewingRequest.shells.flatMap(\.patches).isEmpty == false)
        let selectedResult = try DefaultBRepSewer().sew(
            exactSelection.sewingRequest,
            tolerance: .standard
        )
        try selectedResult.brep.validate(level: .exact, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func disjointDifferenceHasEmptyGraphAndPreservesTarget() throws {
        let target = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument(
            width: 40.0,
            height: 20.0,
            depth: 10.0
        ))
        let translatedToolDocument = try makeRectangleExtrudeDocument(
            width: 10.0,
            height: 10.0,
            depth: 10.0
        ).translatingSources(
            by: Vector3D(x: 1.0, y: 0.0, z: 0.0),
            tolerance: .standard
        )
        let tool = try DocumentEvaluator(tolerance: .standard).evaluate(translatedToolDocument)
        let model = try merged(target.brep, tool.brep)
        let targetBodyID = try #require(target.brep.bodies.keys.first)
        let toolBodyID = try #require(tool.brep.bodies.keys.first)
        let pipeline = BooleanPipeline(evaluator: ExactBRepBooleanEvaluator())

        let graph = try pipeline.intersectionGraph(
            targetBodyIDs: [targetBodyID],
            toolBodyID: toolBodyID,
            operation: .difference,
            model: model,
            tolerance: .standard
        )
        #expect(graph.facePairs.isEmpty)
        #expect(graph.boundaryContacts.isEmpty)
        #expect(graph.faceIntersections.isEmpty)
        let uvGraph = try pipeline.uvSplitGraph(
            intersectionGraph: graph,
            model: model,
            tolerance: .standard
        )
        #expect(uvGraph.splits.isEmpty)
        let classificationGraph = try pipeline.classificationGraph(
            uvSplitGraph: uvGraph,
            targetBodyIDs: [targetBodyID],
            toolBodyID: toolBodyID,
            model: model,
            tolerance: .standard
        )
        let selectionGraph = try pipeline.regionSelectionGraph(
            operation: .difference,
            classificationGraph: classificationGraph,
            tolerance: .standard
        )
        #expect(selectionGraph.decisions.isEmpty)

        let featureID = FeatureID()
        let result = try pipeline.evaluate(
            operation: .difference,
            targetBodyIDs: [targetBodyID],
            toolBodyID: toolBodyID,
            keepTools: false,
            featureID: featureID,
            model: model,
            subshapes: [:],
            toolSubshapes: [:],
            tolerance: .standard
        )
        let repeated = try pipeline.evaluate(
            operation: .difference,
            targetBodyIDs: [targetBodyID],
            toolBodyID: toolBodyID,
            keepTools: false,
            featureID: featureID,
            model: model,
            subshapes: [:],
            toolSubshapes: [:],
            tolerance: .standard
        )
        #expect(result.brep == repeated.brep)
        #expect(result.subshapes == repeated.subshapes)
        #expect(result.lineage == repeated.lineage)
        #expect(result.brep.bodies.count == 1)
        try result.brep.validate(level: .exact, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func orthogonalSolidPointClassifierSeparatesInteriorBoundaryAndExterior() throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument(
            width: 40.0,
            height: 20.0,
            depth: 10.0
        ))
        let bodyID = try #require(evaluated.brep.bodies.keys.first)
        let classifier = OrthogonalSolidPointClassifier()

        #expect(try classifier.classify(
            Point3D(x: 0.0, y: 0.0, z: 0.005),
            in: bodyID,
            model: evaluated.brep,
            tolerance: .standard
        ) == .inside)
        #expect(try classifier.classify(
            Point3D(x: 0.020, y: 0.0, z: 0.005),
            in: bodyID,
            model: evaluated.brep,
            tolerance: .standard
        ) == .boundary)
        #expect(try classifier.classify(
            Point3D(x: 1.0, y: 0.0, z: 0.005),
            in: bodyID,
            model: evaluated.brep,
            tolerance: .standard
        ) == .outside)
    }

    @Test(.timeLimit(.minutes(1)))
    func booleanLineageDistinguishesMergedBodyAndSplitFaces() throws {
        let target = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument(
            width: 40.0,
            height: 20.0,
            depth: 10.0
        ))
        let tool = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument(
            width: 20.0,
            height: 20.0,
            depth: 10.0
        ))
        let model = try merged(target.brep, tool.brep)
        let targetBodyID = try #require(target.brep.bodies.keys.first)
        let toolBodyID = try #require(tool.brep.bodies.keys.first)
        let targetSubshapes = target.subshapes.entries
        let toolSubshapes = tool.subshapes.entries
        let inputSubshapes = targetSubshapes.merging(toolSubshapes) { current, _ in current }
        let inputLineage = target.lineage.merging(tool.lineage) { current, _ in current }

        let result = try BooleanPipeline(evaluator: ExactBRepBooleanEvaluator()).evaluate(
            operation: .difference,
            targetBodyIDs: [targetBodyID],
            toolBodyID: toolBodyID,
            keepTools: false,
            featureID: FeatureID(),
            model: model,
            subshapes: inputSubshapes,
            toolSubshapes: toolSubshapes,
            inputLineage: inputLineage,
            tolerance: .standard
        )

        let bodyLineage = try #require(result.lineage.values.first { $0.output.role == "body" })
        #expect(bodyLineage.relation == .merged)
        #expect(bodyLineage.parents.count == 2)
        #expect(result.lineage.values.contains { $0.relation == .split })
        #expect(result.lineage.values.allSatisfy { $0.isStructurallyValid })
        #expect(result.lineage.values.flatMap(\.parents).allSatisfy { inputLineage[$0] != nil })
        try result.brep.validate(level: .exact, tolerance: .standard)
    }

    private func merged(_ first: BRepModel, _ second: BRepModel) throws -> BRepModel {
        var result = first
        for (id, curve) in second.geometry.curves {
            guard result.geometry.curves[id] == nil else { throw duplicateID("curve") }
            result.geometry.curves[id] = curve
        }
        for (id, surface) in second.geometry.surfaces {
            guard result.geometry.surfaces[id] == nil else { throw duplicateID("surface") }
            result.geometry.surfaces[id] = surface
        }
        for (id, body) in second.bodies {
            guard result.bodies[id] == nil else { throw duplicateID("body") }
            result.bodies[id] = body
        }
        for (id, shell) in second.shells {
            guard result.shells[id] == nil else { throw duplicateID("shell") }
            result.shells[id] = shell
        }
        for (id, face) in second.faces {
            guard result.faces[id] == nil else { throw duplicateID("face") }
            result.faces[id] = face
        }
        for (id, loop) in second.loops {
            guard result.loops[id] == nil else { throw duplicateID("loop") }
            result.loops[id] = loop
        }
        for (id, edge) in second.edges {
            guard result.edges[id] == nil else { throw duplicateID("edge") }
            result.edges[id] = edge
        }
        for (id, vertex) in second.vertices {
            guard result.vertices[id] == nil else { throw duplicateID("vertex") }
            result.vertices[id] = vertex
        }
        try result.validate(tolerance: .standard)
        return result
    }

    private func cylinderSheet(
        stablePrefix: String,
        origin: Point3D,
        axis: Vector3D,
        radius: Double,
        halfLength: Double
    ) throws -> BRepModel {
        let surface = Surface3D.cylinder(Cylinder3D(
            origin: origin,
            axis: axis,
            radius: radius
        ))
        let lowerU = 0.0
        let upperU = Double.pi
        let lowerV = -halfLength
        let upperV = halfLength
        let bottomStart = try surface.point(u: lowerU, v: lowerV, tolerance: .standard)
        let bottomEnd = try surface.point(u: upperU, v: lowerV, tolerance: .standard)
        let topStart = try surface.point(u: upperU, v: upperV, tolerance: .standard)
        let topEnd = try surface.point(u: lowerU, v: upperV, tolerance: .standard)
        let bottomCenter = origin + axis * lowerV
        let topCenter = origin + axis * upperV
        let rightOffset = topStart - bottomEnd
        let leftOffset = bottomStart - topEnd
        let edges = [
            BRepSewingEdge(
                stableID: "\(stablePrefix):bottom",
                curve: .circle(Circle3D(center: bottomCenter, normal: axis, radius: radius)),
                startParameter: lowerU,
                endParameter: upperU,
                startPoint: bottomStart,
                endPoint: bottomEnd,
                surfaceParameterCurve: .constantV(
                    v: lowerV,
                    uStart: lowerU,
                    uEnd: upperU
                )
            ),
            BRepSewingEdge(
                stableID: "\(stablePrefix):right",
                curve: .line(Line3D(
                    origin: bottomEnd,
                    direction: try rightOffset.normalized(
                        tolerance: ModelingTolerance.standard.distance
                    )
                )),
                startParameter: 0.0,
                endParameter: rightOffset.length,
                startPoint: bottomEnd,
                endPoint: topStart,
                surfaceParameterCurve: .constantU(
                    u: upperU,
                    vStart: lowerV,
                    vEnd: upperV
                )
            ),
            BRepSewingEdge(
                stableID: "\(stablePrefix):top",
                curve: .circle(Circle3D(center: topCenter, normal: axis, radius: radius)),
                startParameter: upperU,
                endParameter: lowerU,
                startPoint: topStart,
                endPoint: topEnd,
                surfaceParameterCurve: .constantV(
                    v: upperV,
                    uStart: upperU,
                    uEnd: lowerU
                )
            ),
            BRepSewingEdge(
                stableID: "\(stablePrefix):left",
                curve: .line(Line3D(
                    origin: topEnd,
                    direction: try leftOffset.normalized(
                        tolerance: ModelingTolerance.standard.distance
                    )
                )),
                startParameter: 0.0,
                endParameter: leftOffset.length,
                startPoint: topEnd,
                endPoint: bottomStart,
                surfaceParameterCurve: .constantU(
                    u: lowerU,
                    vStart: upperV,
                    vEnd: lowerV
                )
            ),
        ]
        return try DefaultBRepSewer().sew(BRepSewingRequest(
            featureID: FeatureID(),
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "\(stablePrefix):shell",
                patches: [BRepSewingFacePatch(
                    stableID: "\(stablePrefix):face",
                    surface: surface,
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "\(stablePrefix):loop",
                        role: .outer,
                        edges: edges
                    )]
                )]
            )]
        ), tolerance: .standard).brep
    }

    private struct RequiredIntersectionEvaluator: BRepBooleanEvaluating {
        func exactRegionSelection(
            operation: BooleanOperation,
            targetBodyIDs: [BodyID],
            toolBodyID: BodyID,
            featureID: FeatureID,
            model: BRepModel,
            subshapes: [SubshapeID: TopologyReference],
            uvSplitGraph: BooleanUVSplitGraph,
            regionSelectionGraph: BooleanRegionSelectionGraph,
            tolerance: ModelingTolerance
        ) throws -> BooleanExactRegionSelectionGraph {
            throw unusedPhase(tolerance: tolerance)
        }

        func evaluate(
            operation: BooleanOperation,
            targetBodyIDs: [BodyID],
            toolBodyID: BodyID,
            keepTools: Bool,
            featureID: FeatureID,
            model: BRepModel,
            subshapes: [SubshapeID: TopologyReference],
            toolSubshapes: [SubshapeID: TopologyReference],
            intersectionGraph: BooleanIntersectionGraph,
            uvSplitGraph: BooleanUVSplitGraph,
            classificationGraph: BooleanClassificationGraph,
            exactRegionSelectionGraph: BooleanExactRegionSelectionGraph,
            tolerance: ModelingTolerance
        ) throws -> EvaluationResult {
            throw unusedPhase(tolerance: tolerance)
        }

        private func unusedPhase(tolerance: ModelingTolerance) -> KernelError {
            KernelError(
                phase: .evaluation,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "The broad-phase fixture does not invoke Boolean materialization."
            )
        }
    }

    private func duplicateID(_ kind: String) -> KernelError {
        KernelError(
            phase: .topology,
            code: .invalidInput,
            tolerance: .standard,
            message: "Boolean test model contains a duplicate \(kind) identifier."
        )
    }
}
