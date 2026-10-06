import Foundation
import CADCore
import CADGeometry
import CADIR

/// A pipe's custom section stood across its path: the region is carried rigidly so its area
/// centroid sits on the path's start and its normal turns onto the path's tangent by the least
/// rotation (the normal's sign taken nearer the tangent), then turned by the pipe's angle about the
/// tangent. A wall hollows each of the placed region's loops into a ring by the exact line and arc
/// offset.
package struct PipeCustomSectionPlacement: Sendable {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// `source` placed at `origin` across `tangent`, turned by `angle`, under `featureID`: the
    /// region itself, or with a wall the ring of each of its loops (positive outward, negative
    /// inward).
    package func placed(
        _ source: Profile,
        featureID: FeatureID,
        origin: Point3D,
        tangent: Vector3D,
        angle: Double,
        wall: Double?,
        originalCentroid: Point3D? = nil,
        admission suppliedAdmission: GeometryConversionAdmission? = nil
    ) throws -> [Profile] {
        let normal = try ExactSweepSectionPlane(source.plane, tolerance: tolerance).plane.normal
        let admission = try suppliedAdmission ?? CurvedSweepSourceBudget(tolerance: tolerance).conversionAdmission()
        let centroid: Point3D
        if let originalCentroid { centroid = originalCentroid }
        else {
            let loops = try ExactBSplineCurveSpanBuilder(tolerance: tolerance, admission: admission).profileLoopSpans(from: source)
            centroid = try OriginalPipeSectionMoments().centroid(loops: loops,
                plane: originalPlane(source.plane),
                tolerance: tolerance, admission: admission)
        }
        let placement = try RigidTransform3D.followingPath(
            anchor: centroid, referenceDirection: normal.dot(tangent) >= 0 ? normal : normal * -1,
            pathPoint: origin, pathTangent: tangent, tolerance: tolerance
        )
        let turn = try RigidTransform3D.rotated(around: origin, direction: tangent, angle: angle, tolerance: tolerance)
        func point(_ value: Point3D) -> Point3D { turn.applying(to: placement.applying(to: value)) }
        func vector(_ value: Vector3D) -> Vector3D { turn.applying(to: placement.applying(to: value)) }
        func loop(_ value: ProfileLoop) throws -> ProfileLoop {
            ProfileLoop(vertices: value.vertices.map(point), boundarySegments: try value.boundarySegments.map { segment in
                switch segment {
                case let .line(line):
                    return .line(ProfileLineSegment(start: point(line.start), end: point(line.end)))
                case let .circularArc(arc):
                    return .circularArc(ProfileCircularArcSegment(
                        center: point(arc.center), normal: vector(arc.normal), radius: arc.radius,
                        start: point(arc.start), end: point(arc.end), sweepAngle: arc.sweepAngle
                    ))
                case let .spline(spline):
                    let curve = BSplineCurve3D(
                        degree: spline.curve.degree, knots: spline.curve.knots,
                        controlPoints: spline.curve.controlPoints.map(point), weights: spline.curve.weights
                    )
                    try curve.validate(tolerance: tolerance)
                    return .spline(ProfileSplineSegment(curve: curve))
                }
            })
        }
        let placedNormal = vector(normal)
        let placed = Profile(
            sourceFeatureID: featureID,
            plane: .plane(Plane3D(origin: origin, normal: placedNormal)),
            outerLoop: try loop(source.outerLoop),
            innerLoops: try source.innerLoops.map(loop)
        )
        guard let wall else { return [placed] }
        // Each loop walls into a ring of its own: a positive wall away from the region (the outline
        // out, each hole in), a negative one into it.
        let rings = try ExactDraftedProfileBoundaryBuilder(tolerance: tolerance)
            .wallProfiles(from: placed, planeNormal: placedNormal, thickness: abs(wall), outward: wall > 0)
        guard rings.isEmpty == false else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A hollow pipe's custom section makes no ring.")
        }
        return rings
    }

    private func originalPlane(_ plane: SketchPlane) throws -> Plane3D {
        let source: Plane3D
        switch plane {
        case .xy: source = Plane3D(origin: .origin, normal: .unitZ)
        case .yz: source = Plane3D(origin: .origin, normal: .unitX)
        case .zx: source = Plane3D(origin: .origin, normal: .unitY)
        case .plane(let value): source = value
        }
        try source.validate(tolerance: tolerance)
        return source
    }

    package func placedRegion(_ source: ResolvedModelingSection, featureID: FeatureID,
        origin: Point3D, tangent: Vector3D, angle: Double,
        admission: GeometryConversionAdmission) throws -> ResolvedBoundaryRegion {
        let provenance: ResolvedBoundaryRegion.Source
        switch source {
        case .profile(let profile, .profile(let reference)): provenance = .profile(profile, reference)
        case .face(let face, .face(let reference)): provenance = .face(face, reference)
        case .profile, .face, .curve, .constructedRegion:
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "A placed original region requires its actual Profile or Face reference.")
        }
        let plane = try originalPlane(source.plane())
        let spanLoops = try ExactBSplineCurveSpanBuilder(tolerance: tolerance, admission: admission).loopSpans(from: source)
        let centroid = try OriginalPipeSectionMoments().centroid(loops: spanLoops,
            plane: plane, tolerance: tolerance, admission: admission)
        let placement = try RigidTransform3D.followingPath(anchor: centroid,
            referenceDirection: plane.normal.dot(tangent) >= 0 ? plane.normal : plane.normal * -1,
            pathPoint: origin, pathTangent: tangent, tolerance: tolerance)
        let turn = try RigidTransform3D.rotated(around: origin, direction: tangent,
            angle: angle, tolerance: tolerance)
        let facade = try placed(source.profileFacade(), featureID: featureID, origin: origin,
            tangent: tangent, angle: angle, wall: nil, originalCentroid: centroid,
            admission: admission)[0]
        try admission.chargeStorage(bytes: spanLoops.count * MemoryLayout<[OriginalCurveSpanParameterChart]>.stride)
        var loops: [[OriginalCurveSpanParameterChart]] = []
        loops.reserveCapacity(spanLoops.count)
        for spans in spanLoops {
            try admission.chargeStorage(bytes: spans.count * MemoryLayout<OriginalCurveSpanParameterChart>.stride)
            var charts: [OriginalCurveSpanParameterChart] = []
            charts.reserveCapacity(spans.count)
            for span in spans {
                try admission.chargeWork()
                let moved = Curve3D.rigidImage(try RigidImageCurve3D(source: span.originalChart.curve,
                    transform: placement, tolerance: tolerance,
                    remainingSourceDepth: admission.remainingSourceDepth,
                    maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                    consumeWork: { try admission.chargeWork() },
                    consumeStorage: { try admission.chargeStorage(bytes: $0) }))
                let rotated = Curve3D.rigidImage(try RigidImageCurve3D(source: moved,
                    transform: turn, tolerance: tolerance,
                    remainingSourceDepth: admission.remainingSourceDepth,
                    maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                    consumeWork: { try admission.chargeWork() },
                    consumeStorage: { try admission.chargeStorage(bytes: $0) }))
                let owner = try OriginalCurveSpanSource(curve: rotated, tolerance: tolerance, admission: admission)
                charts.append(span.originalChart.replacingSource(owner)
                    .admittingConstruction(admission))
            }
            loops.append(charts)
        }
        try admission.chargeStorage(bytes: 2 * MemoryLayout<RigidTransform3D>.stride)
        return ResolvedBoundaryRegion(source: provenance, profile: facade,
            loops: loops, placement: [placement, turn])
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This deprecated quadrature method is
    // retained only for legacy direct callers; production Pipe placement uses
    // OriginalPipeSectionMoments. General original spline/rational moment
    // certification is required before this numerical result is an authority.
    @available(*, deprecated, message: "Use OriginalPipeSectionMoments with the retained source admission.")
    /// The area centroid of `profile`'s region (holes subtracted) by Green's theorem: closed forms
    /// for lines and arcs, and Gauss–Legendre quadrature over each spline's knot spans, exact for
    /// polynomial splines.
    package func areaCentroid(of profile: Profile, normal: Vector3D) throws -> Point3D {
        let seed: Vector3D = abs(normal.x) < 0.6 ? .unitX : .unitY
        let u = try normal.cross(seed).normalized(tolerance: tolerance.distance)
        let v = normal.cross(u)
        let origin = profile.outerLoop.vertices.first ?? .origin
        func planar(_ point: Point3D) -> (x: Double, y: Double) {
            let offset = point - origin
            return (offset.dot(u), offset.dot(v))
        }
        // Twice the area, and the moments ∮x² dy and ∮y² dx.
        var (doubleArea, xMoment, yMoment) = (0.0, 0.0, 0.0)
        for loop in profile.boundaryLoops {
            for segment in loop.boundarySegments {
                switch segment {
                case let .line(line):
                    let (a, b) = (planar(line.start), planar(line.end))
                    doubleArea += a.x * b.y - b.x * a.y
                    xMoment += (b.y - a.y) * (a.x * a.x + a.x * b.x + b.x * b.x) / 3
                    yMoment += (b.x - a.x) * (a.y * a.y + a.y * b.y + b.y * b.y) / 3
                case let .circularArc(arc):
                    let center = planar(arc.center), start = planar(arc.start)
                    let r = arc.radius
                    let lower = atan2(start.y - center.y, start.x - center.x)
                    let upper = lower + arc.sweepAngle * (arc.normal.dot(normal) >= 0 ? 1 : -1)
                    func difference(_ f: (Double) -> Double) -> Double { f(upper) - f(lower) }
                    doubleArea += r * (center.x * difference(sin) + center.y * difference { -cos($0) } + r * (upper - lower))
                    xMoment += r * (center.x * center.x * difference(sin)
                        + 2 * center.x * r * difference { $0 / 2 + sin(2 * $0) / 4 }
                        + r * r * difference { sin($0) - pow(sin($0), 3) / 3 })
                    yMoment -= r * (center.y * center.y * difference { -cos($0) }
                        + 2 * center.y * r * difference { $0 / 2 - sin(2 * $0) / 4 }
                        + r * r * difference { -cos($0) + pow(cos($0), 3) / 3 })
                case let .spline(spline):
                    let curve = spline.curve
                    guard case let .closed(lower, upper) = curve.domain else {
                        throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance,
                                          message: "A custom pipe section's spline has no bounded domain.")
                    }
                    let breaks = ([lower, upper] + curve.knots.filter { $0 > lower && $0 < upper }).sorted()
                    let nodes = [-0.906179845938664, -0.5384693101056831, 0, 0.5384693101056831, 0.906179845938664]
                    let weights = [0.2369268850561891, 0.4786286704993665, 0.5688888888888889, 0.4786286704993665, 0.2369268850561891]
                    for (left, right) in zip(breaks, breaks.dropFirst()) where right - left > 0 {
                        let half = (right - left) / 2
                        for (node, weight) in zip(nodes, weights) {
                            let geometry = try curve.differentialGeometry(at: left + half * (1 + node), tolerance: tolerance)
                            let p = planar(geometry.position)
                            let (dx, dy) = (geometry.firstDerivative.dot(u), geometry.firstDerivative.dot(v))
                            doubleArea += weight * half * (p.x * dy - p.y * dx)
                            xMoment += weight * half * p.x * p.x * dy
                            yMoment += weight * half * p.y * p.y * dx
                        }
                    }
                }
            }
        }
        guard abs(doubleArea) > tolerance.distance * tolerance.distance else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance,
                              message: "A custom pipe section encloses no area.")
        }
        return origin + u * (xMoment / doubleArea) + v * (-yMoment / doubleArea)
    }
}
