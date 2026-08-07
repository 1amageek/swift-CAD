import CADCore
import CADGeometry
import Foundation

/// Certifies analytic surface-flux volume over exact rectangular pcurve domains
/// and certified Green-integral pcurve loops. Unsupported intersection-backed
/// trims continue to the next exact evaluator and cannot produce a success here.
struct TrimmedAnalyticSurfaceVolumeEvaluator {
    struct VolumeBounds: Sendable, Hashable {
        let lower: Double
        let upper: Double

        var midpoint: Double {
            lower + (upper - lower) * 0.5
        }

        var errorRadius: Double {
            (upper - lower) * 0.5
        }
    }

    func volume(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        guard let bounds = try volumeBounds(
            of: shell,
            in: model,
            tolerance: tolerance
        ) else {
            return nil
        }
        let reference = try referencePoint(for: shell, in: model)
        let characteristicLength = try characteristicLength(
            of: shell,
            in: model,
            reference: reference,
            tolerance: tolerance
        )
        let requestedError = max(
            tolerance.distance * characteristicLength * characteristicLength * 0.125,
            characteristicLength * characteristicLength * characteristicLength * 1.0e-13
        )
        guard bounds.errorRadius <= requestedError else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: bounds.errorRadius,
                tolerance: tolerance,
                message: "Certified analytic surface-flux volume exceeded its numeric enclosure."
            )
        }
        return bounds.midpoint
    }

    func volumeBounds(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> VolumeBounds? {
        try tolerance.validate()
        let reference = try referencePoint(for: shell, in: model)
        let characteristicLength = try characteristicLength(
            of: shell,
            in: model,
            reference: reference,
            tolerance: tolerance
        )
        let requestedError = max(
            tolerance.distance * characteristicLength * characteristicLength * 0.125,
            characteristicLength * characteristicLength * characteristicLength * 1.0e-13
        )
        let totalCoedgeCount = try coedgeCount(of: shell, in: model)
        guard totalCoedgeCount > 0 else { return nil }
        // A loose first pass hands slow coedges most of the width budget;
        // the uniform per-coedge division stays as the sound fallback when
        // the summed enclosure misses the shell-level error contract.
        var total = Interval.exact(0.0)
        for effectiveCoedgeCount in [min(12, totalCoedgeCount), totalCoedgeCount] {
        total = Interval.exact(0.0)
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Trimmed analytic volume references missing face geometry."
                )
            }
            guard let integrand = try Integrand(
                surface: surface,
                reference: reference,
                tolerance: tolerance
            ) else {
                return nil
            }
            let domain = try ExactRectangularPcurveDomainResolver().resolve(
                face: face,
                model: model,
                tolerance: tolerance
            )
            var contribution: Interval
            if let domain {
                contribution = integrand.integral(over: domain)
            } else if let planeScale = integrand.planeVolumeScale {
                contribution = try planarFaceContribution(
                    face: face,
                    model: model,
                    volumeScale: planeScale,
                    requestedError: requestedError,
                    totalCoedgeCount: effectiveCoedgeCount,
                    tolerance: tolerance
                )
            } else if let analyticContribution = try analyticFaceContribution(
                face: face,
                model: model,
                integrand: integrand,
                requestedError: requestedError,
                totalCoedgeCount: effectiveCoedgeCount,
                tolerance: tolerance
            ) {
                contribution = analyticContribution
            } else {
                return nil
            }
            if face.orientation == .reversed {
                contribution = -contribution
            }
            total = total + contribution
        }
        guard total.lower.isFinite, total.upper.isFinite else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Certified analytic surface-flux volume exceeded finite arithmetic."
            )
        }
        if total.upper - total.lower <= requestedError * 1.98
            || effectiveCoedgeCount == totalCoedgeCount {
            break
        }
        }
        return VolumeBounds(lower: total.lower, upper: total.upper)
    }

    private func planarFaceContribution(
        face: Face,
        model: BRepModel,
        volumeScale: Interval,
        requestedError: Double,
        totalCoedgeCount: Int,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        let scale = max(volumeScale.maximumAbsolute, 1.0)
        let requestedAreaWidth = requestedError * 1.98
            / (scale * Double(totalCoedgeCount))
        guard requestedAreaWidth.isFinite, requestedAreaWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: requestedAreaWidth,
                tolerance: tolerance,
                message: "Planar face volume could not allocate a finite pcurve area enclosure."
            )
        }
        var orientedArea = Interval.exact(0.0)
        for loopID in face.loops {
            guard let loop = model.loops[loopID], !loop.coedges.isEmpty else {
                throw TopologyError.missingReference(
                    "Planar face volume references a missing or empty loop."
                )
            }
            var parameterCurves: [SurfaceParameterCurve] = []
            parameterCurves.reserveCapacity(loop.coedges.count)
            for coedge in loop.coedges {
                guard let curve = coedge.surfaceParameterCurve else {
                    throw TopologyError.invalidTrim(coedge.edgeID)
                }
                parameterCurves.append(curve)
            }
            orientedArea = orientedArea + (try orientedLoopAreaBounds(
                parameterCurves: parameterCurves,
                role: loop.role,
                requestedAreaWidth: requestedAreaWidth,
                tolerance: tolerance
            ))
        }
        return volumeScale * orientedArea
    }

    private func analyticFaceContribution(
        face: Face,
        model: BRepModel,
        integrand: Integrand,
        requestedError: Double,
        totalCoedgeCount: Int,
        tolerance: ModelingTolerance
    ) throws -> Interval? {
        var total = Interval.exact(0.0)
        for loopID in face.loops {
            guard let loop = model.loops[loopID],
                  !loop.coedges.isEmpty else {
                throw TopologyError.missingReference(
                    "Analytic coordinate-loop volume references a missing or empty loop."
                )
            }
            var curves: [SurfaceParameterCurve] = []
            curves.reserveCapacity(loop.coedges.count)
            for coedge in loop.coedges {
                guard let curve = coedge.surfaceParameterCurve else {
                    throw TopologyError.invalidTrim(coedge.edgeID)
                }
                curves.append(curve)
            }
            guard let contribution = try analyticLoopContribution(
                parameterCurves: curves,
                role: loop.role,
                integrand: integrand,
                requestedWidth: requestedError * 1.98 / Double(totalCoedgeCount),
                tolerance: tolerance
            ) else {
                return nil
            }
            total = total + contribution
        }
        return total
    }

    func coordinateLoopVolumeBounds(
        surface: Surface3D,
        parameterCurves: [SurfaceParameterCurve],
        role: LoopRole,
        reference: Point3D,
        tolerance: ModelingTolerance
    ) throws -> VolumeBounds? {
        try tolerance.validate()
        guard let integrand = try Integrand(
            surface: surface,
            reference: reference,
            tolerance: tolerance
        ), let contribution = try coordinateLoopContribution(
            parameterCurves: parameterCurves,
            role: role,
            integrand: integrand,
            tolerance: tolerance
        ) else {
            return nil
        }
        return VolumeBounds(
            lower: contribution.lower,
            upper: contribution.upper
        )
    }

    func analyticLoopVolumeBounds(
        surface: Surface3D,
        parameterCurves: [SurfaceParameterCurve],
        role: LoopRole,
        reference: Point3D,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> VolumeBounds? {
        try tolerance.validate()
        guard requestedWidth.isFinite, requestedWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: requestedWidth,
                tolerance: tolerance,
                message: "Analytic pcurve volume requires a finite positive enclosure width."
            )
        }
        guard let integrand = try Integrand(
            surface: surface,
            reference: reference,
            tolerance: tolerance
        ), let contribution = try analyticLoopContribution(
            parameterCurves: parameterCurves,
            role: role,
            integrand: integrand,
            requestedWidth: requestedWidth,
            tolerance: tolerance
        ) else {
            return nil
        }
        return VolumeBounds(lower: contribution.lower, upper: contribution.upper)
    }

    private func analyticLoopContribution(
        parameterCurves: [SurfaceParameterCurve],
        role: LoopRole,
        integrand: Integrand,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval? {
        guard !parameterCurves.isEmpty else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Analytic pcurve volume requires at least one pcurve."
            )
        }
        let curveWidth = requestedWidth / Double(parameterCurves.count)
        guard curveWidth.isFinite, curveWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: curveWidth,
                tolerance: tolerance,
                message: "Analytic pcurve volume could not allocate a finite curve enclosure."
            )
        }
        let generalIntegrator = CertifiedAnalyticPcurveFluxIntegrator()
        var rawFlux = Interval.exact(0.0)
        var areaBounds = SurfaceParameterAreaBounds.zero
        for curve in parameterCurves {
            if case let .bSpline(spline) = curve,
               let polynomial = try generalIntegrator.polynomialCylinderBounds(
                    for: spline,
                    integrand: integrand,
                    requestedWidth: curveWidth,
                    tolerance: tolerance
               ) {
                rawFlux = rawFlux + polynomial.flux
                areaBounds = areaBounds.adding(polynomial.parameterArea)
                continue
            }
            if let verticalSegments = try coordinateVerticalSegments(
                curve,
                tolerance: tolerance
            ) {
                for segment in verticalSegments {
                    rawFlux = rawFlux + integrand.verticalBoundaryIntegral(
                        u: segment.u,
                        vStart: segment.vStart,
                        vEnd: segment.vEnd
                    )
                }
            } else if let contribution = try generalIntegrator.bounds(
                for: curve,
                integrand: integrand,
                requestedWidth: curveWidth,
                tolerance: tolerance
            ) {
                rawFlux = rawFlux + contribution
            } else {
                return nil
            }
            areaBounds = areaBounds.adding(
                try SurfaceParameterCurveAreaIntegrator().bounds(
                    for: curve,
                    uShift: 0.0,
                    requestedWidth: max(tolerance.relative, Double.ulpOfOne * 256.0),
                    tolerance: tolerance
                )
            )
        }
        return try normalizedLoopContribution(
            rawFlux: rawFlux,
            areaBounds: areaBounds,
            role: role,
            tolerance: tolerance,
            context: "Analytic pcurve-loop volume"
        )
    }

    private func coordinateLoopContribution(
        parameterCurves: [SurfaceParameterCurve],
        role: LoopRole,
        integrand: Integrand,
        tolerance: ModelingTolerance
    ) throws -> Interval? {
        guard !parameterCurves.isEmpty else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Analytic coordinate-loop volume requires at least one pcurve."
            )
        }
        var rawFlux = Interval.exact(0.0)
        var areaBounds = SurfaceParameterAreaBounds.zero
        for curve in parameterCurves {
            guard let verticalSegments = try coordinateVerticalSegments(
                curve,
                tolerance: tolerance
            ) else {
                return nil
            }
            for segment in verticalSegments {
                rawFlux = rawFlux + integrand.verticalBoundaryIntegral(
                    u: segment.u,
                    vStart: segment.vStart,
                    vEnd: segment.vEnd
                )
            }
            areaBounds = areaBounds.adding(
                try SurfaceParameterCurveAreaIntegrator().bounds(
                    for: curve,
                    uShift: 0.0,
                    requestedWidth: max(tolerance.relative, Double.ulpOfOne * 256.0),
                    tolerance: tolerance
                )
            )
        }
        return try normalizedLoopContribution(
            rawFlux: rawFlux,
            areaBounds: areaBounds,
            role: role,
            tolerance: tolerance,
            context: "Analytic coordinate-loop volume"
        )
    }

    private func normalizedLoopContribution(
        rawFlux: Interval,
        areaBounds: SurfaceParameterAreaBounds,
        role: LoopRole,
        tolerance: ModelingTolerance,
        context: String
    ) throws -> Interval {
        let traversalNormalized: Interval
        if areaBounds.lower > 0.0 {
            traversalNormalized = rawFlux
        } else if areaBounds.upper < 0.0 {
            traversalNormalized = -rawFlux
        } else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: areaBounds.minimumAbsoluteValue,
                tolerance: tolerance,
                message: "\(context) could not certify loop orientation."
            )
        }
        return role == .outer ? traversalNormalized : -traversalNormalized
    }

    private func coordinateVerticalSegments(
        _ curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> [(u: Interval, vStart: Interval, vEnd: Interval)]? {
        switch curve {
        case let .constantU(u, vStart, vEnd):
            return [(.exact(u), .exact(vStart), .exact(vEnd))]
        case .constantV:
            return []
        case let .affine(origin, direction, startParameter, endParameter):
            if direction.x == 0.0 {
                return [(
                    .exact(origin.x),
                    .exact(origin.y) + .exact(direction.y) * .exact(startParameter),
                    .exact(origin.y) + .exact(direction.y) * .exact(endParameter)
                )]
            }
            return direction.y == 0.0 ? [] : nil
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            if cosine.x == 0.0, sine.x == 0.0 {
                return [(
                    .exact(center.x),
                    .exact(center.y)
                        + .exact(cosine.y) * .cosine(.exact(startParameter))
                        + .exact(sine.y) * .sine(.exact(startParameter)),
                    .exact(center.y)
                        + .exact(cosine.y) * .cosine(.exact(endParameter))
                        + .exact(sine.y) * .sine(.exact(endParameter))
                )]
            }
            if cosine.y == 0.0, sine.y == 0.0 {
                return []
            }
            return nil
        case let .polyline(points):
            var result: [(u: Interval, vStart: Interval, vEnd: Interval)] = []
            for index in 1..<points.count {
                let start = points[index - 1]
                let end = points[index]
                if start.u == end.u {
                    result.append((.exact(start.u), .exact(start.v), .exact(end.v)))
                } else if start.v != end.v {
                    return nil
                }
            }
            return result
        case let .bSpline(spline):
            guard let lowerKnot = spline.knots.first,
                  let upperKnot = spline.knots.last,
                  spline.knots.prefix(spline.degree + 1).allSatisfy({
                      $0 == lowerKnot
                  }),
                  spline.knots.suffix(spline.degree + 1).allSatisfy({
                      $0 == upperKnot
                  }) else {
                return nil
            }
            if let first = spline.controlPoints.first,
               let last = spline.controlPoints.last,
               spline.controlPoints.allSatisfy({ $0.x == first.x }) {
                return [(.exact(first.x), .exact(first.y), .exact(last.y))]
            }
            if let first = spline.controlPoints.first,
               spline.controlPoints.allSatisfy({ $0.y == first.y }) {
                return []
            }
            return nil
        case .sphericalGreatCircle,
             .certifiedImplicit,
             .certifiedAnalyticImplicit,
             .certifiedAnalyticPair,
             .projectedAnalytic:
            return nil
        case let .periodicTranslation(base, uShift, vShift):
            return try coordinateVerticalSegments(
                base,
                tolerance: tolerance
            )?.map { segment in
                (
                    segment.u + .exact(uShift),
                    segment.vStart + .exact(vShift),
                    segment.vEnd + .exact(vShift)
                )
            }
        }
    }

    func planarLoopVolumeBounds(
        surface: Surface3D,
        parameterCurves: [SurfaceParameterCurve],
        role: LoopRole,
        reference: Point3D,
        requestedAreaWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> VolumeBounds? {
        try tolerance.validate()
        guard let integrand = try Integrand(
            surface: surface,
            reference: reference,
            tolerance: tolerance
        ), let volumeScale = integrand.planeVolumeScale else {
            return nil
        }
        let contribution = volumeScale * (try orientedLoopAreaBounds(
            parameterCurves: parameterCurves,
            role: role,
            requestedAreaWidth: requestedAreaWidth,
            tolerance: tolerance
        ))
        return VolumeBounds(
            lower: contribution.lower,
            upper: contribution.upper
        )
    }

    private func orientedLoopAreaBounds(
        parameterCurves: [SurfaceParameterCurve],
        role: LoopRole,
        requestedAreaWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        guard !parameterCurves.isEmpty else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Planar face volume requires at least one pcurve per loop."
            )
        }
        guard requestedAreaWidth.isFinite, requestedAreaWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: requestedAreaWidth,
                tolerance: tolerance,
                message: "Planar face volume requires a finite positive area enclosure width."
            )
        }
        var loopBounds = SurfaceParameterAreaBounds.zero
        for curve in parameterCurves {
            loopBounds = loopBounds.adding(
                try SurfaceParameterCurveAreaIntegrator().bounds(
                    for: curve,
                    uShift: 0.0,
                    requestedWidth: requestedAreaWidth,
                    tolerance: tolerance
                )
            )
        }
        let absoluteArea: Interval
        if loopBounds.lower > 0.0 {
            absoluteArea = Interval(
                lower: loopBounds.lower,
                upper: loopBounds.upper
            )
        } else if loopBounds.upper < 0.0 {
            absoluteArea = Interval(
                lower: (-loopBounds.upper).nextDown,
                upper: (-loopBounds.lower).nextUp
            )
        } else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: loopBounds.minimumAbsoluteValue,
                tolerance: tolerance,
                message: "Planar face volume could not certify a nonzero pcurve-loop orientation."
            )
        }
        return role == .outer ? absoluteArea : -absoluteArea
    }

    func faceVolumeBounds(
        surface: Surface3D,
        domain: ExactRectangularPcurveDomain,
        reference: Point3D,
        tolerance: ModelingTolerance
    ) throws -> VolumeBounds? {
        try tolerance.validate()
        guard let integrand = try Integrand(
            surface: surface,
            reference: reference,
            tolerance: tolerance
        ) else {
            return nil
        }
        let value = integrand.integral(over: domain)
        return VolumeBounds(lower: value.lower, upper: value.upper)
    }

    private func referencePoint(
        for shell: Shell,
        in model: BRepModel
    ) throws -> Point3D {
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference(
                    "Trimmed analytic volume references a missing face."
                )
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "Trimmed analytic volume references a missing loop."
                    )
                }
                for coedge in loop.coedges {
                    guard let edge = model.edges[coedge.edgeID],
                          let point = model.vertices[edge.startVertexID]?.point else {
                        throw TopologyError.missingReference(
                            "Trimmed analytic volume references a missing boundary vertex."
                        )
                    }
                    return point
                }
            }
        }
        throw TopologyError.openShell(shell.id)
    }

    private func characteristicLength(
        of shell: Shell,
        in model: BRepModel,
        reference: Point3D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        var maximumLength = tolerance.distance
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference(
                    "Trimmed analytic volume references a missing face."
                )
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "Trimmed analytic volume references a missing loop."
                    )
                }
                for coedge in loop.coedges {
                    guard let edge = model.edges[coedge.edgeID],
                          let start = model.vertices[edge.startVertexID]?.point,
                          let end = model.vertices[edge.endVertexID]?.point else {
                        throw TopologyError.missingReference(
                            "Trimmed analytic volume references a missing boundary vertex."
                        )
                    }
                    maximumLength = max(
                        maximumLength,
                        max((start - reference).length, (end - reference).length)
                    )
                }
            }
        }
        return max(maximumLength, 1.0)
    }

    private func coedgeCount(
        of shell: Shell,
        in model: BRepModel
    ) throws -> Int {
        var count = 0
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference(
                    "Trimmed analytic volume references a missing face."
                )
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "Trimmed analytic volume references a missing loop."
                    )
                }
                count += loop.coedges.count
            }
        }
        return count
    }

    enum Integrand {
        case plane(volumeScale: Interval)
        case cylinder(
            radius: Interval,
            offsetU: Interval,
            offsetV: Interval
        )
        case cone(
            sine: Interval,
            cosine: Interval,
            radialOffsetU: Interval,
            radialOffsetV: Interval,
            axialOffset: Interval
        )
        case sphere(
            radius: Interval,
            radialOffsetU: Interval,
            radialOffsetV: Interval,
            axialOffset: Interval
        )
        case torus(
            majorRadius: Interval,
            minorRadius: Interval,
            radialOffsetU: Interval,
            radialOffsetV: Interval,
            axialOffset: Interval
        )

        init?(
            surface: Surface3D,
            reference: Point3D,
            tolerance: ModelingTolerance
        ) throws {
            let kind: Kind
            switch surface {
            case let .plane(plane):
                kind = .plane(origin: plane.origin)
            case let .cylinder(cylinder):
                kind = .cylinder(origin: cylinder.origin, radius: cylinder.radius)
            case let .analytic(.plane(origin, _)):
                kind = .plane(origin: origin)
            case let .analytic(.cylinder(origin, _, radius)):
                kind = .cylinder(origin: origin, radius: radius)
            case let .analytic(.cone(apex, axis, halfAngle)):
                kind = .cone(apex: apex, axis: axis, halfAngle: halfAngle)
            case let .analytic(.sphere(center, radius)):
                kind = .sphere(center: center, radius: radius)
            case let .analytic(.torus(center, axis, majorRadius, minorRadius)):
                kind = .torus(
                    center: center,
                    axis: axis,
                    majorRadius: majorRadius,
                    minorRadius: minorRadius
                )
            case .analytic, .bSpline:
                return nil
            }
            let sampleV = if case .cone = kind { 1.0 } else { 0.0 }
            let geometry = try surface.differentialGeometry(
                atU: 0.0,
                v: sampleV,
                tolerance: tolerance
            )
            switch kind {
            case let .plane(origin):
                let areaVector = geometry.tangentU.cross(geometry.tangentV)
                self = .plane(volumeScale: .floating(
                    (origin - reference).dot(areaVector) / 3.0
                ))
            case let .cylinder(origin, radius):
                let radialU = try (geometry.position - origin).normalized(
                    tolerance: tolerance.distance
                )
                let radialV = try geometry.tangentU.normalized(
                    tolerance: tolerance.distance
                )
                let offset = origin - reference
                self = .cylinder(
                    radius: .exact(radius),
                    offsetU: .floating(offset.dot(radialU)),
                    offsetV: .floating(offset.dot(radialV))
                )
            case let .cone(apex, axis, halfAngle):
                let radialU = try (
                    geometry.position - apex
                        - axis * (geometry.position - apex).dot(axis)
                ).normalized(tolerance: tolerance.distance)
                let radialV = try geometry.tangentU.normalized(
                    tolerance: tolerance.distance
                )
                let offset = apex - reference
                self = .cone(
                    sine: .sine(.exact(halfAngle)),
                    cosine: .cosine(.exact(halfAngle)),
                    radialOffsetU: .floating(offset.dot(radialU)),
                    radialOffsetV: .floating(offset.dot(radialV)),
                    axialOffset: .floating(offset.dot(axis))
                )
            case let .sphere(center, radius):
                let radialU = try (geometry.position - center).normalized(
                    tolerance: tolerance.distance
                )
                let radialV = try geometry.tangentU.normalized(
                    tolerance: tolerance.distance
                )
                let axis = try geometry.tangentV.normalized(
                    tolerance: tolerance.distance
                )
                let offset = center - reference
                self = .sphere(
                    radius: .exact(radius),
                    radialOffsetU: .floating(offset.dot(radialU)),
                    radialOffsetV: .floating(offset.dot(radialV)),
                    axialOffset: .floating(offset.dot(axis))
                )
            case let .torus(center, axis, majorRadius, minorRadius):
                let radialU = try (
                    geometry.position - center
                        - axis * (geometry.position - center).dot(axis)
                ).normalized(tolerance: tolerance.distance)
                let radialV = try geometry.tangentU.normalized(
                    tolerance: tolerance.distance
                )
                let offset = center - reference
                self = .torus(
                    majorRadius: .exact(majorRadius),
                    minorRadius: .exact(minorRadius),
                    radialOffsetU: .floating(offset.dot(radialU)),
                    radialOffsetV: .floating(offset.dot(radialV)),
                    axialOffset: .floating(offset.dot(axis))
                )
            }
        }

        func integral(over domain: ExactRectangularPcurveDomain) -> Interval {
            let uLower = Interval.exact(domain.uLower)
            let uUpper = Interval.exact(domain.uUpper)
            let vLower = Interval.exact(domain.vLower)
            let vUpper = Interval.exact(domain.vUpper)
            let deltaU = uUpper - uLower
            let deltaV = vUpper - vLower
            switch self {
            case let .plane(volumeScale):
                return volumeScale * deltaU * deltaV
            case let .cylinder(radius, offsetU, offsetV):
                let deltaA = Self.deltaAzimuthPrimitive(
                    uLower: uLower,
                    uUpper: uUpper,
                    offsetU: offsetU,
                    offsetV: offsetV
                )
                return radius / .exact(3.0)
                    * (deltaA + radius * deltaU) * deltaV
            case let .cone(
                sine,
                cosine,
                radialOffsetU,
                radialOffsetV,
                axialOffset
            ):
                let deltaA = Self.deltaAzimuthPrimitive(
                    uLower: uLower,
                    uUpper: uUpper,
                    offsetU: radialOffsetU,
                    offsetV: radialOffsetV
                )
                let vMoment = (vUpper * vUpper - vLower * vLower) / .exact(2.0)
                return sine / .exact(3.0)
                    * (cosine * deltaA - sine * axialOffset * deltaU)
                    * vMoment
            case let .sphere(
                radius,
                radialOffsetU,
                radialOffsetV,
                axialOffset
            ):
                let deltaA = Self.deltaAzimuthPrimitive(
                    uLower: uLower,
                    uUpper: uUpper,
                    offsetU: radialOffsetU,
                    offsetV: radialOffsetV
                )
                let moments = Self.trigonometricMoments(
                    lower: vLower,
                    upper: vUpper
                )
                return radius * radius / .exact(3.0) * (
                    deltaA * moments.cosineSquared
                        + deltaU * (
                            axialOffset * moments.cosineSine
                                + radius * moments.cosine
                        )
                )
            case let .torus(
                majorRadius,
                minorRadius,
                radialOffsetU,
                radialOffsetV,
                axialOffset
            ):
                let deltaA = Self.deltaAzimuthPrimitive(
                    uLower: uLower,
                    uUpper: uUpper,
                    offsetU: radialOffsetU,
                    offsetV: radialOffsetV
                )
                let moments = Self.trigonometricMoments(
                    lower: vLower,
                    upper: vUpper
                )
                let azimuthTerm = deltaA * (
                    majorRadius * moments.cosine
                        + minorRadius * moments.cosineSquared
                )
                let axialTerm = deltaU * (
                    axialOffset * majorRadius * moments.sine
                        + axialOffset * minorRadius * moments.cosineSine
                        + majorRadius * majorRadius * moments.cosine
                        + majorRadius * minorRadius * moments.cosineSquared
                        + minorRadius * majorRadius * deltaV
                        + minorRadius * minorRadius * moments.cosine
                )
                return minorRadius / .exact(3.0) * (azimuthTerm + axialTerm)
            }
        }

        func verticalBoundaryIntegral(
            u: Interval,
            vStart: Interval,
            vEnd: Interval
        ) -> Interval {
            let deltaV = vEnd - vStart
            switch self {
            case let .plane(volumeScale):
                return volumeScale * u * deltaV
            case let .cylinder(radius, offsetU, offsetV):
                let primitive = Self.azimuthPrimitive(
                    u: u,
                    offsetU: offsetU,
                    offsetV: offsetV
                )
                return radius / .exact(3.0)
                    * (primitive + radius * u) * deltaV
            case let .cone(
                sine,
                cosine,
                radialOffsetU,
                radialOffsetV,
                axialOffset
            ):
                let primitive = Self.azimuthPrimitive(
                    u: u,
                    offsetU: radialOffsetU,
                    offsetV: radialOffsetV
                )
                let vMoment = (vEnd * vEnd - vStart * vStart) / .exact(2.0)
                return sine / .exact(3.0)
                    * (cosine * primitive - sine * axialOffset * u)
                    * vMoment
            case let .sphere(
                radius,
                radialOffsetU,
                radialOffsetV,
                axialOffset
            ):
                let primitive = Self.azimuthPrimitive(
                    u: u,
                    offsetU: radialOffsetU,
                    offsetV: radialOffsetV
                )
                let moments = Self.trigonometricMoments(
                    lower: vStart,
                    upper: vEnd
                )
                return radius * radius / .exact(3.0) * (
                    primitive * moments.cosineSquared
                        + u * (
                            axialOffset * moments.cosineSine
                                + radius * moments.cosine
                        )
                )
            case let .torus(
                majorRadius,
                minorRadius,
                radialOffsetU,
                radialOffsetV,
                axialOffset
            ):
                let primitive = Self.azimuthPrimitive(
                    u: u,
                    offsetU: radialOffsetU,
                    offsetV: radialOffsetV
                )
                let moments = Self.trigonometricMoments(
                    lower: vStart,
                    upper: vEnd
                )
                let azimuthTerm = primitive * (
                    majorRadius * moments.cosine
                        + minorRadius * moments.cosineSquared
                )
                let axialTerm = u * (
                    axialOffset * majorRadius * moments.sine
                        + axialOffset * minorRadius * moments.cosineSine
                        + majorRadius * majorRadius * moments.cosine
                        + majorRadius * minorRadius * moments.cosineSquared
                        + minorRadius * majorRadius * deltaV
                        + minorRadius * minorRadius * moments.cosine
                )
                return minorRadius / .exact(3.0) * (azimuthTerm + axialTerm)
            }
        }

        func greenPrimitive(u: Interval, v: Interval) -> Interval {
            switch self {
            case let .plane(volumeScale):
                return volumeScale * u
            case let .cylinder(radius, offsetU, offsetV):
                return radius / .exact(3.0) * (
                    Self.azimuthPrimitive(u: u, offsetU: offsetU, offsetV: offsetV)
                        + radius * u
                )
            case let .cone(
                sine,
                cosine,
                radialOffsetU,
                radialOffsetV,
                axialOffset
            ):
                return sine / .exact(3.0) * (
                    cosine * Self.azimuthPrimitive(
                        u: u,
                        offsetU: radialOffsetU,
                        offsetV: radialOffsetV
                    ) - sine * axialOffset * u
                ) * v
            case let .sphere(
                radius,
                radialOffsetU,
                radialOffsetV,
                axialOffset
            ):
                let cosineV = Interval.cosine(v)
                let sineV = Interval.sine(v)
                return radius * radius / .exact(3.0) * (
                    Self.azimuthPrimitive(
                        u: u,
                        offsetU: radialOffsetU,
                        offsetV: radialOffsetV
                    ) * cosineV * cosineV
                        + u * (axialOffset * cosineV * sineV + radius * cosineV)
                )
            case let .torus(
                majorRadius,
                minorRadius,
                radialOffsetU,
                radialOffsetV,
                axialOffset
            ):
                let cosineV = Interval.cosine(v)
                let sineV = Interval.sine(v)
                let azimuthTerm = Self.azimuthPrimitive(
                    u: u,
                    offsetU: radialOffsetU,
                    offsetV: radialOffsetV
                ) * (majorRadius * cosineV + minorRadius * cosineV * cosineV)
                let axialTerm = u * (
                    axialOffset * majorRadius * sineV
                        + axialOffset * minorRadius * cosineV * sineV
                        + majorRadius * majorRadius * cosineV
                        + majorRadius * minorRadius * cosineV * cosineV
                        + minorRadius * majorRadius
                        + minorRadius * minorRadius * cosineV
                )
                return minorRadius / .exact(3.0) * (azimuthTerm + axialTerm)
            }
        }

        var planeVolumeScale: Interval? {
            if case let .plane(volumeScale) = self {
                return volumeScale
            }
            return nil
        }

        private static func deltaAzimuthPrimitive(
            uLower: Interval,
            uUpper: Interval,
            offsetU: Interval,
            offsetV: Interval
        ) -> Interval {
            azimuthPrimitive(u: uUpper, offsetU: offsetU, offsetV: offsetV)
                - azimuthPrimitive(u: uLower, offsetU: offsetU, offsetV: offsetV)
        }

        private static func azimuthPrimitive(
            u: Interval,
            offsetU: Interval,
            offsetV: Interval
        ) -> Interval {
            offsetU * .sine(u) - offsetV * .cosine(u)
        }

        private static func trigonometricMoments(
            lower: Interval,
            upper: Interval
        ) -> (
            cosine: Interval,
            sine: Interval,
            cosineSquared: Interval,
            cosineSine: Interval
        ) {
            let sineLower = Interval.sine(lower)
            let sineUpper = Interval.sine(upper)
            let cosineLower = Interval.cosine(lower)
            let cosineUpper = Interval.cosine(upper)
            let span = upper - lower
            return (
                cosine: sineUpper - sineLower,
                sine: cosineLower - cosineUpper,
                cosineSquared: span / .exact(2.0)
                    + (.sine(upper * .exact(2.0)) - .sine(lower * .exact(2.0)))
                        / .exact(4.0),
                cosineSine: (sineUpper * sineUpper - sineLower * sineLower)
                    / .exact(2.0)
            )
        }

        private enum Kind {
            case plane(origin: Point3D)
            case cylinder(origin: Point3D, radius: Double)
            case cone(apex: Point3D, axis: Vector3D, halfAngle: Double)
            case sphere(center: Point3D, radius: Double)
            case torus(
                center: Point3D,
                axis: Vector3D,
                majorRadius: Double,
                minorRadius: Double
            )
        }
    }

    struct Interval: Sendable, Hashable {
        let lower: Double
        let upper: Double

        init(lower: Double, upper: Double) {
            self.lower = lower
            self.upper = upper
        }

        static func exact(_ value: Double) -> Interval {
            Interval(lower: value, upper: value)
        }

        static func floating(_ value: Double) -> Interval {
            var lower = value
            var upper = value
            for _ in 0..<64 {
                lower = lower.nextDown
                upper = upper.nextUp
            }
            return Interval(lower: lower, upper: upper)
        }

        var maximumAbsolute: Double {
            max(abs(lower), abs(upper)).nextUp
        }

        var width: Double {
            (upper - lower).nextUp
        }

        static func sine(_ value: Interval) -> Interval {
            trigonometric(value, phase: 0.0)
        }

        static func cosine(_ value: Interval) -> Interval {
            trigonometric(value, phase: Double.pi * 0.5)
        }

        private static func trigonometric(
            _ value: Interval,
            phase: Double
        ) -> Interval {
            guard value.upper - value.lower < 2.0 * Double.pi else {
                return Interval(lower: -1.0, upper: 1.0)
            }
            var samples = [sin(value.lower + phase), sin(value.upper + phase)]
            let firstCritical = Int(ceil(
                (value.lower + phase - Double.pi * 0.5) / Double.pi
            ))
            let lastCritical = Int(floor(
                (value.upper + phase - Double.pi * 0.5) / Double.pi
            ))
            if firstCritical <= lastCritical {
                for index in firstCritical...lastCritical {
                    samples.append(index.isMultiple(of: 2) ? 1.0 : -1.0)
                }
            }
            var lower = samples.min() ?? -1.0
            var upper = samples.max() ?? 1.0
            for _ in 0..<16 {
                lower = lower.nextDown
                upper = upper.nextUp
            }
            return Interval(lower: max(-1.0, lower), upper: min(1.0, upper))
        }

        static prefix func - (value: Interval) -> Interval {
            Interval(lower: (-value.upper).nextDown, upper: (-value.lower).nextUp)
        }

        static func + (lhs: Interval, rhs: Interval) -> Interval {
            Interval(
                lower: (lhs.lower + rhs.lower).nextDown,
                upper: (lhs.upper + rhs.upper).nextUp
            )
        }

        static func - (lhs: Interval, rhs: Interval) -> Interval {
            lhs + (-rhs)
        }

        static func * (lhs: Interval, rhs: Interval) -> Interval {
            let products = [
                lhs.lower * rhs.lower,
                lhs.lower * rhs.upper,
                lhs.upper * rhs.lower,
                lhs.upper * rhs.upper,
            ]
            return Interval(
                lower: (products.min() ?? -.infinity).nextDown,
                upper: (products.max() ?? .infinity).nextUp
            )
        }

        static func / (lhs: Interval, rhs: Interval) -> Interval {
            guard rhs.lower > 0.0 || rhs.upper < 0.0 else {
                // A zero-containing divisor has an unbounded real quotient.
                // The volume owner rejects non-finite enclosures explicitly.
                return Interval(lower: -.infinity, upper: .infinity)
            }
            return lhs * Interval(
                lower: (1.0 / rhs.upper).nextDown,
                upper: (1.0 / rhs.lower).nextUp
            )
        }
    }
}
