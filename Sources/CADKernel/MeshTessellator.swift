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
        if case let .bSpline(surface) = surface {
            try appendBSplineFace(
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
        guard innerLoopIDs.isEmpty else {
            guard case let .plane(plane) = surface else {
                throw TessellationError.unsupportedFace(faceID)
            }
            let innerLoops = try innerLoopIDs.map { innerLoopID in
                guard let innerLoop = model.loops[innerLoopID] else {
                    throw TopologyError.missingReference("Missing loop \(innerLoopID).")
                }
                return innerLoop
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
        if case let .cylinder(cylinder) = surface {
            try appendRuledRevolvedFace(
                loop: loop,
                surface: .cylinder(cylinder),
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
        if case .analytic(.cone) = surface {
            try appendRuledRevolvedFace(
                loop: loop,
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
                let currentOriginal = survivors[index]
                let nextOriginal = survivors[(index + 1) % survivors.count]
                let previous = points[previousOriginal]
                let current = points[currentOriginal]
                if (current - previous).length <= tolerance.distance
                    || (points[nextOriginal] - current).length <= tolerance.distance {
                    survivors.remove(at: index)
                    didRemove = true
                    break
                }
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
        faceID: FaceID
    ) throws -> [TriangleIndex] {
        guard points.count >= 3 else {
            throw TessellationError.degenerateFace(faceID)
        }
        if points.count == 3 {
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

    private func appendRuledRevolvedFace(
        loop: Loop,
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
        guard loop.edges.count == 4,
              try edgeCurveKind(for: loop.edges[0], in: model) == .circle,
              try edgeCurveKind(for: loop.edges[2], in: model) == .circle else {
            throw TessellationError.unsupportedFace(faceID)
        }
        let sampledBottom = try sampledPoints(for: loop.edges[0], in: model, options: options)
        let sampledTop = try sampledPoints(for: loop.edges[2], in: model, options: options)
        let segmentCount = max(sampledBottom.count, sampledTop.count) - 1
        guard segmentCount >= 1 else {
            throw TessellationError.degenerateFace(faceID)
        }
        let bottomPoints = try sampledCircularPoints(
            for: loop.edges[0],
            in: model,
            segmentCount: segmentCount
        )
        let reversedTopPoints = try sampledCircularPoints(
            for: loop.edges[2],
            in: model,
            segmentCount: segmentCount
        )
        let topPoints = Array(reversedTopPoints.reversed())
        guard UInt64(positions.count) + UInt64(bottomPoints.count * 2) <= UInt64(UInt32.max) else {
            throw TessellationError.unsupportedFace(faceID)
        }

        let bottomNormals = try surfaceNormals(
            for: bottomPoints,
            on: surface,
            face: face,
            shellOrientation: shellOrientation
        )
        let topNormals = try surfaceNormals(
            for: topPoints,
            on: surface,
            face: face,
            shellOrientation: shellOrientation
        )
        let baseIndex = UInt32(positions.count)
        for index in bottomPoints.indices {
            positions.append(bottomPoints[index])
            normals.append(bottomNormals[index])
            positions.append(topPoints[index])
            normals.append(topNormals[index])
        }

        for index in 0..<(bottomPoints.count - 1) {
            let bottomCurrent = baseIndex + UInt32(index * 2)
            let topCurrent = bottomCurrent + 1
            let bottomNext = baseIndex + UInt32((index + 1) * 2)
            let topNext = bottomNext + 1
            let appendedFirst = appendTriangle(
                bottomCurrent,
                bottomNext,
                topCurrent,
                positions: positions,
                normals: normals,
                indices: &indices
            )
            let appendedSecond = appendTriangle(
                bottomNext,
                topNext,
                topCurrent,
                positions: positions,
                normals: normals,
                indices: &indices
            )
            // A silently skipped quad leaves a hole that mesh compaction hides
            // from validation; fail loudly instead.
            guard appendedFirst, appendedSecond else {
                throw TessellationError.degenerateFace(faceID)
            }
        }
    }

    private func sampledCircularPoints(
        for orientedEdge: Coedge,
        in model: BRepModel,
        segmentCount: Int
    ) throws -> [Point3D] {
        guard segmentCount >= 1,
              let edge = model.edges[orientedEdge.edgeID],
              let curve = model.geometry.curves[edge.curveID],
              let trim = edge.trim,
              try edgeCurveKind(for: orientedEdge, in: model) == .circle else {
            throw TessellationError.degenerateFace(FaceID())
        }
        let startParameter: Double
        let endParameter: Double
        switch orientedEdge.orientation {
        case .forward:
            startParameter = trim.startParameter
            endParameter = trim.endParameter
        case .reversed:
            startParameter = trim.endParameter
            endParameter = trim.startParameter
        }
        return try (0...segmentCount).map { index in
            let fraction = Double(index) / Double(segmentCount)
            return try curve.point(
                at: startParameter + (endParameter - startParameter) * fraction,
                tolerance: tolerance
            )
        }
    }

    private func appendBSplineFace(
        surface: BSplineSurface3D,
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
           let bounds = try rectangularParameterBounds(for: outerLoop, faceID: faceID) {
            try appendBSplineGridFace(
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

        let outerParameters = try sampledParameters(for: outerLoop, options: options, faceID: faceID)
        let innerParameterLoops = try innerLoopIDs.map { innerLoopID -> [SurfaceParameter] in
            guard let innerLoop = model.loops[innerLoopID] else {
                throw TopologyError.missingReference("Missing loop \(innerLoopID).")
            }
            return try sampledParameters(for: innerLoop, options: options, faceID: faceID)
        }
        try appendTrimmedBSplineFace(
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

    private func appendBSplineGridFace(
        surface: BSplineSurface3D,
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
        let uSteps = bSplineStepCount(options: options)
        let vSteps = bSplineStepCount(options: options)
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
                    surface.normal(u: u, v: v, tolerance: tolerance),
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

    private func appendTrimmedBSplineFace(
        surface: BSplineSurface3D,
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

        if innerParameterLoops.isEmpty,
           try isConvexPlanarLoop(parameterPoints, normal: Vector3D.unitZ) {
            guard UInt64(positions.count) + 1 <= UInt64(UInt32.max) else {
                throw TessellationError.unsupportedFace(faceID)
            }
            let centerParameter = centroidParameter(of: parameters)
            let centerIndex = UInt32(positions.count)
            positions.append(try surface.point(u: centerParameter.u, v: centerParameter.v, tolerance: tolerance))
            normals.append(try oriented(
                surface.normal(u: centerParameter.u, v: centerParameter.v, tolerance: tolerance),
                face: face,
                shellOrientation: shellOrientation
            ))
            for index in parameters.indices {
                let next = (index + 1) % parameters.count
                let appended = appendTriangle(
                    centerIndex,
                    baseIndex + UInt32(index),
                    baseIndex + UInt32(next),
                    positions: positions,
                    normals: normals,
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

    private func rectangularParameterBounds(
        for loop: Loop,
        faceID: FaceID
    ) throws -> (u: (lower: Double, upper: Double), v: (lower: Double, upper: Double))? {
        guard loop.edges.count == 4 else {
            return nil
        }
        var hasConstantU = false
        var hasConstantV = false
        var parameters: [SurfaceParameter] = []
        parameters.reserveCapacity(loop.edges.count * 2)
        for orientedEdge in loop.edges {
            guard let parameterCurve = orientedEdge.surfaceParameterCurve else {
                return nil
            }
            switch parameterCurve {
            case .constantU:
                hasConstantU = true
            case .constantV:
                hasConstantV = true
            case .affine, .harmonic, .polyline, .bSpline, .sphericalGreatCircle,
                 .certifiedImplicit, .certifiedAnalyticImplicit,
                 .certifiedAnalyticPair, .projectedAnalytic:
                return nil
            }
            parameters.append(try parameterCurve.startParameter(tolerance: tolerance))
            parameters.append(try parameterCurve.endParameter(tolerance: tolerance))
        }
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

    private func sampledParameters(
        for loop: Loop,
        options: TessellationOptions,
        faceID: FaceID
    ) throws -> [SurfaceParameter] {
        var parameters: [SurfaceParameter] = []
        for orientedEdge in loop.edges {
            guard let parameterCurve = orientedEdge.surfaceParameterCurve else {
                throw TessellationError.unsupportedFace(faceID)
            }
            let edgeParameters = try sampledParameters(for: parameterCurve, options: options)
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
        return parameters
    }

    private func sampledParameters(
        for parameterCurve: SurfaceParameterCurve,
        options: TessellationOptions
    ) throws -> [SurfaceParameter] {
        let segmentCount = parameterCurveSegmentCount(parameterCurve, options: options)
        return try (0...segmentCount).map { index in
            let fraction = Double(index) / Double(segmentCount)
            return try parameterCurve.parameter(atNormalizedFraction: fraction, tolerance: tolerance)
        }
    }

    private func parameterCurveSegmentCount(
        _ parameterCurve: SurfaceParameterCurve,
        options: TessellationOptions
    ) -> Int {
        let defaultCount = bSplineStepCount(options: options)
        let length: Double
        switch parameterCurve {
        case let .affine(_, direction, startParameter, endParameter):
            length = hypot(direction.x, direction.y) * abs(endParameter - startParameter)
        case let .constantU(_, vStart, vEnd):
            length = abs(vEnd - vStart)
        case let .constantV(_, uStart, uEnd):
            length = abs(uEnd - uStart)
        case let .harmonic(_, cosine, sine, startParameter, endParameter):
            let maximumDerivative = hypot(cosine.x, cosine.y) + hypot(sine.x, sine.y)
            length = abs(endParameter - startParameter) * maximumDerivative
        case let .polyline(points):
            length = parameterPolylineLength(points)
        case let .bSpline(curve):
            length = controlPolygonLength(curve.controlPoints.map { Point3D(x: $0.x, y: $0.y, z: 0.0) })
        case let .sphericalGreatCircle(_, _, startParameter, endParameter):
            length = abs(endParameter - startParameter)
        case let .certifiedImplicit(curve):
            length = Double(curve.intersection.cells.count)
        case let .certifiedAnalyticImplicit(curve):
            length = Double(curve.intersection.implicitCurve.cells.count)
        case let .certifiedAnalyticPair(curve):
            length = abs(curve.endFraction - curve.startFraction) * 2.0 * Double.pi
        case let .projectedAnalytic(curve):
            length = abs(curve.endParameter - curve.startParameter)
        }
        let edgeLimit = options.maxEdgeLength.map { clampedSampleCount(length / $0, minimum: 1, maximum: 65_536) } ?? 1
        return min(max(defaultCount, edgeLimit), 256)
    }

    private func parameterPolylineLength(_ points: [SurfaceParameter]) -> Double {
        guard points.count > 1 else {
            return 0.0
        }
        var length = 0.0
        for index in 1..<points.count {
            length += hypot(points[index].u - points[index - 1].u, points[index].v - points[index - 1].v)
        }
        return length
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
        guard let edge = model.edges[orientedEdge.edgeID],
              let curve = model.geometry.curves[edge.curveID] else {
            throw TopologyError.missingReference("Missing edge curve \(orientedEdge.edgeID).")
        }
        let startPoint = try point(for: startVertexID(for: orientedEdge, edge: edge), in: model)
        let endPoint = try point(for: endVertexID(for: orientedEdge, edge: edge), in: model)
        switch curve {
        case .line:
            return [startPoint, endPoint]
        case let .circle(circle):
            guard let trim = edge.trim else {
                throw TopologyError.invalidTrim(edge.id)
            }
            let startParameter: Double
            let endParameter: Double
            switch orientedEdge.orientation {
            case .forward:
                startParameter = trim.startParameter
                endParameter = trim.endParameter
            case .reversed:
                startParameter = trim.endParameter
                endParameter = trim.startParameter
            }
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
                return try point(
                    on: circle,
                    at: startParameter + span * ratio
                )
            }
        case let .analytic(analyticCurve):
            if case .line = analyticCurve {
                return [startPoint, endPoint]
            }
            guard let trim = edge.trim else {
                throw TopologyError.invalidTrim(edge.id)
            }
            let startParameter: Double
            let endParameter: Double
            switch orientedEdge.orientation {
            case .forward:
                startParameter = trim.startParameter
                endParameter = trim.endParameter
            case .reversed:
                startParameter = trim.endParameter
                endParameter = trim.startParameter
            }
            let span = endParameter - startParameter
            let radius: Double
            switch analyticCurve {
            case .line:
                return [startPoint, endPoint]
            case let .circle(_, _, value), let .arc(_, _, value, _, _):
                radius = value
            case let .ellipse(_, _, _, majorRadius, _):
                radius = majorRadius
            case .hyperbola, .parabola:
                let interval = try ScalarInterval(
                    lower: min(startParameter, endParameter),
                    upper: max(startParameter, endParameter)
                )
                guard let spline = try AnalyticCurveBSplineBuilder().boundedCurve(
                    curve: curve,
                    interval: interval,
                    maximumSpanCount: 4_096,
                    tolerance: tolerance
                ) else {
                    throw KernelError(
                        phase: .geometry,
                        code: .unsupportedCapability,
                        tolerance: tolerance,
                        message: "A bounded analytic conic could not be converted for derived-mesh tessellation."
                    )
                }
                return try sampledBoundedCurvePoints(
                    curve: curve,
                    startParameter: startParameter,
                    endParameter: endParameter,
                    extent: try BoundingBox3D(points: spline.controlPoints).size.length,
                    options: options
                )
            case let .planeTorus(planeTorus):
                return try sampledBoundedCurvePoints(
                    curve: curve,
                    startParameter: startParameter,
                    endParameter: endParameter,
                    extent: planeTorus.boundingBox(tolerance: tolerance).size.length,
                    options: options
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
                return try curve.point(
                    at: startParameter + span * ratio,
                    tolerance: tolerance
                )
            }
        case let .bSpline(curve):
            guard let trim = edge.trim else {
                throw TopologyError.invalidTrim(edge.id)
            }
            let startParameter: Double
            let endParameter: Double
            switch orientedEdge.orientation {
            case .forward:
                startParameter = trim.startParameter
                endParameter = trim.endParameter
            case .reversed:
                startParameter = trim.endParameter
                endParameter = trim.startParameter
            }
            let span = endParameter - startParameter
            let segmentCount = bSplineCurveSegmentCount(curve: curve, span: span, options: options)
            return try (0...segmentCount).map { index in
                let ratio = Double(index) / Double(segmentCount)
                return try curve.point(
                    at: startParameter + span * ratio,
                    tolerance: tolerance
                )
            }
        case let .implicit(implicitCurve):
            guard let trim = edge.trim else {
                throw TopologyError.invalidTrim(edge.id)
            }
            let startParameter = orientedEdge.orientation == .forward
                ? trim.startParameter
                : trim.endParameter
            let endParameter = orientedEdge.orientation == .forward
                ? trim.endParameter
                : trim.startParameter
            let extent = try implicitCurve.boundingBox(
                fromNormalizedFraction: min(startParameter, endParameter),
                toNormalizedFraction: max(startParameter, endParameter),
                tolerance: tolerance
            ).size.length
            let edgeLimit = options.maxEdgeLength.map {
                clampedSampleCount(extent / $0, minimum: 4, maximum: 65_536)
            } ?? 4
            let toleranceLimit = clampedSampleCount(
                sqrt(extent / options.linearTolerance),
                minimum: 8,
                maximum: 65_536
            )
            let segmentCount = min(max(edgeLimit, toleranceLimit), 512)
            return try (0...segmentCount).map { index in
                let ratio = Double(index) / Double(segmentCount)
                return try implicitCurve.point(
                    atNormalizedFraction: startParameter
                        + (endParameter - startParameter) * ratio,
                    tolerance: tolerance
                )
            }
        case let .surfaceLift(lift):
            guard let trim = edge.trim else {
                throw TopologyError.invalidTrim(edge.id)
            }
            let startParameter = orientedEdge.orientation == .forward
                ? trim.startParameter
                : trim.endParameter
            let endParameter = orientedEdge.orientation == .forward
                ? trim.endParameter
                : trim.startParameter
            guard case let .bSpline(surface) = lift.surface else {
                throw KernelError(
                    phase: .geometry,
                    code: .unsupportedCapability,
                    tolerance: tolerance,
                    message: "Surface-lift tessellation requires a bounded B-spline support surface."
                )
            }
            let extent = try BoundingBox3D(
                points: surface.controlPoints.flatMap { $0 }
            ).size.length
            return try sampledBoundedCurvePoints(
                curve: curve,
                startParameter: startParameter,
                endParameter: endParameter,
                extent: extent,
                options: options
            )
        case .certifiedIntersection:
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Certified intersection tessellation requires a certified adaptive error bound."
            )
        }
    }

    private func sampledBoundedCurvePoints(
        curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        extent: Double,
        options: TessellationOptions
    ) throws -> [Point3D] {
        let edgeLimit = options.maxEdgeLength.map {
            clampedSampleCount(extent / $0, minimum: 4, maximum: 65_536)
        } ?? 4
        let toleranceLimit = clampedSampleCount(
            sqrt(extent / options.linearTolerance),
            minimum: 8,
            maximum: 65_536
        )
        let segmentCount = min(max(edgeLimit, toleranceLimit), 512)
        return try (0...segmentCount).map { index in
            let ratio = Double(index) / Double(segmentCount)
            return try curve.point(
                at: startParameter + (endParameter - startParameter) * ratio,
                tolerance: tolerance
            )
        }
    }

    private func bSplineCurveSegmentCount(
        curve: BSplineCurve3D,
        span: Double,
        options: TessellationOptions
    ) -> Int {
        let domainLength: Double
        switch curve.domain {
        case let .closed(lower, upper):
            domainLength = max(upper - lower, Double.ulpOfOne)
        case .unbounded, .periodic:
            domainLength = max(abs(span), Double.ulpOfOne)
        }
        let spanFraction = min(max(abs(span) / domainLength, 0.0), 1.0)
        let controlLength = controlPolygonLength(curve.controlPoints) * max(spanFraction, Double.ulpOfOne)
        let edgeLimit = options.maxEdgeLength.map { clampedSampleCount(controlLength / $0, minimum: 1, maximum: 65_536) } ?? 1
        let toleranceLimit = clampedSampleCount(sqrt(controlLength / options.linearTolerance), minimum: 4, maximum: 65_536)
        return min(max(edgeLimit, toleranceLimit), 512)
    }

    private func controlPolygonLength(_ points: [Point3D]) -> Double {
        guard points.count > 1 else {
            return 0.0
        }
        var length = 0.0
        for index in 1..<points.count {
            length += (points[index] - points[index - 1]).length
        }
        return length
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
        case let .bSpline(surface):
            return try points.map { point in
                try oriented(
                    surface.normal(u: 0.5, v: 0.5, tolerance: tolerance),
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
