import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling

struct ConvexPolygonCircleBooleanPlan: Sendable {
    let operation: BooleanOperation
    let axis: Vector3D
    let height: Double
    let boundaries: [[ExactPrismaticBoundarySegment]]

    init(
        operation: BooleanOperation,
        target: ConvexPlanarSolidOperand,
        tool: RevolvedSolidOperand,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard operation == .union
                || operation == .difference
                || operation == .intersect else {
            throw Self.unsupported(operation: operation, tolerance: tolerance)
        }
        let operands = try CapCoincidentCylinderOperands(
            target: target,
            tool: tool,
            tolerance: tolerance
        )
        let intersections = try Self.intersections(
            polygon: operands.polygon,
            circle: operands.circle,
            axis: operands.axis,
            tolerance: tolerance
        )
        guard intersections.count >= 2,
              intersections.count.isMultiple(of: 2) else {
            throw Self.unsupported(operation: operation, tolerance: tolerance)
        }
        let fragments = try Self.selectedFragments(
            operation: operation,
            polygon: operands.polygon,
            circle: operands.circle,
            axis: operands.axis,
            intersections: intersections,
            tolerance: tolerance
        )
        let boundaries = try Self.stitchedBoundaries(
            fragments,
            operation: operation,
            axis: operands.axis,
            tolerance: tolerance
        )
        guard boundaries.isEmpty == false else {
            throw FeatureEvaluationError.emptyResult(
                "Convex polygon and circle Boolean produced no volumetric boundary."
            )
        }

        self.operation = operation
        self.axis = operands.axis
        self.height = operands.height
        self.boundaries = boundaries
    }

    private struct Intersection: Sendable {
        let edgeIndex: Int
        let edgeDistance: Double
        let point: Point3D
        let circleParameter: Double
    }

    private struct Fragment: Sendable {
        let segment: ExactPrismaticBoundarySegment
    }

    private static func intersections(
        polygon: [Point3D],
        circle: Circle3D,
        axis: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> [Intersection] {
        let curve = Curve3D.circle(circle)
        var result: [Intersection] = []
        for edgeIndex in polygon.indices {
            let start = polygon[edgeIndex]
            let end = polygon[(edgeIndex + 1) % polygon.count]
            let edge = end - start
            let length = edge.length
            let direction = try edge.normalized(tolerance: tolerance.distance)
            let inward = try axis.cross(direction).normalized(
                tolerance: tolerance.distance
            )
            let signedDistance = (circle.center - start).dot(inward)
            let radialGap = circle.radius - abs(signedDistance)
            if radialGap < -tolerance.distance {
                continue
            }
            let foot = circle.center + inward * -signedDistance
            let footDistance = (foot - start).dot(direction)
            if abs(radialGap) <= tolerance.distance {
                if footDistance >= -tolerance.distance,
                   footDistance <= length + tolerance.distance {
                    throw Self.contact(tolerance: tolerance)
                }
                continue
            }
            let halfChord = sqrt(max(
                0.0,
                circle.radius * circle.radius - signedDistance * signedDistance
            ))
            for edgeDistance in [footDistance - halfChord, footDistance + halfChord] {
                if abs(edgeDistance) <= tolerance.distance
                    || abs(edgeDistance - length) <= tolerance.distance {
                    throw Self.contact(tolerance: tolerance)
                }
                guard edgeDistance > tolerance.distance,
                      edgeDistance < length - tolerance.distance else {
                    continue
                }
                let point = start + direction * edgeDistance
                let parameter = try curve.parameterProjection(
                    of: point,
                    tolerance: tolerance
                ).parameter
                result.append(Intersection(
                    edgeIndex: edgeIndex,
                    edgeDistance: edgeDistance,
                    point: point,
                    circleParameter: normalizedParameter(parameter)
                ))
            }
        }
        let circularlySorted = result.sorted {
            if abs($0.circleParameter - $1.circleParameter) > tolerance.angle {
                return $0.circleParameter < $1.circleParameter
            }
            if $0.edgeIndex != $1.edgeIndex {
                return $0.edgeIndex < $1.edgeIndex
            }
            return $0.edgeDistance < $1.edgeDistance
        }
        for index in circularlySorted.indices where circularlySorted.count > 1 {
            let next = circularlySorted[(index + 1) % circularlySorted.count]
            let span = positiveSweep(
                from: circularlySorted[index].circleParameter,
                to: next.circleParameter
            )
            guard span > tolerance.angle else {
                throw Self.contact(tolerance: tolerance)
            }
        }
        return circularlySorted
    }

    private static func selectedFragments(
        operation: BooleanOperation,
        polygon: [Point3D],
        circle: Circle3D,
        axis: Vector3D,
        intersections: [Intersection],
        tolerance: ModelingTolerance
    ) throws -> [Fragment] {
        var fragments = try polygonFragments(
            operation: operation,
            polygon: polygon,
            circle: circle,
            intersections: intersections,
            tolerance: tolerance
        )
        fragments.append(contentsOf: try circleFragments(
            operation: operation,
            polygon: polygon,
            circle: circle,
            axis: axis,
            intersections: intersections,
            tolerance: tolerance
        ))
        return fragments
    }

    private static func polygonFragments(
        operation: BooleanOperation,
        polygon: [Point3D],
        circle: Circle3D,
        intersections: [Intersection],
        tolerance: ModelingTolerance
    ) throws -> [Fragment] {
        var fragments: [Fragment] = []
        let intersectionsByEdge = Dictionary(
            grouping: intersections,
            by: \.edgeIndex
        )
        for edgeIndex in polygon.indices {
            let start = polygon[edgeIndex]
            let end = polygon[(edgeIndex + 1) % polygon.count]
            let edge = end - start
            let length = edge.length
            let direction = try edge.normalized(tolerance: tolerance.distance)
            let splitDistances = [0.0]
                + intersectionsByEdge[edgeIndex, default: []]
                    .map(\.edgeDistance)
                    .sorted()
                + [length]
            for splitIndex in 0..<(splitDistances.count - 1) {
                let lower = splitDistances[splitIndex]
                let upper = splitDistances[splitIndex + 1]
                guard upper - lower > tolerance.distance else {
                    throw Self.contact(tolerance: tolerance)
                }
                let fragmentStart = start + direction * lower
                let fragmentEnd = start + direction * upper
                let midpoint = start + direction * ((lower + upper) * 0.5)
                let residual = (midpoint - circle.center).length - circle.radius
                guard abs(residual) > tolerance.distance else {
                    throw Self.contact(tolerance: tolerance)
                }
                let isInsideCircle = residual < 0.0
                let isSelected: Bool
                switch operation {
                case .union, .difference:
                    isSelected = isInsideCircle == false
                case .intersect:
                    isSelected = isInsideCircle
                case .slice:
                    isSelected = false
                }
                if isSelected {
                    fragments.append(Fragment(segment: try .line(
                        from: fragmentStart,
                        to: fragmentEnd,
                        tolerance: tolerance
                    )))
                }
            }
        }
        return fragments
    }

    private static func circleFragments(
        operation: BooleanOperation,
        polygon: [Point3D],
        circle: Circle3D,
        axis: Vector3D,
        intersections: [Intersection],
        tolerance: ModelingTolerance
    ) throws -> [Fragment] {
        let curve = Curve3D.circle(circle)
        let sortedParameters = intersections.map(\.circleParameter).sorted()
        var fragments: [Fragment] = []
        for index in sortedParameters.indices {
            let start = sortedParameters[index]
            let end = index + 1 < sortedParameters.count
                ? sortedParameters[index + 1]
                : sortedParameters[0] + 2.0 * Double.pi
            let midpoint = try curve.point(
                at: (start + end) * 0.5,
                tolerance: tolerance
            )
            let minimumSideDistance = try polygon.indices.map { edgeIndex in
                let edgeStart = polygon[edgeIndex]
                let edgeEnd = polygon[(edgeIndex + 1) % polygon.count]
                let direction = try (edgeEnd - edgeStart).normalized(
                    tolerance: tolerance.distance
                )
                let inward = try axis.cross(direction).normalized(
                    tolerance: tolerance.distance
                )
                return (midpoint - edgeStart).dot(inward)
            }.min() ?? -.infinity
            guard abs(minimumSideDistance) > tolerance.distance else {
                throw Self.contact(tolerance: tolerance)
            }
            let isInsidePolygon = minimumSideDistance > 0.0
            let isSelected: Bool
            switch operation {
            case .union:
                isSelected = isInsidePolygon == false
            case .difference, .intersect:
                isSelected = isInsidePolygon
            case .slice:
                isSelected = false
            }
            guard isSelected else {
                continue
            }
            let segment: ExactPrismaticBoundarySegment
            if operation == .difference {
                segment = try .circularArc(
                    circle: circle,
                    startParameter: end,
                    endParameter: start,
                    tolerance: tolerance
                )
            } else {
                segment = try .circularArc(
                    circle: circle,
                    startParameter: start,
                    endParameter: end,
                    tolerance: tolerance
                )
            }
            fragments.append(Fragment(segment: segment))
        }
        return fragments
    }

    private static func stitchedBoundaries(
        _ fragments: [Fragment],
        operation: BooleanOperation,
        axis: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> [[ExactPrismaticBoundarySegment]] {
        guard fragments.count >= 2 else {
            throw Self.unsupported(
                operation: operation,
                tolerance: tolerance
            )
        }
        var remaining = fragments
        var boundaries: [[ExactPrismaticBoundarySegment]] = []
        while remaining.isEmpty == false {
            let seedIndex = remaining.indices.min {
                isPoint(remaining[$0].segment.startPoint, before: remaining[$1].segment.startPoint)
            } ?? remaining.startIndex
            let seed = remaining.remove(at: seedIndex).segment
            var boundary = [seed]
            let firstPoint = seed.startPoint
            var endPoint = seed.endPoint
            while endPoint.isApproximatelyEqual(
                to: firstPoint,
                tolerance: tolerance.distance
            ) == false {
                let candidates = remaining.indices.filter {
                    remaining[$0].segment.startPoint.isApproximatelyEqual(
                        to: endPoint,
                        tolerance: tolerance.distance
                    )
                }
                guard candidates.count == 1,
                      let nextIndex = candidates.first else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "Selected polygon-circle boundary does not form deterministic closed loops."
                    )
                }
                let next = remaining.remove(at: nextIndex).segment
                boundary.append(next)
                endPoint = next.endPoint
                guard boundary.count <= fragments.count else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "Selected polygon-circle boundary traversal did not terminate."
                    )
                }
            }
            let normalized = normalizedBoundary(boundary)
            guard try signedDoubleArea(
                of: normalized,
                axis: axis,
                tolerance: tolerance
            ) > tolerance.distance * tolerance.distance * 2.0 else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Selected polygon-circle boundary has invalid orientation or area."
                )
            }
            boundaries.append(normalized)
        }
        return boundaries.sorted {
            isPoint($0[0].startPoint, before: $1[0].startPoint)
        }
    }

    private static func normalizedBoundary(
        _ boundary: [ExactPrismaticBoundarySegment]
    ) -> [ExactPrismaticBoundarySegment] {
        guard let startIndex = boundary.indices.min(by: {
            isPoint(boundary[$0].startPoint, before: boundary[$1].startPoint)
        }) else {
            return boundary
        }
        return Array(boundary[startIndex...]) + Array(boundary[..<startIndex])
    }

    private static func signedDoubleArea(
        of boundary: [ExactPrismaticBoundarySegment],
        axis: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard let reference = boundary.first?.startPoint else {
            return 0.0
        }
        var result = 0.0
        for segment in boundary {
            switch segment.geometry {
            case .line:
                result += (segment.startPoint - reference)
                    .cross(segment.endPoint - reference)
                    .dot(axis)
            case let .circularArc(circle, startParameter, endParameter):
                let normal = try circle.normal.normalized(
                    tolerance: tolerance.distance
                )
                result += (circle.center - reference)
                    .cross(segment.endPoint - segment.startPoint)
                    .dot(axis)
                    + circle.radius * circle.radius
                        * normal.dot(axis)
                        * (endParameter - startParameter)
            case .bSpline:
                throw KernelError(
                    phase: .topology,
                    code: .unsupportedCapability,
                    tolerance: tolerance,
                    message: "Polygon-circle Boolean area evaluation does not accept spline boundaries."
                )
            }
        }
        return result
    }

    private static func normalizedParameter(_ parameter: Double) -> Double {
        let period = 2.0 * Double.pi
        let remainder = parameter.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
    }

    private static func positiveSweep(from start: Double, to end: Double) -> Double {
        let period = 2.0 * Double.pi
        let remainder = (end - start).truncatingRemainder(dividingBy: period)
        return remainder > 0.0 ? remainder : remainder + period
    }

    private static func isPoint(_ lhs: Point3D, before rhs: Point3D) -> Bool {
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.z < rhs.z
    }

    private static func contact(
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message: "Polygon-circle clipping rejects tangent, vertex-coincident, and tolerance-collapsed intersections."
        )
    }

    private static func unsupported(
        operation: BooleanOperation,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message: "Convex polygon-circle \(operation.rawValue) requires a cap-coincident axis-parallel cylinder with transverse boundary intersections."
        )
    }
}
