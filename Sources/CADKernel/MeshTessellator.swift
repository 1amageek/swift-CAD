import Foundation
import CADCore
import CADIR

public struct MeshTessellator: Tessellating {
    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance = .standard) {
        self.tolerance = tolerance
    }

    public func tessellate(model: BRepModel, options: TessellationOptions = .standard) throws -> [BodyID: Mesh] {
        do {
            try tolerance.validate()
            try options.validate()
        } catch {
            throw TessellationError.invalidTolerance
        }
        try model.validate(tolerance: tolerance)

        var meshes: [BodyID: Mesh] = [:]
        for (bodyID, body) in model.bodies.sorted(by: { $0.key.description < $1.key.description }) {
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

            let mesh = Mesh(positions: positions, normals: normals, indices: indices, material: body.material)
            try mesh.validate(tolerance: tolerance)
            meshes[bodyID] = mesh
        }
        return meshes
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
        guard innerLoopIDs.isEmpty else {
            guard case let .plane(plane) = surface,
                  innerLoopIDs.count == 1,
                  let innerLoopID = innerLoopIDs.first,
                  let innerLoop = model.loops[innerLoopID],
                  try isLineOnly(loop: loop, model: model),
                  try isLineOnly(loop: innerLoop, model: model) else {
                throw TessellationError.unsupportedFace(faceID)
            }
            try appendPlanarFaceWithHole(
                outerLoop: loop,
                innerLoop: innerLoop,
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
            try appendCylinderFace(
                loop: loop,
                cylinder: cylinder,
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
        if case let .bSpline(surface) = surface {
            try appendBSplineFace(
                surface: surface,
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
            normal: geometricNormal,
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

    private struct PlanarAxes {
        var origin: Point3D
        var normal: Vector3D
        var u: Vector3D
        var v: Vector3D

        func localCoordinates(for point: Point3D) -> (u: Double, v: Double, distance: Double) {
            let offset = point - origin
            return (offset.dot(u), offset.dot(v), offset.dot(normal))
        }

        func point(u localU: Double, v localV: Double) -> Point3D {
            origin + (u * localU) + (v * localV)
        }
    }

    private struct PlanarLoopBounds {
        var minimumU: Double
        var maximumU: Double
        var minimumV: Double
        var maximumV: Double
    }

    private struct PlanarPolygonPoint {
        var point: Point3D
        var projected: PlanarPoint2D
    }

    private func appendPlanarFaceWithHole(
        outerLoop: Loop,
        innerLoop: Loop,
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
        let innerPoints = try sampledPoints(for: innerLoop, in: model, options: options)
        let bridgedPoints = try bridgedPlanarFacePoints(
            outerPoints: outerPoints,
            innerPoints: innerPoints,
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
        innerPoints: [Point3D],
        normal: Vector3D,
        faceID: FaceID
    ) throws -> [Point3D] {
        guard outerPoints.count >= 3, innerPoints.count >= 3 else {
            throw TessellationError.degenerateFace(faceID)
        }
        let projected = try projectedPlanarPoints(
            outerPoints + innerPoints,
            normal: normal
        )
        var outer = outerPoints.indices.map { index in
            PlanarPolygonPoint(point: outerPoints[index], projected: projected[index])
        }
        var inner = innerPoints.indices.map { index in
            PlanarPolygonPoint(
                point: innerPoints[index],
                projected: projected[outerPoints.count + index]
            )
        }
        guard abs(planarSignedArea(outer.map(\.projected))) > tolerance.distance * tolerance.distance,
              abs(planarSignedArea(inner.map(\.projected))) > tolerance.distance * tolerance.distance else {
            throw TessellationError.degenerateFace(faceID)
        }
        if planarSignedArea(outer.map(\.projected)) < 0.0 {
            outer.reverse()
        }
        if planarSignedArea(inner.map(\.projected)) > 0.0 {
            inner.reverse()
        }
        try validateHole(inner, isInside: outer, faceID: faceID)

        let bridge = try visibleBridge(from: inner, to: outer, faceID: faceID)
        var bridged: [Point3D] = []
        bridged.reserveCapacity(outer.count + inner.count + 2)

        for offset in 0..<outer.count {
            bridged.append(outer[(bridge.outerIndex + offset) % outer.count].point)
        }
        bridged.append(outer[bridge.outerIndex].point)
        for offset in 0..<inner.count {
            bridged.append(inner[(bridge.innerIndex + offset) % inner.count].point)
        }
        bridged.append(inner[bridge.innerIndex].point)
        return bridged
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
        to outer: [PlanarPolygonPoint],
        faceID: FaceID
    ) throws -> (innerIndex: Int, outerIndex: Int) {
        var candidates: [(innerIndex: Int, outerIndex: Int, distance: Double)] = []
        candidates.reserveCapacity(inner.count * outer.count)
        for innerIndex in inner.indices {
            for outerIndex in outer.indices {
                let distance = planarDistance(
                    inner[innerIndex].projected,
                    to: outer[outerIndex].projected
                )
                candidates.append((innerIndex, outerIndex, distance))
            }
        }
        candidates.sort { lhs, rhs in
            if abs(lhs.distance - rhs.distance) > tolerance.distance {
                return lhs.distance < rhs.distance
            }
            if lhs.innerIndex != rhs.innerIndex {
                return lhs.innerIndex < rhs.innerIndex
            }
            return lhs.outerIndex < rhs.outerIndex
        }

        for candidate in candidates {
            if bridgeIsVisible(
                innerIndex: candidate.innerIndex,
                outerIndex: candidate.outerIndex,
                inner: inner,
                outer: outer
            ) {
                return (candidate.innerIndex, candidate.outerIndex)
            }
        }
        throw TessellationError.unsupportedFace(faceID)
    }

    private func bridgeIsVisible(
        innerIndex: Int,
        outerIndex: Int,
        inner: [PlanarPolygonPoint],
        outer: [PlanarPolygonPoint]
    ) -> Bool {
        let start = inner[innerIndex].projected
        let end = outer[outerIndex].projected
        guard planarDistance(start, to: end) > tolerance.distance else {
            return false
        }
        let midpoint = PlanarPoint2D(
            x: (start.x + end.x) * 0.5,
            y: (start.y + end.y) * 0.5
        )
        guard point(midpoint, isInsidePolygonWith: outer.map(\.projected)),
              point(midpoint, isInsidePolygonWith: inner.map(\.projected)) == false else {
            return false
        }

        for index in outer.indices {
            let edgeStart = outer[index].projected
            let edgeEnd = outer[(index + 1) % outer.count].projected
            let touchesBridgeEnd = index == outerIndex || (index + 1) % outer.count == outerIndex
            if bridgeSegment(
                from: start,
                to: end,
                intersectsEdgeFrom: edgeStart,
                to: edgeEnd,
                allowedSharedPoint: touchesBridgeEnd ? end : nil
            ) {
                return false
            }
        }

        for index in inner.indices {
            let edgeStart = inner[index].projected
            let edgeEnd = inner[(index + 1) % inner.count].projected
            let touchesBridgeStart = index == innerIndex || (index + 1) % inner.count == innerIndex
            if bridgeSegment(
                from: start,
                to: end,
                intersectsEdgeFrom: edgeStart,
                to: edgeEnd,
                allowedSharedPoint: touchesBridgeStart ? start : nil
            ) {
                return false
            }
        }
        return true
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

    private func appendPlanarFaceWithRectangularHole(
        outerLoop: Loop,
        innerLoop: Loop,
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
        let innerPoints = try sampledPoints(for: innerLoop, in: model, options: options)
        guard let firstOuterPoint = outerPoints.first else {
            throw TessellationError.degenerateFace(faceID)
        }
        let axes = try planarAxes(
            plane: plane,
            firstPoint: firstOuterPoint,
            points: outerPoints,
            faceID: faceID
        )
        let outerBounds = try rectangularBounds(for: outerPoints, axes: axes, faceID: faceID)
        let innerBounds = try rectangularBounds(for: innerPoints, axes: axes, faceID: faceID)
        guard innerBounds.minimumU - outerBounds.minimumU > tolerance.distance,
              outerBounds.maximumU - innerBounds.maximumU > tolerance.distance,
              innerBounds.minimumV - outerBounds.minimumV > tolerance.distance,
              outerBounds.maximumV - innerBounds.maximumV > tolerance.distance else {
            throw TessellationError.unsupportedFace(faceID)
        }

        let quads = [
            rectangleCorners(
                minimumU: outerBounds.minimumU,
                maximumU: outerBounds.maximumU,
                minimumV: outerBounds.minimumV,
                maximumV: innerBounds.minimumV,
                axes: axes
            ),
            rectangleCorners(
                minimumU: innerBounds.maximumU,
                maximumU: outerBounds.maximumU,
                minimumV: innerBounds.minimumV,
                maximumV: innerBounds.maximumV,
                axes: axes
            ),
            rectangleCorners(
                minimumU: outerBounds.minimumU,
                maximumU: outerBounds.maximumU,
                minimumV: innerBounds.maximumV,
                maximumV: outerBounds.maximumV,
                axes: axes
            ),
            rectangleCorners(
                minimumU: outerBounds.minimumU,
                maximumU: innerBounds.minimumU,
                minimumV: innerBounds.minimumV,
                maximumV: innerBounds.maximumV,
                axes: axes
            ),
        ]
        for quad in quads {
            try appendPlanarQuad(
                points: quad,
                surface: surface,
                face: face,
                faceID: faceID,
                shellOrientation: shellOrientation,
                positions: &positions,
                normals: &normals,
                indices: &indices
            )
        }
    }

    private func planarAxes(
        plane: Plane3D,
        firstPoint: Point3D,
        points: [Point3D],
        faceID: FaceID
    ) throws -> PlanarAxes {
        let normal = try plane.normal.normalized(tolerance: tolerance.distance)
        let origin = firstPoint
        for point in points.dropFirst() {
            let candidate = point - origin
            let tangent = candidate - (normal * candidate.dot(normal))
            if tangent.length > tolerance.distance {
                let u = try tangent.normalized(tolerance: tolerance.distance)
                let v = normal.cross(u)
                return PlanarAxes(origin: origin, normal: normal, u: u, v: v)
            }
        }
        throw TessellationError.degenerateFace(faceID)
    }

    private func rectangularBounds(
        for points: [Point3D],
        axes: PlanarAxes,
        faceID: FaceID
    ) throws -> PlanarLoopBounds {
        guard points.count == 4 else {
            throw TessellationError.unsupportedFace(faceID)
        }
        let coordinates = points.map { point in
            axes.localCoordinates(for: point)
        }
        for coordinate in coordinates {
            guard abs(coordinate.distance) <= tolerance.distance else {
                throw TessellationError.unsupportedFace(faceID)
            }
        }
        let uValues = uniqueSortedCoordinates(coordinates.map { $0.u })
        let vValues = uniqueSortedCoordinates(coordinates.map { $0.v })
        guard uValues.count == 2,
              vValues.count == 2,
              uValues[1] - uValues[0] > tolerance.distance,
              vValues[1] - vValues[0] > tolerance.distance else {
            throw TessellationError.unsupportedFace(faceID)
        }
        let expectedCorners = [
            (uValues[0], vValues[0]),
            (uValues[1], vValues[0]),
            (uValues[1], vValues[1]),
            (uValues[0], vValues[1]),
        ]
        for expected in expectedCorners {
            let hasCorner = coordinates.contains { coordinate in
                abs(coordinate.u - expected.0) <= tolerance.distance
                    && abs(coordinate.v - expected.1) <= tolerance.distance
            }
            guard hasCorner else {
                throw TessellationError.unsupportedFace(faceID)
            }
        }
        return PlanarLoopBounds(
            minimumU: uValues[0],
            maximumU: uValues[1],
            minimumV: vValues[0],
            maximumV: vValues[1]
        )
    }

    private func uniqueSortedCoordinates(_ values: [Double]) -> [Double] {
        let sorted = values.sorted()
        var result: [Double] = []
        for value in sorted {
            guard let last = result.last else {
                result.append(value)
                continue
            }
            if abs(value - last) > tolerance.distance {
                result.append(value)
            }
        }
        return result
    }

    private func rectangleCorners(
        minimumU: Double,
        maximumU: Double,
        minimumV: Double,
        maximumV: Double,
        axes: PlanarAxes
    ) -> [Point3D] {
        [
            axes.point(u: minimumU, v: minimumV),
            axes.point(u: maximumU, v: minimumV),
            axes.point(u: maximumU, v: maximumV),
            axes.point(u: minimumU, v: maximumV),
        ]
    }

    private func appendPlanarQuad(
        points: [Point3D],
        surface: Surface3D,
        face: Face,
        faceID: FaceID,
        shellOrientation: Orientation,
        positions: inout [Point3D],
        normals: inout [Vector3D],
        indices: inout [UInt32]
    ) throws {
        guard points.count == 4 else {
            throw TessellationError.degenerateFace(faceID)
        }
        guard UInt64(positions.count) + UInt64(points.count) <= UInt64(UInt32.max) else {
            throw TessellationError.unsupportedFace(faceID)
        }
        let geometricNormal = try faceNormal(points: points, faceID: faceID)
        let pointNormals = try surfaceNormals(
            for: points,
            on: surface,
            face: face,
            shellOrientation: shellOrientation
        )
        let referenceNormal = try averageNormal(pointNormals, faceID: faceID)
        let shouldReverse = geometricNormal.dot(referenceNormal) < 0.0
        let baseIndex = UInt32(positions.count)
        positions.append(contentsOf: points)
        normals.append(contentsOf: pointNormals)

        if shouldReverse {
            indices.append(baseIndex)
            indices.append(baseIndex + 2)
            indices.append(baseIndex + 1)
            indices.append(baseIndex)
            indices.append(baseIndex + 3)
            indices.append(baseIndex + 2)
        } else {
            indices.append(baseIndex)
            indices.append(baseIndex + 1)
            indices.append(baseIndex + 2)
            indices.append(baseIndex)
            indices.append(baseIndex + 2)
            indices.append(baseIndex + 3)
        }
    }

    private func faceNormal(points: [Point3D], faceID: FaceID) throws -> Vector3D {
        let origin = points[0]
        let areaTolerance = tolerance.distance * tolerance.distance
        for index in 1..<(points.count - 1) {
            let first = points[index] - origin
            let second = points[index + 1] - origin
            let cross = first.cross(second)
            try cross.validate()
            let length = cross.length
            guard length.isFinite else {
                throw GeometryError.invalidVectorLength(length)
            }
            if length > areaTolerance {
                return cross / length
            }
        }
        throw TessellationError.degenerateFace(faceID)
    }

    private func simplifiedPlanarPoints(
        _ points: [Point3D],
        normal: Vector3D,
        faceID: FaceID
    ) throws -> [Point3D] {
        let normalizedNormal = try normal.normalized(tolerance: tolerance.distance)
        let areaTolerance = tolerance.distance * tolerance.distance
        var simplified = points
        var didRemove = true
        while didRemove, simplified.count > 3 {
            didRemove = false
            for index in simplified.indices {
                let previous = simplified[(index + simplified.count - 1) % simplified.count]
                let current = simplified[index]
                let next = simplified[(index + 1) % simplified.count]
                let incoming = current - previous
                let outgoing = next - current
                if incoming.length <= tolerance.distance || outgoing.length <= tolerance.distance {
                    simplified.remove(at: index)
                    didRemove = true
                    break
                }
                let signedArea = incoming.cross(outgoing).dot(normalizedNormal)
                if abs(signedArea) <= areaTolerance {
                    simplified.remove(at: index)
                    didRemove = true
                    break
                }
            }
        }
        guard simplified.count >= 3 else {
            throw TessellationError.degenerateFace(faceID)
        }
        _ = try faceNormal(points: simplified, faceID: faceID)
        return simplified
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
        guard turn > tolerance.distance * tolerance.distance else {
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
        let areaTolerance = tolerance.distance * tolerance.distance
        let firstCross = planarCross(first, second, point)
        let secondCross = planarCross(second, third, point)
        let thirdCross = planarCross(third, first, point)
        let hasNegative = firstCross < -areaTolerance
            || secondCross < -areaTolerance
            || thirdCross < -areaTolerance
        let hasPositive = firstCross > areaTolerance
            || secondCross > areaTolerance
            || thirdCross > areaTolerance
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
            normal: geometricNormal,
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
            if turn < -areaTolerance {
                return false
            }
            if turn > areaTolerance {
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

    private func appendCylinderFace(
        loop: Loop,
        cylinder: Cylinder3D,
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
        let bottomPoints = try sampledPoints(for: loop.edges[0], in: model, options: options)
        let reversedTopPoints = try sampledPoints(for: loop.edges[2], in: model, options: options)
        let topPoints = Array(reversedTopPoints.reversed())
        guard bottomPoints.count == topPoints.count,
              bottomPoints.count >= 2 else {
            throw TessellationError.degenerateFace(faceID)
        }
        guard UInt64(positions.count) + UInt64(bottomPoints.count * 2) <= UInt64(UInt32.max) else {
            throw TessellationError.unsupportedFace(faceID)
        }

        let surface = Surface3D.cylinder(cylinder)
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
            appendTriangle(
                bottomCurrent,
                bottomNext,
                topCurrent,
                positions: positions,
                normals: normals,
                indices: &indices
            )
            appendTriangle(
                bottomNext,
                topNext,
                topCurrent,
                positions: positions,
                normals: normals,
                indices: &indices
            )
        }
    }

    private func appendBSplineFace(
        surface: BSplineSurface3D,
        face: Face,
        faceID: FaceID,
        shellOrientation: Orientation,
        options: TessellationOptions,
        positions: inout [Point3D],
        normals: inout [Vector3D],
        indices: inout [UInt32]
    ) throws {
        try surface.validate(tolerance: tolerance)
        let uBounds = try closedBounds(surface.uDomain, faceID: faceID)
        let vBounds = try closedBounds(surface.vDomain, faceID: faceID)
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
                appendTriangle(
                    lowerLeft,
                    lowerRight,
                    upperRight,
                    positions: positions,
                    normals: normals,
                    indices: &indices
                )
                appendTriangle(
                    lowerLeft,
                    upperRight,
                    upperLeft,
                    positions: positions,
                    normals: normals,
                    indices: &indices
                )
            }
        }
    }

    private func closedBounds(_ domain: ParameterDomain, faceID: FaceID) throws -> (lower: Double, upper: Double) {
        try domain.validate(tolerance: tolerance)
        guard case let .closed(lower, upper) = domain else {
            throw TessellationError.unsupportedFace(faceID)
        }
        return (lower, upper)
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
            return min(64, max(4, Int(ceil(1.0 / maxEdgeLength))))
        }
        return 8
    }

    private func sampledPoints(
        for orientedEdge: OrientedEdge,
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
            let segmentCount = max(2, Int(ceil(abs(span) / options.angularTolerance)))
            return try (0...segmentCount).map { index in
                let ratio = Double(index) / Double(segmentCount)
                return try point(
                    on: circle,
                    at: startParameter + span * ratio
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
        let edgeLimit = options.maxEdgeLength.map { max(1, Int(ceil(controlLength / $0))) } ?? 1
        let toleranceLimit = max(4, Int(ceil(sqrt(controlLength / options.linearTolerance))))
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

    private func startVertexID(for orientedEdge: OrientedEdge, edge: Edge) -> VertexID {
        switch orientedEdge.orientation {
        case .forward:
            return edge.startVertexID
        case .reversed:
            return edge.endVertexID
        }
    }

    private func endVertexID(for orientedEdge: OrientedEdge, edge: Edge) -> VertexID {
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

    private func edgeCurveKind(for orientedEdge: OrientedEdge, in model: BRepModel) throws -> EdgeCurveKind {
        guard let edge = model.edges[orientedEdge.edgeID],
              let curve = model.geometry.curves[edge.curveID] else {
            throw TopologyError.missingReference("Missing edge curve \(orientedEdge.edgeID).")
        }
        switch curve {
        case .line:
            return .line
        case .circle:
            return .circle
        case .bSpline:
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

    private func isLineOnly(loop: Loop, model: BRepModel) throws -> Bool {
        for orientedEdge in loop.edges {
            if try edgeCurveKind(for: orientedEdge, in: model) != .line {
                return false
            }
        }
        return true
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
        let areaVector = (secondPoint - firstPoint).cross(thirdPoint - firstPoint)
        let area = areaVector.length
        guard area.isFinite, area > tolerance.distance * tolerance.distance else {
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
}
