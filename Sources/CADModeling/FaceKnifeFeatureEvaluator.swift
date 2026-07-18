import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct FaceKnifeFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let subshapeResolver: any StableSubshapeResolving

    public init(
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()
    ) {
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
        guard case let .faceKnife(faceKnife) = feature.operation else {
            throw KernelError.unsupportedEvaluation(tolerance: context.tolerance, message:
                "FaceKnifeFeatureEvaluator only supports faceKnife."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try faceKnife.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context.brep,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        var model = context.brep
        let bodyID = try targetBodyID(for: faceKnife.target.featureID, context: context)
        let faceID = try targetFaceID(for: faceKnife.face, context: context)
        guard try body(bodyID, contains: faceID, in: model) else {
            throw FeatureEvaluationError.missingInput("Face Knife target face is not on the target body.")
        }

        let generatedSubshapes = try splitPlanarFace(
            faceID,
            with: faceKnife.loop,
            featureID: feature.id,
            bodyID: bodyID,
            tolerance: context.tolerance,
            model: &model
        )
        let parentResolver = LiveTopologyParentResolver()
        let bodyParentSubshapeID = try parentResolver.resolve(
            .body(bodyID),
            in: context.subshapes,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let faceParentSubshapeID = try parentResolver.resolve(
            .face(faceID),
            in: context.subshapes,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let lineage = topologyLineage(
            subshapes: generatedSubshapes,
            bodyParent: bodyParentSubshapeID,
            faceParent: faceParentSubshapeID
        )
        return EvaluationResult(
            brep: model,
            subshapes: generatedSubshapes,
            removedSubshapeIDs: [bodyParentSubshapeID, faceParentSubshapeID],
            lineage: lineage
        )
    }

    private func targetBodyID(
        for featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        try context.bodyID(generatedBy: featureID)
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
    ) throws -> [SubshapeID: TopologyReference] {
        guard var face = model.faces[faceID] else {
            throw TopologyError.missingReference("Missing Face Knife face \(faceID).")
        }
        guard face.loops.count == 1,
              let outerLoopID = face.loops.first,
              let outerLoop = model.loops[outerLoopID],
              outerLoop.role == .outer else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Face Knife currently requires one outer loop with no existing inner loops."
            )
        }
        guard let surface = model.geometry.surfaces[face.surfaceID],
              case let .plane(plane) = surface else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Face Knife currently supports planar faces only."
            )
        }
        try plane.validate(tolerance: tolerance)
        try validateLineOnlyLoop(outerLoop, model: model, tolerance: tolerance)

        let frame = try PlanarFaceFrame(plane: plane, tolerance: tolerance)
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
        var topologyIDs = FeatureTopologyIDAllocator(featureID: featureID)
        var generatedSubshapes: [SubshapeID: TopologyReference] = [:]
        let knifeVertexIDs = knifePoints.enumerated().map { index, point -> VertexID in
            let vertexID = topologyIDs.nextVertexID()
            model.vertices[vertexID] = Vertex(id: vertexID, point: point)
            generatedSubshapes[subshapeID(featureID, "knifeVertex", index)] = .vertex(vertexID)
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
            knifeEdgeIDs.append(edgeID)
            generatedSubshapes[subshapeID(featureID, "knifeEdge", index)] = .edge(edgeID)
        }

        let ringInnerLoopID = topologyIDs.nextLoopID()
        let centerLoopID = topologyIDs.nextLoopID()
        let reversedKnifeEdges = knifeEdgeIDs.indices.reversed().map { index in
            let nextIndex = (index + 1) % knifeEdgeIDs.count
            return Coedge(
                edgeID: knifeEdgeIDs[index],
                orientation: .reversed,
                surfaceParameterCurve: surfaceParameterCurve(from: knife2D[nextIndex], to: knife2D[index])
            )
        }
        let centerEdges = knifeEdgeIDs.indices.map { index in
            let nextIndex = (index + 1) % knifeEdgeIDs.count
            return Coedge(
                edgeID: knifeEdgeIDs[index],
                orientation: .forward,
                surfaceParameterCurve: surfaceParameterCurve(from: knife2D[index], to: knife2D[nextIndex])
            )
        }
        model.loops[ringInnerLoopID] = Loop(id: ringInnerLoopID, role: .inner, edges: reversedKnifeEdges)
        model.loops[centerLoopID] = Loop(id: centerLoopID, role: .outer, edges: centerEdges)

        let centerFaceID = topologyIDs.nextFaceID()
        face.loops.append(ringInnerLoopID)
        model.faces[faceID] = face
        model.faces[centerFaceID] = Face(
            id: centerFaceID,
            surfaceID: face.surfaceID,
            loops: [centerLoopID],
            orientation: face.orientation
        )
        try append(centerFaceID, after: faceID, in: &model)
        generatedSubshapes[SubshapeID(
            featureID: featureID,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        )] = .body(bodyID)
        generatedSubshapes[subshapeID(featureID, "ringFace", 0)] = .face(faceID)
        generatedSubshapes[subshapeID(featureID, "centerFace", 0)] = .face(centerFaceID)
        return generatedSubshapes
    }

    private func topologyLineage(
        subshapes: [SubshapeID: TopologyReference],
        bodyParent: SubshapeID,
        faceParent: SubshapeID
    ) -> [SubshapeID: TopologyLineage] {
        Dictionary(uniqueKeysWithValues: subshapes.map { output, reference in
            let entry: TopologyLineage
            switch reference {
            case .body:
                entry = TopologyLineage(
                    output: output,
                    parents: [bodyParent],
                    relation: .preserved
                )
            case .face:
                entry = TopologyLineage(
                    output: output,
                    parents: [faceParent],
                    relation: .split
                )
            case .edge, .vertex:
                entry = TopologyLineage(output: output, relation: .generated)
            }
            return (output, entry)
        })
    }

    private func validateLineOnlyLoop(
        _ loop: Loop,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        for orientedEdge in loop.edges {
            guard let edge = model.edges[orientedEdge.edgeID],
                  let curve = model.geometry.curves[edge.curveID],
                  case .line = curve else {
                throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                    "Face Knife currently requires a line-only target face loop."
                )
            }
        }
    }

    private func normalizedKnifeLoop(
        _ points: [Point3D],
        outer2D: [Point2D],
        frame: PlanarFaceFrame,
        tolerance: ModelingTolerance
    ) throws -> [Point2D] {
        guard points.count >= 3 else {
            throw FeatureEvaluationError.invalidGraph("Face Knife requires at least three loop points.")
        }
        let projected = try points.map { point -> Point2D in
            let local = frame.localPoint(point)
            let reconstructed = frame.worldPoint(local)
            guard (point - reconstructed).length <= tolerance.distance * 10.0 else {
                throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
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
        if loopArea * outerArea < 0.0 {
            loop.reverse()
        }
        try validateSimpleLoop(loop, tolerance: tolerance)
        try validateLoop(loop, isInside: outer2D, tolerance: tolerance)
        return loop
    }

    private func surfaceParameterCurve(from start: Point2D, to end: Point2D) -> SurfaceParameterCurve {
        .affine(
            origin: start,
            direction: Point2D(x: end.x - start.x, y: end.y - start.y),
            startParameter: 0.0,
            endParameter: 1.0
        )
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
                if try segmentsIntersect(
                    firstStart,
                    firstEnd,
                    secondStart,
                    secondEnd,
                    tolerance: tolerance
                ) {
                    throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
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
            guard try containsStrictly(point, in: outer, tolerance: tolerance) else {
                throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
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
                guard try segmentsIntersect(
                    start,
                    end,
                    outerStart,
                    outerEnd,
                    tolerance: tolerance
                ) == false else {
                    throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
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
    ) throws -> Bool {
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
        let determinantTolerance = determinantTolerance(
            points: polygon + [point],
            tolerance: tolerance
        )
        var windingNumber = 0
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            let orientation = try RobustPredicates.orientation2D(
                start,
                end,
                relativeTo: point,
                determinantTolerance: determinantTolerance
            )
            guard orientation != .zero, orientation != .indeterminate else {
                return false
            }
            if start.y <= point.y,
               end.y > point.y,
               orientation == .positive {
                windingNumber += 1
            } else if start.y > point.y,
                      end.y <= point.y,
                      orientation == .negative {
                windingNumber -= 1
            }
        }
        return windingNumber != 0
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
    ) throws -> Bool {
        guard max(firstStart.x, firstEnd.x) + tolerance.distance
                >= min(secondStart.x, secondEnd.x),
              max(secondStart.x, secondEnd.x) + tolerance.distance
                >= min(firstStart.x, firstEnd.x),
              max(firstStart.y, firstEnd.y) + tolerance.distance
                >= min(secondStart.y, secondEnd.y),
              max(secondStart.y, secondEnd.y) + tolerance.distance
                >= min(firstStart.y, firstEnd.y) else {
            return false
        }
        let determinantTolerance = determinantTolerance(
            points: [firstStart, firstEnd, secondStart, secondEnd],
            tolerance: tolerance
        )
        let firstSecondStart = try RobustPredicates.orientation2D(
            firstStart,
            firstEnd,
            relativeTo: secondStart,
            determinantTolerance: determinantTolerance
        )
        let firstSecondEnd = try RobustPredicates.orientation2D(
            firstStart,
            firstEnd,
            relativeTo: secondEnd,
            determinantTolerance: determinantTolerance
        )
        let secondFirstStart = try RobustPredicates.orientation2D(
            secondStart,
            secondEnd,
            relativeTo: firstStart,
            determinantTolerance: determinantTolerance
        )
        let secondFirstEnd = try RobustPredicates.orientation2D(
            secondStart,
            secondEnd,
            relativeTo: firstEnd,
            determinantTolerance: determinantTolerance
        )
        if opposite(firstSecondStart, firstSecondEnd),
           opposite(secondFirstStart, secondFirstEnd) {
            return true
        }
        if (firstSecondStart == .zero || firstSecondStart == .indeterminate),
           point(secondStart, liesOnSegmentFrom: firstStart, to: firstEnd, tolerance: tolerance) {
            return true
        }
        if (firstSecondEnd == .zero || firstSecondEnd == .indeterminate),
           point(secondEnd, liesOnSegmentFrom: firstStart, to: firstEnd, tolerance: tolerance) {
            return true
        }
        if (secondFirstStart == .zero || secondFirstStart == .indeterminate),
           point(firstStart, liesOnSegmentFrom: secondStart, to: secondEnd, tolerance: tolerance) {
            return true
        }
        if (secondFirstEnd == .zero || secondFirstEnd == .indeterminate),
           point(firstEnd, liesOnSegmentFrom: secondStart, to: secondEnd, tolerance: tolerance) {
            return true
        }
        return false
    }

    private func determinantTolerance(
        points: [Point2D],
        tolerance: ModelingTolerance
    ) -> Double {
        let scale = max(
            1.0,
            points.reduce(0.0) { partial, point in
                max(partial, max(abs(point.x), abs(point.y)))
            }
        )
        return max(tolerance.distance, tolerance.angle) * scale
    }

    private func opposite(_ first: RobustSign, _ second: RobustSign) -> Bool {
        (first == .negative && second == .positive)
            || (first == .positive && second == .negative)
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

    private func subshapeID(
        _ featureID: FeatureID,
        _ role: String,
        _ ordinal: Int
    ) -> SubshapeID {
        SubshapeID(
            featureID: featureID,
            role: SubshapeIdentityRole.compose(
                generatedRole: "faceKnife",
                subshapeRole: role
            ),
            ordinal: ordinal
        )
    }
}
