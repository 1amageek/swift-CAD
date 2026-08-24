import Foundation
import CADCore
import CADGeometry

struct ExchangePolygonTriangulator: Sendable {
    private let predicates: any PlanarPredicateEvaluating

    init(predicates: any PlanarPredicateEvaluating = AdaptivePlanarPredicateEvaluator()) {
        self.predicates = predicates
    }

    func triangles(
        for points: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> [(Int, Int, Int)] {
        guard points.count >= 3 else {
            throw ImportError.invalidData("A polygon requires at least three vertices.")
        }
        let projection = try planarProjection(points, tolerance: tolerance)
        var remaining = Array(points.indices)
        try removeRedundantCorners(
            from: &remaining,
            projected: projection,
            tolerance: tolerance
        )
        guard remaining.count >= 3 else {
            throw ImportError.invalidData("A polygon collapses after redundant corners are removed.")
        }
        try validateSimplePolygon(
            remaining,
            projected: projection,
            tolerance: tolerance
        )
        let polygon = remaining.map { projection[$0] }
        let orientation = try predicates.orientation(of: polygon, tolerance: tolerance)
        guard orientation == .positive || orientation == .negative else {
            throw ImportError.invalidData("A polygon has no certifiable orientation.")
        }

        var result: [(Int, Int, Int)] = []
        result.reserveCapacity(remaining.count - 2)
        while remaining.count > 3 {
            var earIndex: Int?
            for candidate in remaining.indices {
                if try isEar(
                    candidate,
                    remaining: remaining,
                    projected: projection,
                    polygonOrientation: orientation,
                    tolerance: tolerance
                ) {
                    earIndex = candidate
                    break
                }
            }
            guard let earIndex else {
                throw ImportError.invalidData("A polygon could not be triangulated without crossing its boundary.")
            }
            let previous = remaining[(earIndex + remaining.count - 1) % remaining.count]
            let current = remaining[earIndex]
            let next = remaining[(earIndex + 1) % remaining.count]
            result.append((previous, current, next))
            remaining.remove(at: earIndex)
        }
        result.append((remaining[0], remaining[1], remaining[2]))
        return result
    }

    private func planarProjection(
        _ points: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> [Point2D] {
        let origin = points[0]
        var normal: Vector3D?
        for firstIndex in 1..<(points.count - 1) {
            let first = points[firstIndex] - origin
            for secondIndex in (firstIndex + 1)..<points.count {
                let candidate = first.cross(points[secondIndex] - origin)
                if candidate.length > tolerance.distance * tolerance.distance {
                    normal = candidate / candidate.length
                    break
                }
            }
            if normal != nil {
                break
            }
        }
        guard let normal else {
            throw ImportError.invalidData("A polygon is collinear.")
        }
        for point in points {
            let distance = abs((point - origin).dot(normal))
            guard distance <= tolerance.distance else {
                throw ImportError.invalidData("A polygon is not planar within modeling tolerance.")
            }
        }
        let x = abs(normal.x)
        let y = abs(normal.y)
        let z = abs(normal.z)
        if z >= x, z >= y {
            return points.map { Point2D(x: $0.x, y: $0.y) }
        }
        if y >= x {
            return points.map { Point2D(x: $0.x, y: $0.z) }
        }
        return points.map { Point2D(x: $0.y, y: $0.z) }
    }

    private func removeRedundantCorners(
        from indices: inout [Int],
        projected: [Point2D],
        tolerance: ModelingTolerance
    ) throws {
        var changed = true
        while changed, indices.count > 3 {
            changed = false
            for index in indices.indices {
                let previous = projected[indices[(index + indices.count - 1) % indices.count]]
                let current = projected[indices[index]]
                let next = projected[indices[(index + 1) % indices.count]]
                let firstLength = hypot(current.x - previous.x, current.y - previous.y)
                let secondLength = hypot(next.x - current.x, next.y - current.y)
                if firstLength <= tolerance.distance || secondLength <= tolerance.distance {
                    indices.remove(at: index)
                    changed = true
                    break
                }
                let sign = try predicates.orientation(
                    previous,
                    current,
                    relativeTo: next,
                    tolerance: tolerance
                )
                if sign == .zero || sign == .indeterminate {
                    indices.remove(at: index)
                    changed = true
                    break
                }
            }
        }
    }

    private func validateSimplePolygon(
        _ indices: [Int],
        projected: [Point2D],
        tolerance: ModelingTolerance
    ) throws {
        for firstIndex in indices.indices {
            let firstNext = (firstIndex + 1) % indices.count
            for secondIndex in indices.indices where secondIndex > firstIndex {
                let secondNext = (secondIndex + 1) % indices.count
                if firstIndex == secondIndex
                    || firstNext == secondIndex
                    || secondNext == firstIndex {
                    continue
                }
                if try predicates.segmentsIntersectOrTouch(
                    projected[indices[firstIndex]],
                    projected[indices[firstNext]],
                    projected[indices[secondIndex]],
                    projected[indices[secondNext]],
                    tolerance: tolerance
                ) {
                    throw ImportError.invalidData("A polygon boundary self-intersects or touches itself.")
                }
            }
        }
    }

    private func isEar(
        _ candidate: Int,
        remaining: [Int],
        projected: [Point2D],
        polygonOrientation: RobustSign,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let previousIndex = remaining[(candidate + remaining.count - 1) % remaining.count]
        let currentIndex = remaining[candidate]
        let nextIndex = remaining[(candidate + 1) % remaining.count]
        let previous = projected[previousIndex]
        let current = projected[currentIndex]
        let next = projected[nextIndex]
        let cornerOrientation = try predicates.orientation(
            previous,
            current,
            relativeTo: next,
            tolerance: tolerance
        )
        guard cornerOrientation == polygonOrientation else {
            return false
        }
        let triangle = [previous, current, next]
        for index in remaining where index != previousIndex && index != currentIndex && index != nextIndex {
            let classification = try predicates.classify(
                projected[index],
                in: triangle,
                tolerance: tolerance
            )
            guard classification == .outside else {
                return false
            }
        }
        return true
    }
}
