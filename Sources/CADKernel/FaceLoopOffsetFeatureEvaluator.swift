import Foundation
import CADCore
import CADIR

public struct FaceLoopOffsetFeatureEvaluator: FeatureEvaluating {
    private let resolver: ParameterResolving

    public init(resolver: ParameterResolving = ParameterResolver()) {
        self.resolver = resolver
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .faceLoopOffset(faceLoopOffset) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation(
                "FaceLoopOffsetFeatureEvaluator only supports faceLoopOffset."
            )
        }
        let distance = try resolvedDistance(faceLoopOffset.distance, context: context)
        var model = context.brep

        let bodyID = try targetBodyID(for: faceLoopOffset.target.featureID, context: context)
        let faceID = try targetFaceID(for: faceLoopOffset.facePersistentName, context: context)
        guard try body(bodyID, contains: faceID, in: model) else {
            throw FeatureEvaluationError.missingInput("Face loop offset target face is not on the target body.")
        }

        let generatedNames = try splitRectangularPlanarFace(
            faceID,
            distance: distance,
            featureID: feature.id,
            bodyID: bodyID,
            tolerance: context.tolerance,
            model: &model
        )
        return EvaluationResult(brep: model, generatedNames: generatedNames)
    }

    private func resolvedDistance(
        _ expression: CADExpression,
        context: EvaluationContext
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(
                operation: "faceLoopOffset.distance",
                expected: .length,
                actual: quantity.kind
            )
        }
        guard quantity.value > context.tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(quantity.value)
        }
        return quantity.value
    }

    private func targetBodyID(
        for featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        let name = PersistentName(components: [.feature(featureID), .generated(GeneratedSubshapeRole.body.rawValue)])
        guard let reference = context.generatedNames[name],
              case let .body(bodyID) = reference else {
            throw FeatureEvaluationError.missingInput("Face loop offset target body could not be resolved.")
        }
        return bodyID
    }

    private func targetFaceID(
        for persistentName: PersistentName,
        context: EvaluationContext
    ) throws -> FaceID {
        guard let reference = context.generatedNames[persistentName],
              case let .face(faceID) = reference else {
            throw FeatureEvaluationError.missingInput("Face loop offset target face could not be resolved.")
        }
        return faceID
    }

    private func body(
        _ bodyID: BodyID,
        contains faceID: FaceID,
        in model: BRepModel
    ) throws -> Bool {
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Missing face loop offset body \(bodyID).")
        }
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing face loop offset shell \(shellID).")
            }
            if shell.faceIDs.contains(faceID) {
                return true
            }
        }
        return false
    }

    private func splitRectangularPlanarFace(
        _ faceID: FaceID,
        distance: Double,
        featureID: FeatureID,
        bodyID: BodyID,
        tolerance: ModelingTolerance,
        model: inout BRepModel
    ) throws -> [PersistentName: TopologyReference] {
        guard var face = model.faces[faceID] else {
            throw TopologyError.missingReference("Missing face loop offset face \(faceID).")
        }
        guard face.loops.count == 1,
              let outerLoopID = face.loops.first,
              let outerLoop = model.loops[outerLoopID],
              outerLoop.role == .outer else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Face loop offset currently requires one outer loop with no existing inner loops."
            )
        }
        guard let surface = model.geometry.surfaces[face.surfaceID],
              case let .plane(plane) = surface else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Face loop offset currently supports planar faces only."
            )
        }
        try plane.validate()
        guard outerLoop.edges.count == 4 else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Face loop offset currently requires a rectangular four-edge face loop."
            )
        }
        for orientedEdge in outerLoop.edges {
            guard let edge = model.edges[orientedEdge.edgeID],
                  let curve = model.geometry.curves[edge.curveID],
                  case .line = curve else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Face loop offset currently requires line-only rectangular face loops."
                )
            }
        }

        let outerVertexIDs = try model.orderedVertexIDs(for: outerLoopID)
        let outerPoints = try outerVertexIDs.map { vertexID -> Point3D in
            guard let vertex = model.vertices[vertexID] else {
                throw TopologyError.missingReference("Missing face loop offset vertex \(vertexID).")
            }
            return vertex.point
        }
        let frame = try FaceFrame(plane: plane, tolerance: tolerance)
        let outer2D = outerPoints.map(frame.localPoint)
        try validateRectangularLoop(outer2D, tolerance: tolerance)
        let inner2D = try insetPolygon(outer2D, distance: distance, tolerance: tolerance)
        let innerPoints = inner2D.map(frame.worldPoint)
        var generatedNames: [PersistentName: TopologyReference] = [:]
        let innerVertexIDs = innerPoints.enumerated().map { index, point -> VertexID in
            let vertexID = VertexID()
            model.vertices[vertexID] = Vertex(id: vertexID, point: point)
            generatedNames[persistentName(featureID, "offsetVertex", index)] = .vertex(vertexID)
            return vertexID
        }

        var innerEdgeIDs: [EdgeID] = []
        for index in innerVertexIDs.indices {
            let startVertexID = innerVertexIDs[index]
            let endVertexID = innerVertexIDs[(index + 1) % innerVertexIDs.count]
            let start = innerPoints[index]
            let end = innerPoints[(index + 1) % innerPoints.count]
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
            innerEdgeIDs.append(edgeID)
            generatedNames[persistentName(featureID, "offsetEdge", index)] = .edge(edgeID)
        }

        let ringInnerLoopID = LoopID()
        let centerLoopID = LoopID()
        let reversedInnerEdges = innerEdgeIDs.indices.reversed().map { index in
            let nextIndex = (index + 1) % innerEdgeIDs.count
            return OrientedEdge(
                edgeID: innerEdgeIDs[index],
                orientation: .reversed,
                surfaceParameterCurve: surfaceParameterCurve(from: inner2D[nextIndex], to: inner2D[index])
            )
        }
        let centerEdges = innerEdgeIDs.indices.map { index in
            let nextIndex = (index + 1) % innerEdgeIDs.count
            return OrientedEdge(
                edgeID: innerEdgeIDs[index],
                orientation: .forward,
                surfaceParameterCurve: surfaceParameterCurve(from: inner2D[index], to: inner2D[nextIndex])
            )
        }
        model.loops[ringInnerLoopID] = Loop(id: ringInnerLoopID, role: .inner, edges: reversedInnerEdges)
        model.loops[centerLoopID] = Loop(id: centerLoopID, role: .outer, edges: centerEdges)

        let centerFaceID = FaceID()
        face.loops.append(ringInnerLoopID)
        model.faces[faceID] = face
        model.faces[centerFaceID] = Face(
            id: centerFaceID,
            surfaceID: face.surfaceID,
            loops: [centerLoopID],
            orientation: face.orientation
        )
        try append(centerFaceID, after: faceID, in: &model)
        generatedNames[PersistentName(components: [
            .feature(featureID),
            .generated(GeneratedSubshapeRole.body.rawValue),
        ])] = .body(bodyID)
        generatedNames[persistentName(featureID, "centerFace", nil)] = .face(centerFaceID)
        return generatedNames
    }

    private func append(
        _ insertedFaceID: FaceID,
        after faceID: FaceID,
        in model: inout BRepModel
    ) throws {
        for (shellID, var shell) in model.shells {
            guard let index = shell.faceIDs.firstIndex(of: faceID) else {
                continue
            }
            shell.faceIDs.insert(insertedFaceID, at: shell.faceIDs.index(after: index))
            model.shells[shellID] = shell
            return
        }
        throw TopologyError.missingReference("Face loop offset shell for face \(faceID) was not found.")
    }

    private func insetPolygon(
        _ points: [Point2D],
        distance: Double,
        tolerance: ModelingTolerance
    ) throws -> [Point2D] {
        guard points.count == 4 else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Face loop offset currently requires four polygon points."
            )
        }
        let signedArea = polygonSignedArea(points)
        guard abs(signedArea) > tolerance.distance * tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(abs(signedArea))
        }
        let sign = signedArea >= 0.0 ? 1.0 : -1.0
        let count = points.count
        var offsetLines: [(point: Point2D, direction: Point2D)] = []
        for index in points.indices {
            let start = points[index]
            let end = points[(index + 1) % count]
            let direction = try normalized(
                Point2D(x: end.x - start.x, y: end.y - start.y),
                tolerance: tolerance
            )
            let inward = Point2D(x: -direction.y * sign, y: direction.x * sign)
            offsetLines.append((
                point: Point2D(
                    x: start.x + inward.x * distance,
                    y: start.y + inward.y * distance
                ),
                direction: direction
            ))
        }

        var inner: [Point2D] = []
        for index in points.indices {
            let previous = offsetLines[(index + count - 1) % count]
            let current = offsetLines[index]
            inner.append(try lineIntersection(previous, current, tolerance: tolerance))
        }
        let innerArea = polygonSignedArea(inner)
        guard innerArea.sign == signedArea.sign,
              abs(innerArea) > tolerance.distance * tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(distance)
        }
        return inner
    }

    private func surfaceParameterCurve(from start: Point2D, to end: Point2D) -> SurfaceParameterCurve {
        .polyline([
            SurfaceParameter(u: start.x, v: start.y),
            SurfaceParameter(u: end.x, v: end.y),
        ])
    }

    private func validateRectangularLoop(
        _ points: [Point2D],
        tolerance: ModelingTolerance
    ) throws {
        guard points.count == 4 else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Face loop offset currently requires four polygon points."
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
                    "Face loop offset currently requires perpendicular adjacent rectangular edges."
                )
            }
        }
        for index in 0..<2 {
            let opposite = index + 2
            let normalizedCross = abs(cross(directions[index], directions[opposite])) /
                (lengths[index] * lengths[opposite])
            guard normalizedCross <= angularTolerance else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Face loop offset currently requires parallel opposite rectangular edges."
                )
            }
        }
    }

    private func lineIntersection(
        _ first: (point: Point2D, direction: Point2D),
        _ second: (point: Point2D, direction: Point2D),
        tolerance: ModelingTolerance
    ) throws -> Point2D {
        let delta = Point2D(
            x: second.point.x - first.point.x,
            y: second.point.y - first.point.y
        )
        let denominator = cross(first.direction, second.direction)
        guard abs(denominator) > tolerance.angle else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Face loop offset cannot inset parallel adjacent loop edges."
            )
        }
        let t = cross(delta, second.direction) / denominator
        return Point2D(
            x: first.point.x + first.direction.x * t,
            y: first.point.y + first.direction.y * t
        )
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

    private func persistentName(
        _ featureID: FeatureID,
        _ subshape: String,
        _ index: Int?
    ) -> PersistentName {
        var components: [NameComponent] = [
            .feature(featureID),
            .generated("faceLoopOffset"),
            .subshape(subshape),
        ]
        if let index {
            components.append(.index(index))
        }
        return PersistentName(components: components)
    }
}

private struct FaceFrame {
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

private extension Double {
    var sign: Int {
        self < 0.0 ? -1 : 1
    }
}
