import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct DefaultFacePointContainmentTester: FacePointContainmentTesting {
    private let planarPredicates: any PlanarPredicateEvaluating

    public init(
        planarPredicates: any PlanarPredicateEvaluating = AdaptivePlanarPredicateEvaluator()
    ) {
        self.planarPredicates = planarPredicates
    }

    public func contains(
        _ point: Point3D,
        on faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        var preparationCache = FacePointContainmentPreparationCache()
        return try contains(
            point,
            on: faceID,
            in: model,
            preparationCache: &preparationCache,
            tolerance: tolerance
        )
    }

    func contains(
        _ point: Point3D,
        on faceID: FaceID,
        in model: BRepModel,
        preparationCache: inout FacePointContainmentPreparationCache,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try tolerance.validate()
        try point.validate()
        let preparedFace: FacePointContainmentPreparationCache.PreparedFace
        if let cached = preparationCache.faces[faceID] {
            preparedFace = cached
        } else {
            preparedFace = try prepare(
                faceID: faceID,
                model: model,
                tolerance: tolerance
            )
            preparationCache.faces[faceID] = preparedFace
        }
        let projection = try preparedFace.surface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        var insideOuter = false
        for loop in preparedFace.loops {
            let query = aligned(
                UV(u: projection.u, v: projection.v),
                to: loop.polygon,
                on: preparedFace.surface
            )
            let classification: PlanarPointClassification
            if isOutsidePolygonBounds(query, polygon: loop.polygon) {
                // Chart-pole and seam artifacts can distort the sampled
                // polygon's winding far from the loop; a query beyond the
                // polygon's parameter extent can never be inside it.
                classification = .outside
            } else {
                classification = try classify(
                    query,
                    in: loop.polygon,
                    tolerance: tolerance
                )
            }
            guard classification != .indeterminate else {
                throw KernelError(
                    phase: .classification,
                    code: .classificationFailure,
                    tolerance: tolerance,
                    message: "Trimmed-face containment could not resolve a planar predicate."
                )
            }
            switch loop.role {
            case .outer:
                insideOuter = classification != .outside
            case .inner:
                if classification == .inside { return false }
            }
        }
        return insideOuter
    }

    private func prepare(
        faceID: FaceID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> FacePointContainmentPreparationCache.PreparedFace {
        guard let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID] else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message: "Trimmed-face containment references missing face geometry."
            )
        }
        let regions = try face.loops.map { loopID in
            guard let loop = model.loops[loopID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Trimmed-face containment references a missing loop."
                )
            }
            let polygon = try loopParameters(
                loop,
                surface: surface,
                model: model,
                tolerance: tolerance
            )
            return FacePointContainmentPreparationCache.LoopRegion(
                role: loop.role,
                polygon: polygon
            )
        }
        return FacePointContainmentPreparationCache.PreparedFace(
            surface: surface,
            loops: regions
        )
    }

    private func loopParameters(
        _ loop: Loop,
        surface: Surface3D,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [UV] {
        var polygon: [UV] = []
        for coedge in loop.coedges {
            guard let edge = model.edges[coedge.edgeID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Trimmed-face containment references a missing edge."
                )
            }
            let samples = try edgeSamples(
                edge,
                orientation: coedge.orientation,
                model: model,
                tolerance: tolerance
            )
            for sample in samples {
                let projection = try surface.parameterProjection(of: sample, tolerance: tolerance)
                let parameter = unwrapped(
                    UV(u: projection.u, v: projection.v),
                    relativeTo: polygon.last,
                    on: surface
                )
                append(
                    parameter,
                    to: &polygon,
                    tolerance: tolerance.distance
                )
            }
        }
        if polygon.count > 1,
           let first = polygon.first,
           let last = polygon.last,
           hypot(last.u - first.u, last.v - first.v) <= tolerance.distance {
            polygon.removeLast()
        }
        return polygon
    }

    private func appendAuthoredParameterSamples(
        _ samples: [SurfaceParameter],
        to polygon: inout [UV],
        on surface: Surface3D,
        tolerance: Double
    ) {
        guard let first = samples.first else { return }
        let authoredFirst = UV(u: first.u, v: first.v)
        let alignedFirst = unwrapped(
            authoredFirst,
            relativeTo: polygon.last,
            on: surface
        )
        let uOffset = alignedFirst.u - authoredFirst.u
        let vOffset = alignedFirst.v - authoredFirst.v
        for sample in samples {
            append(
                UV(u: sample.u + uOffset, v: sample.v + vOffset),
                to: &polygon,
                tolerance: tolerance
            )
        }
    }

    private func unwrapped(
        _ point: UV,
        relativeTo reference: UV?,
        on surface: Surface3D
    ) -> UV {
        guard let reference else { return point }
        return UV(
            u: unwrapped(point.u, relativeTo: reference.u, domain: surface.uDomain),
            v: unwrapped(point.v, relativeTo: reference.v, domain: surface.vDomain)
        )
    }

    private func edgeSamples(
        _ edge: Edge,
        orientation: Orientation,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        guard let curve = model.geometry.curves[edge.curveID],
              let startVertex = model.vertices[edge.startVertexID],
              let endVertex = model.vertices[edge.endVertexID] else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message: "Trimmed-face containment references missing edge geometry."
            )
        }
        guard let trim = edge.trim else {
            return orientation == .forward
                ? [startVertex.point, endVertex.point]
                : [endVertex.point, startVertex.point]
        }
        let startParameter = orientation == .forward
            ? trim.startParameter
            : trim.endParameter
        let endParameter = orientation == .forward
            ? trim.endParameter
            : trim.startParameter
        let start = try curve.point(at: startParameter, tolerance: tolerance)
        let end = try curve.point(at: endParameter, tolerance: tolerance)
        var result = [start]
        try appendEdgeSamples(
            curve: curve,
            lowerParameter: startParameter,
            lowerPoint: start,
            upperParameter: endParameter,
            upperPoint: end,
            depth: 0,
            points: &result,
            tolerance: tolerance
        )
        return result
    }

    private func appendEdgeSamples(
        curve: Curve3D,
        lowerParameter: Double,
        lowerPoint: Point3D,
        upperParameter: Double,
        upperPoint: Point3D,
        depth: Int,
        points: inout [Point3D],
        tolerance: ModelingTolerance
    ) throws {
        let midpointParameter = lowerParameter + (upperParameter - lowerParameter) * 0.5
        let midpoint = try curve.point(at: midpointParameter, tolerance: tolerance)
        let deviation = distance(midpoint, toSegmentFrom: lowerPoint, to: upperPoint)
        if deviation <= tolerance.distance {
            points.append(upperPoint)
            return
        }
        guard depth < 20 else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: deviation,
                tolerance: tolerance,
                message: "Trimmed-face boundary sampling exceeded its subdivision limit."
            )
        }
        try appendEdgeSamples(
            curve: curve,
            lowerParameter: lowerParameter,
            lowerPoint: lowerPoint,
            upperParameter: midpointParameter,
            upperPoint: midpoint,
            depth: depth + 1,
            points: &points,
            tolerance: tolerance
        )
        try appendEdgeSamples(
            curve: curve,
            lowerParameter: midpointParameter,
            lowerPoint: midpoint,
            upperParameter: upperParameter,
            upperPoint: upperPoint,
            depth: depth + 1,
            points: &points,
            tolerance: tolerance
        )
    }

    private func parameterSamples(
        _ curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameter] {
        return try SurfaceParameterCurveSampler(tolerance: tolerance).sample(curve)
    }

    private func unwrapped(
        _ value: Double,
        relativeTo reference: Double,
        domain: ParameterDomain
    ) -> Double {
        guard case let .periodic(period) = domain else { return value }
        var result = value
        while result - reference > period * 0.5 { result -= period }
        while result - reference < -period * 0.5 { result += period }
        return result
    }

    private func isOutsidePolygonBounds(_ point: UV, polygon: [UV]) -> Bool {
        guard let firstU = polygon.first?.u, let firstV = polygon.first?.v else {
            return true
        }
        var minU = firstU
        var maxU = firstU
        var minV = firstV
        var maxV = firstV
        for vertex in polygon {
            minU = min(minU, vertex.u)
            maxU = max(maxU, vertex.u)
            minV = min(minV, vertex.v)
            maxV = max(maxV, vertex.v)
        }
        // The polygon samples curved parameter edges, so the true region
        // can bulge slightly past the sampled extent; the pad covers that
        // sampling slack while still rejecting far-off-chart queries.
        let pad = 0.05 + max(maxU - minU, maxV - minV) * 0.01
        return point.u < minU - pad
            || point.u > maxU + pad
            || point.v < minV - pad
            || point.v > maxV + pad
    }

    private func aligned(_ point: UV, to polygon: [UV], on surface: Surface3D) -> UV {
        guard polygon.isEmpty == false else { return point }
        let centerU = polygon.map(\.u).reduce(0.0, +) / Double(polygon.count)
        let centerV = polygon.map(\.v).reduce(0.0, +) / Double(polygon.count)
        return UV(
            u: unwrapped(point.u, relativeTo: centerU, domain: surface.uDomain),
            v: unwrapped(point.v, relativeTo: centerV, domain: surface.vDomain)
        )
    }

    private func classify(
        _ point: UV,
        in polygon: [UV],
        tolerance: ModelingTolerance
    ) throws -> PlanarPointClassification {
        try planarPredicates.classify(
            Point2D(x: point.u, y: point.v),
            in: polygon.map { Point2D(x: $0.u, y: $0.v) },
            tolerance: tolerance
        )
    }

    private func distance(
        _ point: Point3D,
        toSegmentFrom start: Point3D,
        to end: Point3D
    ) -> Double {
        let segment = end - start
        let lengthSquared = segment.dot(segment)
        guard lengthSquared > Double.ulpOfOne else { return (point - start).length }
        let fraction = min(max((point - start).dot(segment) / lengthSquared, 0.0), 1.0)
        return (point - (start + segment * fraction)).length
    }

    private func append(_ point: UV, to polygon: inout [UV], tolerance: Double) {
        guard polygon.last.map({ hypot($0.u - point.u, $0.v - point.v) <= tolerance }) != true else {
            return
        }
        polygon.append(point)
    }

    private typealias UV = FacePointContainmentPreparationCache.UV

}
