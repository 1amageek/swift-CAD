import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

public struct DefaultFacePointContainmentTester: FacePointContainmentTesting,
    FacePointContainmentSessionPreparing,
    FacePointContainmentPreparationCaching,
    FaceParameterContainmentPreparationCaching,
    FaceParameterContainmentSessionPreparing {
    public init() {}

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

    func makeParameterContainmentSession(
        for faceIDs: [FaceID],
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> any FaceParameterContainmentSession {
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
        switch try preparedFace.surface.parameterProjectionResult(
            of: point,
            tolerance: tolerance
        ) {
        case let .projected(projection):
            return try contains(
                SurfaceParameter(u: projection.u, v: projection.v),
                on: preparedFace,
                tolerance: tolerance
            )
        case .outsideTolerance:
            return false
        }
    }

    func contains(
        _ parameter: SurfaceParameter,
        on faceID: FaceID,
        in model: BRepModel,
        preparationCache: inout FacePointContainmentPreparationCache,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try tolerance.validate()
        try parameter.validate()
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
            parameter,
            on: preparedFace,
            tolerance: tolerance
        )
    }

    private func contains(
        _ parameter: SurfaceParameter,
        on preparedFace: FacePointContainmentPreparationCache.PreparedFace,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        if preparedFace.loops.isEmpty {
            return try preparedFace.surface.uDomain.contains(
                parameter.u,
                tolerance: tolerance
            ) && preparedFace.surface.vDomain.contains(
                parameter.v,
                tolerance: tolerance
            )
        }
        // Band faces are bounded by loops that wind a periodic direction;
        // their unwrapped polygons are open paths, so planar winding is
        // undefined and containment reduces to lying between the winding
        // loops' levels in the transverse coordinate.
        var windingULevels: [Double] = []
        var windingVLevels: [Double] = []
        for loop in preparedFace.loops {
            if loop.uWinding != 0,
               loop.vWinding == 0,
               let level = loop.constantVLevel {
                windingVLevels.append(level)
            }
            if loop.vWinding != 0,
               loop.uWinding == 0,
               let level = loop.constantULevel {
                windingULevels.append(level)
            }
        }
        if windingVLevels.count >= 2 || windingULevels.count >= 2 {
            let projectionPoint = UV(u: parameter.u, v: parameter.v)
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
                UV(u: parameter.u, v: parameter.v),
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
            ) {
                let candidate: PlanarPointClassification
                if let predicate = loop.certifiedPredicate {
                    candidate = try predicate.classify(
                        Point2D(x: representative.u, y: representative.v),
                        tolerance: tolerance
                    )
                } else {
                    throw KernelError(
                        phase: .classification,
                        code: .unsupportedCapability,
                        tolerance: tolerance,
                        message: "Trimmed-face containment requires a certified contractible pcurve loop or a certified constant-level periodic band."
                    )
                }
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
            let polygon: [UV]
            let certification: LoopCertification
            do {
                polygon = try loopParameters(
                    loop,
                    surface: surface,
                    model: model,
                    tolerance: tolerance
                )
                certification = try certifyLoop(
                    loop,
                    surface: surface,
                    model: model,
                    tolerance: tolerance
                )
            } catch {
                let wrapped = KernelError.wrapping(
                    error,
                    phase: .classification,
                    tolerance: tolerance
                )
                throw KernelError(
                    phase: wrapped.phase,
                    code: wrapped.code,
                    featureID: wrapped.featureID,
                    subshapeID: wrapped.subshapeID,
                    residual: wrapped.residual,
                    tolerance: wrapped.tolerance ?? tolerance,
                    message: "Trimmed-face containment could not parameterize loop \(loopID) on face \(faceID): \(wrapped.message)"
                )
            }
            return FacePointContainmentPreparationCache.LoopRegion(
                role: loop.role,
                polygon: polygon,
                certifiedPredicate: certification.predicate,
                uWinding: certification.uWinding,
                vWinding: certification.vWinding,
                constantULevel: certification.constantULevel,
                constantVLevel: certification.constantVLevel
            )
        }
        return FacePointContainmentPreparationCache.PreparedFace(
            surface: surface,
            loops: regions
        )
    }

    private func certifyLoop(
        _ loop: Loop,
        surface: Surface3D,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> LoopCertification {
        let parameterTolerance = max(tolerance.distance, tolerance.angle)
        let parameterTopology = SurfaceParameterTopology(surface: surface)
        var authoredCurves: [SurfaceParameterCurve] = []
        for coedge in loop.coedges {
            guard let edge = model.edges[coedge.edgeID],
                  let spatialCurve = model.geometry.curves[edge.curveID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Certified face containment references missing edge geometry."
                )
            }
            let parameterCurve: SurfaceParameterCurve
            if let authored = coedge.surfaceParameterCurve {
                parameterCurve = authored
            } else {
                guard let trim = edge.trim else {
                    throw KernelError(
                        phase: .classification,
                        code: .unsupportedCapability,
                        tolerance: tolerance,
                        message: "Certified face containment requires exact pcurves or exact trimmed edge geometry."
                    )
                }
                let startParameter = coedge.orientation == .forward
                    ? trim.startParameter
                    : trim.endParameter
                let endParameter = coedge.orientation == .forward
                    ? trim.endParameter
                    : trim.startParameter
                parameterCurve = try ExactFacePcurveBuilder().surfaceParameterCurve(
                    for: spatialCurve,
                    startParameter: startParameter,
                    endParameter: endParameter,
                    on: surface,
                    tolerance: tolerance
                )
            }
            try parameterCurve.validate(on: surface, tolerance: tolerance)
            authoredCurves.append(parameterCurve)
        }
        guard authoredCurves.isEmpty == false else {
            throw KernelError(
                phase: .classification,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified face containment requires a non-empty trim loop."
            )
        }
        if let singularStartIndex = try authoredCurves.firstIndex(where: { curve in
            parameterTopology.isUSingular(
                try curve.startParameter(tolerance: tolerance),
                tolerance: tolerance
            )
        }), singularStartIndex != authoredCurves.startIndex {
            authoredCurves = Array(authoredCurves[singularStartIndex...])
                + Array(authoredCurves[..<singularStartIndex])
        }

        var alignedCurves: [SurfaceParameterCurve] = []
        var firstStart: SurfaceParameter?
        var previousEnd: SurfaceParameter?
        for parameterCurve in authoredCurves {
            let rawStart = try parameterCurve.startParameter(tolerance: tolerance)
            let crossesUSingularity = previousEnd.map {
                parameterTopology.isUSingular($0, tolerance: tolerance)
                    && parameterTopology.isUSingular(rawStart, tolerance: tolerance)
            } ?? false
            let alignedStart = crossesUSingularity
                ? UV(u: rawStart.u, v: rawStart.v)
                : unwrapped(
                    UV(u: rawStart.u, v: rawStart.v),
                    relativeTo: previousEnd.map { UV(u: $0.u, v: $0.v) },
                    on: surface
                )
            let uShift = alignedStart.u - rawStart.u
            let vShift = alignedStart.v - rawStart.v
            let alignedCurve: SurfaceParameterCurve
            if uShift == 0.0, vShift == 0.0 {
                alignedCurve = parameterCurve
            } else {
                alignedCurve = .periodicTranslation(
                    base: parameterCurve,
                    uShift: uShift,
                    vShift: vShift
                )
            }
            let start = try alignedCurve.startParameter(tolerance: tolerance)
            if let previousEnd {
                let residual = hypot(start.u - previousEnd.u, start.v - previousEnd.v)
                if residual > parameterTolerance,
                   parameterTopology.isUSingular(previousEnd, tolerance: tolerance),
                   parameterTopology.isUSingular(start, tolerance: tolerance) {
                    alignedCurves.append(.constantV(
                        v: start.v,
                        uStart: previousEnd.u,
                        uEnd: start.u
                    ))
                } else if residual > parameterTolerance {
                    throw KernelError(
                        phase: .classification,
                        code: .topologyFailure,
                        residual: residual,
                        tolerance: tolerance,
                        message: "Certified face pcurves do not form one continuous chart chain."
                    )
                }
            } else {
                firstStart = start
            }
            previousEnd = try continuousEndParameter(
                of: alignedCurve,
                from: start,
                on: surface,
                tolerance: tolerance
            )
            alignedCurves.append(alignedCurve)
        }
        guard let firstStart, var previousEnd else {
            throw KernelError(
                phase: .classification,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified face containment requires a non-empty trim loop."
            )
        }
        let closureResidual = hypot(
            previousEnd.u - firstStart.u,
            previousEnd.v - firstStart.v
        )
        if closureResidual > parameterTolerance,
           parameterTopology.isUSingular(previousEnd, tolerance: tolerance),
           parameterTopology.isUSingular(firstStart, tolerance: tolerance) {
            alignedCurves.append(.constantV(
                v: firstStart.v,
                uStart: previousEnd.u,
                uEnd: firstStart.u
            ))
            previousEnd = firstStart
        }
        let uWinding = try periodicWinding(
            displacement: previousEnd.u - firstStart.u,
            domain: surface.uDomain,
            tolerance: tolerance
        )
        let vWinding = try periodicWinding(
            displacement: previousEnd.v - firstStart.v,
            domain: surface.vDomain,
            tolerance: tolerance
        )
        if uWinding == 0, vWinding == 0 {
            return LoopCertification(
                predicate: try CertifiedSurfaceParameterLoopPredicate(
                    curves: alignedCurves,
                    uPeriod: parameterTopology.uPeriod,
                    vPeriod: parameterTopology.vPeriod,
                    tolerance: tolerance
                ),
                uWinding: 0,
                vWinding: 0,
                constantULevel: nil,
                constantVLevel: nil
            )
        }
        guard abs(uWinding) + abs(vWinding) == 1 else {
            throw KernelError(
                phase: .classification,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Certified face containment supports primitive periodic trim loops with one winding generator."
            )
        }
        let bounds = try certifiedBounds(
            of: alignedCurves,
            tolerance: tolerance
        )
        if uWinding != 0,
           vWinding == 0,
           bounds.v.width <= parameterTolerance * 2.0 {
            return LoopCertification(
                predicate: nil,
                uWinding: uWinding,
                vWinding: 0,
                constantULevel: nil,
                constantVLevel: bounds.v.midpoint
            )
        }
        if vWinding != 0,
           uWinding == 0,
           bounds.u.width <= parameterTolerance * 2.0 {
            return LoopCertification(
                predicate: nil,
                uWinding: 0,
                vWinding: vWinding,
                constantULevel: bounds.u.midpoint,
                constantVLevel: nil
            )
        }
        throw KernelError(
            phase: .classification,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message: "A non-contractible face trim must have a certified constant transverse level."
        )
    }

    private func continuousEndParameter(
        of curve: SurfaceParameterCurve,
        from start: SurfaceParameter,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        let topology = SurfaceParameterTopology(surface: surface)
        let periodicWidths = [topology.uPeriod, topology.vPeriod].compactMap { $0 }
        guard let minimumPeriod = periodicWidths.min() else {
            return try curve.endParameter(tolerance: tolerance)
        }
        let enclosures = try CertifiedSurfaceParameterCurveEncloser().enclosures(
            for: curve,
            maximumWidth: minimumPeriod * 0.25,
            tolerance: tolerance
        ).sorted { $0.lowerFraction < $1.lowerFraction }
        var reference = UV(u: start.u, v: start.v)
        for enclosure in enclosures {
            reference = UV(
                u: unwrapped(
                    enclosure.u.midpoint,
                    relativeTo: reference.u,
                    domain: surface.uDomain
                ),
                v: unwrapped(
                    enclosure.v.midpoint,
                    relativeTo: reference.v,
                    domain: surface.vDomain
                )
            )
        }
        let rawEnd = try curve.endParameter(tolerance: tolerance)
        return SurfaceParameter(
            u: unwrapped(
                rawEnd.u,
                relativeTo: reference.u,
                domain: surface.uDomain
            ),
            v: unwrapped(
                rawEnd.v,
                relativeTo: reference.v,
                domain: surface.vDomain
            )
        )
    }

    private func certifiedBounds(
        of curves: [SurfaceParameterCurve],
        tolerance: ModelingTolerance
    ) throws -> (u: ScalarInterval, v: ScalarInterval) {
        var minimumU = Double.infinity
        var maximumU = -Double.infinity
        var minimumV = Double.infinity
        var maximumV = -Double.infinity
        for curve in curves {
            let enclosures = try CertifiedSurfaceParameterCurveEncloser().enclosures(
                for: curve,
                maximumWidth: Double.greatestFiniteMagnitude.squareRoot(),
                tolerance: tolerance
            )
            for enclosure in enclosures {
                minimumU = min(minimumU, enclosure.u.lower)
                maximumU = max(maximumU, enclosure.u.upper)
                minimumV = min(minimumV, enclosure.v.lower)
                maximumV = max(maximumV, enclosure.v.upper)
            }
        }
        guard minimumU.isFinite,
              maximumU.isFinite,
              minimumV.isFinite,
              maximumV.isFinite else {
            throw KernelError(
                phase: .classification,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Certified face containment produced no finite pcurve bounds."
            )
        }
        return (
            try ScalarInterval(lower: minimumU, upper: maximumU),
            try ScalarInterval(lower: minimumV, upper: maximumV)
        )
    }

    private func periodicWinding(
        displacement: Double,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> Int {
        let parameterTolerance = max(tolerance.distance, tolerance.angle)
        guard case let .periodic(period) = domain else {
            guard abs(displacement) <= parameterTolerance else {
                throw KernelError(
                    phase: .classification,
                    code: .topologyFailure,
                    residual: abs(displacement),
                    tolerance: tolerance,
                    message: "A face trim does not close in a non-periodic chart direction."
                )
            }
            return 0
        }
        let rounded = (displacement / period).rounded()
        let residual = abs(displacement - rounded * period)
        guard rounded >= Double(Int.min),
              rounded <= Double(Int.max),
              residual <= parameterTolerance else {
            throw KernelError(
                phase: .classification,
                code: .topologyFailure,
                residual: residual,
                tolerance: tolerance,
                message: "A face trim has a non-integral periodic winding."
            )
        }
        return Int(rounded)
    }

    private func loopParameters(
        _ loop: Loop,
        surface: Surface3D,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [UV] {
        var polygon: [UV] = []
        var uSingularFlags: [Bool] = []
        let singularVValues = SurfaceParameterTopology(
            surface: surface
        ).uSingularVValues
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
             .projectedAnalytic, .rigidImage:
            return false
        case let .periodicTranslation(base, _, _):
            return preservesAuthoredWinding(base)
        case let .sameParameterImage(image):
            return preservesAuthoredWinding(image.source)
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

    private func aligned(_ point: UV, to center: UV, on surface: Surface3D) -> UV {
        return UV(
            u: unwrapped(point.u, relativeTo: center.u, domain: surface.uDomain),
            v: unwrapped(point.v, relativeTo: center.v, domain: surface.vDomain)
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

    private struct LoopCertification {
        let predicate: CertifiedSurfaceParameterLoopPredicate?
        let uWinding: Int
        let vWinding: Int
        let constantULevel: Double?
        let constantVLevel: Double?
    }

    private struct Session: FacePointContainmentSession,
        FaceParameterContainmentSession {
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

        func contains(
            _ parameter: SurfaceParameter,
            on faceID: FaceID
        ) throws -> Bool {
            try parameter.validate()
            guard let preparedFace = preparedFaces[faceID] else {
                throw KernelError(
                    phase: .classification,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Face containment session does not own the requested face."
                )
            }
            return try tester.contains(
                parameter,
                on: preparedFace,
                tolerance: tolerance
            )
        }
    }
}
