import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct MeshTessellator: Tessellating {
    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    public func tessellate(model: BRepModel, options: TessellationOptions = .standard) throws -> [BodyID: Mesh] {
        let validatedModel = try ValidatedBRepModel(
            model,
            tolerance: tolerance,
            validationLevel: .modeling
        )
        return try tessellate(validatedModel: validatedModel, options: options)
    }

    public func tessellate(
        validatedModel: ValidatedBRepModel,
        options: TessellationOptions = .standard
    ) throws -> [BodyID: Mesh] {
        do {
            try tolerance.validate()
            try options.validate()
        } catch {
            throw TessellationError.invalidTolerance
        }
        guard validatedModel.tolerance == tolerance else {
            throw TessellationError.invalidTolerance
        }
        let model = validatedModel.model

        var meshes: [BodyID: Mesh] = [:]
        for (bodyID, body) in model.bodies.sorted(by: { $0.key < $1.key }) {
            var positions: [Point3D] = []
            var normals: [Vector3D] = []
            var indices: [UInt32] = []

            for shellID in body.shellIDs {
                guard let shell = model.shells[shellID] else {
                    throw TopologyError.missingReference("Missing shell \(shellID).")
                }
                for faceID in shell.faceIDs {
                    try append(
                        faceID: faceID,
                        shellOrientation: shell.orientation,
                        model: model,
                        options: options,
                        positions: &positions,
                        normals: &normals,
                        indices: &indices
                    )
                }
            }

            let mesh = try compactedMesh(Mesh(
                positions: positions,
                normals: normals,
                indices: indices,
                material: body.material
            ))
            try mesh.validate(tolerance: tolerance)
            meshes[bodyID] = mesh
        }
        return meshes
    }

    private func compactedMesh(_ mesh: Mesh) throws -> Mesh {
        var remappedIndexes = Array<Int?>(repeating: nil, count: mesh.positions.count)
        var compactPositions: [Point3D] = []
        var compactNormals: [Vector3D] = []
        var compactTextureCoordinates: [Point2D] = []
        var compactVertexColors: [ColorRGBA] = []
        var compactIndices: [UInt32] = []
        compactIndices.reserveCapacity(mesh.indices.count)

        let hasNormals = mesh.normals.isEmpty == false
        let hasTextureCoordinates = mesh.textureCoordinates.isEmpty == false
        let hasVertexColors = mesh.vertexColors.isEmpty == false
        guard hasNormals == false || mesh.normals.count == mesh.positions.count,
              hasTextureCoordinates == false || mesh.textureCoordinates.count == mesh.positions.count,
              hasVertexColors == false || mesh.vertexColors.count == mesh.positions.count else {
            throw TessellationError.unsupportedFace(FaceID())
        }

        for index in mesh.indices {
            let sourceIndex = Int(index)
            guard mesh.positions.indices.contains(sourceIndex) else {
                throw TessellationError.unsupportedFace(FaceID())
            }
            let remappedIndex: Int
            if let existingIndex = remappedIndexes[sourceIndex] {
                remappedIndex = existingIndex
            } else {
                remappedIndex = compactPositions.count
                remappedIndexes[sourceIndex] = remappedIndex
                compactPositions.append(mesh.positions[sourceIndex])
                if hasNormals {
                    compactNormals.append(mesh.normals[sourceIndex])
                }
                if hasTextureCoordinates {
                    compactTextureCoordinates.append(mesh.textureCoordinates[sourceIndex])
                }
                if hasVertexColors {
                    compactVertexColors.append(mesh.vertexColors[sourceIndex])
                }
            }
            guard remappedIndex <= Int(UInt32.max) else {
                throw TessellationError.unsupportedFace(FaceID())
            }
            compactIndices.append(UInt32(remappedIndex))
        }

        return Mesh(
            positions: compactPositions,
            normals: compactNormals,
            indices: compactIndices,
            textureCoordinates: compactTextureCoordinates,
            vertexColors: compactVertexColors,
            material: mesh.material
        )
    }

    private func append(
        faceID: FaceID,
        shellOrientation: Orientation,
        model: BRepModel,
        options: TessellationOptions,
        positions: inout [Point3D],
        normals: inout [Vector3D],
        indices: inout [UInt32]
    ) throws {
        guard let face = model.faces[faceID] else {
            throw TessellationError.unsupportedFace(faceID)
        }
        let outerLoopIDs = face.loops.filter { loopID in
            model.loops[loopID]?.role == .outer
        }
        let innerLoopIDs = face.loops.filter { loopID in
            model.loops[loopID]?.role == .inner
        }
        guard outerLoopIDs.count == 1,
              outerLoopIDs.count + innerLoopIDs.count == face.loops.count,
              let firstLoopID = outerLoopIDs.first else {
            throw TessellationError.unsupportedFace(faceID)
        }
        guard let surface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingSurface(face.surfaceID)
        }
        guard let loop = model.loops[firstLoopID] else {
            throw TopologyError.missingReference("Missing loop \(firstLoopID).")
        }
        if case .plane = surface {
            if innerLoopIDs.isEmpty == false {
                let innerLoops = try innerLoopIDs.map { innerLoopID in
                    guard let innerLoop = model.loops[innerLoopID] else {
                        throw TopologyError.missingReference("Missing loop \(innerLoopID).")
                    }
                    return innerLoop
                }
                guard case let .plane(plane) = surface else {
                    throw TessellationError.unsupportedFace(faceID)
                }
                try appendPlanarFaceWithHoles(
                    outerLoop: loop,
                    innerLoops: innerLoops,
                    plane: plane,
                    surface: surface,
                    face: face,
                    faceID: faceID,
                    shellOrientation: shellOrientation,
                    model: model,
                    options: options,
                    positions: &positions,
                    normals: &normals,
                    indices: &indices
                )
                return
            }
        } else {
            try appendParametricFace(
                surface: surface,
                outerLoop: loop,
                innerLoopIDs: innerLoopIDs,
                face: face,
                faceID: faceID,
                shellOrientation: shellOrientation,
                model: model,
                options: options,
                positions: &positions,
                normals: &normals,
                indices: &indices
            )
            return
        }

        let points = try sampledPoints(for: loop, in: model, options: options)
        guard points.count >= 3 else {
            throw TessellationError.degenerateFace(faceID)
        }
        if try containsCircularEdge(in: loop, model: model) {
            try appendPlanarCurvedFace(
                points: points,
                surface: surface,
                face: face,
                faceID: faceID,
                shellOrientation: shellOrientation,
                positions: &positions,
                normals: &normals,
                indices: &indices
            )
            return
        }
        guard UInt64(positions.count) + UInt64(points.count) <= UInt64(UInt32.max) else {
            throw TessellationError.unsupportedFace(faceID)
        }
        let geometricNormal = try faceNormal(points: points, faceID: faceID)
        let tessellationPoints = try simplifiedPlanarPoints(
            points,
            faceID: faceID
        )
        let pointNormals = try surfaceNormals(
            for: tessellationPoints,
            on: surface,
            face: face,
            shellOrientation: shellOrientation
        )
        let baseIndex = UInt32(positions.count)
        positions.append(contentsOf: tessellationPoints)
        normals.append(contentsOf: pointNormals)

        let triangles = try planarFaceTriangles(
            points: tessellationPoints,
            normal: geometricNormal,
            faceID: faceID
        )
        for triangle in triangles {
            let appended = appendTriangle(
                baseIndex + UInt32(triangle.first),
                baseIndex + UInt32(triangle.second),
                baseIndex + UInt32(triangle.third),
                positions: positions,
                normals: normals,
                indices: &indices
            )
            guard appended else {
                throw TessellationError.degenerateFace(faceID)
            }
        }
    }

    private struct TriangleIndex {
        var first: Int
        var second: Int
        var third: Int
    }

    private struct PlanarPoint2D {
        var x: Double
        var y: Double
    }

    private struct PlanarPolygonPoint {
        var point: Point3D
        var projected: PlanarPoint2D
    }

    private func appendPlanarFaceWithHoles(
        outerLoop: Loop,
        innerLoops: [Loop],
        plane: Plane3D,
        surface: Surface3D,
        face: Face,
        faceID: FaceID,
        shellOrientation: Orientation,
        model: BRepModel,
        options: TessellationOptions,
        positions: inout [Point3D],
        normals: inout [Vector3D],
        indices: inout [UInt32]
    ) throws {
        let outerPoints = try sampledPoints(for: outerLoop, in: model, options: options)
        let innerPointLoops = try innerLoops.map { innerLoop in
            try sampledPoints(for: innerLoop, in: model, options: options)
        }
        let maximumDeviation = max(tolerance.distance, options.linearTolerance)
        let simplifiedOuterPoints = try simplifiedPlanarPoints(
            outerPoints,
            faceID: faceID,
            maximumDeviation: maximumDeviation
        )
        let simplifiedInnerPointLoops = try innerPointLoops.map {
            try simplifiedPlanarPoints(
                $0,
                faceID: faceID,
                maximumDeviation: maximumDeviation
            )
        }
        let bridgedPoints = try bridgedPlanarFacePoints(
            outerPoints: simplifiedOuterPoints,
            innerPointLoops: simplifiedInnerPointLoops,
            normal: plane.normal,
            faceID: faceID
        )
        guard UInt64(positions.count) + UInt64(bridgedPoints.count) <= UInt64(UInt32.max) else {
            throw TessellationError.unsupportedFace(faceID)
        }

        let geometricNormal = try faceNormal(points: bridgedPoints, faceID: faceID)
        let pointNormals = try surfaceNormals(
            for: bridgedPoints,
            on: surface,
            face: face,
            shellOrientation: shellOrientation
        )
        let baseIndex = UInt32(positions.count)
        positions.append(contentsOf: bridgedPoints)
        normals.append(contentsOf: pointNormals)

        let triangles = try planarFaceTriangles(
            points: bridgedPoints,
            normal: geometricNormal,
            faceID: faceID
        )
        for triangle in triangles {
            let appended = appendTriangle(
                baseIndex + UInt32(triangle.first),
                baseIndex + UInt32(triangle.second),
                baseIndex + UInt32(triangle.third),
                positions: positions,
                normals: normals,
                indices: &indices
            )
            guard appended else {
                throw TessellationError.degenerateFace(faceID)
            }
        }
    }

    private func bridgedPlanarFacePoints(
        outerPoints: [Point3D],
        innerPointLoops: [[Point3D]],
        normal: Vector3D,
        faceID: FaceID
    ) throws -> [Point3D] {
        guard outerPoints.count >= 3 else {
            throw TessellationError.degenerateFace(faceID)
        }
        for innerPoints in innerPointLoops {
            guard innerPoints.count >= 3 else {
                throw TessellationError.degenerateFace(faceID)
            }
        }
        guard innerPointLoops.isEmpty == false else {
            return outerPoints
        }

        let allPoints = [outerPoints] + innerPointLoops
        let projected = try projectedPlanarPoints(
            allPoints.flatMap { $0 },
            normal: normal
        )
        var cursor = 0
        var outer = planarPolygonPoints(
            points: outerPoints,
            projected: projected,
            cursor: &cursor
        )
        if planarSignedArea(outer.map(\.projected)) < 0.0 {
            outer.reverse()
        }
        guard abs(planarSignedArea(outer.map(\.projected))) > tolerance.distance * tolerance.distance else {
            throw TessellationError.degenerateFace(faceID)
        }
        try validateSimplePolygon(outer.map(\.projected), faceID: faceID)

        var innerLoops: [[PlanarPolygonPoint]] = []
        innerLoops.reserveCapacity(innerPointLoops.count)
        for innerPoints in innerPointLoops {
            var inner = planarPolygonPoints(
                points: innerPoints,
                projected: projected,
                cursor: &cursor
            )
            guard abs(planarSignedArea(inner.map(\.projected))) > tolerance.distance * tolerance.distance else {
                throw TessellationError.degenerateFace(faceID)
            }
            if planarSignedArea(inner.map(\.projected)) > 0.0 {
                inner.reverse()
            }
            try validateHole(inner, isInside: outer, faceID: faceID)
            innerLoops.append(inner)
        }
        try validateDisjointHoles(innerLoops, faceID: faceID)

        var bridged = outer
        let orderedInnerLoops = innerLoops.sorted { lhs, rhs in
            let left = rightmostPlanarPoint(in: lhs)
            let right = rightmostPlanarPoint(in: rhs)
            if left.x != right.x {
                return left.x > right.x
            }
            return left.y < right.y
        }
        for inner in orderedInnerLoops {
            let bridge = try visibleBridge(
                from: inner,
                to: bridged,
                outer: outer,
                holes: innerLoops,
                faceID: faceID
            )
            bridged = bridgedPlanarBoundary(
                boundary: bridged,
                inner: inner,
                bridge: bridge
            )
        }
        return bridged.map(\.point)
    }

    private func planarPolygonPoints(
        points: [Point3D],
        projected: [PlanarPoint2D],
        cursor: inout Int
    ) -> [PlanarPolygonPoint] {
        let start = cursor
        cursor += points.count
        return points.indices.map { index in
            PlanarPolygonPoint(
                point: points[index],
                projected: projected[start + index]
            )
        }
    }

    private func rightmostPlanarPoint(in points: [PlanarPolygonPoint]) -> PlanarPoint2D {
        points.map(\.projected).max { lhs, rhs in
            if lhs.x != rhs.x {
                return lhs.x < rhs.x
            }
            return lhs.y > rhs.y
        } ?? PlanarPoint2D(x: 0.0, y: 0.0)
    }

    private func bridgedPlanarBoundary(
        boundary: [PlanarPolygonPoint],
        inner: [PlanarPolygonPoint],
        bridge: (innerIndex: Int, boundaryIndex: Int)
    ) -> [PlanarPolygonPoint] {
        var bridged: [PlanarPolygonPoint] = []
        bridged.reserveCapacity(boundary.count + inner.count + 2)
        bridged.append(contentsOf: boundary[...bridge.boundaryIndex])
        for offset in 0..<inner.count {
            bridged.append(inner[(bridge.innerIndex + offset) % inner.count])
        }
        bridged.append(inner[bridge.innerIndex])
        bridged.append(boundary[bridge.boundaryIndex])
        let nextBoundaryIndex = bridge.boundaryIndex + 1
        if nextBoundaryIndex < boundary.count {
            bridged.append(contentsOf: boundary[nextBoundaryIndex...])
        }
        return bridged
    }

    private func validateDisjointHoles(
        _ holes: [[PlanarPolygonPoint]],
        faceID: FaceID
    ) throws {
        for firstIndex in holes.indices {
            let first = holes[firstIndex].map(\.projected)
            for secondIndex in holes.indices where secondIndex > firstIndex {
                let second = holes[secondIndex].map(\.projected)
                for firstEdgeIndex in first.indices {
                    let firstStart = first[firstEdgeIndex]
                    let firstEnd = first[(firstEdgeIndex + 1) % first.count]
                    for secondEdgeIndex in second.indices {
                        let secondStart = second[secondEdgeIndex]
                        let secondEnd = second[(secondEdgeIndex + 1) % second.count]
                        guard segmentsIntersect(firstStart, firstEnd, secondStart, secondEnd) == false else {
                            throw TessellationError.unsupportedFace(faceID)
                        }
                    }
                }
                if let firstPoint = first.first,
                   point(firstPoint, isInsidePolygonWith: second) {
                    throw TessellationError.unsupportedFace(faceID)
                }
                if let secondPoint = second.first,
                   point(secondPoint, isInsidePolygonWith: first) {
                    throw TessellationError.unsupportedFace(faceID)
                }
            }
        }
    }

    private func validateHole(
        _ inner: [PlanarPolygonPoint],
        isInside outer: [PlanarPolygonPoint],
        faceID: FaceID
    ) throws {
        let outerProjected = outer.map(\.projected)
        let innerProjected = inner.map(\.projected)
        try validateSimplePolygon(outerProjected, faceID: faceID)
        try validateSimplePolygon(innerProjected, faceID: faceID)
        for projectedPoint in innerProjected {
            guard point(projectedPoint, isInsidePolygonWith: outerProjected) else {
                throw TessellationError.unsupportedFace(faceID)
            }
        }
        for innerIndex in innerProjected.indices {
            let innerStart = innerProjected[innerIndex]
            let innerEnd = innerProjected[(innerIndex + 1) % innerProjected.count]
            for outerIndex in outerProjected.indices {
                let outerStart = outerProjected[outerIndex]
                let outerEnd = outerProjected[(outerIndex + 1) % outerProjected.count]
                guard segmentsIntersect(innerStart, innerEnd, outerStart, outerEnd) == false else {
                    throw TessellationError.unsupportedFace(faceID)
                }
            }
        }
    }

    private func visibleBridge(
        from inner: [PlanarPolygonPoint],
        to boundary: [PlanarPolygonPoint],
        outer: [PlanarPolygonPoint],
        holes: [[PlanarPolygonPoint]],
        faceID: FaceID
    ) throws -> (innerIndex: Int, boundaryIndex: Int) {
        var candidates: [(innerIndex: Int, boundaryIndex: Int, distance: Double)] = []
        candidates.reserveCapacity(inner.count * boundary.count)
        for innerIndex in inner.indices {
            for boundaryIndex in boundary.indices {
                let distance = planarDistance(
                    inner[innerIndex].projected,
                    to: boundary[boundaryIndex].projected
                )
                candidates.append((innerIndex, boundaryIndex, distance))
            }
        }
        candidates.sort { lhs, rhs in
            if lhs.distance != rhs.distance {
                return lhs.distance < rhs.distance
            }
            if lhs.innerIndex != rhs.innerIndex {
                return lhs.innerIndex < rhs.innerIndex
            }
            return lhs.boundaryIndex < rhs.boundaryIndex
        }

        for candidate in candidates {
            if bridgeIsVisible(
                innerIndex: candidate.innerIndex,
                boundaryIndex: candidate.boundaryIndex,
                inner: inner,
                boundary: boundary,
                outer: outer,
                holes: holes
            ) {
                return (candidate.innerIndex, candidate.boundaryIndex)
            }
        }
        throw TessellationError.unsupportedFace(faceID)
    }

    private func bridgeIsVisible(
        innerIndex: Int,
        boundaryIndex: Int,
        inner: [PlanarPolygonPoint],
        boundary: [PlanarPolygonPoint],
        outer: [PlanarPolygonPoint],
        holes: [[PlanarPolygonPoint]]
    ) -> Bool {
        let start = inner[innerIndex].projected
        let end = boundary[boundaryIndex].projected
        guard planarDistance(start, to: end) > tolerance.distance else {
            return false
        }
        let midpoint = PlanarPoint2D(
            x: (start.x + end.x) * 0.5,
            y: (start.y + end.y) * 0.5
        )
        guard point(midpoint, isInsidePolygonWith: outer.map(\.projected)),
              holes.allSatisfy({ point(midpoint, isInsidePolygonWith: $0.map(\.projected)) == false }) else {
            return false
        }

        guard bridgeSegment(from: start, to: end, avoids: boundary, allowedSharedPoint: end),
              bridgeSegment(from: start, to: end, avoids: inner, allowedSharedPoint: start) else {
            return false
        }

        for hole in holes where planarLoop(hole, matches: inner) == false {
            let allowedSharedPoint = planarLoop(hole, contains: end) ? end : nil
            guard bridgeSegment(
                from: start,
                to: end,
                avoids: hole,
                allowedSharedPoint: allowedSharedPoint
            ) else {
                return false
            }
        }
        return true
    }

    private func bridgeSegment(
        from start: PlanarPoint2D,
        to end: PlanarPoint2D,
        avoids loop: [PlanarPolygonPoint],
        allowedSharedPoint: PlanarPoint2D?
    ) -> Bool {
        for index in loop.indices {
            let edgeStart = loop[index].projected
            let edgeEnd = loop[(index + 1) % loop.count].projected
            if bridgeSegment(
                from: start,
                to: end,
                intersectsEdgeFrom: edgeStart,
                to: edgeEnd,
                allowedSharedPoint: edgeTouches(edgeStart, edgeEnd, point: allowedSharedPoint) ? allowedSharedPoint : nil
            ) {
                return false
            }
        }
        return true
    }

    private func edgeTouches(
        _ start: PlanarPoint2D,
        _ end: PlanarPoint2D,
        point candidate: PlanarPoint2D?
    ) -> Bool {
        guard let candidate else {
            return false
        }
        return point(candidate, matches: start) || point(candidate, matches: end)
    }

    private func planarLoop(
        _ loop: [PlanarPolygonPoint],
        contains point: PlanarPoint2D
    ) -> Bool {
        loop.contains { candidate in
            self.point(candidate.projected, matches: point)
        }
    }

    private func planarLoop(
        _ lhs: [PlanarPolygonPoint],
        matches rhs: [PlanarPolygonPoint]
    ) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        return zip(lhs, rhs).allSatisfy { first, second in
            point(first.projected, matches: second.projected)
        }
    }

    private func bridgeSegment(
        from start: PlanarPoint2D,
        to end: PlanarPoint2D,
        intersectsEdgeFrom edgeStart: PlanarPoint2D,
        to edgeEnd: PlanarPoint2D,
        allowedSharedPoint: PlanarPoint2D?
    ) -> Bool {
        guard segmentsIntersect(start, end, edgeStart, edgeEnd) else {
            return false
        }
        guard let allowedSharedPoint,
              point(allowedSharedPoint, matches: edgeStart) || point(allowedSharedPoint, matches: edgeEnd) else {
            return true
        }
        let otherEndpoint = point(allowedSharedPoint, matches: edgeStart) ? edgeEnd : edgeStart
        return point(otherEndpoint, liesOnSegmentFrom: start, to: end)
    }

    private func faceNormal(points: [Point3D], faceID: FaceID) throws -> Vector3D {
        guard points.count >= 3 else {
            throw TessellationError.degenerateFace(faceID)
        }
        // Newell summation over the whole loop: the former first-cross scan
        // let near-collinear leading arc samples pick the projection normal
        // from rounding noise. Rebasing at the first point keeps the
        // summation well conditioned far from the model origin. The summed
        // vector length equals twice the enclosed loop area, so reuse the
        // same degeneracy gate Mesh.validate applies to triangle areas.
        let origin = points[0]
        var sum = Vector3D(x: 0.0, y: 0.0, z: 0.0)
        var previous = points[points.count - 1] - origin
        for point in points {
            let current = point - origin
            sum = sum + previous.cross(current)
            previous = current
        }
        try sum.validate()
        let length = sum.length
        guard length.isFinite else {
            throw GeometryError.invalidVectorLength(length)
        }
        guard length > tolerance.distance * tolerance.distance else {
            throw TessellationError.degenerateFace(faceID)
        }
        return sum / length
    }

    private func simplifiedPlanarPoints(
        _ points: [Point3D],
        faceID: FaceID
    ) throws -> [Point3D] {
        try simplifiedPlanarPoints(
            points,
            faceID: faceID,
            maximumDeviation: tolerance.distance
        )
    }

    private func simplifiedPlanarPoints(
        _ points: [Point3D],
        faceID: FaceID,
        maximumDeviation: Double
    ) throws -> [Point3D] {
        // Chord-height (sagitta) simplification. A vertex may be removed only
        // when EVERY original sample covered by the replacement chord stays
        // within the requested deviation of that chord; checking only
        // the candidate against its immediate neighbours lets the deviation
        // accumulate far beyond the tolerance on long arc runs. Unlike the
        // former |cross| <= distance^2 area criterion this is scale-correct:
        // it collapses near-collinear arc-sample runs (the sliver seeds that
        // break ear clipping) while bounding the Hausdorff deviation of the
        // simplified loop by maximumDeviation.
        var survivors = Array(points.indices)
        var didRemove = true
        while didRemove, survivors.count > 3 {
            didRemove = false
            for index in survivors.indices {
                let previousOriginal = survivors[(index + survivors.count - 1) % survivors.count]
                let nextOriginal = survivors[(index + 1) % survivors.count]
                if chordCoversOriginalPoints(
                    from: previousOriginal,
                    to: nextOriginal,
                    within: maximumDeviation,
                    points: points
                ) {
                    survivors.remove(at: index)
                    didRemove = true
                    break
                }
            }
        }
        guard survivors.count >= 3 else {
            throw TessellationError.degenerateFace(faceID)
        }
        let simplified = survivors.map { points[$0] }
        _ = try faceNormal(points: simplified, faceID: faceID)
        return simplified
    }

    /// True when every original point strictly between the two original
    /// indices (walking forward cyclically) lies within `limit` of the chord
    /// joining them.
    private func chordCoversOriginalPoints(
        from startIndex: Int,
        to endIndex: Int,
        within limit: Double,
        points: [Point3D]
    ) -> Bool {
        let start = points[startIndex]
        let end = points[endIndex]
        var index = (startIndex + 1) % points.count
        while index != endIndex {
            guard distance(of: points[index], toSegmentFrom: start, to: end) <= limit else {
                return false
            }
            index = (index + 1) % points.count
        }
        return true
    }

    private func distance(
        of point: Point3D,
        toSegmentFrom start: Point3D,
        to end: Point3D
    ) -> Double {
        let axis = end - start
        let lengthSquared = axis.dot(axis)
        guard lengthSquared > 0.0 else {
            return (point - start).length
        }
        let ratio = max(0.0, min(1.0, (point - start).dot(axis) / lengthSquared))
        let projection = start + axis * ratio
        return (point - projection).length
    }

    private func planarFaceTriangles(
        points: [Point3D],
        normal: Vector3D,
        faceID: FaceID,
        physicalPoints: [Point3D]? = nil
    ) throws -> [TriangleIndex] {
        guard points.count >= 3 else {
            throw TessellationError.degenerateFace(faceID)
        }
        guard physicalPoints == nil || physicalPoints?.count == points.count else {
            throw TessellationError.unsupportedFace(faceID)
        }
        if points.count == 3 {
            if let physicalPoints,
               triangleHasUsableArea(
                   first: 0,
                   second: 1,
                   third: 2,
                   points: physicalPoints
               ) == false {
                throw TessellationError.degenerateFace(faceID)
            }
            return [TriangleIndex(first: 0, second: 1, third: 2)]
        }

        let projectedPoints = try projectedPlanarPoints(
            points,
            normal: normal
        )
        let signedArea = planarSignedArea(projectedPoints)
        guard abs(signedArea) > tolerance.distance * tolerance.distance else {
            throw TessellationError.degenerateFace(faceID)
        }

        var remaining = Array(points.indices)
        let windingSign = signedArea >= 0.0 ? 1.0 : -1.0
        var triangles: [TriangleIndex] = []
        var guardCount = 0
        while remaining.count > 3 {
            guardCount += 1
            guard guardCount <= points.count * points.count else {
                throw TessellationError.unsupportedFace(faceID)
            }

            var didClipEar = false
            for localIndex in remaining.indices {
                let previousIndex = remaining[(localIndex + remaining.count - 1) % remaining.count]
                let currentIndex = remaining[localIndex]
                let nextIndex = remaining[(localIndex + 1) % remaining.count]
                guard isEar(
                    previousIndex: previousIndex,
                    currentIndex: currentIndex,
                    nextIndex: nextIndex,
                    remaining: remaining,
                    points: projectedPoints,
                    physicalPoints: physicalPoints,
                    windingSign: windingSign
                ) else {
                    continue
                }
                triangles.append(TriangleIndex(
                    first: previousIndex,
                    second: currentIndex,
                    third: nextIndex
                ))
                remaining.remove(at: localIndex)
                didClipEar = true
                break
            }

            guard didClipEar else {
                throw TessellationError.unsupportedFace(faceID)
            }
        }

        if let physicalPoints,
           triangleHasUsableArea(
               first: remaining[0],
               second: remaining[1],
               third: remaining[2],
               points: physicalPoints
           ) == false {
            throw TessellationError.unsupportedFace(faceID)
        }
        triangles.append(TriangleIndex(
            first: remaining[0],
            second: remaining[1],
            third: remaining[2]
        ))
        return triangles
    }

    private func projectedPlanarPoints(
        _ points: [Point3D],
        normal: Vector3D
    ) throws -> [PlanarPoint2D] {
        let normalizedNormal = try normal.normalized(tolerance: tolerance.distance)
        let helper = abs(normalizedNormal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let uAxis = try helper.cross(normalizedNormal).normalized(tolerance: tolerance.distance)
        let vAxis = normalizedNormal.cross(uAxis)
        let origin = points[0]
        return points.map { point in
            let offset = point - origin
            return PlanarPoint2D(
                x: offset.dot(uAxis),
                y: offset.dot(vAxis)
            )
        }
    }

    private func isEar(
        previousIndex: Int,
        currentIndex: Int,
        nextIndex: Int,
        remaining: [Int],
        points: [PlanarPoint2D],
        physicalPoints: [Point3D]?,
        windingSign: Double
    ) -> Bool {
        let previous = points[previousIndex]
        let current = points[currentIndex]
        let next = points[nextIndex]
        let turn = planarCross(previous, current, next) * windingSign
        let convexGate = max(
            tolerance.distance * tolerance.distance,
            minimumMeaningfulCross(
                planarDistance(previous, to: current),
                planarDistance(previous, to: next)
            )
        )
        guard turn > convexGate else {
            return false
        }
        if let physicalPoints,
           triangleHasUsableArea(
               first: previousIndex,
               second: currentIndex,
               third: nextIndex,
               points: physicalPoints
           ) == false {
            return false
        }

        for candidateIndex in remaining {
            guard candidateIndex != previousIndex,
                  candidateIndex != currentIndex,
                  candidateIndex != nextIndex else {
                continue
            }
            let candidate = points[candidateIndex]
            if point(candidate, matches: previous)
                || point(candidate, matches: current)
                || point(candidate, matches: next) {
                continue
            }
            if point(
                candidate,
                isInsideOrOnTriangleWith: previous,
                current,
                next
            ) {
                return false
            }
        }
        return true
    }

    private func triangleHasUsableArea(
        first: Int,
        second: Int,
        third: Int,
        points: [Point3D]
    ) -> Bool {
        triangleHasUsableArea(
            firstPoint: points[first],
            secondPoint: points[second],
            thirdPoint: points[third]
        )
    }

    private func triangleHasUsableArea(
        firstPoint: Point3D,
        secondPoint: Point3D,
        thirdPoint: Point3D
    ) -> Bool {
        let firstEdge = secondPoint - firstPoint
        let secondEdge = thirdPoint - firstPoint
        let area = firstEdge.cross(secondEdge).length
        let adoptionGate = max(
            tolerance.distance * tolerance.distance,
            minimumMeaningfulCross(firstEdge.length, secondEdge.length)
        )
        return area.isFinite && area > adoptionGate
    }

    private func point(
        _ point: PlanarPoint2D,
        isInsideOrOnTriangleWith first: PlanarPoint2D,
        _ second: PlanarPoint2D,
        _ third: PlanarPoint2D
    ) -> Bool {
        // planarCross(a, b, p) == |b - a| * signedDistance(p, line(a, b)), so
        // scaling the band by the edge length turns the former absolute
        // distance^2 area band into a proper distance-from-edge test.
        let bandFloor = tolerance.distance * tolerance.distance
        let firstBand = max(bandFloor, tolerance.distance * planarDistance(first, to: second))
        let secondBand = max(bandFloor, tolerance.distance * planarDistance(second, to: third))
        let thirdBand = max(bandFloor, tolerance.distance * planarDistance(third, to: first))
        let firstCross = planarCross(first, second, point)
        let secondCross = planarCross(second, third, point)
        let thirdCross = planarCross(third, first, point)
        let hasNegative = firstCross < -firstBand
            || secondCross < -secondBand
            || thirdCross < -thirdBand
        let hasPositive = firstCross > firstBand
            || secondCross > secondBand
            || thirdCross > thirdBand
        return !(hasNegative && hasPositive)
    }

    private func validateSimplePolygon(
        _ points: [PlanarPoint2D],
        faceID: FaceID
    ) throws {
        guard points.count >= 3 else {
            throw TessellationError.degenerateFace(faceID)
        }
        for index in points.indices {
            guard planarDistance(points[index], to: points[(index + 1) % points.count]) > tolerance.distance else {
                throw TessellationError.degenerateFace(faceID)
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
                guard segmentsIntersect(firstStart, firstEnd, secondStart, secondEnd) == false else {
                    throw TessellationError.unsupportedFace(faceID)
                }
            }
        }
    }

    private func point(
        _ candidate: PlanarPoint2D,
        isInsidePolygonWith polygon: [PlanarPoint2D]
    ) -> Bool {
        guard polygon.count >= 3 else {
            return false
        }
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            if point(candidate, liesOnSegmentFrom: start, to: end) {
                return false
            }
        }

        var isInside = false
        var previousIndex = polygon.count - 1
        for currentIndex in polygon.indices {
            let current = polygon[currentIndex]
            let previous = polygon[previousIndex]
            let crosses = (current.y > candidate.y) != (previous.y > candidate.y)
            if crosses {
                let x = (previous.x - current.x) * (candidate.y - current.y) /
                    (previous.y - current.y) + current.x
                if candidate.x < x {
                    isInside.toggle()
                }
            }
            previousIndex = currentIndex
        }
        return isInside
    }

    private func segmentsIntersect(
        _ firstStart: PlanarPoint2D,
        _ firstEnd: PlanarPoint2D,
        _ secondStart: PlanarPoint2D,
        _ secondEnd: PlanarPoint2D
    ) -> Bool {
        let areaTolerance = tolerance.distance * tolerance.distance
        let firstSecondStart = planarCross(firstStart, firstEnd, secondStart)
        let firstSecondEnd = planarCross(firstStart, firstEnd, secondEnd)
        let secondFirstStart = planarCross(secondStart, secondEnd, firstStart)
        let secondFirstEnd = planarCross(secondStart, secondEnd, firstEnd)

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
           point(secondStart, liesOnSegmentFrom: firstStart, to: firstEnd) {
            return true
        }
        if abs(firstSecondEnd) <= areaTolerance,
           point(secondEnd, liesOnSegmentFrom: firstStart, to: firstEnd) {
            return true
        }
        if abs(secondFirstStart) <= areaTolerance,
           point(firstStart, liesOnSegmentFrom: secondStart, to: secondEnd) {
            return true
        }
        if abs(secondFirstEnd) <= areaTolerance,
           point(firstEnd, liesOnSegmentFrom: secondStart, to: secondEnd) {
            return true
        }
        return false
    }

    private func point(
        _ point: PlanarPoint2D,
        liesOnSegmentFrom start: PlanarPoint2D,
        to end: PlanarPoint2D
    ) -> Bool {
        planarDistance(point, toSegmentFrom: start, to: end) <= tolerance.distance * 10.0
            && point.x >= min(start.x, end.x) - tolerance.distance * 10.0
            && point.x <= max(start.x, end.x) + tolerance.distance * 10.0
            && point.y >= min(start.y, end.y) - tolerance.distance * 10.0
            && point.y <= max(start.y, end.y) + tolerance.distance * 10.0
    }

    private func point(_ lhs: PlanarPoint2D, matches rhs: PlanarPoint2D) -> Bool {
        planarDistance(lhs, to: rhs) <= tolerance.distance * 10.0
    }

    private func planarDistance(_ start: PlanarPoint2D, to end: PlanarPoint2D) -> Double {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func planarDistance(
        _ point: PlanarPoint2D,
        toSegmentFrom start: PlanarPoint2D,
        to end: PlanarPoint2D
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.0 else {
            return planarDistance(point, to: start)
        }
        let t = max(0.0, min(1.0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = PlanarPoint2D(x: start.x + dx * t, y: start.y + dy * t)
        return planarDistance(point, to: projection)
    }

    private func planarSignedArea(_ points: [PlanarPoint2D]) -> Double {
        var twiceArea = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            twiceArea += current.x * next.y - next.x * current.y
        }
        return twiceArea * 0.5
    }

    private func planarCross(
        _ first: PlanarPoint2D,
        _ second: PlanarPoint2D,
        _ third: PlanarPoint2D
    ) -> Double {
        (second.x - first.x) * (third.y - first.y)
            - (second.y - first.y) * (third.x - first.x)
    }

    private func sampledPoints(
        for loopID: LoopID,
        in model: BRepModel,
        options: TessellationOptions
    ) throws -> [Point3D] {
        guard let loop = model.loops[loopID] else {
            throw TopologyError.missingReference("Missing loop \(loopID).")
        }
        return try sampledPoints(for: loop, in: model, options: options)
    }

    private func sampledPoints(
        for loop: Loop,
        in model: BRepModel,
        options: TessellationOptions
    ) throws -> [Point3D] {
        var points: [Point3D] = []
        for orientedEdge in loop.edges {
            let edgePoints = try sampledPoints(
                for: orientedEdge,
                in: model,
                options: options
            )
            guard let first = edgePoints.first else {
                continue
            }
            if points.last.map({ isClose($0, first) }) != true {
                points.append(first)
            }
            points.append(contentsOf: edgePoints.dropFirst().dropLast())
        }
        if let first = points.first,
           let last = points.last,
           isClose(first, last) {
            points.removeLast()
        }
        return points
    }

    private func appendPlanarCurvedFace(
        points: [Point3D],
        surface: Surface3D,
        face: Face,
        faceID: FaceID,
        shellOrientation: Orientation,
        positions: inout [Point3D],
        normals: inout [Vector3D],
        indices: inout [UInt32]
    ) throws {
        let geometricNormal = try faceNormal(points: points, faceID: faceID)
        let pointNormals = try surfaceNormals(
            for: points,
            on: surface,
            face: face,
            shellOrientation: shellOrientation
        )
        let referenceNormal = try averageNormal(pointNormals, faceID: faceID)
        let shouldReverse = geometricNormal.dot(referenceNormal) < 0.0

        if try isCircularPlanarLoop(points) || isConvexPlanarLoop(points, normal: geometricNormal) {
            guard UInt64(positions.count) + UInt64(points.count) + 1 <= UInt64(UInt32.max) else {
                throw TessellationError.unsupportedFace(faceID)
            }
            let center = centroid(of: points)
            let centerNormal = try averageNormal(pointNormals, faceID: faceID)
            let centerIndex = UInt32(positions.count)
            positions.append(center)
            normals.append(centerNormal)
            let pointBaseIndex = UInt32(positions.count)
            positions.append(contentsOf: points)
            normals.append(contentsOf: pointNormals)

            for index in points.indices {
                let next = (index + 1) % points.count
                indices.append(centerIndex)
                if shouldReverse {
                    indices.append(pointBaseIndex + UInt32(next))
                    indices.append(pointBaseIndex + UInt32(index))
                } else {
                    indices.append(pointBaseIndex + UInt32(index))
                    indices.append(pointBaseIndex + UInt32(next))
                }
            }
            return
        }

        let tessellationPoints = try simplifiedPlanarPoints(
            points,
            faceID: faceID
        )
        let tessellationNormals = try surfaceNormals(
            for: tessellationPoints,
            on: surface,
            face: face,
            shellOrientation: shellOrientation
        )
        guard UInt64(positions.count) + UInt64(tessellationPoints.count) <= UInt64(UInt32.max) else {
            throw TessellationError.unsupportedFace(faceID)
        }
        let pointBaseIndex = UInt32(positions.count)
        positions.append(contentsOf: tessellationPoints)
        normals.append(contentsOf: tessellationNormals)

        let triangles = try planarFaceTriangles(
            points: tessellationPoints,
            normal: geometricNormal,
            faceID: faceID
        )
        for triangle in triangles {
            let appended: Bool
            if shouldReverse {
                appended = appendTriangle(
                    pointBaseIndex + UInt32(triangle.first),
                    pointBaseIndex + UInt32(triangle.third),
                    pointBaseIndex + UInt32(triangle.second),
                    positions: positions,
                    normals: normals,
                    indices: &indices
                )
            } else {
                appended = appendTriangle(
                    pointBaseIndex + UInt32(triangle.first),
                    pointBaseIndex + UInt32(triangle.second),
                    pointBaseIndex + UInt32(triangle.third),
                    positions: positions,
                    normals: normals,
                    indices: &indices
                )
            }
            guard appended else {
                throw TessellationError.degenerateFace(faceID)
            }
        }
    }

    /// Smallest cross-product magnitude that is geometrically meaningful for
    /// two edges of the given lengths: |e1 x e2| = |e1||e2|sin(angle), so a
    /// turn is real only when the sine of the angle between the edges exceeds
    /// the angular modeling tolerance. Absolute epsilons fail here: short
    /// arc-sample chords produce legitimate turns far below distance^2.
    private func minimumMeaningfulCross(
        _ firstEdgeLength: Double,
        _ secondEdgeLength: Double
    ) -> Double {
        tolerance.angle * firstEdgeLength * secondEdgeLength
    }

    private func isConvexPlanarLoop(
        _ points: [Point3D],
        normal: Vector3D
    ) throws -> Bool {
        guard points.count >= 3 else {
            return false
        }
        let projectedPoints = try projectedPlanarPoints(points, normal: normal)
        let signedArea = planarSignedArea(projectedPoints)
        let areaTolerance = tolerance.distance * tolerance.distance
        guard abs(signedArea) > areaTolerance else {
            return false
        }

        let windingSign = signedArea >= 0.0 ? 1.0 : -1.0
        var hasNonCollinearTurn = false
        for index in projectedPoints.indices {
            let previous = projectedPoints[(index + projectedPoints.count - 1) % projectedPoints.count]
            let current = projectedPoints[index]
            let next = projectedPoints[(index + 1) % projectedPoints.count]
            let turn = planarCross(previous, current, next) * windingSign
            let sliverGate = minimumMeaningfulCross(
                planarDistance(previous, to: current),
                planarDistance(previous, to: next)
            )
            // Reflex detection must not carry the absolute distance^2 floor:
            // legitimate reflex turns on short arc chords sit far below it
            // (annulus caps misclassify as convex and fan-triangulate with
            // flipped winding).
            if turn < -sliverGate {
                return false
            }
            if turn > max(sliverGate, areaTolerance) {
                hasNonCollinearTurn = true
            }
        }
        return hasNonCollinearTurn
    }

    private func isCircularPlanarLoop(_ points: [Point3D]) throws -> Bool {
        guard points.count >= 8 else {
            return false
        }
        let center = centroid(of: points)
        let distances = points.map { ($0 - center).length }
        guard let firstDistance = distances.first,
              firstDistance > tolerance.distance else {
            return false
        }
        let allowedDeviation = max(tolerance.distance * 10.0, firstDistance * 1.0e-6)
        return distances.allSatisfy { abs($0 - firstDistance) <= allowedDeviation }
    }

    private func appendParametricFace(
        surface: Surface3D,
        outerLoop: Loop,
        innerLoopIDs: [LoopID],
        face: Face,
        faceID: FaceID,
        shellOrientation: Orientation,
        model: BRepModel,
        options: TessellationOptions,
        positions: inout [Point3D],
        normals: inout [Vector3D],
        indices: inout [UInt32]
    ) throws {
        try surface.validate(tolerance: tolerance)
        if innerLoopIDs.isEmpty,
           let bounds = try rectangularParameterBounds(
               for: outerLoop,
               on: surface,
               in: model,
               options: options,
               faceID: faceID
           ) {
            try appendParametricGridFace(
                surface: surface,
                uBounds: bounds.u,
                vBounds: bounds.v,
                face: face,
                faceID: faceID,
                shellOrientation: shellOrientation,
                options: options,
                positions: &positions,
                normals: &normals,
                indices: &indices
            )
            return
        }

        let outerParameters = try sampledParameters(
            for: outerLoop,
            on: surface,
            in: model,
            options: options,
            faceID: faceID
        )
        let innerParameterLoops = try innerLoopIDs.map { innerLoopID -> [SurfaceParameter] in
            guard let innerLoop = model.loops[innerLoopID] else {
                throw TopologyError.missingReference("Missing loop \(innerLoopID).")
            }
            return try sampledParameters(
                for: innerLoop,
                on: surface,
                in: model,
                options: options,
                faceID: faceID
            )
        }
        try appendTrimmedParametricFace(
            surface: surface,
            outerParameters: outerParameters,
            innerParameterLoops: innerParameterLoops,
            face: face,
            faceID: faceID,
            shellOrientation: shellOrientation,
            positions: &positions,
            normals: &normals,
            indices: &indices
        )
    }

    private func appendParametricGridFace(
        surface: Surface3D,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        face: Face,
        faceID: FaceID,
        shellOrientation: Orientation,
        options: TessellationOptions,
        positions: inout [Point3D],
        normals: inout [Vector3D],
        indices: inout [UInt32]
    ) throws {
        let stepCounts = try parametricGridStepCounts(
            surface: surface,
            uBounds: uBounds,
            vBounds: vBounds,
            options: options
        )
        let uSteps = stepCounts.u
        let vSteps = stepCounts.v
        let pointCount = (uSteps + 1) * (vSteps + 1)
        guard UInt64(positions.count) + UInt64(pointCount) <= UInt64(UInt32.max) else {
            throw TessellationError.unsupportedFace(faceID)
        }

        let baseIndex = UInt32(positions.count)
        for vIndex in 0...vSteps {
            let v = interpolatedParameter(
                lowerBound: vBounds.lower,
                upperBound: vBounds.upper,
                index: vIndex,
                count: vSteps
            )
            for uIndex in 0...uSteps {
                let u = interpolatedParameter(
                    lowerBound: uBounds.lower,
                    upperBound: uBounds.upper,
                    index: uIndex,
                    count: uSteps
                )
                let point = try surface.point(u: u, v: v, tolerance: tolerance)
                // Trust the surface normal composed with face and shell
                // orientation. The previous first-vertex hemisphere heuristic
                // silently flipped normals (and therefore winding) on patches
                // whose normals turn more than 90 degrees, corrupting the mesh
                // orientation the divergence volume relies on.
                let normal = try oriented(
                    parametricGridNormal(
                        surface: surface,
                        u: u,
                        v: v,
                        uIndex: uIndex,
                        vIndex: vIndex,
                        uSteps: uSteps,
                        vSteps: vSteps,
                        uBounds: uBounds,
                        vBounds: vBounds
                    ),
                    face: face,
                    shellOrientation: shellOrientation
                )
                positions.append(point)
                normals.append(normal)
            }
        }

        for vIndex in 0..<vSteps {
            for uIndex in 0..<uSteps {
                let lowerLeft = baseIndex + UInt32(vIndex * (uSteps + 1) + uIndex)
                let lowerRight = lowerLeft + 1
                let upperLeft = lowerLeft + UInt32(uSteps + 1)
                let upperRight = upperLeft + 1
                let appendedFirst = appendTriangleWithNormalFallback(
                    lowerLeft,
                    lowerRight,
                    upperRight,
                    positions: &positions,
                    normals: &normals,
                    indices: &indices
                )
                let appendedSecond = appendTriangleWithNormalFallback(
                    lowerLeft,
                    upperRight,
                    upperLeft,
                    positions: &positions,
                    normals: &normals,
                    indices: &indices
                )
                // A silently skipped quad leaves a hole that mesh compaction
                // hides from validation; fail loudly instead.
                guard appendedFirst, appendedSecond else {
                    throw TessellationError.degenerateFace(face.id)
                }
            }
        }
    }

    private func parametricGridStepCounts(
        surface: Surface3D,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        options: TessellationOptions
    ) throws -> (u: Int, v: Int) {
        let uSpan = abs(uBounds.upper - uBounds.lower)
        let vSpan = abs(vBounds.upper - vBounds.lower)
        switch surface {
        case .plane:
            return (
                linearStepCount(length: uSpan, options: options),
                linearStepCount(length: vSpan, options: options)
            )
        case let .cylinder(cylinder):
            return (
                try circularStepCount(
                    radius: cylinder.radius,
                    angleSpan: uSpan,
                    options: options
                ),
                linearStepCount(length: vSpan, options: options)
            )
        case let .analytic(analyticSurface):
            switch analyticSurface {
            case .plane:
                return (
                    linearStepCount(length: uSpan, options: options),
                    linearStepCount(length: vSpan, options: options)
                )
            case let .cylinder(_, _, radius):
                return (
                    try circularStepCount(
                        radius: radius,
                        angleSpan: uSpan,
                        options: options
                    ),
                    linearStepCount(length: vSpan, options: options)
                )
            case let .cone(_, _, halfAngle):
                let maximumRadius = max(abs(vBounds.lower), abs(vBounds.upper)) * sin(halfAngle)
                let uSteps = maximumRadius > tolerance.distance
                    ? try circularStepCount(
                        radius: maximumRadius,
                        angleSpan: uSpan,
                        options: options
                    )
                    : 1
                return (
                    uSteps,
                    linearStepCount(length: vSpan, options: options)
                )
            case let .sphere(_, radius):
                return (
                    try circularStepCount(
                        radius: radius,
                        angleSpan: uSpan,
                        options: options
                    ),
                    try circularStepCount(
                        radius: radius,
                        angleSpan: vSpan,
                        options: options
                    )
                )
            case let .torus(_, _, majorRadius, minorRadius):
                return (
                    try circularStepCount(
                        radius: majorRadius + minorRadius,
                        angleSpan: uSpan,
                        options: options
                    ),
                    try circularStepCount(
                        radius: minorRadius,
                        angleSpan: vSpan,
                        options: options
                    )
                )
            }
        case .bSpline:
            let steps = bSplineStepCount(options: options)
            return (steps, steps)
        case let .procedural(.offset(offset)):
            if let equivalent = try offset.exactChartPreservingSurface(
                tolerance: tolerance
            ) {
                return try parametricGridStepCounts(
                    surface: equivalent,
                    uBounds: uBounds,
                    vBounds: vBounds,
                    options: options
                )
            }
            return try certifiedProceduralSurfaceStepCounts(
                surface: surface,
                uBounds: uBounds,
                vBounds: vBounds,
                options: options
            )
        case .procedural(.ruled):
            return try certifiedProceduralSurfaceStepCounts(
                surface: surface,
                uBounds: uBounds,
                vBounds: vBounds,
                options: options
            )
        }
    }

    private func certifiedProceduralSurfaceStepCounts(
        surface: Surface3D,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        options: TessellationOptions
    ) throws -> (u: Int, v: Int) {
        let uInterval = try ScalarInterval(
            lower: min(uBounds.lower, uBounds.upper),
            upper: max(uBounds.lower, uBounds.upper)
        )
        let vInterval = try ScalarInterval(
            lower: min(vBounds.lower, vBounds.upper),
            upper: max(vBounds.lower, vBounds.upper)
        )
        let bounds = try DefaultSurfaceDifferentialEncloser().tessellationBounds(
            of: surface,
            over: SurfaceParameterBox(u: uInterval, v: vInterval),
            tolerance: tolerance
        )
        let uSpan = uInterval.width
        let vSpan = vInterval.width
        let maximumStepCount = 65_536
        var uSteps = 1
        var vSteps = 1
        if let maximumEdgeLength = options.maxEdgeLength {
            uSteps = clampedSampleCount(
                bounds.tangentUMagnitudeUpperBound * uSpan / maximumEdgeLength,
                minimum: 1,
                maximum: maximumStepCount
            )
            vSteps = clampedSampleCount(
                bounds.tangentVMagnitudeUpperBound * vSpan / maximumEdgeLength,
                minimum: 1,
                maximum: maximumStepCount
            )
        }

        while true {
            let uStep = uSpan / Double(uSteps)
            let vStep = vSpan / Double(vSteps)
            let mixedContribution = 2.0
                * bounds.secondDerivativeUVMagnitudeUpperBound
                * uStep * vStep
            let linearErrorBound = (
                bounds.secondDerivativeUUMagnitudeUpperBound * uStep * uStep
                    + mixedContribution
                    + bounds.secondDerivativeVVMagnitudeUpperBound * vStep * vStep
            ).nextUp
            let angularErrorBound = (
                bounds.unitNormalDerivativeUMagnitudeUpperBound * uStep
                    + bounds.unitNormalDerivativeVMagnitudeUpperBound * vStep
            ).nextUp
            let uEdgeLength = bounds.tangentUMagnitudeUpperBound * uStep
            let vEdgeLength = bounds.tangentVMagnitudeUpperBound * vStep
            let satisfiesEdgeLength = options.maxEdgeLength.map {
                uEdgeLength <= $0 && vEdgeLength <= $0
            } ?? true
            if linearErrorBound <= options.linearTolerance,
               angularErrorBound <= options.angularTolerance,
               satisfiesEdgeLength {
                return (uSteps, vSteps)
            }
            guard uSteps < maximumStepCount || vSteps < maximumStepCount else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Procedural surface tessellation exceeded its certified grid budget."
                )
            }
            let uContribution = bounds.secondDerivativeUUMagnitudeUpperBound
                    * uStep * uStep
                + bounds.secondDerivativeUVMagnitudeUpperBound * uStep * vStep
                + bounds.unitNormalDerivativeUMagnitudeUpperBound * uStep
                + uEdgeLength
            let vContribution = bounds.secondDerivativeVVMagnitudeUpperBound
                    * vStep * vStep
                + bounds.secondDerivativeUVMagnitudeUpperBound * uStep * vStep
                + bounds.unitNormalDerivativeVMagnitudeUpperBound * vStep
                + vEdgeLength
            if (uContribution >= vContribution && uSteps < maximumStepCount)
                || vSteps == maximumStepCount {
                uSteps = min(maximumStepCount, uSteps * 2)
            } else {
                vSteps = min(maximumStepCount, vSteps * 2)
            }
        }
    }

    private func circularStepCount(
        radius: Double,
        angleSpan: Double,
        options: TessellationOptions
    ) throws -> Int {
        let angularSteps = try CircularCurveSamplingPolicy.standard
            .boundedTessellationArcSegmentCount(
                radius: radius,
                angleSpan: angleSpan,
                angularTolerance: options.angularTolerance,
                modelingTolerance: tolerance
            )
        guard let maxEdgeLength = options.maxEdgeLength else {
            return angularSteps
        }
        let edgeLengthSteps = clampedSampleCount(
            radius * angleSpan / maxEdgeLength,
            minimum: 1,
            maximum: 65_536
        )
        return max(angularSteps, edgeLengthSteps)
    }

    private func linearStepCount(
        length: Double,
        options: TessellationOptions
    ) -> Int {
        guard let maxEdgeLength = options.maxEdgeLength else {
            return 1
        }
        return clampedSampleCount(
            length / maxEdgeLength,
            minimum: 1,
            maximum: 65_536
        )
    }

    private func parametricGridNormal(
        surface: Surface3D,
        u: Double,
        v: Double,
        uIndex: Int,
        vIndex: Int,
        uSteps: Int,
        vSteps: Int,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double)
    ) throws -> Vector3D {
        do {
            return try surface.normal(
                u: u,
                v: v,
                tolerance: tolerance
            )
        } catch let error as KernelError
            where error.code == .singularSystem
                && (
                    uIndex == 0
                        || uIndex == uSteps
                        || vIndex == 0
                        || vIndex == vSteps
                ) {
            let normalU = interpolatedParameter(
                lowerBound: uBounds.lower,
                upperBound: uBounds.upper,
                index: min(max(uIndex, 1), uSteps - 1),
                count: uSteps
            )
            let normalV = interpolatedParameter(
                lowerBound: vBounds.lower,
                upperBound: vBounds.upper,
                index: min(max(vIndex, 1), vSteps - 1),
                count: vSteps
            )
            return try surface.normal(
                u: normalU,
                v: normalV,
                tolerance: tolerance
            )
        }
    }

    /// Converts a sample-count estimate to Int without trapping: non-finite or
    /// huge estimates (e.g. a subnormal angular tolerance driving span/tol to
    /// infinity) clamp to the cap instead of crashing or exhausting memory.
    private func clampedSampleCount(
        _ estimate: Double,
        minimum: Int,
        maximum: Int
    ) -> Int {
        guard estimate.isFinite else {
            return maximum
        }
        let bounded = min(Double(maximum), estimate.rounded(.up))
        return max(minimum, Int(bounded))
    }

    private func appendTrimmedParametricFace(
        surface: Surface3D,
        outerParameters: [SurfaceParameter],
        innerParameterLoops: [[SurfaceParameter]],
        face: Face,
        faceID: FaceID,
        shellOrientation: Orientation,
        positions: inout [Point3D],
        normals: inout [Vector3D],
        indices: inout [UInt32]
    ) throws {
        guard outerParameters.count >= 3 else {
            throw TessellationError.degenerateFace(faceID)
        }
        let innerPointLoops = try innerParameterLoops.map { innerParameters in
            guard innerParameters.count >= 3 else {
                throw TessellationError.degenerateFace(faceID)
            }
            return innerParameters.map(parameterPoint)
        }
        let parameterPoints = try bridgedPlanarFacePoints(
            outerPoints: outerParameters.map(parameterPoint),
            innerPointLoops: innerPointLoops,
            normal: Vector3D.unitZ,
            faceID: faceID
        )
        guard parameterPoints.count >= 3,
              UInt64(positions.count) + UInt64(parameterPoints.count) <= UInt64(UInt32.max) else {
            throw TessellationError.unsupportedFace(faceID)
        }

        let parameters = parameterPoints.map(surfaceParameter)
        let baseIndex = UInt32(positions.count)
        for parameter in parameters {
            positions.append(try surface.point(u: parameter.u, v: parameter.v, tolerance: tolerance))
            normals.append(try oriented(
                surface.normal(u: parameter.u, v: parameter.v, tolerance: tolerance),
                face: face,
                shellOrientation: shellOrientation
            ))
        }

        let boundaryPhysicalPoints = Array(
            positions[Int(baseIndex)..<(Int(baseIndex) + parameters.count)]
        )
        if innerParameterLoops.isEmpty,
           let fanCenter = try parametricFanCenter(
               surface: surface,
               parameters: parameters,
               physicalPoints: boundaryPhysicalPoints,
               face: face,
               shellOrientation: shellOrientation
           ) {
            guard UInt64(positions.count) + 1 <= UInt64(UInt32.max) else {
                throw TessellationError.unsupportedFace(faceID)
            }
            let centerIndex = UInt32(positions.count)
            positions.append(fanCenter.point)
            normals.append(fanCenter.normal)
            for index in parameters.indices {
                let next = (index + 1) % parameters.count
                let appended = appendTriangleWithNormalFallback(
                    centerIndex,
                    baseIndex + UInt32(index),
                    baseIndex + UInt32(next),
                    positions: &positions,
                    normals: &normals,
                    indices: &indices
                )
                guard appended else {
                    throw TessellationError.degenerateFace(faceID)
                }
            }
            return
        }

        let triangles = try planarFaceTriangles(
            points: parameterPoints,
            normal: Vector3D.unitZ,
            faceID: faceID,
            physicalPoints: boundaryPhysicalPoints
        )
        for triangle in triangles {
            let appended = appendTriangleWithNormalFallback(
                baseIndex + UInt32(triangle.first),
                baseIndex + UInt32(triangle.second),
                baseIndex + UInt32(triangle.third),
                positions: &positions,
                normals: &normals,
                indices: &indices
            )
            guard appended else {
                throw TessellationError.degenerateFace(faceID)
            }
        }
    }

    private struct ParametricFanCenter {
        let point: Point3D
        let normal: Vector3D
    }

    private func parametricFanCenter(
        surface: Surface3D,
        parameters: [SurfaceParameter],
        physicalPoints: [Point3D],
        face: Face,
        shellOrientation: Orientation
    ) throws -> ParametricFanCenter? {
        if let parameter = fanTriangulationCenter(for: parameters) {
            return ParametricFanCenter(
                point: try surface.point(
                    u: parameter.u,
                    v: parameter.v,
                    tolerance: tolerance
                ),
                normal: try oriented(
                    surface.normal(
                        u: parameter.u,
                        v: parameter.v,
                        tolerance: tolerance
                    ),
                    face: face,
                    shellOrientation: shellOrientation
                )
            )
        }
        guard case let .analytic(.sphere(center, radius)) = surface,
              let sphericalCenter = try sphericalFanCenter(
                  sphereCenter: center,
                  radius: radius,
                  boundaryPoints: physicalPoints
              ) else {
            return nil
        }
        return ParametricFanCenter(
            point: sphericalCenter.point,
            normal: oriented(
                sphericalCenter.radial,
                face: face,
                shellOrientation: shellOrientation
            )
        )
    }

    private func sphericalFanCenter(
        sphereCenter: Point3D,
        radius: Double,
        boundaryPoints: [Point3D]
    ) throws -> (point: Point3D, radial: Vector3D)? {
        guard boundaryPoints.count >= 3 else {
            return nil
        }
        let radials = try boundaryPoints.map { point in
            try (point - sphereCenter).normalized(tolerance: tolerance.distance)
        }
        let radialSum = radials.reduce(Vector3D.zero, +)
        guard radialSum.length > tolerance.distance else {
            return nil
        }
        let centerRadial = try radialSum.normalized(tolerance: tolerance.distance)
        let helper = abs(centerRadial.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let projectionU = try helper.cross(centerRadial).normalized(
            tolerance: tolerance.distance
        )
        let projectionV = centerRadial.cross(projectionU)
        var projected: [PlanarPoint2D] = []
        projected.reserveCapacity(radials.count)
        for radial in radials {
            let denominator = radial.dot(centerRadial)
            guard denominator > tolerance.angle else {
                return nil
            }
            projected.append(PlanarPoint2D(
                x: radial.dot(projectionU) / denominator,
                y: radial.dot(projectionV) / denominator
            ))
        }
        let signedArea = planarSignedArea(projected)
        guard abs(signedArea) > tolerance.distance * tolerance.distance else {
            return nil
        }
        let windingSign = signedArea > 0.0 ? 1.0 : -1.0
        for index in projected.indices {
            let current = projected[index]
            let next = projected[(index + 1) % projected.count]
            let edgeLength = planarDistance(current, to: next)
            let turn = (current.x * next.y - next.x * current.y) * windingSign
            guard turn > max(
                tolerance.angle * tolerance.angle,
                tolerance.angle * edgeLength
            ), triangleHasUsableArea(
                firstPoint: sphereCenter + centerRadial * radius,
                secondPoint: boundaryPoints[index],
                thirdPoint: boundaryPoints[(index + 1) % boundaryPoints.count]
            ) else {
                return nil
            }
        }
        return (
            point: sphereCenter + centerRadial * radius,
            radial: centerRadial
        )
    }

    private func fanTriangulationCenter(
        for parameters: [SurfaceParameter]
    ) -> SurfaceParameter? {
        guard parameters.count >= 3 else {
            return nil
        }
        let points = parameters.map(parameterPoint)
        let signedArea = planarSignedArea(points.map {
            PlanarPoint2D(x: $0.x, y: $0.y)
        })
        guard abs(signedArea) > tolerance.distance * tolerance.distance else {
            return nil
        }
        var candidates: [SurfaceParameter] = []
        if let areaCentroid = planarAreaCentroid(
            of: parameters,
            signedArea: signedArea
        ) {
            candidates.append(areaCentroid)
        }
        candidates.append(centroidParameter(of: parameters))
        let windingSign = signedArea > 0.0 ? 1.0 : -1.0
        return candidates.first { candidate in
            parameters.indices.allSatisfy { index in
                let current = parameters[index]
                let next = parameters[(index + 1) % parameters.count]
                let edgeLength = hypot(next.u - current.u, next.v - current.v)
                let turn = (
                    (next.u - current.u) * (candidate.v - current.v)
                        - (next.v - current.v) * (candidate.u - current.u)
                ) * windingSign
                return turn > max(
                    tolerance.distance * tolerance.distance,
                    tolerance.distance * edgeLength
                )
            }
        }
    }

    private func planarAreaCentroid(
        of parameters: [SurfaceParameter],
        signedArea: Double
    ) -> SurfaceParameter? {
        var weightedU = 0.0
        var weightedV = 0.0
        for index in parameters.indices {
            let current = parameters[index]
            let next = parameters[(index + 1) % parameters.count]
            let cross = current.u * next.v - next.u * current.v
            weightedU += (current.u + next.u) * cross
            weightedV += (current.v + next.v) * cross
        }
        let denominator = 6.0 * signedArea
        guard denominator.isFinite,
              abs(denominator) > Double.ulpOfOne else {
            return nil
        }
        let centroid = SurfaceParameter(
            u: weightedU / denominator,
            v: weightedV / denominator
        )
        guard centroid.u.isFinite, centroid.v.isFinite else {
            return nil
        }
        return centroid
    }

    private func rectangularParameterBounds(
        for loop: Loop,
        on surface: Surface3D,
        in model: BRepModel,
        options: TessellationOptions,
        faceID: FaceID
    ) throws -> (u: (lower: Double, upper: Double), v: (lower: Double, upper: Double))? {
        guard loop.edges.count == 4 else {
            return nil
        }
        var hasConstantU = false
        var hasConstantV = false
        for orientedEdge in loop.edges {
            guard let parameterCurve = orientedEdge.surfaceParameterCurve else {
                return nil
            }
            switch rectangularParameterAxis(parameterCurve) {
            case .u?:
                hasConstantU = true
            case .v?:
                hasConstantV = true
            case nil:
                return nil
            }
        }
        let parameters = try sampledParameters(
            for: loop,
            on: surface,
            in: model,
            options: options,
            faceID: faceID
        )
        guard hasConstantU, hasConstantV,
              let first = parameters.first else {
            return nil
        }
        let bounds = parameters.dropFirst().reduce(
            (
                minU: first.u,
                maxU: first.u,
                minV: first.v,
                maxV: first.v
            )
        ) { partial, parameter in
            (
                minU: min(partial.minU, parameter.u),
                maxU: max(partial.maxU, parameter.u),
                minV: min(partial.minV, parameter.v),
                maxV: max(partial.maxV, parameter.v)
            )
        }
        guard bounds.maxU - bounds.minU > tolerance.distance,
              bounds.maxV - bounds.minV > tolerance.distance else {
            throw TessellationError.degenerateFace(faceID)
        }
        return (
            u: (lower: bounds.minU, upper: bounds.maxU),
            v: (lower: bounds.minV, upper: bounds.maxV)
        )
    }

    private enum RectangularParameterAxis {
        case u
        case v
    }

    private func rectangularParameterAxis(
        _ curve: SurfaceParameterCurve
    ) -> RectangularParameterAxis? {
        switch curve {
        case .constantU:
            return .u
        case .constantV:
            return .v
        case let .periodicTranslation(base, _, _):
            return rectangularParameterAxis(base)
        case let .offsetSurfaceImage(image):
            return rectangularParameterAxis(image.source)
        case .affine, .harmonic, .polyline, .bSpline, .sphericalGreatCircle,
             .certifiedImplicit, .certifiedAnalyticImplicit,
             .certifiedAnalyticPair, .projectedAnalytic, .rigidImage:
            return nil
        }
    }

    private func sampledParameters(
        for loop: Loop,
        on surface: Surface3D,
        in model: BRepModel,
        options: TessellationOptions,
        faceID: FaceID
    ) throws -> [SurfaceParameter] {
        var parameters: [SurfaceParameter] = []
        for orientedEdge in loop.edges {
            guard let parameterCurve = orientedEdge.surfaceParameterCurve else {
                throw TessellationError.unsupportedFace(faceID)
            }
            let edgeSamples = try sampledCurveSamples(
                for: orientedEdge,
                in: model,
                options: options
            )
            let edgeParameters = try edgeSamples.map { sample in
                try parameterCurve.parameter(
                    atNormalizedFraction: sample.normalizedFraction,
                    tolerance: tolerance
                )
            }
            guard let first = edgeParameters.first else {
                continue
            }
            if parameters.last.map({ $0.isApproximatelyEqual(to: first, tolerance: tolerance.distance) }) != true {
                parameters.append(first)
            }
            parameters.append(contentsOf: edgeParameters.dropFirst().dropLast())
        }
        if let first = parameters.first,
           let last = parameters.last,
           first.isApproximatelyEqual(to: last, tolerance: tolerance.distance) {
            parameters.removeLast()
        }
        guard parameters.count >= 3 else {
            throw TessellationError.unsupportedFace(faceID)
        }
        return unwrappedPeriodicParameters(parameters, on: surface)
    }

    private func unwrappedPeriodicParameters(
        _ parameters: [SurfaceParameter],
        on surface: Surface3D
    ) -> [SurfaceParameter] {
        guard let first = parameters.first else {
            return []
        }
        var result = [first]
        result.reserveCapacity(parameters.count)
        for parameter in parameters.dropFirst() {
            let previous = result[result.count - 1]
            result.append(SurfaceParameter(
                u: unwrappedPeriodicParameter(
                    parameter.u,
                    relativeTo: previous.u,
                    domain: surface.uDomain
                ),
                v: unwrappedPeriodicParameter(
                    parameter.v,
                    relativeTo: previous.v,
                    domain: surface.vDomain
                )
            ))
        }
        return result
    }

    private func unwrappedPeriodicParameter(
        _ parameter: Double,
        relativeTo previous: Double,
        domain: ParameterDomain
    ) -> Double {
        guard case let .periodic(period) = domain,
              period.isFinite,
              period > 0.0 else {
            return parameter
        }
        return parameter + ((previous - parameter) / period).rounded() * period
    }

    private func parameterPoint(_ parameter: SurfaceParameter) -> Point3D {
        Point3D(x: parameter.u, y: parameter.v, z: 0.0)
    }

    private func surfaceParameter(from point: Point3D) -> SurfaceParameter {
        SurfaceParameter(u: point.x, v: point.y)
    }

    private func centroidParameter(of parameters: [SurfaceParameter]) -> SurfaceParameter {
        let sum = parameters.reduce((u: 0.0, v: 0.0)) { partial, parameter in
            (u: partial.u + parameter.u, v: partial.v + parameter.v)
        }
        let count = Double(parameters.count)
        return SurfaceParameter(u: sum.u / count, v: sum.v / count)
    }

    private func interpolatedParameter(
        lowerBound: Double,
        upperBound: Double,
        index: Int,
        count: Int
    ) -> Double {
        guard count > 0 else {
            return lowerBound
        }
        let fraction = Double(index) / Double(count)
        return lowerBound + (upperBound - lowerBound) * fraction
    }

    private func bSplineStepCount(options: TessellationOptions) -> Int {
        if let maxEdgeLength = options.maxEdgeLength, maxEdgeLength > 0.0 {
            return min(64, clampedSampleCount(1.0 / maxEdgeLength, minimum: 4, maximum: 65_536))
        }
        return 8
    }

    private func sampledPoints(
        for orientedEdge: Coedge,
        in model: BRepModel,
        options: TessellationOptions
    ) throws -> [Point3D] {
        try sampledCurveSamples(
            for: orientedEdge,
            in: model,
            options: options
        ).map(\.point)
    }

    private struct CurveTessellationSample {
        let normalizedFraction: Double
        let point: Point3D
    }

    private struct ParameterizedCurveTessellationSample {
        let parameter: Double
        let point: Point3D
    }

    private func sampledCurveSamples(
        for orientedEdge: Coedge,
        in model: BRepModel,
        options: TessellationOptions
    ) throws -> [CurveTessellationSample] {
        guard let edge = model.edges[orientedEdge.edgeID],
              let curve = model.geometry.curves[edge.curveID] else {
            throw TopologyError.missingReference("Missing edge curve \(orientedEdge.edgeID).")
        }
        let startPoint = try point(for: startVertexID(for: orientedEdge, edge: edge), in: model)
        let endPoint = try point(for: endVertexID(for: orientedEdge, edge: edge), in: model)
        switch curve {
        case .line:
            return [
                CurveTessellationSample(normalizedFraction: 0.0, point: startPoint),
                CurveTessellationSample(normalizedFraction: 1.0, point: endPoint),
            ]
        case let .circle(circle):
            let (startParameter, endParameter) = try orientedTrimParameters(
                edge: edge,
                coedge: orientedEdge
            )
            let span = endParameter - startParameter
            let segmentCount = try CircularCurveSamplingPolicy.standard
                .boundedTessellationArcSegmentCount(
                    radius: circle.radius,
                    angleSpan: abs(span),
                    angularTolerance: options.angularTolerance,
                    modelingTolerance: tolerance
                )
            return try (0...segmentCount).map { index in
                let ratio = Double(index) / Double(segmentCount)
                return CurveTessellationSample(
                    normalizedFraction: ratio,
                    point: try point(
                        on: circle,
                        at: startParameter + span * ratio
                    )
                )
            }
        case let .analytic(analyticCurve):
            if case .line = analyticCurve {
                return [
                    CurveTessellationSample(normalizedFraction: 0.0, point: startPoint),
                    CurveTessellationSample(normalizedFraction: 1.0, point: endPoint),
                ]
            }
            let (startParameter, endParameter) = try orientedTrimParameters(
                edge: edge,
                coedge: orientedEdge
            )
            let span = endParameter - startParameter
            let radius: Double
            switch analyticCurve {
            case .line:
                return [
                    CurveTessellationSample(normalizedFraction: 0.0, point: startPoint),
                    CurveTessellationSample(normalizedFraction: 1.0, point: endPoint),
                ]
            case let .circle(_, _, value), let .arc(_, _, value, _, _):
                radius = value
            case let .ellipse(_, _, _, majorRadius, _):
                radius = majorRadius
            case .hyperbola, .parabola, .planeTorus:
                return try normalizedCurveSamples(
                    try sampledBoundedCurveSamples(
                        curve: curve,
                        startParameter: startParameter,
                        endParameter: endParameter,
                        options: options
                    ),
                    startParameter: startParameter,
                    endParameter: endParameter
                )
            }
            let segmentCount = try CircularCurveSamplingPolicy.standard
                .boundedTessellationArcSegmentCount(
                    radius: radius,
                    angleSpan: abs(span),
                    angularTolerance: options.angularTolerance,
                    modelingTolerance: tolerance
                )
            return try (0...segmentCount).map { index in
                let ratio = Double(index) / Double(segmentCount)
                return CurveTessellationSample(
                    normalizedFraction: ratio,
                    point: try curve.point(
                        at: startParameter + span * ratio,
                        tolerance: tolerance
                    )
                )
            }
        case .bSpline, .implicit, .surfaceLift, .certifiedIntersection,
             .rigidImage, .affineImage:
            let (startParameter, endParameter) = try orientedTrimParameters(
                edge: edge,
                coedge: orientedEdge
            )
            return try normalizedCurveSamples(
                try sampledBoundedCurveSamples(
                    curve: curve,
                    startParameter: startParameter,
                    endParameter: endParameter,
                    options: options
                ),
                startParameter: startParameter,
                endParameter: endParameter
            )
        }
    }

    private func orientedTrimParameters(
        edge: Edge,
        coedge: Coedge
    ) throws -> (start: Double, end: Double) {
        guard let trim = edge.trim else {
            throw TopologyError.invalidTrim(edge.id)
        }
        switch coedge.orientation {
        case .forward:
            return (trim.startParameter, trim.endParameter)
        case .reversed:
            return (trim.endParameter, trim.startParameter)
        }
    }

    private func normalizedCurveSamples(
        _ samples: [ParameterizedCurveTessellationSample],
        startParameter: Double,
        endParameter: Double
    ) throws -> [CurveTessellationSample] {
        let span = endParameter - startParameter
        guard span.isFinite, abs(span) > Double.ulpOfOne else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Curve tessellation requires a nonzero finite oriented trim span."
            )
        }
        return samples.map { sample in
            CurveTessellationSample(
                normalizedFraction: min(max(
                    (sample.parameter - startParameter) / span,
                    0.0
                ), 1.0),
                point: sample.point
            )
        }
    }

    private func sampledBoundedCurveSamples(
        curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        options: TessellationOptions
    ) throws -> [ParameterizedCurveTessellationSample] {
        let lower = min(startParameter, endParameter)
        let upper = max(startParameter, endParameter)
        guard lower.isFinite, upper.isFinite, upper > lower else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Bounded curve tessellation requires a positive finite parameter interval."
            )
        }
        struct PendingInterval {
            let interval: ScalarInterval
            let upperPoint: Point3D
            let subdivisionDepth: Int
            let inheritedSecondDerivativeMagnitudeUpperBound: Double?
        }
        let validatedCurve = try ValidatedCurve3D(
            curve,
            tolerance: tolerance
        )
        // A containing derivative bound remains correct for every child, but
        // can become too loose to prove the requested angular tolerance. Exact
        // rational-image curves retain a Bernstein certificate that can be
        // restricted efficiently, so cap how long one enclosure is inherited.
        let maximumDerivativeCertificateInheritanceDepth = 4
        let localizesDerivativeCertificate =
            curve.supportsEfficientLocalizedTessellationDerivativeBounds
        let interval = try ScalarInterval(lower: lower, upper: upper)
        let lowerPoint = try validatedCurve.point(at: lower)
        let upperPoint = try validatedCurve.point(at: upper)
        var pending = [PendingInterval(
            interval: interval,
            upperPoint: upperPoint,
            subdivisionDepth: 0,
            inheritedSecondDerivativeMagnitudeUpperBound: nil
        )]
        var samples = [ParameterizedCurveTessellationSample(
            parameter: lower,
            point: lowerPoint
        )]
        samples.reserveCapacity(64)
        let maximumSegmentCount = 65_536
        var processedIntervalCount = 0
        while let current = pending.popLast() {
            processedIntervalCount += 1
            guard processedIntervalCount <= maximumSegmentCount * 2 - 1 else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Certified curve tessellation exceeded its interval budget."
                )
            }
            let evaluation = try validatedCurve.tessellationIntervalEvaluation(
                current.interval,
                usingCertifiedSecondDerivativeMagnitudeUpperBound:
                    localizesDerivativeCertificate
                        && current.subdivisionDepth.isMultiple(
                            of: maximumDerivativeCertificateInheritanceDepth
                        )
                        ? nil
                        : current.inheritedSecondDerivativeMagnitudeUpperBound
            )
            let bounds = evaluation.bounds
            let satisfiesEdgeLength = options.maxEdgeLength.map {
                bounds.arcLengthUpperBound <= $0
            } ?? true
            if bounds.chordDeviationUpperBound <= options.linearTolerance,
               bounds.tangentDeviationUpperBound <= options.angularTolerance,
               satisfiesEdgeLength {
                samples.append(ParameterizedCurveTessellationSample(
                    parameter: current.interval.upper,
                    point: current.upperPoint
                ))
                guard samples.count <= maximumSegmentCount + 1 else {
                    throw KernelError(
                        phase: .geometry,
                        code: .resourceLimitExceeded,
                        tolerance: tolerance,
                        message: "Certified curve tessellation exceeded its segment budget."
                    )
                }
                continue
            }
            let middle = current.interval.midpoint
            guard middle > current.interval.lower,
                  middle < current.interval.upper else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Certified curve tessellation reached floating-point subdivision resolution before satisfying its error budget."
                )
            }
            let middlePoint = evaluation.midpointPoint
            let reusableSecondDerivativeBound =
                bounds.secondDerivativeMagnitudeUpperBound.isFinite
                    ? bounds.secondDerivativeMagnitudeUpperBound
                    : nil
            pending.append(PendingInterval(
                interval: try ScalarInterval(
                    lower: middle,
                    upper: current.interval.upper
                ),
                upperPoint: current.upperPoint,
                subdivisionDepth: current.subdivisionDepth + 1,
                inheritedSecondDerivativeMagnitudeUpperBound: reusableSecondDerivativeBound
            ))
            pending.append(PendingInterval(
                interval: try ScalarInterval(
                    lower: current.interval.lower,
                    upper: middle
                ),
                upperPoint: middlePoint,
                subdivisionDepth: current.subdivisionDepth + 1,
                inheritedSecondDerivativeMagnitudeUpperBound: reusableSecondDerivativeBound
            ))
        }
        if startParameter > endParameter {
            samples.reverse()
        }
        return samples
    }

    private func startVertexID(for orientedEdge: Coedge, edge: Edge) -> VertexID {
        switch orientedEdge.orientation {
        case .forward:
            return edge.startVertexID
        case .reversed:
            return edge.endVertexID
        }
    }

    private func endVertexID(for orientedEdge: Coedge, edge: Edge) -> VertexID {
        switch orientedEdge.orientation {
        case .forward:
            return edge.endVertexID
        case .reversed:
            return edge.startVertexID
        }
    }

    private func point(for vertexID: VertexID, in model: BRepModel) throws -> Point3D {
        guard let point = model.vertices[vertexID]?.point else {
            throw TopologyError.missingReference("Missing vertex \(vertexID).")
        }
        return point
    }

    private enum EdgeCurveKind {
        case line
        case circle
        case bSpline
    }

    private func edgeCurveKind(for orientedEdge: Coedge, in model: BRepModel) throws -> EdgeCurveKind {
        guard let edge = model.edges[orientedEdge.edgeID],
              let curve = model.geometry.curves[edge.curveID] else {
            throw TopologyError.missingReference("Missing edge curve \(orientedEdge.edgeID).")
        }
        return edgeCurveKind(for: curve)
    }

    private func edgeCurveKind(for curve: Curve3D) -> EdgeCurveKind {
        switch curve {
        case .line:
            return .line
        case .circle:
            return .circle
        case let .analytic(curve):
            switch curve {
            case .line:
                return .line
            case .circle, .arc:
                return .circle
            case let .ellipse(_, _, _, majorRadius, minorRadius)
                where abs(majorRadius - minorRadius) <= tolerance.distance:
                return .circle
            case .ellipse, .hyperbola, .parabola, .planeTorus:
                return .bSpline
            }
        case .bSpline:
            return .bSpline
        case .implicit:
            return .bSpline
        case .surfaceLift:
            return .bSpline
        case .certifiedIntersection:
            return .bSpline
        case let .rigidImage(image):
            return edgeCurveKind(for: image.source)
        case .affineImage:
            return curve.exactLinearLocus == nil ? .bSpline : .line
        }
    }

    private func containsCircularEdge(in loop: Loop, model: BRepModel) throws -> Bool {
        for orientedEdge in loop.edges {
            if try edgeCurveKind(for: orientedEdge, in: model) == .circle {
                return true
            }
        }
        return false
    }

    private func isClose(_ lhs: Point3D, _ rhs: Point3D) -> Bool {
        (lhs - rhs).length <= tolerance.distance
    }

    private func point(on circle: Circle3D, at parameter: Double) throws -> Point3D {
        let (u, v) = try circleBasis(for: circle.normal)
        return circle.center
            + (u * (circle.radius * cos(parameter)))
            + (v * (circle.radius * sin(parameter)))
    }

    private func centroid(of points: [Point3D]) -> Point3D {
        let sum = points.reduce(Vector3D.zero) { partial, point in
            partial + Vector3D(x: point.x, y: point.y, z: point.z)
        }
        let count = Double(points.count)
        return Point3D(x: sum.x / count, y: sum.y / count, z: sum.z / count)
    }

    private func circleBasis(for normal: Vector3D) throws -> (Vector3D, Vector3D) {
        let normal = try normal.normalized(tolerance: tolerance.distance)
        let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
        let v = normal.cross(u)
        return (u, v)
    }

    private func surfaceNormals(
        for points: [Point3D],
        on surface: Surface3D,
        face: Face,
        shellOrientation: Orientation
    ) throws -> [Vector3D] {
        switch surface {
        case let .plane(plane):
            let normal = oriented(
                try plane.normal.normalized(tolerance: tolerance.distance),
                face: face,
                shellOrientation: shellOrientation
            )
            return Array(repeating: normal, count: points.count)
        case let .cylinder(cylinder):
            try cylinder.validate(tolerance: tolerance)
            let axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
            return try points.map { point in
                let offset = point - cylinder.origin
                let radial = offset - (axis * offset.dot(axis))
                return try oriented(
                    radial.normalized(tolerance: tolerance.distance),
                    face: face,
                    shellOrientation: shellOrientation
                )
            }
        case let .analytic(surface):
            try surface.validate(tolerance: tolerance)
            return try points.map { point in
                let normal: Vector3D
                switch surface {
                case let .plane(_, planeNormal):
                    normal = planeNormal
                case let .cylinder(origin, axis, _):
                    let offset = point - origin
                    normal = try (offset - axis * offset.dot(axis))
                        .normalized(tolerance: tolerance.distance)
                case let .cone(apex, axis, halfAngle):
                    let offset = point - apex
                    let axialDistance = offset.dot(axis)
                    let radial = offset - axis * axialDistance
                    let radialDirection = try radial.normalized(tolerance: tolerance.distance)
                    let axialSign = axialDistance >= 0.0 ? 1.0 : -1.0
                    normal = try (radialDirection * cos(halfAngle) - axis * (axialSign * sin(halfAngle)))
                        .normalized(tolerance: tolerance.distance)
                case let .sphere(center, _):
                    normal = try (point - center).normalized(tolerance: tolerance.distance)
                case let .torus(center, axis, majorRadius, _):
                    let offset = point - center
                    let axialDistance = offset.dot(axis)
                    let radialDirection = try (offset - axis * axialDistance)
                        .normalized(tolerance: tolerance.distance)
                    let tubeCenter = center + radialDirection * majorRadius
                    normal = try (point - tubeCenter).normalized(tolerance: tolerance.distance)
                }
                return oriented(normal, face: face, shellOrientation: shellOrientation)
            }
        case .bSpline, .procedural:
            return try points.map { point in
                let parameter = try surface.parameterProjection(
                    of: point,
                    tolerance: tolerance
                )
        return try oriented(
            surface.normal(
                u: parameter.u,
                v: parameter.v,
                        tolerance: tolerance
                    ),
                    face: face,
                    shellOrientation: shellOrientation
                )
            }
        }
    }

    private func oriented(
        _ normal: Vector3D,
        face: Face,
        shellOrientation: Orientation
    ) -> Vector3D {
        switch (shellOrientation, face.orientation) {
        case (.forward, .forward), (.reversed, .reversed):
            return normal
        case (.forward, .reversed), (.reversed, .forward):
            return -normal
        }
    }

    private func averageNormal(_ normals: [Vector3D], faceID: FaceID) throws -> Vector3D {
        let sum = normals.reduce(Vector3D.zero) { partial, normal in
            partial + normal
        }
        do {
            return try sum.normalized(tolerance: tolerance.distance)
        } catch {
            throw TessellationError.degenerateFace(faceID)
        }
    }

    @discardableResult
    private func appendTriangle(
        _ first: UInt32,
        _ second: UInt32,
        _ third: UInt32,
        positions: [Point3D],
        normals: [Vector3D],
        indices: inout [UInt32]
    ) -> Bool {
        let firstPoint = positions[Int(first)]
        let secondPoint = positions[Int(second)]
        let thirdPoint = positions[Int(third)]
        let firstEdge = secondPoint - firstPoint
        let secondEdge = thirdPoint - firstPoint
        let areaVector = firstEdge.cross(secondEdge)
        let area = areaVector.length
        // Absolute floor: what Mesh.validate rejects as degenerate. Relative
        // term: below it the cross DIRECTION - and therefore the winding
        // decision against the vertex normals - is rounding noise.
        let adoptionGate = max(
            tolerance.distance * tolerance.distance,
            minimumMeaningfulCross(firstEdge.length, secondEdge.length)
        )
        guard area.isFinite, area > adoptionGate else {
            return false
        }
        let referenceNormal = normals[Int(first)] + normals[Int(second)] + normals[Int(third)]
        indices.append(first)
        if areaVector.dot(referenceNormal) < 0.0 {
            indices.append(third)
            indices.append(second)
        } else {
            indices.append(second)
            indices.append(third)
        }
        return true
    }

    @discardableResult
    private func appendTriangleWithNormalFallback(
        _ first: UInt32,
        _ second: UInt32,
        _ third: UInt32,
        positions: inout [Point3D],
        normals: inout [Vector3D],
        indices: inout [UInt32]
    ) -> Bool {
        let firstPoint = positions[Int(first)]
        let secondPoint = positions[Int(second)]
        let thirdPoint = positions[Int(third)]
        let firstEdge = secondPoint - firstPoint
        let secondEdge = thirdPoint - firstPoint
        let areaVector = firstEdge.cross(secondEdge)
        let area = areaVector.length
        // Absolute floor: what Mesh.validate rejects as degenerate. Relative
        // term: below it the cross DIRECTION - and therefore the winding
        // decision against the vertex normals - is rounding noise.
        let adoptionGate = max(
            tolerance.distance * tolerance.distance,
            minimumMeaningfulCross(firstEdge.length, secondEdge.length)
        )
        guard area.isFinite, area > adoptionGate else {
            return false
        }
        let referenceNormal = normals[Int(first)] + normals[Int(second)] + normals[Int(third)]
        let usesReversedWinding = areaVector.dot(referenceNormal) < 0.0
        let ordered = usesReversedWinding ? [first, third, second] : [first, second, third]
        let orientedAreaVector = usesReversedWinding ? -areaVector : areaVector
        let flatNormal = orientedAreaVector / area

        if triangleNormalsAgree(
            ordered,
            faceNormal: flatNormal,
            normals: normals
        ) {
            indices.append(contentsOf: ordered)
            return true
        }

        let baseIndex = UInt32(positions.count)
        for sourceIndex in ordered {
            positions.append(positions[Int(sourceIndex)])
            normals.append(flatNormal)
        }
        indices.append(baseIndex)
        indices.append(baseIndex + 1)
        indices.append(baseIndex + 2)
        return true
    }

    private func triangleNormalsAgree(
        _ ordered: [UInt32],
        faceNormal: Vector3D,
        normals: [Vector3D]
    ) -> Bool {
        ordered.allSatisfy { index in
            normals[Int(index)].dot(faceNormal) > tolerance.angle
        }
    }
}
