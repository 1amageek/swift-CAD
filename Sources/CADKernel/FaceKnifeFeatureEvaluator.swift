import Foundation
import CADCore
import CADIR

public struct FaceKnifeFeatureEvaluator: FeatureEvaluating {
    public init() {}

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .faceKnife(faceKnife) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation(
                "FaceKnifeFeatureEvaluator only supports faceKnife."
            )
        }
        var model = context.brep
        let bodyID = try targetBodyID(for: faceKnife.target.featureID, context: context)
        let faceID = try targetFaceID(for: faceKnife.facePersistentName, context: context)
        guard try body(bodyID, contains: faceID, in: model) else {
            throw FeatureEvaluationError.missingInput("Face Knife target face is not on the target body.")
        }

        let generatedNames = try splitPlanarFace(
            faceID,
            with: faceKnife.loop,
            featureID: feature.id,
            bodyID: bodyID,
            tolerance: context.tolerance,
            model: &model
        )
        return EvaluationResult(brep: model, generatedNames: generatedNames)
    }

    private func targetBodyID(
        for featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        let name = PersistentName(components: [.feature(featureID), .generated(GeneratedSubshapeRole.body.rawValue)])
        guard let reference = context.generatedNames[name],
              case let .body(bodyID) = reference else {
            throw FeatureEvaluationError.missingInput("Face Knife target body could not be resolved.")
        }
        return bodyID
    }

    private func targetFaceID(
        for persistentName: PersistentName,
        context: EvaluationContext
    ) throws -> FaceID {
        guard let reference = context.generatedNames[persistentName],
              case let .face(faceID) = reference else {
            throw FeatureEvaluationError.missingInput("Face Knife target face could not be resolved.")
        }
        return faceID
    }

    private func body(
        _ bodyID: BodyID,
        contains faceID: FaceID,
        in model: BRepModel
    ) throws -> Bool {
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Missing Face Knife body \(bodyID).")
        }
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing Face Knife shell \(shellID).")
            }
            if shell.faceIDs.contains(faceID) {
                return true
            }
        }
        return false
    }

    private func splitPlanarFace(
        _ faceID: FaceID,
        with loopPoints: [Point3D],
        featureID: FeatureID,
        bodyID: BodyID,
        tolerance: ModelingTolerance,
        model: inout BRepModel
    ) throws -> [PersistentName: TopologyReference] {
        guard var face = model.faces[faceID] else {
            throw TopologyError.missingReference("Missing Face Knife face \(faceID).")
        }
        guard face.loops.count == 1,
              let outerLoopID = face.loops.first,
              let outerLoop = model.loops[outerLoopID],
              outerLoop.role == .outer else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Face Knife currently requires one outer loop with no existing inner loops."
            )
        }
        guard let surface = model.geometry.surfaces[face.surfaceID],
              case let .plane(plane) = surface else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Face Knife currently supports planar faces only."
            )
        }
        try plane.validate()
        try validateLineOnlyLoop(outerLoop, model: model)

        let frame = try FaceKnifeFrame(plane: plane, tolerance: tolerance)
        let outerPoints = try model.orderedVertexIDs(for: outerLoopID).map { vertexID -> Point3D in
            guard let vertex = model.vertices[vertexID] else {
                throw TopologyError.missingReference("Missing Face Knife outer vertex \(vertexID).")
            }
            return vertex.point
        }
        let outer2D = outerPoints.map(frame.localPoint)
        let knife2D = try normalizedKnifeLoop(
            loopPoints,
            outer2D: outer2D,
            frame: frame,
            tolerance: tolerance
        )
        let knifePoints = knife2D.map(frame.worldPoint)
        var generatedNames: [PersistentName: TopologyReference] = [:]
        let knifeVertexIDs = knifePoints.enumerated().map { index, point -> VertexID in
            let vertexID = VertexID()
            model.vertices[vertexID] = Vertex(id: vertexID, point: point)
            generatedNames[persistentName(featureID, "knifeVertex", index)] = .vertex(vertexID)
            return vertexID
        }

        var knifeEdgeIDs: [EdgeID] = []
        for index in knifeVertexIDs.indices {
            let startVertexID = knifeVertexIDs[index]
            let endVertexID = knifeVertexIDs[(index + 1) % knifeVertexIDs.count]
            let start = knifePoints[index]
            let end = knifePoints[(index + 1) % knifePoints.count]
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
            knifeEdgeIDs.append(edgeID)
            generatedNames[persistentName(featureID, "knifeEdge", index)] = .edge(edgeID)
        }

        let ringInnerLoopID = LoopID()
        let centerLoopID = LoopID()
        let reversedKnifeEdges = knifeEdgeIDs.indices.reversed().map { index in
            let nextIndex = (index + 1) % knifeEdgeIDs.count
            return OrientedEdge(
                edgeID: knifeEdgeIDs[index],
                orientation: .reversed,
                surfaceParameterCurve: surfaceParameterCurve(from: knife2D[nextIndex], to: knife2D[index])
            )
        }
        let centerEdges = knifeEdgeIDs.indices.map { index in
            let nextIndex = (index + 1) % knifeEdgeIDs.count
            return OrientedEdge(
                edgeID: knifeEdgeIDs[index],
                orientation: .forward,
                surfaceParameterCurve: surfaceParameterCurve(from: knife2D[index], to: knife2D[nextIndex])
            )
        }
        model.loops[ringInnerLoopID] = Loop(id: ringInnerLoopID, role: .inner, edges: reversedKnifeEdges)
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
        try addCarriedBodyTopologyNames(
            featureID: featureID,
            bodyID: bodyID,
            model: model,
            generatedNames: &generatedNames
        )
        return generatedNames
    }

    private func addCarriedBodyTopologyNames(
        featureID: FeatureID,
        bodyID: BodyID,
        model: BRepModel,
        generatedNames: inout [PersistentName: TopologyReference]
    ) throws {
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Missing Face Knife body \(bodyID).")
        }

        var faceIndex = 0
        var edgeIndex = 0
        var vertexIndex = 0
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing Face Knife shell \(shellID).")
            }
            for faceID in shell.faceIDs {
                if generatedNames.containsFace(faceID) == false {
                    generatedNames[persistentName(featureID, "carriedFace", faceIndex)] = .face(faceID)
                    faceIndex += 1
                }
                guard let face = model.faces[faceID] else {
                    throw TopologyError.missingReference("Missing Face Knife face \(faceID).")
                }
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else {
                        throw TopologyError.missingReference("Missing Face Knife loop \(loopID).")
                    }
                    for orientedEdge in loop.edges {
                        let edgeID = orientedEdge.edgeID
                        if generatedNames.containsEdge(edgeID) == false {
                            generatedNames[persistentName(featureID, "carriedEdge", edgeIndex)] = .edge(edgeID)
                            edgeIndex += 1
                        }
                        guard let edge = model.edges[edgeID] else {
                            throw TopologyError.missingReference("Missing Face Knife edge \(edgeID).")
                        }
                        if generatedNames.containsVertex(edge.startVertexID) == false {
                            generatedNames[persistentName(featureID, "carriedVertex", vertexIndex)] = .vertex(edge.startVertexID)
                            vertexIndex += 1
                        }
                        if generatedNames.containsVertex(edge.endVertexID) == false {
                            generatedNames[persistentName(featureID, "carriedVertex", vertexIndex)] = .vertex(edge.endVertexID)
                            vertexIndex += 1
                        }
                    }
                }
            }
        }
    }

    private func validateLineOnlyLoop(_ loop: Loop, model: BRepModel) throws {
        for orientedEdge in loop.edges {
            guard let edge = model.edges[orientedEdge.edgeID],
                  let curve = model.geometry.curves[edge.curveID],
                  case .line = curve else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Face Knife currently requires a line-only target face loop."
                )
            }
        }
    }

    private func normalizedKnifeLoop(
        _ points: [Point3D],
        outer2D: [Point2D],
        frame: FaceKnifeFrame,
        tolerance: ModelingTolerance
    ) throws -> [Point2D] {
        guard points.count >= 3 else {
            throw FeatureEvaluationError.invalidGraph("Face Knife requires at least three loop points.")
        }
        let projected = try points.map { point -> Point2D in
            let local = frame.localPoint(point)
            let reconstructed = frame.worldPoint(local)
            guard (point - reconstructed).length <= tolerance.distance * 10.0 else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Face Knife loop points must lie on the target face plane."
                )
            }
            return local
        }
        let outerArea = polygonSignedArea(outer2D)
        guard abs(outerArea) > tolerance.distance * tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(abs(outerArea))
        }
        var loop = projected
        let loopArea = polygonSignedArea(loop)
        guard abs(loopArea) > tolerance.distance * tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(abs(loopArea))
        }
        if loopArea.sign != outerArea.sign {
            loop.reverse()
        }
        try validateSimpleLoop(loop, tolerance: tolerance)
        try validateLoop(loop, isInside: outer2D, tolerance: tolerance)
        return loop
    }

    private func surfaceParameterCurve(from start: Point2D, to end: Point2D) -> SurfaceParameterCurve {
        .polyline([
            SurfaceParameter(u: start.x, v: start.y),
            SurfaceParameter(u: end.x, v: end.y),
        ])
    }

    private func validateSimpleLoop(_ points: [Point2D], tolerance: ModelingTolerance) throws {
        guard points.count >= 3 else {
            throw FeatureEvaluationError.invalidGraph("Face Knife requires at least three loop points.")
        }
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let edgeLength = distance(current, to: next)
            guard edgeLength > tolerance.distance else {
                throw FeatureEvaluationError.invalidDistance(edgeLength)
            }
        }

        for firstIndex in points.indices {
            let firstStart = points[firstIndex]
            let firstEnd = points[(firstIndex + 1) % points.count]
            for secondIndex in points.indices {
                guard secondIndex > firstIndex else {
                    continue
                }
                let areAdjacent = firstIndex == secondIndex
                    || (firstIndex + 1) % points.count == secondIndex
                    || (secondIndex + 1) % points.count == firstIndex
                guard areAdjacent == false else {
                    continue
                }
                let secondStart = points[secondIndex]
                let secondEnd = points[(secondIndex + 1) % points.count]
                if segmentsIntersect(
                    firstStart,
                    firstEnd,
                    secondStart,
                    secondEnd,
                    tolerance: tolerance
                ) {
                    throw FeatureEvaluationError.unsupportedOperation(
                        "Face Knife loop must be a simple closed loop without self-intersections."
                    )
                }
            }
        }
    }

    private func validateLoop(
        _ points: [Point2D],
        isInside outer: [Point2D],
        tolerance: ModelingTolerance
    ) throws {
        for point in points {
            guard containsStrictly(point, in: outer, tolerance: tolerance) else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Face Knife loop must be fully inside the target face boundary."
                )
            }
        }
        for index in points.indices {
            let start = points[index]
            let end = points[(index + 1) % points.count]
            for outerIndex in outer.indices {
                let outerStart = outer[outerIndex]
                let outerEnd = outer[(outerIndex + 1) % outer.count]
                guard segmentsIntersect(
                    start,
                    end,
                    outerStart,
                    outerEnd,
                    tolerance: tolerance
                ) == false else {
                    throw FeatureEvaluationError.unsupportedOperation(
                        "Face Knife loop must be fully inside the target face boundary."
                    )
                }
            }
        }
    }

    private func containsStrictly(
        _ point: Point2D,
        in polygon: [Point2D],
        tolerance: ModelingTolerance
    ) -> Bool {
        guard polygon.count >= 3 else {
            return false
        }
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            if distance(point, toSegmentFrom: start, to: end) <= tolerance.distance * 10.0 {
                return false
            }
        }
        var isInside = false
        var previousIndex = polygon.count - 1
        for currentIndex in polygon.indices {
            let current = polygon[currentIndex]
            let previous = polygon[previousIndex]
            let crosses = (current.y > point.y) != (previous.y > point.y)
            if crosses {
                let x = (previous.x - current.x) * (point.y - current.y) /
                    (previous.y - current.y) + current.x
                if point.x < x {
                    isInside.toggle()
                }
            }
            previousIndex = currentIndex
        }
        return isInside
    }

    private func distance(
        _ point: Point2D,
        toSegmentFrom start: Point2D,
        to end: Point2D
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let t = max(0.0, min(1.0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = Point2D(x: start.x + dx * t, y: start.y + dy * t)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private func distance(_ start: Point2D, to end: Point2D) -> Double {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func segmentsIntersect(
        _ firstStart: Point2D,
        _ firstEnd: Point2D,
        _ secondStart: Point2D,
        _ secondEnd: Point2D,
        tolerance: ModelingTolerance
    ) -> Bool {
        let areaTolerance = tolerance.distance * tolerance.distance
        let firstSecondStart = cross(firstStart, firstEnd, secondStart)
        let firstSecondEnd = cross(firstStart, firstEnd, secondEnd)
        let secondFirstStart = cross(secondStart, secondEnd, firstStart)
        let secondFirstEnd = cross(secondStart, secondEnd, firstEnd)

        if firstSecondStart > areaTolerance,
           firstSecondEnd < -areaTolerance,
           secondFirstStart < -areaTolerance,
           secondFirstEnd > areaTolerance {
            return true
        }
        if firstSecondStart < -areaTolerance,
           firstSecondEnd > areaTolerance,
           secondFirstStart > areaTolerance,
           secondFirstEnd < -areaTolerance {
            return true
        }
        if abs(firstSecondStart) <= areaTolerance,
           point(secondStart, liesOnSegmentFrom: firstStart, to: firstEnd, tolerance: tolerance) {
            return true
        }
        if abs(firstSecondEnd) <= areaTolerance,
           point(secondEnd, liesOnSegmentFrom: firstStart, to: firstEnd, tolerance: tolerance) {
            return true
        }
        if abs(secondFirstStart) <= areaTolerance,
           point(firstStart, liesOnSegmentFrom: secondStart, to: secondEnd, tolerance: tolerance) {
            return true
        }
        if abs(secondFirstEnd) <= areaTolerance,
           point(firstEnd, liesOnSegmentFrom: secondStart, to: secondEnd, tolerance: tolerance) {
            return true
        }
        return false
    }

    private func point(
        _ point: Point2D,
        liesOnSegmentFrom start: Point2D,
        to end: Point2D,
        tolerance: ModelingTolerance
    ) -> Bool {
        distance(point, toSegmentFrom: start, to: end) <= tolerance.distance * 10.0
            && point.x >= min(start.x, end.x) - tolerance.distance * 10.0
            && point.x <= max(start.x, end.x) + tolerance.distance * 10.0
            && point.y >= min(start.y, end.y) - tolerance.distance * 10.0
            && point.y <= max(start.y, end.y) + tolerance.distance * 10.0
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
        throw TopologyError.missingReference("Face Knife shell for face \(faceID) was not found.")
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

    private func cross(_ first: Point2D, _ second: Point2D, _ third: Point2D) -> Double {
        (second.x - first.x) * (third.y - first.y)
            - (second.y - first.y) * (third.x - first.x)
    }

    private func persistentName(
        _ featureID: FeatureID,
        _ subshape: String,
        _ index: Int?
    ) -> PersistentName {
        var components: [NameComponent] = [
            .feature(featureID),
            .generated("faceKnife"),
            .subshape(subshape),
        ]
        if let index {
            components.append(.index(index))
        }
        return PersistentName(components: components)
    }
}

private struct FaceKnifeFrame {
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

private extension Dictionary where Key == PersistentName, Value == TopologyReference {
    func containsFace(_ faceID: FaceID) -> Bool {
        values.contains { reference in
            if case .face(let referenceFaceID) = reference {
                return referenceFaceID == faceID
            }
            return false
        }
    }

    func containsEdge(_ edgeID: EdgeID) -> Bool {
        values.contains { reference in
            if case .edge(let referenceEdgeID) = reference {
                return referenceEdgeID == edgeID
            }
            return false
        }
    }

    func containsVertex(_ vertexID: VertexID) -> Bool {
        values.contains { reference in
            if case .vertex(let referenceVertexID) = reference {
                return referenceVertexID == vertexID
            }
            return false
        }
    }
}
