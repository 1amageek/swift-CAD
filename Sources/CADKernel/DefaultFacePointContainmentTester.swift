import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct DefaultFacePointContainmentTester: FacePointContainmentTesting,
    FacePointContainmentSessionPreparing,
    FacePointContainmentPreparationCaching {
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

    func makeContainmentSession(
        for faceIDs: [FaceID],
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> any FacePointContainmentSession {
        try tolerance.validate()
        var preparedFaces: [FaceID: FacePointContainmentPreparationCache.PreparedFace] = [:]
        for faceID in faceIDs where preparedFaces[faceID] == nil {
            preparedFaces[faceID] = try prepare(
                faceID: faceID,
                model: model,
                tolerance: tolerance
            )
        }
        return Session(
            tester: self,
            preparedFaces: preparedFaces,
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
        return try contains(
            point,
            on: preparedFace,
            tolerance: tolerance
        )
    }

    func contains(
        _ point: Point3D,
        on preparedFace: FacePointContainmentPreparationCache.PreparedFace,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let projection = try preparedFace.surface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        // Band faces are bounded by loops that wind a periodic direction;
        // their unwrapped polygons are open paths, so planar winding is
        // undefined and containment reduces to lying between the winding
        // loops' levels in the transverse coordinate.
        var windingULevels: [Double] = []
        var windingVLevels: [Double] = []
        for loop in preparedFace.loops {
            guard let first = loop.polygon.first,
                  let last = loop.polygon.last else { continue }
            let deltaU = last.u - first.u
            let deltaV = last.v - first.v
            if case let .periodic(uPeriod) = preparedFace.surface.uDomain,
               abs(abs(deltaU) - uPeriod) <= uPeriod * 0.01,
               abs(deltaV) <= uPeriod * 0.01 {
                windingVLevels.append(loop.center.v)
            }
            if case let .periodic(vPeriod) = preparedFace.surface.vDomain,
               abs(abs(deltaV) - vPeriod) <= vPeriod * 0.01,
               abs(deltaU) <= vPeriod * 0.01 {
                windingULevels.append(loop.center.u)
            }
        }
        if windingVLevels.count >= 2 || windingULevels.count >= 2 {
            let projectionPoint = UV(u: projection.u, v: projection.v)
            var inside = true
            if windingVLevels.count >= 2,
               let lowerLevel = windingVLevels.min(),
               let upperLevel = windingVLevels.max() {
                let query = aligned(
                    projectionPoint,
                    to: UV(u: 0.0, v: (lowerLevel + upperLevel) * 0.5),
                    on: preparedFace.surface
                )
                inside = inside
                    && query.v >= lowerLevel - tolerance.angle
                    && query.v <= upperLevel + tolerance.angle
            }
            if windingULevels.count >= 2,
               let lowerLevel = windingULevels.min(),
               let upperLevel = windingULevels.max() {
                let query = aligned(
                    projectionPoint,
                    to: UV(u: (lowerLevel + upperLevel) * 0.5, v: 0.0),
                    on: preparedFace.surface
                )
                inside = inside
                    && query.u >= lowerLevel - tolerance.angle
                    && query.u <= upperLevel + tolerance.angle
            }
            return inside
        }
        var insideOuter = false
        for loop in preparedFace.loops {
            let query = aligned(
                UV(u: projection.u, v: projection.v),
                to: loop.center,
                on: preparedFace.surface
            )
            // A near-seam query has several periodic chart representatives
            // and only one of them lines up with the unrolled polygon, so
            // every in-extent representative votes and any inside verdict
            // wins; representatives beyond the polygon's parameter extent
            // can never be inside it.
            var classification = PlanarPointClassification.outside
            for representative in periodicRepresentatives(
                of: query,
                on: preparedFace.surface
            ) where isOutsidePolygonBounds(
                representative,
                bounds: loop.bounds
            ) == false {
                let candidate = try classify(
                    representative,
                    in: loop.planarPolygon,
                    tolerance: tolerance
                )
                if candidate == .inside {
                    classification = .inside
                    break
                }
                if candidate != .outside {
                    classification = candidate
                }
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

    func prepare(
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
        var uSingularFlags: [Bool] = []
        let singularVValues = uSingularVValues(on: surface)
        for coedge in loop.coedges {
            guard let edge = model.edges[coedge.edgeID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Trimmed-face containment references a missing edge."
                )
            }
            if let parameterCurve = coedge.surfaceParameterCurve {
                try parameterCurve.validate(on: surface, tolerance: tolerance)
                let authoredSamples = try parameterSamples(
                    parameterCurve,
                    tolerance: tolerance
                )
                appendAuthoredParameterSamples(
                    authoredSamples,
                    to: &polygon,
                    uSingularFlags: &uSingularFlags,
                    singularVValues: singularVValues,
                    on: surface,
                    preservesAuthoredWinding: preservesAuthoredWinding(
                        parameterCurve
                    ),
                    tolerance: tolerance.distance
                )
                continue
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
                let countBefore = polygon.count
                append(
                    parameter,
                    to: &polygon,
                    tolerance: tolerance.distance
                )
                if polygon.count > countBefore {
                    uSingularFlags.append(singularVValues.contains {
                        abs(projection.v - $0) <= tolerance.distance
                    })
                }
            }
        }
        // A vertex at a u-singular locus (cone apex, sphere pole) projects
        // to an arbitrary u; drawing its edge with that u cuts a diagonal
        // through the face interior, so the singular vertex inherits its
        // polygon neighbor's u instead.
        if uSingularFlags.contains(true), uSingularFlags.contains(false) {
            for index in polygon.indices where uSingularFlags[index] {
                var neighbor: Int? = nil
                var offset = 1
                while offset < polygon.count {
                    let previous = (index - offset + polygon.count) % polygon.count
                    if uSingularFlags[previous] == false {
                        neighbor = previous
                        break
                    }
                    let next = (index + offset) % polygon.count
                    if uSingularFlags[next] == false {
                        neighbor = next
                        break
                    }
                    offset += 1
                }
                if let neighbor {
                    polygon[index] = UV(
                        u: polygon[neighbor].u,
                        v: polygon[index].v
                    )
                }
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

    private func uSingularVValues(on surface: Surface3D) -> [Double] {
        guard case let .analytic(analytic) = surface else { return [] }
        switch analytic {
        case .sphere:
            return [-Double.pi * 0.5, Double.pi * 0.5]
        case .cone:
            return [0.0]
        case .plane, .cylinder, .torus:
            return []
        }
    }

    private func appendAuthoredParameterSamples(
        _ samples: [SurfaceParameter],
        to polygon: inout [UV],
        uSingularFlags: inout [Bool],
        singularVValues: [Double],
        on surface: Surface3D,
        preservesAuthoredWinding: Bool,
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
            let authored = UV(u: sample.u, v: sample.v)
            let parameter: UV
            if preservesAuthoredWinding {
                // Explicit parameter curves may intentionally traverse more
                // than half a period. Translate their whole chart once so
                // winding and orientation remain unchanged.
                parameter = UV(
                    u: authored.u + uOffset,
                    v: authored.v + vOffset
                )
            } else {
                // Projection-backed curves return canonical chart values at
                // each evaluation, so their samples must be unwrapped
                // continuously along the loop.
                parameter = unwrapped(
                    authored,
                    relativeTo: polygon.last,
                    on: surface
                )
            }
            let countBefore = polygon.count
            append(
                parameter,
                to: &polygon,
                tolerance: tolerance
            )
            if polygon.count > countBefore {
                uSingularFlags.append(singularVValues.contains {
                    abs(parameter.v - $0) <= tolerance
                })
            }
        }
    }

    private func preservesAuthoredWinding(
        _ curve: SurfaceParameterCurve
    ) -> Bool {
        switch curve {
        case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline:
            return true
        case .sphericalGreatCircle, .certifiedImplicit,
             .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic:
            return false
        case let .periodicTranslation(base, _, _):
            return preservesAuthoredWinding(base)
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


    private func periodicRepresentatives(
        of point: UV,
        on surface: Surface3D
    ) -> [UV] {
        var uCandidates = [point.u]
        if case let .periodic(uPeriod) = surface.uDomain {
            uCandidates.append(point.u - uPeriod)
            uCandidates.append(point.u + uPeriod)
        }
        var vCandidates = [point.v]
        if case let .periodic(vPeriod) = surface.vDomain {
            vCandidates.append(point.v - vPeriod)
            vCandidates.append(point.v + vPeriod)
        }
        var result: [UV] = []
        for u in uCandidates {
            for v in vCandidates {
                result.append(UV(u: u, v: v))
            }
        }
        return result
    }

    private func isOutsidePolygonBounds(
        _ point: UV,
        bounds: FacePointContainmentPreparationCache.LoopRegion.ParameterBounds?
    ) -> Bool {
        guard let bounds else {
            return true
        }
        // The polygon samples curved parameter edges, so the true region
        // can bulge slightly past the sampled extent; the pad covers that
        // sampling slack while still rejecting far-off-chart queries.
        let pad = 0.05 + max(
            bounds.maximumU - bounds.minimumU,
            bounds.maximumV - bounds.minimumV
        ) * 0.01
        return point.u < bounds.minimumU - pad
            || point.u > bounds.maximumU + pad
            || point.v < bounds.minimumV - pad
            || point.v > bounds.maximumV + pad
    }

    private func aligned(_ point: UV, to center: UV, on surface: Surface3D) -> UV {
        return UV(
            u: unwrapped(point.u, relativeTo: center.u, domain: surface.uDomain),
            v: unwrapped(point.v, relativeTo: center.v, domain: surface.vDomain)
        )
    }

    private func classify(
        _ point: UV,
        in polygon: [Point2D],
        tolerance: ModelingTolerance
    ) throws -> PlanarPointClassification {
        try planarPredicates.classify(
            Point2D(x: point.u, y: point.v),
            in: polygon,
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

    private struct Session: FacePointContainmentSession {
        let tester: DefaultFacePointContainmentTester
        let preparedFaces: [FaceID: FacePointContainmentPreparationCache.PreparedFace]
        let tolerance: ModelingTolerance

        func contains(_ point: Point3D, on faceID: FaceID) throws -> Bool {
            try point.validate()
            guard let preparedFace = preparedFaces[faceID] else {
                throw KernelError(
                    phase: .classification,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Face containment session does not own the requested face."
                )
            }
            return try tester.contains(
                point,
                on: preparedFace,
                tolerance: tolerance
            )
        }
    }
}
