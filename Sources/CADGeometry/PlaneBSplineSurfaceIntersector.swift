import Foundation
import CADCore

struct PlaneBSplineSurfaceIntersector {
    private struct UVSegment: Sendable {
        let first: Point2D
        let second: Point2D
    }

    private struct UVKey: Hashable, Comparable, Sendable {
        let u: Int64
        let v: Int64

        static func < (lhs: UVKey, rhs: UVKey) -> Bool {
            lhs.u == rhs.u ? lhs.v < rhs.v : lhs.u < rhs.u
        }
    }

    private struct GraphEdge: Sendable {
        let first: UVKey
        let second: UVKey
    }

    private struct UndirectedEdgeKey: Hashable, Sendable {
        let lower: UVKey
        let upper: UVKey

        init(_ first: UVKey, _ second: UVKey) {
            lower = min(first, second)
            upper = max(first, second)
        }
    }

    func intersections(
        plane: CanonicalAnalyticSurface.Plane,
        surface: BSplineSurface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        planeIsFirst: Bool,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        do {
            return try PlaneBSplineBoundarySurfaceIntersector().intersections(
                plane: plane,
                surface: surface,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
        } catch let error as KernelError where error.code == .unsupportedCapability {
            return try adaptiveIntersections(
                plane: plane,
                surface: surface,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                planeIsFirst: planeIsFirst,
                options: options,
                tolerance: tolerance
            )
        }
    }

    private func adaptiveIntersections(
        plane: CanonicalAnalyticSurface.Plane,
        surface: BSplineSurface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        planeIsFirst: Bool,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let patches = try BSplineSurfaceBezierDecomposer().scalarDistancePatches(
            surface: surface,
            plane: plane,
            tolerance: tolerance
        )
        var segments: [UVSegment] = []
        var remainingSeedCount = options.maximumSeedCount
        for patch in patches {
            try trace(
                patch: patch,
                depth: 0,
                surface: surface,
                plane: plane,
                options: options,
                tolerance: tolerance,
                remainingSeedCount: &remainingSeedCount,
                segments: &segments
            )
        }
        guard segments.isEmpty == false else {
            return []
        }

        let polylines = try connectedPolylines(
            segments,
            surface: surface,
            tolerance: tolerance
        )
        var result: [SurfaceSurfaceIntersection] = []
        result.reserveCapacity(polylines.count)
        var remainingPointCount = min(max(options.maximumSeedCount * 64, 4_096), 65_536)
        for polyline in polylines {
            let refined = try refinedPolyline(
                polyline,
                surface: surface,
                plane: plane,
                options: options,
                tolerance: tolerance,
                remainingPointCount: &remainingPointCount
            )
            result.append(try curveIntersection(
                parameters: refined,
                surface: surface,
                plane: plane,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                planeIsFirst: planeIsFirst,
                tolerance: tolerance
            ))
        }
        return result
    }

    private func trace(
        patch: RationalScalarBezierPatch,
        depth: Int,
        surface: BSplineSurface3D,
        plane: CanonicalAnalyticSurface.Plane,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingSeedCount: inout Int,
        segments: inout [UVSegment]
    ) throws {
        let bounds = patch.distanceBounds
        let rootTolerance = max(tolerance.distance * 1.0e-3, Double.ulpOfOne)
        if bounds.lower > rootTolerance || bounds.upper < -rootTolerance {
            return
        }
        if bounds.lower >= -tolerance.distance,
           bounds.upper <= tolerance.distance {
            throw KernelError(
                phase: .geometry,
                code: .nonDiscreteIntersection,
                residual: max(abs(bounds.lower), abs(bounds.upper)),
                tolerance: tolerance,
                message: "Plane and B-spline surface share a two-dimensional region within tolerance."
            )
        }
        if let certifiedSegment = patch.certifiedAxisAlignedZeroSegment() {
            guard remainingSeedCount > 0 else {
                throw resourceLimit(
                    tolerance: tolerance,
                    message: "Plane–B-spline tracing exceeded its seed limit."
                )
            }
            remainingSeedCount -= 1
            segments.append(UVSegment(
                first: certifiedSegment.first,
                second: certifiedSegment.second
            ))
            return
        }
        if depth < options.maximumSubdivisionDepth {
            for child in patch.subdivided() {
                try trace(
                    patch: child,
                    depth: depth + 1,
                    surface: surface,
                    plane: plane,
                    options: options,
                    tolerance: tolerance,
                    remainingSeedCount: &remainingSeedCount,
                    segments: &segments
                )
            }
            return
        }
        guard remainingSeedCount > 0 else {
            throw resourceLimit(tolerance: tolerance, message: "Plane–B-spline tracing exceeded its seed limit.")
        }
        let leafSegments = try leafSegments(
            in: patch,
            surface: surface,
            plane: plane,
            options: options,
            tolerance: tolerance
        )
        remainingSeedCount -= leafSegments.count
        segments.append(contentsOf: leafSegments)
    }

    private func leafSegments(
        in patch: RationalScalarBezierPatch,
        surface: BSplineSurface3D,
        plane: CanonicalAnalyticSurface.Plane,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [UVSegment] {
        let corners = [
            Point2D(x: patch.uLower, y: patch.vLower),
            Point2D(x: patch.uUpper, y: patch.vLower),
            Point2D(x: patch.uUpper, y: patch.vUpper),
            Point2D(x: patch.uLower, y: patch.vUpper),
        ]
        let values = try corners.map {
            try signedDistance(at: $0, surface: surface, plane: plane, tolerance: tolerance)
        }
        let edgeCorners = [(0, 1), (1, 2), (2, 3), (3, 0)]
        let rootTolerance = max(tolerance.distance * 1.0e-3, Double.ulpOfOne)
        var fullEdges: [UVSegment] = []
        var roots: [(edge: Int, parameter: Point2D)] = []
        for edgeIndex in edgeCorners.indices {
            let indices = edgeCorners[edgeIndex]
            let firstValue = values[indices.0]
            let secondValue = values[indices.1]
            if abs(firstValue) <= rootTolerance,
               abs(secondValue) <= rootTolerance {
                fullEdges.append(UVSegment(first: corners[indices.0], second: corners[indices.1]))
                continue
            }
            if let root = try edgeRoot(
                first: corners[indices.0],
                second: corners[indices.1],
                firstValue: firstValue,
                secondValue: secondValue,
                surface: surface,
                plane: plane,
                options: options,
                tolerance: tolerance
            ) {
                if roots.contains(where: { parameterDistance($0.parameter, root) <= 1.0e-12 }) == false {
                    roots.append((edgeIndex, root))
                }
            }
        }
        if fullEdges.isEmpty == false {
            guard roots.count <= 2 else {
                throw unresolvedLeaf(patch: patch, tolerance: tolerance)
            }
            return fullEdges
        }
        switch roots.count {
        case 0:
            let bounds = patch.distanceBounds
            if bounds.lower <= 0.0, bounds.upper >= 0.0 {
                throw unresolvedLeaf(patch: patch, tolerance: tolerance)
            }
            return []
        case 2:
            return [UVSegment(first: roots[0].parameter, second: roots[1].parameter)]
        case 4:
            let center = Point2D(
                x: patch.uLower + (patch.uUpper - patch.uLower) * 0.5,
                y: patch.vLower + (patch.vUpper - patch.vLower) * 0.5
            )
            let centerValue = try signedDistance(
                at: center,
                surface: surface,
                plane: plane,
                tolerance: tolerance
            )
            let byEdge = Dictionary(uniqueKeysWithValues: roots.map { ($0.edge, $0.parameter) })
            guard let edge0 = byEdge[0],
                  let edge1 = byEdge[1],
                  let edge2 = byEdge[2],
                  let edge3 = byEdge[3] else {
                throw unresolvedLeaf(patch: patch, tolerance: tolerance)
            }
            if sameSign(centerValue, values[0]) {
                return [
                    UVSegment(first: edge0, second: edge1),
                    UVSegment(first: edge2, second: edge3),
                ]
            }
            return [
                UVSegment(first: edge3, second: edge0),
                UVSegment(first: edge1, second: edge2),
            ]
        default:
            throw unresolvedLeaf(patch: patch, tolerance: tolerance)
        }
    }

    private func edgeRoot(
        first: Point2D,
        second: Point2D,
        firstValue: Double,
        secondValue: Double,
        surface: BSplineSurface3D,
        plane: CanonicalAnalyticSurface.Plane,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> Point2D? {
        let rootTolerance = max(tolerance.distance * 1.0e-3, Double.ulpOfOne)
        if abs(firstValue) <= rootTolerance { return first }
        if abs(secondValue) <= rootTolerance { return second }
        guard firstValue.sign != secondValue.sign else { return nil }

        var lower = 0.0
        var upper = 1.0
        var lowerValue = firstValue
        var parameter = abs(firstValue) / (abs(firstValue) + abs(secondValue))
        var residual = Double.greatestFiniteMagnitude
        for _ in 0..<options.maximumIterations {
            let uv = interpolated(first, second, fraction: parameter)
            let geometry = try surface.differentialGeometry(
                atU: uv.x,
                v: uv.y,
                tolerance: tolerance
            )
            residual = (geometry.position - plane.origin).dot(plane.normal)
            if abs(residual) <= rootTolerance {
                return uv
            }
            if lowerValue.sign == residual.sign {
                lower = parameter
                lowerValue = residual
            } else {
                upper = parameter
            }
            let directionU = second.x - first.x
            let directionV = second.y - first.y
            let derivative = geometry.tangentU.dot(plane.normal) * directionU
                + geometry.tangentV.dot(plane.normal) * directionV
            let newton = parameter - residual / derivative
            if derivative.isFinite,
               abs(derivative) > Double.ulpOfOne,
               newton > lower,
               newton < upper {
                parameter = newton
            } else {
                parameter = lower + (upper - lower) * 0.5
            }
        }
        throw KernelError(
            phase: .geometry,
            code: .intersectionFailure,
            residual: abs(residual),
            tolerance: tolerance,
            message: "Bracketed Newton refinement did not converge on a plane–B-spline edge root."
        )
    }

    private func connectedPolylines(
        _ segments: [UVSegment],
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> [[Point2D]] {
        let uBounds = try closedBounds(surface.uDomain, tolerance: tolerance)
        let vBounds = try closedBounds(surface.vDomain, tolerance: tolerance)
        var points: [UVKey: Point2D] = [:]
        var edges: [GraphEdge] = []
        var edgeKeys = Set<UndirectedEdgeKey>()
        for segment in segments {
            let firstKey = quantizedKey(segment.first, uBounds: uBounds, vBounds: vBounds)
            let secondKey = quantizedKey(segment.second, uBounds: uBounds, vBounds: vBounds)
            guard firstKey != secondKey else { continue }
            let edgeKey = UndirectedEdgeKey(firstKey, secondKey)
            guard edgeKeys.insert(edgeKey).inserted else { continue }
            points[firstKey] = points[firstKey] ?? segment.first
            points[secondKey] = points[secondKey] ?? segment.second
            edges.append(GraphEdge(first: firstKey, second: secondKey))
        }
        var adjacency: [UVKey: [Int]] = [:]
        for index in edges.indices {
            adjacency[edges[index].first, default: []].append(index)
            adjacency[edges[index].second, default: []].append(index)
        }
        guard adjacency.values.allSatisfy({ $0.count <= 2 }) else {
            throw KernelError(
                phase: .geometry,
                code: .nonDiscreteIntersection,
                tolerance: tolerance,
                message: "Plane–B-spline intersection tracing produced a branching contour."
            )
        }
        var visited = Set<Int>()
        var result: [[Point2D]] = []
        let openStarts = adjacency.keys.filter { adjacency[$0]?.count == 1 }.sorted()
        for start in openStarts where hasUnvisitedEdge(start, adjacency: adjacency, visited: visited) {
            result.append(try walk(
                start: start,
                points: points,
                edges: edges,
                adjacency: adjacency,
                visited: &visited
            ))
        }
        while let edgeIndex = edges.indices.first(where: { visited.contains($0) == false }) {
            let start = min(edges[edgeIndex].first, edges[edgeIndex].second)
            result.append(try walk(
                start: start,
                points: points,
                edges: edges,
                adjacency: adjacency,
                visited: &visited
            ))
        }
        return result.filter { $0.count >= 2 }
    }

    private func walk(
        start: UVKey,
        points: [UVKey: Point2D],
        edges: [GraphEdge],
        adjacency: [UVKey: [Int]],
        visited: inout Set<Int>
    ) throws -> [Point2D] {
        guard let startPoint = points[start] else {
            throw GeometryError.invalidDistance(0.0)
        }
        var result = [startPoint]
        var current = start
        while true {
            let candidates = (adjacency[current] ?? [])
                .filter { visited.contains($0) == false }
                .sorted { first, second in
                    otherEndpoint(edges[first], from: current) < otherEndpoint(edges[second], from: current)
                }
            guard let edgeIndex = candidates.first else { break }
            visited.insert(edgeIndex)
            current = otherEndpoint(edges[edgeIndex], from: current)
            guard let point = points[current] else {
                throw GeometryError.invalidDistance(0.0)
            }
            result.append(point)
            if current == start { break }
        }
        return result
    }

    private func refinedPolyline(
        _ source: [Point2D],
        surface: BSplineSurface3D,
        plane: CanonicalAnalyticSurface.Plane,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingPointCount: inout Int
    ) throws -> [Point2D] {
        guard source.count >= 2 else { return source }
        var result = [source[0]]
        for index in 1..<source.count {
            let firstPoint = try surface.point(
                u: source[index - 1].x,
                v: source[index - 1].y,
                tolerance: tolerance
            )
            let secondPoint = try surface.point(
                u: source[index].x,
                v: source[index].y,
                tolerance: tolerance
            )
            try refineSegment(
                firstParameter: source[index - 1],
                firstPoint: firstPoint,
                secondParameter: source[index],
                secondPoint: secondPoint,
                depth: 0,
                surface: surface,
                plane: plane,
                options: options,
                tolerance: tolerance,
                remainingPointCount: &remainingPointCount,
                result: &result
            )
        }
        return result
    }

    private func refineSegment(
        firstParameter: Point2D,
        firstPoint: Point3D,
        secondParameter: Point2D,
        secondPoint: Point3D,
        depth: Int,
        surface: BSplineSurface3D,
        plane: CanonicalAnalyticSurface.Plane,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingPointCount: inout Int,
        result: inout [Point2D]
    ) throws {
        guard remainingPointCount > 0 else {
            throw resourceLimit(tolerance: tolerance, message: "Plane–B-spline curve refinement exceeded its point limit.")
        }
        let seed = interpolated(firstParameter, secondParameter, fraction: 0.5)
        let middleParameter = try correctedParameter(
            seed,
            surface: surface,
            plane: plane,
            options: options,
            tolerance: tolerance
        )
        let middlePoint = try surface.point(
            u: middleParameter.x,
            v: middleParameter.y,
            tolerance: tolerance
        )
        let chordMiddle = interpolated(firstPoint, secondPoint, fraction: 0.5)
        let deviation = (middlePoint - chordMiddle).length
        let planeResidual = abs((middlePoint - plane.origin).dot(plane.normal))
        if deviation <= tolerance.distance * 0.5,
           planeResidual <= tolerance.distance * 0.1 {
            remainingPointCount -= 1
            result.append(secondParameter)
            return
        }
        guard depth < 18 else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: max(deviation, planeResidual),
                tolerance: tolerance,
                message: "Plane–B-spline intersection curve did not converge within tolerance."
            )
        }
        try refineSegment(
            firstParameter: firstParameter,
            firstPoint: firstPoint,
            secondParameter: middleParameter,
            secondPoint: middlePoint,
            depth: depth + 1,
            surface: surface,
            plane: plane,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount,
            result: &result
        )
        try refineSegment(
            firstParameter: middleParameter,
            firstPoint: middlePoint,
            secondParameter: secondParameter,
            secondPoint: secondPoint,
            depth: depth + 1,
            surface: surface,
            plane: plane,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount,
            result: &result
        )
    }

    private func correctedParameter(
        _ seed: Point2D,
        surface: BSplineSurface3D,
        plane: CanonicalAnalyticSurface.Plane,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> Point2D {
        let uBounds = try closedBounds(surface.uDomain, tolerance: tolerance)
        let vBounds = try closedBounds(surface.vDomain, tolerance: tolerance)
        var parameter = seed
        var residual = Double.greatestFiniteMagnitude
        for _ in 0..<options.maximumIterations {
            let geometry = try surface.differentialGeometry(
                atU: parameter.x,
                v: parameter.y,
                tolerance: tolerance
            )
            residual = (geometry.position - plane.origin).dot(plane.normal)
            if abs(residual) <= tolerance.distance * 0.1 {
                return parameter
            }
            let gradientU = geometry.tangentU.dot(plane.normal)
            let gradientV = geometry.tangentV.dot(plane.normal)
            let squaredLength = gradientU * gradientU + gradientV * gradientV
            guard squaredLength.isFinite,
                  squaredLength > Double.ulpOfOne else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: abs(residual),
                    tolerance: tolerance,
                    message: "Plane–B-spline Newton correction encountered a singular level-set gradient."
                )
            }
            let scale = residual / squaredLength
            parameter = Point2D(
                x: min(max(parameter.x - gradientU * scale, uBounds.lower), uBounds.upper),
                y: min(max(parameter.y - gradientV * scale, vBounds.lower), vBounds.upper)
            )
        }
        throw KernelError(
            phase: .geometry,
            code: .intersectionFailure,
            residual: abs(residual),
            tolerance: tolerance,
            message: "Plane–B-spline Newton correction did not converge."
        )
    }

    private func curveIntersection(
        parameters: [Point2D],
        surface: BSplineSurface3D,
        plane: CanonicalAnalyticSurface.Plane,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        planeIsFirst: Bool,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        guard parameters.count >= 2 else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Plane–B-spline intersection component has fewer than two points."
            )
        }
        let points = try parameters.map {
            try surface.point(u: $0.x, v: $0.y, tolerance: tolerance)
        }
        let knots = degreeOneKnots(controlPointCount: points.count)
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: knots,
            controlPoints: points
        ))
        let planeSurface = planeIsFirst ? firstSurface : secondSurface
        let planeParameters = try points.map { point -> Point2D in
            let projection = try planeSurface.parameterProjection(of: point, tolerance: tolerance)
            return Point2D(x: projection.u, y: projection.v)
        }
        let planePcurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 1,
            knots: knots,
            controlPoints: planeParameters
        ))
        let surfacePcurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 1,
            knots: knots,
            controlPoints: parameters
        ))
        try planePcurve.validate(on: planeSurface, tolerance: tolerance)
        try surfacePcurve.validate(on: .bSpline(surface), tolerance: tolerance)
        let firstAnchor = try firstSurface.parameterProjection(of: points[0], tolerance: tolerance)
        let secondAnchor = try secondSurface.parameterProjection(of: points[0], tolerance: tolerance)
        let maximumResidual = try verifiedResidual(
            points: points,
            planeParameters: planeParameters,
            surfaceParameters: parameters,
            planeSurface: planeSurface,
            surface: surface,
            tolerance: tolerance
        )
        let kind = try contactKind(
            parameters: parameters,
            surface: surface,
            plane: plane,
            tolerance: tolerance
        )
        return .curve(try SurfaceSurfaceIntersectionCurve(
            truth: .parametric(curve),
            derivedRepresentation: try SurfaceSurfaceIntersectionDerivedRepresentation(
                curve: curve,
                firstSurfaceParameterCurve: planeIsFirst ? planePcurve : surfacePcurve,
                secondSurfaceParameterCurve: planeIsFirst ? surfacePcurve : planePcurve,
                maximumResidualUpperBound: maximumResidual,
                tolerance: tolerance
            ),
            kind: kind,
            firstSurfaceAnchor: firstAnchor,
            secondSurfaceAnchor: secondAnchor,
            tolerance: tolerance
        ))
    }

    private func verifiedResidual(
        points: [Point3D],
        planeParameters: [Point2D],
        surfaceParameters: [Point2D],
        planeSurface: Surface3D,
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        var maximumResidual = 0.0
        for index in 1..<points.count {
            for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let curvePoint = interpolated(points[index - 1], points[index], fraction: fraction)
                let planeUV = interpolated(
                    planeParameters[index - 1],
                    planeParameters[index],
                    fraction: fraction
                )
                let surfaceUV = interpolated(
                    surfaceParameters[index - 1],
                    surfaceParameters[index],
                    fraction: fraction
                )
                let planePoint = try planeSurface.point(
                    u: planeUV.x,
                    v: planeUV.y,
                    tolerance: tolerance
                )
                let surfacePoint = try surface.point(
                    u: surfaceUV.x,
                    v: surfaceUV.y,
                    tolerance: tolerance
                )
                maximumResidual = max(
                    maximumResidual,
                    (curvePoint - planePoint).length,
                    (curvePoint - surfacePoint).length
                )
            }
        }
        guard maximumResidual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidual,
                tolerance: tolerance,
                message: "Plane–B-spline intersection failed adaptive residual verification."
            )
        }
        return maximumResidual
    }

    private func contactKind(
        parameters: [Point2D],
        surface: BSplineSurface3D,
        plane: CanonicalAnalyticSurface.Plane,
        tolerance: ModelingTolerance
    ) throws -> CurveSurfaceIntersectionKind {
        var transverseCount = 0
        var tangentCount = 0
        for parameter in parameters {
            let normal = try surface.normal(u: parameter.x, v: parameter.y, tolerance: tolerance)
            if normal.cross(plane.normal).length > tolerance.angle {
                transverseCount += 1
            } else {
                tangentCount += 1
            }
        }
        if transverseCount == 0 { return .tangent }
        if tangentCount == 0 { return .transverse }
        return .mixed
    }

    private func signedDistance(
        at parameter: Point2D,
        surface: BSplineSurface3D,
        plane: CanonicalAnalyticSurface.Plane,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let point = try surface.point(u: parameter.x, v: parameter.y, tolerance: tolerance)
        return (point - plane.origin).dot(plane.normal)
    }

    private func closedBounds(
        _ domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> (lower: Double, upper: Double) {
        guard case let .closed(lower, upper) = domain,
              upper - lower > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Plane–B-spline tracing requires finite non-degenerate parameter domains."
            )
        }
        return (lower, upper)
    }

    private func quantizedKey(
        _ point: Point2D,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double)
    ) -> UVKey {
        let scale = 1.0e10
        return UVKey(
            u: Int64((((point.x - uBounds.lower) / (uBounds.upper - uBounds.lower)) * scale).rounded()),
            v: Int64((((point.y - vBounds.lower) / (vBounds.upper - vBounds.lower)) * scale).rounded())
        )
    }

    private func hasUnvisitedEdge(
        _ key: UVKey,
        adjacency: [UVKey: [Int]],
        visited: Set<Int>
    ) -> Bool {
        (adjacency[key] ?? []).contains { visited.contains($0) == false }
    }

    private func otherEndpoint(_ edge: GraphEdge, from endpoint: UVKey) -> UVKey {
        edge.first == endpoint ? edge.second : edge.first
    }

    private func degreeOneKnots(controlPointCount: Int) -> [Double] {
        guard controlPointCount >= 2 else { return [] }
        return [0.0, 0.0]
            + (1..<(controlPointCount - 1)).map(Double.init)
            + [Double(controlPointCount - 1), Double(controlPointCount - 1)]
    }

    private func interpolated(_ first: Point2D, _ second: Point2D, fraction: Double) -> Point2D {
        Point2D(
            x: first.x + (second.x - first.x) * fraction,
            y: first.y + (second.y - first.y) * fraction
        )
    }

    private func interpolated(_ first: Point3D, _ second: Point3D, fraction: Double) -> Point3D {
        Point3D(
            x: first.x + (second.x - first.x) * fraction,
            y: first.y + (second.y - first.y) * fraction,
            z: first.z + (second.z - first.z) * fraction
        )
    }

    private func parameterDistance(_ first: Point2D, _ second: Point2D) -> Double {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func sameSign(_ first: Double, _ second: Double) -> Bool {
        (first >= 0.0 && second >= 0.0) || (first < 0.0 && second < 0.0)
    }

    private func unresolvedLeaf(
        patch: RationalScalarBezierPatch,
        tolerance: ModelingTolerance
    ) -> KernelError {
        let bounds = patch.distanceBounds
        return KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            residual: min(abs(bounds.lower), abs(bounds.upper)),
            tolerance: tolerance,
            message: "Plane–B-spline interval bounds remain ambiguous at the subdivision limit."
        )
    }

    private func resourceLimit(tolerance: ModelingTolerance, message: String) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: message
        )
    }
}
