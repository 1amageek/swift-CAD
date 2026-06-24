import Foundation
import CADCore
import CADIR

public struct EdgeOffsetFeatureEvaluator: FeatureEvaluating {
    private let resolver: ParameterResolving

    public init(resolver: ParameterResolving = ParameterResolver()) {
        self.resolver = resolver
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .edgeOffset(edgeOffset) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation(
                "EdgeOffsetFeatureEvaluator only supports edgeOffset."
            )
        }
        let distance = try resolvedDistance(edgeOffset.distance, context: context)
        var model = context.brep

        let bodyID = try targetBodyID(for: edgeOffset.target.featureID, context: context)
        let edgeID = try targetEdgeID(for: edgeOffset.edgePersistentName, context: context)
        let supportFaceID = try targetFaceID(for: edgeOffset.supportFacePersistentName, context: context)
        guard try body(bodyID, contains: supportFaceID, in: model) else {
            throw FeatureEvaluationError.missingInput("Edge offset support face is not on the target body.")
        }

        let result: EdgeOffsetEvaluationChange
        if edgeOffset.isSymmetric {
            let oppositeFaceID = try oppositeSupportFaceID(
                for: edgeID,
                excluding: supportFaceID,
                bodyID: bodyID,
                model: model
            )
            var primary = try splitRectangularSupportFace(
                supportFaceID,
                selectedEdgeID: edgeID,
                distance: distance,
                featureID: feature.id,
                bodyID: bodyID,
                generatedNameIndex: 0,
                contextGeneratedNames: context.generatedNames,
                tolerance: context.tolerance,
                model: &model
            )
            let secondary = try splitRectangularSupportFace(
                oppositeFaceID,
                selectedEdgeID: edgeID,
                distance: distance,
                featureID: feature.id,
                bodyID: bodyID,
                generatedNameIndex: 1,
                contextGeneratedNames: context.generatedNames,
                tolerance: context.tolerance,
                model: &model
            )
            primary.merge(secondary)
            result = primary
        } else {
            result = try splitRectangularSupportFace(
                supportFaceID,
                selectedEdgeID: edgeID,
                distance: distance,
                featureID: feature.id,
                bodyID: bodyID,
                generatedNameIndex: nil,
                contextGeneratedNames: context.generatedNames,
                tolerance: context.tolerance,
                model: &model
            )
        }
        return EvaluationResult(
            brep: model,
            generatedNames: result.generatedNames,
            removedGeneratedNames: result.removedGeneratedNames
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
        let name = PersistentName(components: [.feature(featureID), .generated(GeneratedSubshapeRole.body.rawValue)])
        guard let reference = context.generatedNames[name],
              case let .body(bodyID) = reference else {
            throw FeatureEvaluationError.missingInput("Edge offset target body could not be resolved.")
        }
        return bodyID
    }

    private func targetEdgeID(for persistentName: PersistentName, context: EvaluationContext) throws -> EdgeID {
        guard let reference = context.generatedNames[persistentName],
              case let .edge(edgeID) = reference else {
            throw FeatureEvaluationError.missingInput("Edge offset target edge could not be resolved.")
        }
        return edgeID
    }

    private func targetFaceID(for persistentName: PersistentName, context: EvaluationContext) throws -> FaceID {
        guard let reference = context.generatedNames[persistentName],
              case let .face(faceID) = reference else {
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
        model: BRepModel
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
            throw FeatureEvaluationError.unsupportedOperation(
                "Symmetric edge offset requires exactly one opposite support face sharing the selected edge."
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

    private func splitRectangularSupportFace(
        _ faceID: FaceID,
        selectedEdgeID: EdgeID,
        distance: Double,
        featureID: FeatureID,
        bodyID: BodyID,
        generatedNameIndex: Int?,
        contextGeneratedNames: [PersistentName: TopologyReference],
        tolerance: ModelingTolerance,
        model: inout BRepModel
    ) throws -> EdgeOffsetEvaluationChange {
        guard var face = model.faces[faceID] else {
            throw TopologyError.missingReference("Missing edge offset support face \(faceID).")
        }
        guard face.loops.count == 1,
              let loopID = face.loops.first,
              let loop = model.loops[loopID],
              loop.role == .outer else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Edge offset currently requires a support face with one outer loop."
            )
        }
        guard let surface = model.geometry.surfaces[face.surfaceID],
              case let .plane(plane) = surface else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Edge offset currently supports planar support faces only."
            )
        }
        try plane.validate(tolerance: tolerance)
        guard loop.edges.count == 4 else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Edge offset currently requires a rectangular four-edge support face."
            )
        }
        for orientedEdge in loop.edges {
            guard let edge = model.edges[orientedEdge.edgeID],
                  let curve = model.geometry.curves[edge.curveID],
                  case .line = curve else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Edge offset currently requires line-only rectangular support faces."
                )
            }
        }
        guard let selectedIndex = loop.edges.firstIndex(where: { $0.edgeID == selectedEdgeID }) else {
            throw FeatureEvaluationError.missingInput("Edge offset selected edge is not on the support face.")
        }

        let frame = try EdgeOffsetFaceFrame(plane: plane, tolerance: tolerance)
        let outerPoints = try model.orderedPoints(for: loopID)
        let outer2D = outerPoints.map(frame.localPoint)
        try validateRectangularLoop(outer2D, tolerance: tolerance)

        let selected = loop.edges[selectedIndex]
        let previous = loop.edges[(selectedIndex + loop.edges.count - 1) % loop.edges.count]
        let next = loop.edges[(selectedIndex + 1) % loop.edges.count]
        let opposite = loop.edges[(selectedIndex + 2) % loop.edges.count]

        let selectedStart = try point(startVertexID(for: selected, in: model), in: model)
        let selectedEnd = try point(endVertexID(for: selected, in: model), in: model)
        let selectedStart2D = frame.localPoint(selectedStart)
        let selectedEnd2D = frame.localPoint(selectedEnd)
        let offset = try offsetSegment(
            start: selectedStart2D,
            end: selectedEnd2D,
            polygon: outer2D,
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
            featureID: featureID,
            subshapePrefix: "previous",
            generatedNameIndex: generatedNameIndex,
            model: &model,
            tolerance: tolerance
        )
        let nextSplit = try splitBoundaryEdge(
            next.edgeID,
            at: offsetEnd,
            featureID: featureID,
            subshapePrefix: "next",
            generatedNameIndex: generatedNameIndex,
            model: &model,
            tolerance: tolerance
        )
        replaceEdge(previous.edgeID, with: previousSplit, in: &model)
        replaceEdge(next.edgeID, with: nextSplit, in: &model)

        let offsetEdgeID = try addLineEdge(
            startVertexID: previousSplit.splitVertexID,
            endVertexID: nextSplit.splitVertexID,
            start: offsetStart,
            end: offsetEnd,
            model: &model,
            tolerance: tolerance
        )
        let previousSegments = orientedSegments(for: previous, split: previousSplit)
        let nextSegments = orientedSegments(for: next, split: nextSplit)

        let stripLoopID = LoopID()
        let remainderLoopID = LoopID()
        model.loops[stripLoopID] = Loop(
            id: stripLoopID,
            role: .outer,
            edges: [
                selected,
                nextSegments.first,
                OrientedEdge(edgeID: offsetEdgeID, orientation: .reversed),
                previousSegments.second,
            ]
        )
        model.loops[remainderLoopID] = Loop(
            id: remainderLoopID,
            role: .outer,
            edges: [
                OrientedEdge(edgeID: offsetEdgeID, orientation: .forward),
                nextSegments.second,
                opposite,
                previousSegments.first,
            ]
        )
        model.loops.removeValue(forKey: loopID)

        let remainderFaceID = FaceID()
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

        var generatedNames = previousSplit.generatedNames
        for (name, reference) in nextSplit.generatedNames {
            generatedNames[name] = reference
        }
        generatedNames[PersistentName(components: [
            .feature(featureID),
            .generated(GeneratedSubshapeRole.body.rawValue),
        ])] = .body(bodyID)
        generatedNames[persistentName(featureID, "offsetEdge", generatedNameIndex)] = .edge(offsetEdgeID)
        generatedNames[persistentName(featureID, "remainderFace", generatedNameIndex)] = .face(remainderFaceID)

        let removedGeneratedNames = generatedNamesReferencing(
            edgeIDs: [previous.edgeID, next.edgeID],
            contextGeneratedNames: contextGeneratedNames
        )
        return EdgeOffsetEvaluationChange(
            generatedNames: generatedNames,
            removedGeneratedNames: removedGeneratedNames
        )
    }

    private func splitBoundaryEdge(
        _ edgeID: EdgeID,
        at splitPoint: Point3D,
        featureID: FeatureID,
        subshapePrefix: String,
        generatedNameIndex: Int?,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BoundaryEdgeSplit {
        guard let edge = model.edges[edgeID] else {
            throw TopologyError.missingReference("Missing edge offset boundary edge \(edgeID).")
        }
        let start = try point(edge.startVertexID, in: model)
        let end = try point(edge.endVertexID, in: model)
        let splitVertexID = VertexID()
        model.vertices[splitVertexID] = Vertex(id: splitVertexID, point: splitPoint)
        let firstEdgeID = try addLineEdge(
            startVertexID: edge.startVertexID,
            endVertexID: splitVertexID,
            start: start,
            end: splitPoint,
            model: &model,
            tolerance: tolerance
        )
        let secondEdgeID = try addLineEdge(
            startVertexID: splitVertexID,
            endVertexID: edge.endVertexID,
            start: splitPoint,
            end: end,
            model: &model,
            tolerance: tolerance
        )
        return BoundaryEdgeSplit(
            originalEdgeID: edgeID,
            originalCurveID: edge.curveID,
            splitVertexID: splitVertexID,
            firstEdgeID: firstEdgeID,
            secondEdgeID: secondEdgeID,
            generatedNames: [
                persistentName(featureID, "\(subshapePrefix)SplitVertex", generatedNameIndex): .vertex(splitVertexID),
                persistentName(featureID, "\(subshapePrefix)FirstEdge", generatedNameIndex): .edge(firstEdgeID),
                persistentName(featureID, "\(subshapePrefix)SecondEdge", generatedNameIndex): .edge(secondEdgeID),
            ]
        )
    }

    private func addLineEdge(
        startVertexID: VertexID,
        endVertexID: VertexID,
        start: Point3D,
        end: Point3D,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws -> EdgeID {
        let length = (end - start).length
        guard length > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(length)
        }
        let direction = try (end - start).normalized(tolerance: tolerance.distance)
        let curveID = CurveID()
        let edgeID = EdgeID()
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

    private func replaceEdge(_ edgeID: EdgeID, with split: BoundaryEdgeSplit, in model: inout BRepModel) {
        for (loopID, var loop) in model.loops {
            var edges: [OrientedEdge] = []
            edges.reserveCapacity(loop.edges.count + 1)
            for orientedEdge in loop.edges {
                guard orientedEdge.edgeID == edgeID else {
                    edges.append(orientedEdge)
                    continue
                }
                switch orientedEdge.orientation {
                case .forward:
                    edges.append(OrientedEdge(edgeID: split.firstEdgeID, orientation: .forward))
                    edges.append(OrientedEdge(edgeID: split.secondEdgeID, orientation: .forward))
                case .reversed:
                    edges.append(OrientedEdge(edgeID: split.secondEdgeID, orientation: .reversed))
                    edges.append(OrientedEdge(edgeID: split.firstEdgeID, orientation: .reversed))
                }
            }
            loop.edges = edges
            model.loops[loopID] = loop
        }
    }

    private func orientedSegments(
        for orientedEdge: OrientedEdge,
        split: BoundaryEdgeSplit
    ) -> (first: OrientedEdge, second: OrientedEdge) {
        switch orientedEdge.orientation {
        case .forward:
            return (
                OrientedEdge(edgeID: split.firstEdgeID, orientation: .forward),
                OrientedEdge(edgeID: split.secondEdgeID, orientation: .forward)
            )
        case .reversed:
            return (
                OrientedEdge(edgeID: split.secondEdgeID, orientation: .reversed),
                OrientedEdge(edgeID: split.firstEdgeID, orientation: .reversed)
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

    private func offsetSegment(
        start: Point2D,
        end: Point2D,
        polygon: [Point2D],
        distance: Double,
        tolerance: ModelingTolerance
    ) throws -> (start: Point2D, end: Point2D) {
        let direction = try normalized(Point2D(x: end.x - start.x, y: end.y - start.y), tolerance: tolerance)
        let signedArea = polygonSignedArea(polygon)
        guard abs(signedArea) > tolerance.distance * tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(abs(signedArea))
        }
        let sign = signedArea >= 0.0 ? 1.0 : -1.0
        let inward = Point2D(x: -direction.y * sign, y: direction.x * sign)
        let offsetStart = Point2D(x: start.x + inward.x * distance, y: start.y + inward.y * distance)
        let offsetEnd = Point2D(x: end.x + inward.x * distance, y: end.y + inward.y * distance)
        guard point(offsetStart, isInside: polygon, tolerance: tolerance),
              point(offsetEnd, isInside: polygon, tolerance: tolerance) else {
            throw FeatureEvaluationError.invalidDistance(distance)
        }
        return (offsetStart, offsetEnd)
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

    private func validateRectangularLoop(_ points: [Point2D], tolerance: ModelingTolerance) throws {
        guard points.count == 4 else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Edge offset currently requires four polygon points."
            )
        }
        let angularTolerance = max(tolerance.angle, 1.0e-8)
        var directions: [Point2D] = []
        var lengths: [Double] = []
        directions.reserveCapacity(points.count)
        lengths.reserveCapacity(points.count)
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let direction = Point2D(x: next.x - current.x, y: next.y - current.y)
            let length = hypot(direction.x, direction.y)
            guard length > tolerance.distance else {
                throw FeatureEvaluationError.invalidDistance(length)
            }
            directions.append(direction)
            lengths.append(length)
        }
        for index in directions.indices {
            let next = (index + 1) % directions.count
            let normalizedDot = abs(dot(directions[index], directions[next])) / (lengths[index] * lengths[next])
            guard normalizedDot <= angularTolerance else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Edge offset currently requires perpendicular adjacent rectangular edges."
                )
            }
        }
        for index in 0..<2 {
            let opposite = index + 2
            let normalizedCross = abs(cross(directions[index], directions[opposite])) /
                (lengths[index] * lengths[opposite])
            guard normalizedCross <= angularTolerance else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Edge offset currently requires parallel opposite rectangular edges."
                )
            }
        }
    }

    private func point(_ vertexID: VertexID, in model: BRepModel) throws -> Point3D {
        guard let vertex = model.vertices[vertexID] else {
            throw TopologyError.missingReference("Missing edge offset vertex \(vertexID).")
        }
        return vertex.point
    }

    private func startVertexID(for orientedEdge: OrientedEdge, in model: BRepModel) throws -> VertexID {
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

    private func endVertexID(for orientedEdge: OrientedEdge, in model: BRepModel) throws -> VertexID {
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

    private func generatedNamesReferencing(
        edgeIDs: Set<EdgeID>,
        contextGeneratedNames: [PersistentName: TopologyReference]
    ) -> Set<PersistentName> {
        Set(contextGeneratedNames.compactMap { name, reference in
            guard case let .edge(edgeID) = reference,
                  edgeIDs.contains(edgeID) else {
                return nil
            }
            return name
        })
    }

    private func point(_ point: Point2D, isInside polygon: [Point2D], tolerance: ModelingTolerance) -> Bool {
        guard polygon.count >= 3 else {
            return false
        }
        let signedArea = polygonSignedArea(polygon)
        let sign = signedArea >= 0.0 ? 1.0 : -1.0
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            let edge = Point2D(x: end.x - start.x, y: end.y - start.y)
            let candidate = Point2D(x: point.x - start.x, y: point.y - start.y)
            guard cross(edge, candidate) * sign >= -tolerance.distance else {
                return false
            }
        }
        return true
    }

    private func normalized(_ vector: Point2D, tolerance: ModelingTolerance) throws -> Point2D {
        let length = hypot(vector.x, vector.y)
        guard length > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(length)
        }
        return Point2D(x: vector.x / length, y: vector.y / length)
    }

    private func polygonSignedArea(_ points: [Point2D]) -> Double {
        var area = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            area += current.x * next.y - next.x * current.y
        }
        return area * 0.5
    }

    private func cross(_ lhs: Point2D, _ rhs: Point2D) -> Double {
        lhs.x * rhs.y - lhs.y * rhs.x
    }

    private func dot(_ lhs: Point2D, _ rhs: Point2D) -> Double {
        lhs.x * rhs.x + lhs.y * rhs.y
    }

    private func persistentName(_ featureID: FeatureID, _ subshape: String, _ index: Int?) -> PersistentName {
        var components: [NameComponent] = [
            .feature(featureID),
            .generated("edgeOffset"),
            .subshape(subshape),
        ]
        if let index {
            components.append(.index(index))
        }
        return PersistentName(components: components)
    }
}

private struct BoundaryEdgeSplit {
    var originalEdgeID: EdgeID
    var originalCurveID: CurveID
    var splitVertexID: VertexID
    var firstEdgeID: EdgeID
    var secondEdgeID: EdgeID
    var generatedNames: [PersistentName: TopologyReference]
}

private struct EdgeOffsetEvaluationChange {
    var generatedNames: [PersistentName: TopologyReference]
    var removedGeneratedNames: Set<PersistentName>

    mutating func merge(_ other: EdgeOffsetEvaluationChange) {
        for (name, reference) in other.generatedNames {
            generatedNames[name] = reference
        }
        removedGeneratedNames.formUnion(other.removedGeneratedNames)
    }
}

private struct EdgeOffsetFaceFrame {
    var origin: Point3D
    var u: Vector3D
    var v: Vector3D

    init(plane: Plane3D, tolerance: ModelingTolerance) throws {
        let normal = try plane.normal.normalized(tolerance: tolerance.distance)
        let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
        v = normal.cross(u)
        origin = plane.origin
    }

    func localPoint(_ point: Point3D) -> Point2D {
        let delta = point - origin
        return Point2D(x: delta.dot(u), y: delta.dot(v))
    }

    func worldPoint(_ point: Point2D) -> Point3D {
        origin + (u * point.x) + (v * point.y)
    }
}
