import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct EdgeOffsetFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving

    public init(
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()
    ) {
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
    }

    public func evaluate(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try evaluateUnvalidated(feature: feature, context: context)
        }
    }

    private func evaluateUnvalidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard case let .edgeOffset(edgeOffset) = feature.operation else {
            throw KernelError.unsupportedEvaluation(tolerance: context.tolerance, message:
                "EdgeOffsetFeatureEvaluator only supports edgeOffset."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try edgeOffset.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context.brep,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let distance = try resolvedDistance(edgeOffset.distance, context: context)
        var model = context.brep
        var topologyIDs = FeatureTopologyIDAllocator(featureID: feature.id)

        let bodyID = try targetBodyID(for: edgeOffset.target.featureID, context: context)
        let edgeID = try targetEdgeID(for: edgeOffset.edge, context: context)
        let supportFaceID = try targetFaceID(for: edgeOffset.supportFace, context: context)
        guard try body(bodyID, contains: supportFaceID, in: model) else {
            throw FeatureEvaluationError.missingInput("Edge offset support face is not on the target body.")
        }

        let result: EdgeOffsetEvaluationChange
        if edgeOffset.isSymmetric {
            let oppositeFaceID = try oppositeSupportFaceID(
                for: edgeID,
                excluding: supportFaceID,
                bodyID: bodyID,
                model: model,
                tolerance: context.tolerance
            )
            var primary = try splitConvexSupportFace(
                supportFaceID,
                selectedEdgeID: edgeID,
                distance: distance,
                featureID: feature.id,
                bodyID: bodyID,
                subshapeOrdinal: 0,
                contextSubshapes: context.subshapes.entries,
                tolerance: context.tolerance,
                topologyIDs: &topologyIDs,
                model: &model
            )
            let secondary = try splitConvexSupportFace(
                oppositeFaceID,
                selectedEdgeID: edgeID,
                distance: distance,
                featureID: feature.id,
                bodyID: bodyID,
                subshapeOrdinal: 1,
                contextSubshapes: context.subshapes.entries,
                tolerance: context.tolerance,
                topologyIDs: &topologyIDs,
                model: &model
            )
            try primary.merge(secondary)
            result = primary
        } else {
            result = try splitConvexSupportFace(
                supportFaceID,
                selectedEdgeID: edgeID,
                distance: distance,
                featureID: feature.id,
                bodyID: bodyID,
                subshapeOrdinal: 0,
                contextSubshapes: context.subshapes.entries,
                tolerance: context.tolerance,
                topologyIDs: &topologyIDs,
                model: &model
            )
        }
        return EvaluationResult(
            brep: model,
            subshapes: result.subshapes,
            removedSubshapeIDs: result.removedSubshapeIDs,
            lineage: result.lineage
        )
    }

    private func resolvedDistance(
        _ expression: CADExpression,
        context: EvaluationContext
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(
                operation: "edgeOffset.distance",
                expected: .length,
                actual: quantity.kind
            )
        }
        guard quantity.value > context.tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(quantity.value)
        }
        return quantity.value
    }

    private func targetBodyID(for featureID: FeatureID, context: EvaluationContext) throws -> BodyID {
        try context.bodyID(generatedBy: featureID)
    }

    private func targetEdgeID(
        for stableReference: StableSubshapeReference,
        context: EvaluationContext
    ) throws -> EdgeID {
        let reference = try subshapeResolver.topologyReference(
            for: stableReference,
            model: context.brep,
            subshapes: context.subshapes,
            lineage: context.lineage,
            tolerance: context.tolerance
        )
        guard case let .edge(edgeID) = reference else {
            throw FeatureEvaluationError.missingInput("Edge offset target edge could not be resolved.")
        }
        return edgeID
    }

    private func targetFaceID(
        for stableReference: StableSubshapeReference,
        context: EvaluationContext
    ) throws -> FaceID {
        let reference = try subshapeResolver.topologyReference(
            for: stableReference,
            model: context.brep,
            subshapes: context.subshapes,
            lineage: context.lineage,
            tolerance: context.tolerance
        )
        guard case let .face(faceID) = reference else {
            throw FeatureEvaluationError.missingInput("Edge offset support face could not be resolved.")
        }
        return faceID
    }

    private func body(_ bodyID: BodyID, contains faceID: FaceID, in model: BRepModel) throws -> Bool {
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Missing edge offset body \(bodyID).")
        }
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing edge offset shell \(shellID).")
            }
            if shell.faceIDs.contains(faceID) {
                return true
            }
        }
        return false
    }

    private func oppositeSupportFaceID(
        for selectedEdgeID: EdgeID,
        excluding supportFaceID: FaceID,
        bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> FaceID {
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Missing edge offset body \(bodyID).")
        }
        var candidates: [FaceID] = []
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing edge offset shell \(shellID).")
            }
            for faceID in shell.faceIDs where faceID != supportFaceID {
                guard let face = model.faces[faceID] else {
                    throw TopologyError.missingReference("Missing edge offset face \(faceID).")
                }
                if try faceContainsEdge(face, edgeID: selectedEdgeID, in: model) {
                    candidates.append(faceID)
                }
            }
        }
        guard candidates.count == 1, let faceID = candidates.first else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Symmetric edge offset requires exactly one opposite support face sharing the selected edge; found \(candidates.count)."
            )
        }
        return faceID
    }

    private func faceContainsEdge(
        _ face: Face,
        edgeID selectedEdgeID: EdgeID,
        in model: BRepModel
    ) throws -> Bool {
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                throw TopologyError.missingReference("Missing edge offset loop \(loopID).")
            }
            if loop.edges.contains(where: { $0.edgeID == selectedEdgeID }) {
                return true
            }
        }
        return false
    }

    private func splitConvexSupportFace(
        _ faceID: FaceID,
        selectedEdgeID: EdgeID,
        distance: Double,
        featureID: FeatureID,
        bodyID: BodyID,
        subshapeOrdinal: Int,
        contextSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance,
        topologyIDs: inout FeatureTopologyIDAllocator,
        model: inout BRepModel
    ) throws -> EdgeOffsetEvaluationChange {
        guard var face = model.faces[faceID] else {
            throw TopologyError.missingReference("Missing edge offset support face \(faceID).")
        }
        guard face.loops.count == 1,
              let loopID = face.loops.first,
              let loop = model.loops[loopID],
              loop.role == .outer else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Edge offset currently requires a support face with one outer loop."
            )
        }
        guard let surface = model.geometry.surfaces[face.surfaceID],
              case let .plane(plane) = surface else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Edge offset currently supports planar support faces only."
            )
        }
        try plane.validate(tolerance: tolerance)
        guard loop.edges.count >= 3 else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Edge offset requires at least three support face boundary edges."
            )
        }
        for orientedEdge in loop.edges {
            guard let edge = model.edges[orientedEdge.edgeID],
                  let curve = model.geometry.curves[edge.curveID],
                  case .line = curve else {
                throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                    "Edge offset requires a line-only planar support face."
                )
            }
        }
        guard let selectedIndex = loop.edges.firstIndex(where: { $0.edgeID == selectedEdgeID }) else {
            throw FeatureEvaluationError.missingInput("Edge offset selected edge is not on the support face.")
        }
        let contextIndex = SubshapeIndex(contextSubshapes)
        let parentResolver = LiveTopologyParentResolver()
        let bodyParent = try parentResolver.resolve(
            .body(bodyID),
            in: contextIndex,
            featureID: featureID,
            tolerance: tolerance
        )
        let faceParent = try parentResolver.resolve(
            .face(faceID),
            in: contextIndex,
            featureID: featureID,
            tolerance: tolerance
        )

        let frame = try PlanarFaceFrame(plane: plane, tolerance: tolerance)
        let outerPoints = try model.orderedPoints(for: loopID)
        let outer2D = outerPoints.map(frame.localPoint)
        let polygon = try StrictlyConvexPlanarLoop(points: outer2D, tolerance: tolerance)

        let selected = loop.edges[selectedIndex]
        let previous = loop.edges[(selectedIndex + loop.edges.count - 1) % loop.edges.count]
        let next = loop.edges[(selectedIndex + 1) % loop.edges.count]
        let offset = try polygon.offsetBoundary(
            edgeAt: selectedIndex,
            distance: distance,
            tolerance: tolerance
        )
        let offsetStart = frame.worldPoint(offset.start)
        let offsetEnd = frame.worldPoint(offset.end)

        try validateSplitPoint(offsetStart, liesOn: previous.edgeID, in: model, tolerance: tolerance)
        try validateSplitPoint(offsetEnd, liesOn: next.edgeID, in: model, tolerance: tolerance)

        let previousSplit = try splitBoundaryEdge(
            previous.edgeID,
            at: offsetStart,
            parentSubshapeID: try parentResolver.resolve(
                .edge(previous.edgeID),
                in: contextIndex,
                featureID: featureID,
                tolerance: tolerance
            ),
            featureID: featureID,
            subshapePrefix: "previous",
            subshapeOrdinal: subshapeOrdinal,
            model: &model,
            tolerance: tolerance,
            topologyIDs: &topologyIDs
        )
        let nextSplit = try splitBoundaryEdge(
            next.edgeID,
            at: offsetEnd,
            parentSubshapeID: try parentResolver.resolve(
                .edge(next.edgeID),
                in: contextIndex,
                featureID: featureID,
                tolerance: tolerance
            ),
            featureID: featureID,
            subshapePrefix: "next",
            subshapeOrdinal: subshapeOrdinal,
            model: &model,
            tolerance: tolerance,
            topologyIDs: &topologyIDs
        )
        try replaceEdge(previous.edgeID, with: previousSplit, in: &model, tolerance: tolerance)
        try replaceEdge(next.edgeID, with: nextSplit, in: &model, tolerance: tolerance)

        let offsetEdgeID = try addLineEdge(
            startVertexID: previousSplit.splitVertexID,
            endVertexID: nextSplit.splitVertexID,
            start: offsetStart,
            end: offsetEnd,
            model: &model,
            tolerance: tolerance,
            topologyIDs: &topologyIDs
        )
        let previousSegments = orientedSegments(for: previous, split: previousSplit)
        let nextSegments = orientedSegments(for: next, split: nextSplit)

        let stripLoopID = topologyIDs.nextLoopID()
        let remainderLoopID = topologyIDs.nextLoopID()
        let stripEdges = try planarCoedges(
            [
                selected,
                nextSegments.first,
                Coedge(edgeID: offsetEdgeID, orientation: .reversed),
                previousSegments.second,
            ],
            frame: frame,
            model: model
        )
        var remainderBoundary = [
            Coedge(edgeID: offsetEdgeID, orientation: .forward),
            nextSegments.second,
        ]
        let previousIndex = (selectedIndex + loop.edges.count - 1) % loop.edges.count
        var middleIndex = (selectedIndex + 2) % loop.edges.count
        while middleIndex != previousIndex {
            remainderBoundary.append(loop.edges[middleIndex])
            middleIndex = (middleIndex + 1) % loop.edges.count
        }
        remainderBoundary.append(previousSegments.first)
        let remainderEdges = try planarCoedges(
            remainderBoundary,
            frame: frame,
            model: model
        )
        model.loops[stripLoopID] = Loop(
            id: stripLoopID,
            role: .outer,
            edges: stripEdges
        )
        model.loops[remainderLoopID] = Loop(
            id: remainderLoopID,
            role: .outer,
            edges: remainderEdges
        )
        model.loops.removeValue(forKey: loopID)

        let remainderFaceID = topologyIDs.nextFaceID()
        face.loops = [stripLoopID]
        model.faces[faceID] = face
        model.faces[remainderFaceID] = Face(
            id: remainderFaceID,
            surfaceID: face.surfaceID,
            loops: [remainderLoopID],
            orientation: face.orientation
        )
        try append(remainderFaceID, after: faceID, in: &model)

        let previousOriginalCurveID = previousSplit.originalCurveID
        let nextOriginalCurveID = nextSplit.originalCurveID
        model.edges.removeValue(forKey: previous.edgeID)
        model.edges.removeValue(forKey: next.edgeID)
        model.geometry.curves.removeValue(forKey: previousOriginalCurveID)
        model.geometry.curves.removeValue(forKey: nextOriginalCurveID)

        var subshapes = previousSplit.subshapes
        var lineage = previousSplit.lineage
        for (subshapeID, reference) in nextSplit.subshapes {
            subshapes[subshapeID] = reference
        }
        for (subshapeID, entry) in nextSplit.lineage {
            lineage[subshapeID] = entry
        }
        let bodyOutput = SubshapeID(
            featureID: featureID,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        )
        let stripFaceOutput = subshapeID(featureID, "stripFace", subshapeOrdinal)
        let remainderFaceOutput = subshapeID(featureID, "remainderFace", subshapeOrdinal)
        let offsetEdgeOutput = subshapeID(featureID, "offsetEdge", subshapeOrdinal)
        subshapes[bodyOutput] = .body(bodyID)
        subshapes[stripFaceOutput] = .face(faceID)
        subshapes[remainderFaceOutput] = .face(remainderFaceID)
        subshapes[offsetEdgeOutput] = .edge(offsetEdgeID)
        lineage[bodyOutput] = TopologyLineage(
            output: bodyOutput,
            parents: [bodyParent],
            relation: .preserved
        )
        lineage[stripFaceOutput] = TopologyLineage(
            output: stripFaceOutput,
            parents: [faceParent],
            relation: .split
        )
        lineage[remainderFaceOutput] = TopologyLineage(
            output: remainderFaceOutput,
            parents: [faceParent],
            relation: .split
        )
        lineage[offsetEdgeOutput] = TopologyLineage(
            output: offsetEdgeOutput,
            relation: .generated
        )

        var removedSubshapeIDs = subshapeIDsReferencing(
            edgeIDs: [previous.edgeID, next.edgeID],
            contextSubshapes: contextSubshapes
        )
        removedSubshapeIDs.formUnion([bodyParent, faceParent])
        return EdgeOffsetEvaluationChange(
            subshapes: subshapes,
            removedSubshapeIDs: removedSubshapeIDs,
            lineage: lineage
        )
    }

    private func splitBoundaryEdge(
        _ edgeID: EdgeID,
        at splitPoint: Point3D,
        parentSubshapeID: SubshapeID,
        featureID: FeatureID,
        subshapePrefix: String,
        subshapeOrdinal: Int,
        model: inout BRepModel,
        tolerance: ModelingTolerance,
        topologyIDs: inout FeatureTopologyIDAllocator
    ) throws -> BoundaryEdgeSplit {
        guard let edge = model.edges[edgeID] else {
            throw TopologyError.missingReference("Missing edge offset boundary edge \(edgeID).")
        }
        let start = try point(edge.startVertexID, in: model)
        let end = try point(edge.endVertexID, in: model)
        let totalLength = (end - start).length
        let firstLength = (splitPoint - start).length
        guard totalLength > tolerance.distance,
              firstLength > tolerance.distance,
              totalLength - firstLength > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(firstLength)
        }
        let splitFraction = firstLength / totalLength
        let splitVertexID = topologyIDs.nextVertexID()
        model.vertices[splitVertexID] = Vertex(id: splitVertexID, point: splitPoint)
        let firstEdgeID = try addLineEdge(
            startVertexID: edge.startVertexID,
            endVertexID: splitVertexID,
            start: start,
            end: splitPoint,
            model: &model,
            tolerance: tolerance,
            topologyIDs: &topologyIDs
        )
        let secondEdgeID = try addLineEdge(
            startVertexID: splitVertexID,
            endVertexID: edge.endVertexID,
            start: splitPoint,
            end: end,
            model: &model,
            tolerance: tolerance,
            topologyIDs: &topologyIDs
        )
        let splitVertexOutput = subshapeID(
            featureID,
            "\(subshapePrefix)SplitVertex",
            subshapeOrdinal
        )
        let firstEdgeOutput = subshapeID(
            featureID,
            "\(subshapePrefix)FirstEdge",
            subshapeOrdinal
        )
        let secondEdgeOutput = subshapeID(
            featureID,
            "\(subshapePrefix)SecondEdge",
            subshapeOrdinal
        )
        return BoundaryEdgeSplit(
            originalEdgeID: edgeID,
            originalCurveID: edge.curveID,
            splitVertexID: splitVertexID,
            firstEdgeID: firstEdgeID,
            secondEdgeID: secondEdgeID,
            splitFraction: splitFraction,
            subshapes: [
                splitVertexOutput: .vertex(splitVertexID),
                firstEdgeOutput: .edge(firstEdgeID),
                secondEdgeOutput: .edge(secondEdgeID),
            ],
            lineage: [
                splitVertexOutput: TopologyLineage(
                    output: splitVertexOutput,
                    relation: .generated
                ),
                firstEdgeOutput: TopologyLineage(
                    output: firstEdgeOutput,
                    parents: [parentSubshapeID],
                    relation: .split
                ),
                secondEdgeOutput: TopologyLineage(
                    output: secondEdgeOutput,
                    parents: [parentSubshapeID],
                    relation: .split
                ),
            ]
        )
    }

    private func addLineEdge(
        startVertexID: VertexID,
        endVertexID: VertexID,
        start: Point3D,
        end: Point3D,
        model: inout BRepModel,
        tolerance: ModelingTolerance,
        topologyIDs: inout FeatureTopologyIDAllocator
    ) throws -> EdgeID {
        let length = (end - start).length
        guard length > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(length)
        }
        let direction = try (end - start).normalized(tolerance: tolerance.distance)
        let curveID = topologyIDs.nextCurveID()
        let edgeID = topologyIDs.nextEdgeID()
        model.geometry.curves[curveID] = .line(Line3D(origin: start, direction: direction))
        model.edges[edgeID] = Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: startVertexID,
            endVertexID: endVertexID,
            trim: CurveTrim(startParameter: 0.0, endParameter: length)
        )
        return edgeID
    }

    private func replaceEdge(
        _ edgeID: EdgeID,
        with split: BoundaryEdgeSplit,
        in model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        for (loopID, var loop) in model.loops {
            var edges: [Coedge] = []
            edges.reserveCapacity(loop.edges.count + 1)
            for orientedEdge in loop.edges {
                guard orientedEdge.edgeID == edgeID else {
                    edges.append(orientedEdge)
                    continue
                }
                let parameterCurves = try splitParameterCurves(
                    for: orientedEdge,
                    split: split,
                    tolerance: tolerance
                )
                switch orientedEdge.orientation {
                case .forward:
                    edges.append(Coedge(
                        edgeID: split.firstEdgeID,
                        orientation: .forward,
                        surfaceParameterCurve: parameterCurves.first
                    ))
                    edges.append(Coedge(
                        edgeID: split.secondEdgeID,
                        orientation: .forward,
                        surfaceParameterCurve: parameterCurves.second
                    ))
                case .reversed:
                    edges.append(Coedge(
                        edgeID: split.secondEdgeID,
                        orientation: .reversed,
                        surfaceParameterCurve: parameterCurves.first
                    ))
                    edges.append(Coedge(
                        edgeID: split.firstEdgeID,
                        orientation: .reversed,
                        surfaceParameterCurve: parameterCurves.second
                    ))
                }
            }
            loop.edges = edges
            model.loops[loopID] = loop
        }
    }

    private func splitParameterCurves(
        for coedge: Coedge,
        split: BoundaryEdgeSplit,
        tolerance: ModelingTolerance
    ) throws -> (first: SurfaceParameterCurve?, second: SurfaceParameterCurve?) {
        guard let parameterCurve = coedge.surfaceParameterCurve else {
            return (nil, nil)
        }
        let traversalFraction = coedge.orientation == .forward
            ? split.splitFraction
            : 1.0 - split.splitFraction
        return (
            try parameterCurve.subcurve(
                fromNormalizedFraction: 0.0,
                toNormalizedFraction: traversalFraction,
                tolerance: tolerance
            ),
            try parameterCurve.subcurve(
                fromNormalizedFraction: traversalFraction,
                toNormalizedFraction: 1.0,
                tolerance: tolerance
            )
        )
    }

    private func orientedSegments(
        for orientedEdge: Coedge,
        split: BoundaryEdgeSplit
    ) -> (first: Coedge, second: Coedge) {
        switch orientedEdge.orientation {
        case .forward:
            return (
                Coedge(edgeID: split.firstEdgeID, orientation: .forward),
                Coedge(edgeID: split.secondEdgeID, orientation: .forward)
            )
        case .reversed:
            return (
                Coedge(edgeID: split.secondEdgeID, orientation: .reversed),
                Coedge(edgeID: split.firstEdgeID, orientation: .reversed)
            )
        }
    }

    private func planarCoedges(
        _ coedges: [Coedge],
        frame: PlanarFaceFrame,
        model: BRepModel
    ) throws -> [Coedge] {
        try coedges.map { coedge in
            let start = frame.localPoint(try point(startVertexID(for: coedge, in: model), in: model))
            let end = frame.localPoint(try point(endVertexID(for: coedge, in: model), in: model))
            return Coedge(
                edgeID: coedge.edgeID,
                orientation: coedge.orientation,
                surfaceParameterCurve: .affine(
                    origin: start,
                    direction: Point2D(x: end.x - start.x, y: end.y - start.y),
                    startParameter: 0.0,
                    endParameter: 1.0
                )
            )
        }
    }

    private func append(_ insertedFaceID: FaceID, after faceID: FaceID, in model: inout BRepModel) throws {
        for (shellID, var shell) in model.shells {
            guard let index = shell.faceIDs.firstIndex(of: faceID) else {
                continue
            }
            shell.faceIDs.insert(insertedFaceID, at: shell.faceIDs.index(after: index))
            model.shells[shellID] = shell
            return
        }
        throw TopologyError.missingReference("Edge offset shell for face \(faceID) was not found.")
    }

    private func validateSplitPoint(
        _ splitPoint: Point3D,
        liesOn edgeID: EdgeID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        guard let edge = model.edges[edgeID] else {
            throw TopologyError.missingReference("Missing edge offset boundary edge \(edgeID).")
        }
        let start = try point(edge.startVertexID, in: model)
        let end = try point(edge.endVertexID, in: model)
        let total = (end - start).length
        let first = (splitPoint - start).length
        let second = (end - splitPoint).length
        guard first > tolerance.distance,
              second > tolerance.distance,
              abs((first + second) - total) <= max(tolerance.distance, total * 1.0e-8) else {
            throw FeatureEvaluationError.invalidDistance(first)
        }
    }

    private func point(_ vertexID: VertexID, in model: BRepModel) throws -> Point3D {
        guard let vertex = model.vertices[vertexID] else {
            throw TopologyError.missingReference("Missing edge offset vertex \(vertexID).")
        }
        return vertex.point
    }

    private func startVertexID(for orientedEdge: Coedge, in model: BRepModel) throws -> VertexID {
        guard let edge = model.edges[orientedEdge.edgeID] else {
            throw TopologyError.missingReference("Missing edge offset edge \(orientedEdge.edgeID).")
        }
        switch orientedEdge.orientation {
        case .forward:
            return edge.startVertexID
        case .reversed:
            return edge.endVertexID
        }
    }

    private func endVertexID(for orientedEdge: Coedge, in model: BRepModel) throws -> VertexID {
        guard let edge = model.edges[orientedEdge.edgeID] else {
            throw TopologyError.missingReference("Missing edge offset edge \(orientedEdge.edgeID).")
        }
        switch orientedEdge.orientation {
        case .forward:
            return edge.endVertexID
        case .reversed:
            return edge.startVertexID
        }
    }

    private func subshapeIDsReferencing(
        edgeIDs: Set<EdgeID>,
        contextSubshapes: [SubshapeID: TopologyReference]
    ) -> Set<SubshapeID> {
        Set(contextSubshapes.compactMap { subshapeID, reference in
            guard case let .edge(edgeID) = reference,
                  edgeIDs.contains(edgeID) else {
                return nil
            }
            return subshapeID
        })
    }

    private func subshapeID(_ featureID: FeatureID, _ role: String, _ ordinal: Int) -> SubshapeID {
        SubshapeID(
            featureID: featureID,
            role: SubshapeIdentityRole.compose(
                generatedRole: "edgeOffset",
                subshapeRole: role
            ),
            ordinal: ordinal
        )
    }
}
