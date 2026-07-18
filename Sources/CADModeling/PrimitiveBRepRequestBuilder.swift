import Foundation
import CADCore
import CADGeometry
import CADIR

struct PrimitiveBRepRequestBuilder: Sendable {
    let tolerance: ModelingTolerance

    func box(
        _ primitive: BoxPrimitive,
        width: Double,
        depth: Double,
        height: Double,
        featureID: FeatureID
    ) throws -> BRepSewingRequest {
        let frame = try PrimitiveFrame(primitive.placement, tolerance: tolerance)
        let p0 = frame.origin
        let p1 = p0 + frame.x * width
        let p2 = p1 + frame.y * depth
        let p3 = p0 + frame.y * depth
        let boundary = try [
            ExactPrismaticBoundarySegment.line(from: p0, to: p1, tolerance: tolerance),
            ExactPrismaticBoundarySegment.line(from: p1, to: p2, tolerance: tolerance),
            ExactPrismaticBoundarySegment.line(from: p2, to: p3, tolerance: tolerance),
            ExactPrismaticBoundarySegment.line(from: p3, to: p0, tolerance: tolerance),
        ]
        return try ExactPrismaticFacePatchBuilder(tolerance: tolerance).request(
            boundary: boundary,
            axis: frame.z,
            height: height,
            featureID: featureID,
            stablePrefix: "primitive:box"
        )
    }

    func cylinder(
        _ primitive: CylinderPrimitive,
        radius: Double,
        height: Double,
        featureID: FeatureID
    ) throws -> BRepSewingRequest {
        let frame = try PrimitiveFrame(primitive.placement, tolerance: tolerance)
        let circle = Circle3D(center: frame.origin, normal: frame.z, radius: radius)
        let curve = Curve3D.circle(circle)
        let seamPoint = frame.origin + frame.x * radius
        let start = try curve.parameterProjection(
            of: seamPoint,
            tolerance: tolerance
        ).parameter
        let boundary = try (0..<4).map { index in
            try ExactPrismaticBoundarySegment.circularArc(
                circle: circle,
                startParameter: start + Double(index) * Double.pi * 0.5,
                endParameter: start + Double(index + 1) * Double.pi * 0.5,
                tolerance: tolerance
            )
        }
        return try ExactPrismaticFacePatchBuilder(tolerance: tolerance).request(
            boundary: boundary,
            axis: frame.z,
            height: height,
            featureID: featureID,
            stablePrefix: "primitive:cylinder"
        )
    }

    func cone(
        _ primitive: ConePrimitive,
        baseRadius: Double,
        height: Double,
        featureID: FeatureID
    ) throws -> BRepSewingRequest {
        let frame = try PrimitiveFrame(primitive.placement, tolerance: tolerance)
        let slantHeight = hypot(baseRadius, height)
        let halfAngle = atan2(baseRadius, height)
        let surface = Surface3D.analytic(.cone(
            apex: frame.origin,
            axis: frame.z,
            halfAngle: halfAngle
        ))
        let baseCenter = frame.origin + frame.z * height
        let baseSurface = Surface3D.analytic(.plane(origin: baseCenter, normal: frame.z))
        let baseCircle = AnalyticCurve3D.circle(
            center: baseCenter,
            normal: frame.z,
            radius: baseRadius
        )
        let seamProjection = try surface.parameterProjection(
            of: baseCenter + frame.x * baseRadius,
            tolerance: tolerance
        )
        let uStart = seamProjection.u
        var sidePatches: [BRepSewingFacePatch] = []
        var capEdges: [BRepSewingEdge] = []
        for index in 0..<4 {
            let u0 = uStart + Double(index) * Double.pi * 0.5
            let u1 = uStart + Double(index + 1) * Double.pi * 0.5
            let um = (u0 + u1) * 0.5
            let base0 = try surface.point(u: u0, v: slantHeight, tolerance: tolerance)
            let base1 = try surface.point(u: u1, v: slantHeight, tolerance: tolerance)
            let baseMid = try surface.point(u: um, v: slantHeight, tolerance: tolerance)
            let sidePrefix = "primitive:cone:side:\(index)"
            let outbound = try lineEdge(
                stableID: "\(sidePrefix):outbound",
                from: frame.origin,
                to: base1,
                pcurve: .constantU(u: u1, vStart: 0.0, vEnd: slantHeight)
            )
            let base = try circleEdge(
                stableID: "\(sidePrefix):base",
                definition: baseCircle,
                startPoint: base1,
                midpoint: baseMid,
                endPoint: base0,
                pcurve: { _, _ in
                    .constantV(v: slantHeight, uStart: u1, uEnd: u0)
                }
            )
            let inbound = try lineEdge(
                stableID: "\(sidePrefix):inbound",
                from: base0,
                to: frame.origin,
                pcurve: .constantU(u: u0, vStart: slantHeight, vEnd: 0.0)
            )
            sidePatches.append(BRepSewingFacePatch(
                stableID: sidePrefix,
                surface: surface,
                orientation: .forward,
                loops: [BRepSewingLoop(
                    stableID: "\(sidePrefix):loop",
                    role: .outer,
                    edges: [outbound, base, inbound]
                )]
            ))
            capEdges.append(try circleEdge(
                stableID: "primitive:cone:cap:edge:\(index)",
                definition: baseCircle,
                startPoint: base0,
                midpoint: baseMid,
                endPoint: base1,
                pcurve: { start, end in
                    try planarHarmonicPcurve(
                        curve: .analytic(baseCircle),
                        center: baseCenter,
                        startParameter: start,
                        endParameter: end,
                        surface: baseSurface
                    )
                }
            ))
        }
        let cap = BRepSewingFacePatch(
            stableID: "primitive:cone:cap",
            surface: baseSurface,
            orientation: .forward,
            loops: [BRepSewingLoop(
                stableID: "primitive:cone:cap:loop",
                role: .outer,
                edges: capEdges
            )]
        )
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [BRepSewingShell(
                stableID: "primitive:cone:shell",
                patches: sidePatches + [cap]
            )]
        )
    }

    func sphere(
        _ primitive: SpherePrimitive,
        radius: Double,
        featureID: FeatureID
    ) throws -> BRepSewingRequest {
        let frame = try PrimitiveFrame(primitive.placement, tolerance: tolerance)
        let surface = Surface3D.analytic(.sphere(center: frame.origin, radius: radius))
        let north = frame.origin + frame.z * radius
        let south = frame.origin + (-frame.z) * radius
        let equator = AnalyticCurve3D.circle(
            center: frame.origin,
            normal: frame.z,
            radius: radius
        )
        var patches: [BRepSewingFacePatch] = []
        for index in 0..<4 {
            let angle0 = Double(index) * Double.pi * 0.5
            let angle1 = Double(index + 1) * Double.pi * 0.5
            let angleMid = (angle0 + angle1) * 0.5
            let radial0 = frame.x * cos(angle0) + frame.y * sin(angle0)
            let radial1 = frame.x * cos(angle1) + frame.y * sin(angle1)
            let radialMid = frame.x * cos(angleMid) + frame.y * sin(angleMid)
            let equator0 = frame.origin + radial0 * radius
            let equator1 = frame.origin + radial1 * radius
            let equatorMid = frame.origin + radialMid * radius
            let northMid0Direction = try (radial0 + frame.z).normalized(
                tolerance: tolerance.distance
            )
            let northMid1Direction = try (radial1 + frame.z).normalized(
                tolerance: tolerance.distance
            )
            let southMid0Direction = try (radial0 - frame.z).normalized(
                tolerance: tolerance.distance
            )
            let southMid1Direction = try (radial1 - frame.z).normalized(
                tolerance: tolerance.distance
            )

            let northPrefix = "primitive:sphere:north:\(index)"
            let northOutbound = try sphereMeridianEdge(
                stableID: "\(northPrefix):outbound",
                center: frame.origin,
                radius: radius,
                axis: frame.z,
                radial: radial1,
                startPoint: equator1,
                midpoint: frame.origin + northMid1Direction * radius,
                endPoint: north
            )
            let northInbound = try sphereMeridianEdge(
                stableID: "\(northPrefix):inbound",
                center: frame.origin,
                radius: radius,
                axis: frame.z,
                radial: radial0,
                startPoint: north,
                midpoint: frame.origin + northMid0Direction * radius,
                endPoint: equator0
            )
            let northEquator = try sphereCircleEdge(
                stableID: "\(northPrefix):equator",
                definition: equator,
                center: frame.origin,
                startPoint: equator0,
                midpoint: equatorMid,
                endPoint: equator1
            )
            patches.append(sphericalPatch(
                stableID: northPrefix,
                surface: surface,
                edges: [northEquator, northOutbound, northInbound]
            ))

            let southPrefix = "primitive:sphere:south:\(index)"
            let southOutbound = try sphereMeridianEdge(
                stableID: "\(southPrefix):outbound",
                center: frame.origin,
                radius: radius,
                axis: frame.z,
                radial: radial1,
                startPoint: south,
                midpoint: frame.origin + southMid1Direction * radius,
                endPoint: equator1
            )
            let southEquator = try sphereCircleEdge(
                stableID: "\(southPrefix):equator",
                definition: equator,
                center: frame.origin,
                startPoint: equator1,
                midpoint: equatorMid,
                endPoint: equator0
            )
            let southInbound = try sphereMeridianEdge(
                stableID: "\(southPrefix):inbound",
                center: frame.origin,
                radius: radius,
                axis: frame.z,
                radial: radial0,
                startPoint: equator0,
                midpoint: frame.origin + southMid0Direction * radius,
                endPoint: south
            )
            patches.append(sphericalPatch(
                stableID: southPrefix,
                surface: surface,
                edges: [southOutbound, southEquator, southInbound]
            ))
        }
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [BRepSewingShell(
                stableID: "primitive:sphere:shell",
                patches: patches
            )]
        )
    }

    func torus(
        _ primitive: TorusPrimitive,
        majorRadius: Double,
        minorRadius: Double,
        featureID: FeatureID
    ) throws -> BRepSewingRequest {
        let frame = try PrimitiveFrame(primitive.placement, tolerance: tolerance)
        let surface = Surface3D.analytic(.torus(
            center: frame.origin,
            axis: frame.z,
            majorRadius: majorRadius,
            minorRadius: minorRadius
        ))
        let seamPoint = frame.origin + frame.x * (majorRadius + minorRadius)
        let uStart = try surface.parameterProjection(
            of: seamPoint,
            tolerance: tolerance
        ).u
        var patches: [BRepSewingFacePatch] = []
        for uIndex in 0..<4 {
            let u0 = uStart + Double(uIndex) * Double.pi * 0.5
            let u1 = uStart + Double(uIndex + 1) * Double.pi * 0.5
            for vIndex in 0..<4 {
                let v0 = Double(vIndex) * Double.pi * 0.5
                let v1 = Double(vIndex + 1) * Double.pi * 0.5
                let prefix = "primitive:torus:u:\(uIndex):v:\(vIndex)"
                let bottom = try torusConstantVEdge(
                    stableID: "\(prefix):bottom",
                    surface: surface,
                    center: frame.origin,
                    axis: frame.z,
                    majorRadius: majorRadius,
                    minorRadius: minorRadius,
                    uStart: u0,
                    uEnd: u1,
                    v: v0
                )
                let right = try torusConstantUEdge(
                    stableID: "\(prefix):right",
                    surface: surface,
                    center: frame.origin,
                    axis: frame.z,
                    majorRadius: majorRadius,
                    minorRadius: minorRadius,
                    u: u1,
                    vStart: v0,
                    vEnd: v1
                )
                let top = try torusConstantVEdge(
                    stableID: "\(prefix):top",
                    surface: surface,
                    center: frame.origin,
                    axis: frame.z,
                    majorRadius: majorRadius,
                    minorRadius: minorRadius,
                    uStart: u1,
                    uEnd: u0,
                    v: v1
                )
                let left = try torusConstantUEdge(
                    stableID: "\(prefix):left",
                    surface: surface,
                    center: frame.origin,
                    axis: frame.z,
                    majorRadius: majorRadius,
                    minorRadius: minorRadius,
                    u: u0,
                    vStart: v1,
                    vEnd: v0
                )
                patches.append(BRepSewingFacePatch(
                    stableID: prefix,
                    surface: surface,
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "\(prefix):loop",
                        role: .outer,
                        edges: [bottom, right, top, left]
                    )]
                ))
            }
        }
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [BRepSewingShell(
                stableID: "primitive:torus:shell",
                patches: patches
            )]
        )
    }

    private func sphericalPatch(
        stableID: String,
        surface: Surface3D,
        edges: [BRepSewingEdge]
    ) -> BRepSewingFacePatch {
        BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: .forward,
            loops: [BRepSewingLoop(
                stableID: "\(stableID):loop",
                role: .outer,
                edges: edges
            )]
        )
    }

    private func sphereMeridianEdge(
        stableID: String,
        center: Point3D,
        radius: Double,
        axis: Vector3D,
        radial: Vector3D,
        startPoint: Point3D,
        midpoint: Point3D,
        endPoint: Point3D
    ) throws -> BRepSewingEdge {
        let normal = try axis.cross(radial).normalized(tolerance: tolerance.distance)
        return try sphereCircleEdge(
            stableID: stableID,
            definition: .circle(center: center, normal: normal, radius: radius),
            center: center,
            startPoint: startPoint,
            midpoint: midpoint,
            endPoint: endPoint
        )
    }

    private func sphereCircleEdge(
        stableID: String,
        definition: AnalyticCurve3D,
        center: Point3D,
        startPoint: Point3D,
        midpoint: Point3D,
        endPoint: Point3D
    ) throws -> BRepSewingEdge {
        let curve = Curve3D.analytic(definition)
        return try circleEdge(
            stableID: stableID,
            definition: definition,
            startPoint: startPoint,
            midpoint: midpoint,
            endPoint: endPoint,
            pcurve: { start, end in
                let cosine = try (curve.point(at: 0.0, tolerance: tolerance) - center)
                    .normalized(tolerance: tolerance.distance)
                let sine = try (curve.point(at: Double.pi * 0.5, tolerance: tolerance) - center)
                    .normalized(tolerance: tolerance.distance)
                return .sphericalGreatCircle(
                    cosine: cosine,
                    sine: sine,
                    startParameter: start,
                    endParameter: end
                )
            }
        )
    }

    private func torusConstantVEdge(
        stableID: String,
        surface: Surface3D,
        center: Point3D,
        axis: Vector3D,
        majorRadius: Double,
        minorRadius: Double,
        uStart: Double,
        uEnd: Double,
        v: Double
    ) throws -> BRepSewingEdge {
        let circle = AnalyticCurve3D.circle(
            center: center + axis * (minorRadius * sin(v)),
            normal: axis,
            radius: majorRadius + minorRadius * cos(v)
        )
        let midpoint = (uStart + uEnd) * 0.5
        return try circleEdge(
            stableID: stableID,
            definition: circle,
            startPoint: try surface.point(u: uStart, v: v, tolerance: tolerance),
            midpoint: try surface.point(u: midpoint, v: v, tolerance: tolerance),
            endPoint: try surface.point(u: uEnd, v: v, tolerance: tolerance),
            pcurve: { _, _ in
                .constantV(v: v, uStart: uStart, uEnd: uEnd)
            }
        )
    }

    private func torusConstantUEdge(
        stableID: String,
        surface: Surface3D,
        center: Point3D,
        axis: Vector3D,
        majorRadius: Double,
        minorRadius: Double,
        u: Double,
        vStart: Double,
        vEnd: Double
    ) throws -> BRepSewingEdge {
        let outer = try surface.point(u: u, v: 0.0, tolerance: tolerance)
        let radial = try (outer - center - axis * (outer - center).dot(axis))
            .normalized(tolerance: tolerance.distance)
        let circleCenter = center + radial * majorRadius
        let normal = try axis.cross(radial).normalized(tolerance: tolerance.distance)
        let circle = AnalyticCurve3D.circle(
            center: circleCenter,
            normal: normal,
            radius: minorRadius
        )
        let midpoint = (vStart + vEnd) * 0.5
        return try circleEdge(
            stableID: stableID,
            definition: circle,
            startPoint: try surface.point(u: u, v: vStart, tolerance: tolerance),
            midpoint: try surface.point(u: u, v: midpoint, tolerance: tolerance),
            endPoint: try surface.point(u: u, v: vEnd, tolerance: tolerance),
            pcurve: { _, _ in
                .constantU(u: u, vStart: vStart, vEnd: vEnd)
            }
        )
    }

    private func lineEdge(
        stableID: String,
        from start: Point3D,
        to end: Point3D,
        pcurve: SurfaceParameterCurve
    ) throws -> BRepSewingEdge {
        let delta = end - start
        let length = delta.length
        let direction = try delta.normalized(tolerance: tolerance.distance)
        return BRepSewingEdge(
            stableID: stableID,
            curve: .analytic(.line(origin: start, direction: direction)),
            startParameter: 0.0,
            endParameter: length,
            startPoint: start,
            endPoint: end,
            surfaceParameterCurve: pcurve
        )
    }

    private func circleEdge(
        stableID: String,
        definition: AnalyticCurve3D,
        startPoint: Point3D,
        midpoint: Point3D,
        endPoint: Point3D,
        pcurve: (Double, Double) throws -> SurfaceParameterCurve
    ) throws -> BRepSewingEdge {
        let curve = Curve3D.analytic(definition)
        let trim = try circleTrim(
            curve: curve,
            startPoint: startPoint,
            midpoint: midpoint,
            endPoint: endPoint
        )
        return BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: trim.start,
            endParameter: trim.end,
            startPoint: startPoint,
            endPoint: endPoint,
            surfaceParameterCurve: try pcurve(trim.start, trim.end)
        )
    }

    private func circleTrim(
        curve: Curve3D,
        startPoint: Point3D,
        midpoint: Point3D,
        endPoint: Point3D
    ) throws -> (start: Double, end: Double) {
        let start = try curve.parameterProjection(
            of: startPoint,
            tolerance: tolerance
        ).parameter
        let projectedEnd = try curve.parameterProjection(
            of: endPoint,
            tolerance: tolerance
        ).parameter
        let period = Double.pi * 2.0
        var best: (end: Double, residual: Double, span: Double)?
        for offset in -2...2 {
            let candidate = projectedEnd + Double(offset) * period
            let span = abs(candidate - start)
            guard span > tolerance.angle,
                  span <= Double.pi + tolerance.angle else {
                continue
            }
            let candidateMidpoint = try curve.point(
                at: (start + candidate) * 0.5,
                tolerance: tolerance
            )
            let residual = (candidateMidpoint - midpoint).length
            if best == nil
                || residual < best!.residual
                || (residual == best!.residual && span < best!.span) {
                best = (candidate, residual, span)
            }
        }
        guard let best, best.residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: best?.residual,
                tolerance: tolerance,
                message: "Primitive circular boundary could not be assigned an exact directed trim."
            )
        }
        return (start, best.end)
    }

    private func planarHarmonicPcurve(
        curve: Curve3D,
        center: Point3D,
        startParameter: Double,
        endParameter: Double,
        surface: Surface3D
    ) throws -> SurfaceParameterCurve {
        let centerUV = try surface.parameterProjection(of: center, tolerance: tolerance)
        let cosineUV = try surface.parameterProjection(
            of: curve.point(at: 0.0, tolerance: tolerance),
            tolerance: tolerance
        )
        let sineUV = try surface.parameterProjection(
            of: curve.point(at: Double.pi * 0.5, tolerance: tolerance),
            tolerance: tolerance
        )
        return .harmonic(
            center: Point2D(x: centerUV.u, y: centerUV.v),
            cosine: Point2D(x: cosineUV.u - centerUV.u, y: cosineUV.v - centerUV.v),
            sine: Point2D(x: sineUV.u - centerUV.u, y: sineUV.v - centerUV.v),
            startParameter: startParameter,
            endParameter: endParameter
        )
    }
}

private struct PrimitiveFrame: Sendable {
    let origin: Point3D
    let x: Vector3D
    let y: Vector3D
    let z: Vector3D

    init(_ placement: PrimitivePlacement, tolerance: ModelingTolerance) throws {
        try placement.validate(tolerance: tolerance)
        origin = placement.origin
        x = placement.referenceDirection
        z = placement.axis
        y = try z.cross(x).normalized(tolerance: tolerance.distance)
    }
}
