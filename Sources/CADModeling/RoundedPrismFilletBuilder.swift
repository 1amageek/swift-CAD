import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Exact all-edge fillet of a convex prism, independent of display sampling.
///
/// The profile the fillet rides is read by `PrismFilletProfile`; this builder only turns it and a
/// radius into surfaces. Every boundary is oriented from one convention: each patch traverses its
/// loop with the solid's interior on the left seen from outside, so a loop shared by two patches
/// runs one way on each.
struct RoundedPrismFilletBuilder {
    let tolerance: ModelingTolerance

    func request(
        bodyID: BodyID,
        radius: Double,
        featureID: FeatureID,
        model: BRepModel
    ) throws -> BRepSewingRequest {
        let profile = try PrismFilletProfile(bodyID: bodyID, model: model, tolerance: tolerance)
        try validate(radius: radius, of: profile)

        let axis = profile.axis
        let height = profile.height
        let segments = profile.segments
        let corners = profile.corners
        let count = segments.count
        let bandHeight = height - 2.0 * radius
        let quarter = Double.pi * 0.5
        let primitives = PrimitiveBRepRequestBuilder(tolerance: tolerance)

        func next(_ index: Int) -> Int { (index + 1) % count }
        // Rotation about the axis, for radial vectors in the cap plane.
        func rotated(_ vector: Vector3D, by angle: Double) -> Vector3D {
            vector * cos(angle) + axis.cross(vector) * sin(angle)
        }

        // Both patches meeting on a boundary read its endpoints from these, so the sewer sees one
        // edge instead of two coincident ones.
        //
        // The foot of each corner's fillet axis sits one radius inside both faces that meet there,
        // which the bisector reaches at `radius / cos(turn / 2)`. At a tangent seam the turn is
        // zero and the foot is simply one radius inward.
        let feet = corners.map { $0.point + $0.bisector * (radius / cos($0.turn * 0.5)) }
        let topFeet = feet.map { $0 + axis * height }
        let lowCenters = feet.map { $0 + axis * radius }
        let highCenters = feet.map { $0 + axis * (height - radius) }
        // Where each segment leaves its corners once they have consumed the radius.
        let entries = (0..<count).map { index in
            corners[index].point
                + segments[index].startTangent * (radius * tan(corners[index].turn * 0.5))
        }
        let exits = (0..<count).map { index -> Point3D in
            let corner = corners[next(index)]
            return corner.point
                + segments[index].endTangent * (-radius * tan(corner.turn * 0.5))
        }

        /// The radial frame of one arc segment, or `nil` where the segment is straight.
        struct ArcFrame {
            let center: Point3D
            let radius: Double
            let sweep: Double
            let startDirection: Vector3D
            let midDirection: Vector3D
            let endDirection: Vector3D
        }
        let arcs = segments.map { segment -> ArcFrame? in
            guard let center = segment.center else { return nil }
            let start = (segment.start - center) * (1.0 / segment.radius)
            return ArcFrame(
                center: center, radius: segment.radius, sweep: segment.sweep,
                startDirection: start,
                midDirection: rotated(start, by: segment.sweep * 0.5),
                endDirection: (segment.end - center) * (1.0 / segment.radius))
        }

        let bottomCap = Surface3D.plane(Plane3D(origin: feet[0], normal: axis * -1.0))
        let topCap = Surface3D.plane(Plane3D(origin: topFeet[0], normal: axis))

        var patches: [BRepSewingFacePatch] = []
        func patch(
            _ id: String, _ surface: Surface3D, _ edges: [BRepSewingEdge]
        ) -> BRepSewingFacePatch {
            .init(
                stableID: id,
                surface: surface,
                orientation: .forward,
                loops: [.init(stableID: id + ":loop", role: .outer, edges: edges)]
            )
        }
        func line(
            _ id: String, _ from: Point3D, _ to: Point3D, _ surface: Surface3D
        ) throws -> BRepSewingEdge {
            let firstUV = try surface.parameterProjection(of: from, tolerance: tolerance)
            let lastUV = try surface.parameterProjection(of: to, tolerance: tolerance)
            let length = (to - from).length
            return try primitives.lineEdge(
                stableID: id, from: from, to: to,
                pcurve: .affine(
                    origin: .init(x: firstUV.u, y: firstUV.v),
                    direction: .init(
                        x: (lastUV.u - firstUV.u) / length, y: (lastUV.v - firstUV.v) / length),
                    startParameter: 0.0, endParameter: length))
        }
        /// A quarter or sector of a cylinder spanning `sweep` from `a` toward `b` about its own
        /// axis, which every fillet surface but the arcs' tori is an instance of.
        func filletCylinder(
            _ id: String, lower: Point3D, upper: Point3D, direction: Vector3D,
            a: Vector3D, b: Vector3D, sweep: Double
        ) throws -> BRepSewingFacePatch {
            let surface = Surface3D.cylinder(
                Cylinder3D(origin: lower, axis: direction, radius: radius))
            let length = (upper - lower).length
            let mid = try (a + b).normalized(tolerance: tolerance.distance)
            let u0 = try surface.parameterProjection(of: lower + a * radius, tolerance: tolerance).u
            let u1 = u0 + sweep
            let low = try primitives.circleEdge(
                stableID: id + ":low",
                definition: .circle(center: lower, normal: direction, radius: radius),
                startPoint: lower + a * radius,
                midpoint: lower + mid * radius,
                endPoint: lower + b * radius,
                pcurve: { _, _ in .constantV(v: 0.0, uStart: u0, uEnd: u1) })
            let up = try primitives.lineEdge(
                stableID: id + ":up", from: lower + b * radius, to: upper + b * radius,
                pcurve: .constantU(u: u1, vStart: 0.0, vEnd: length))
            let high = try primitives.circleEdge(
                stableID: id + ":high",
                definition: .circle(center: upper, normal: direction, radius: radius),
                startPoint: upper + b * radius,
                midpoint: upper + mid * radius,
                endPoint: upper + a * radius,
                pcurve: { _, _ in .constantV(v: length, uStart: u1, uEnd: u0) })
            let down = try primitives.lineEdge(
                stableID: id + ":down", from: upper + a * radius, to: lower + a * radius,
                pcurve: .constantU(u: u0, vStart: length, vEnd: 0.0))
            return patch(id, surface, [low, up, high, down])
        }
        /// An octant of a sphere bounded by three great arcs through the given directions, whose
        /// order is already right-handed.
        func filletSphere(
            _ id: String, center: Point3D, directions: [Vector3D]
        ) throws -> BRepSewingFacePatch {
            let surface = Surface3D.analytic(.sphere(center: center, radius: radius))
            let boundary = try (0..<3).map { index -> BRepSewingEdge in
                let a = directions[index]
                let b = directions[(index + 1) % 3]
                return try primitives.sphereCircleEdge(
                    stableID: id + ":\(index)",
                    definition: .circle(
                        center: center,
                        normal: try a.cross(b).normalized(tolerance: tolerance.distance),
                        radius: radius),
                    center: center,
                    startPoint: center + a * radius,
                    midpoint: center
                        + (try (a + b).normalized(tolerance: tolerance.distance)) * radius,
                    endPoint: center + b * radius)
            }
            return patch(id, surface, boundary)
        }

        // Each segment keeps its own surface between the two cap fillets, inset by the radius at
        // top and bottom and trimmed at each end by what its corners consume.
        for index in 0..<count {
            let id = "prism-fillet:lateral:\(index)"
            let lowStart = entries[index] + axis * radius
            let lowEnd = exits[index] + axis * radius
            let highEnd = exits[index] + axis * (height - radius)
            let highStart = entries[index] + axis * (height - radius)
            guard let arc = arcs[index] else {
                let surface = Surface3D.plane(
                    Plane3D(origin: lowStart, normal: corners[index].inwardAfter * -1.0))
                patches.append(patch(id, surface, [
                    try line(id + ":low", lowStart, lowEnd, surface),
                    try line(id + ":up", lowEnd, highEnd, surface),
                    try line(id + ":high", highEnd, highStart, surface),
                    try line(id + ":down", highStart, lowStart, surface)]))
                continue
            }
            let lowCenter = arc.center + axis * radius
            let highCenter = arc.center + axis * (height - radius)
            let surface = Surface3D.cylinder(
                Cylinder3D(origin: lowCenter, axis: axis, radius: arc.radius))
            let u0 = try surface.parameterProjection(of: lowStart, tolerance: tolerance).u
            let u1 = u0 + arc.sweep
            let low = try primitives.circleEdge(
                stableID: id + ":low",
                definition: .circle(center: lowCenter, normal: axis, radius: arc.radius),
                startPoint: lowStart,
                midpoint: lowCenter + arc.midDirection * arc.radius,
                endPoint: lowEnd,
                pcurve: { _, _ in .constantV(v: 0.0, uStart: u0, uEnd: u1) })
            let up = try primitives.lineEdge(
                stableID: id + ":up", from: lowEnd, to: highEnd,
                pcurve: .constantU(u: u1, vStart: 0.0, vEnd: bandHeight))
            let high = try primitives.circleEdge(
                stableID: id + ":high",
                definition: .circle(center: highCenter, normal: axis, radius: arc.radius),
                startPoint: highEnd,
                midpoint: highCenter + arc.midDirection * arc.radius,
                endPoint: highStart,
                pcurve: { _, _ in .constantV(v: bandHeight, uStart: u1, uEnd: u0) })
            let down = try primitives.lineEdge(
                stableID: id + ":down", from: highStart, to: lowStart,
                pcurve: .constantU(u: u0, vStart: bandHeight, vEnd: 0.0))
            patches.append(patch(id, surface, [low, up, high, down]))
        }

        // The two inset caps, each traversed against the fillets that surround it: the bottom
        // against the profile's winding and the top with it.
        var bottomCapEdges: [BRepSewingEdge] = []
        for step in 0..<count {
            let index = count - 1 - step
            let id = "prism-fillet:cap:bottom:\(index)"
            guard let arc = arcs[index] else {
                bottomCapEdges.append(try line(id, feet[next(index)], feet[index], bottomCap))
                continue
            }
            let rim = AnalyticCurve3D.circle(
                center: arc.center, normal: axis, radius: arc.radius - radius)
            bottomCapEdges.append(try primitives.circleEdge(
                stableID: id, definition: rim,
                startPoint: feet[next(index)],
                midpoint: arc.center + arc.midDirection * (arc.radius - radius),
                endPoint: feet[index],
                pcurve: { start, end in
                    try primitives.planarHarmonicPcurve(
                        curve: .analytic(rim), center: arc.center,
                        startParameter: start, endParameter: end, surface: bottomCap)
                }))
        }
        patches.append(patch("prism-fillet:cap:bottom", bottomCap, bottomCapEdges))

        var topCapEdges: [BRepSewingEdge] = []
        for index in 0..<count {
            let id = "prism-fillet:cap:top:\(index)"
            guard let arc = arcs[index] else {
                topCapEdges.append(try line(id, topFeet[index], topFeet[next(index)], topCap))
                continue
            }
            let center = arc.center + axis * height
            let rim = AnalyticCurve3D.circle(
                center: center, normal: axis, radius: arc.radius - radius)
            topCapEdges.append(try primitives.circleEdge(
                stableID: id, definition: rim,
                startPoint: topFeet[index],
                midpoint: center + arc.midDirection * (arc.radius - radius),
                endPoint: topFeet[next(index)],
                pcurve: { start, end in
                    try primitives.planarHarmonicPcurve(
                        curve: .analytic(rim), center: center,
                        startParameter: start, endParameter: end, surface: topCap)
                }))
        }
        patches.append(patch("prism-fillet:cap:top", topCap, topCapEdges))

        // Each segment blends into both caps. A straight run rolls the ball along itself, which
        // sweeps a quarter cylinder about the segment; an arc rolls it around the arc's own
        // center, which sweeps a quarter of a torus instead.
        for index in 0..<count {
            guard let arc = arcs[index] else {
                let tangent = segments[index].startTangent
                let inward = corners[index].inwardAfter
                // `(-inward) x (-axis) . tangent` and `axis x (-inward) . tangent` are both one,
                // so each pair is already right-handed about the segment it rides.
                patches.append(try filletCylinder(
                    "prism-fillet:bottom:\(index)",
                    lower: lowCenters[index], upper: lowCenters[next(index)],
                    direction: tangent, a: inward * -1.0, b: axis * -1.0, sweep: quarter))
                patches.append(try filletCylinder(
                    "prism-fillet:top:\(index)",
                    lower: highCenters[index], upper: highCenters[next(index)],
                    direction: tangent, a: axis, b: inward * -1.0, sweep: quarter))
                continue
            }
            let innerRadius = arc.radius - radius
            func meridian(_ center: Point3D, _ direction: Vector3D) throws -> AnalyticCurve3D {
                .circle(
                    center: center + direction * innerRadius,
                    normal: try axis.cross(direction).normalized(tolerance: tolerance.distance),
                    radius: radius)
            }
            func meridianPoint(
                _ center: Point3D, _ direction: Vector3D, _ v: Double
            ) -> Point3D {
                center + direction * (innerRadius + radius * cos(v)) + axis * (radius * sin(v))
            }
            let lowCenter = arc.center + axis * radius
            let highCenter = arc.center + axis * (height - radius)
            let lowBand = AnalyticCurve3D.circle(
                center: lowCenter, normal: axis, radius: arc.radius)
            let highBand = AnalyticCurve3D.circle(
                center: highCenter, normal: axis, radius: arc.radius)
            let lowStart = segments[index].start + axis * radius
            let lowEnd = segments[index].end + axis * radius
            let highStart = segments[index].start + axis * (height - radius)
            let highEnd = segments[index].end + axis * (height - radius)

            let bottomTorus = Surface3D.analytic(.torus(
                center: lowCenter, axis: axis,
                majorRadius: innerRadius, minorRadius: radius))
            let bottomID = "prism-fillet:bottom:\(index)"
            let bottomU0 = try bottomTorus.parameterProjection(
                of: lowStart, tolerance: tolerance).u
            let bottomU1 = bottomU0 + arc.sweep
            let bottomV0 = Double.pi * 1.5
            let bottomV1 = Double.pi * 2.0
            let bottomRim = AnalyticCurve3D.circle(
                center: arc.center, normal: axis, radius: innerRadius)
            patches.append(patch(bottomID, bottomTorus, [
                try primitives.circleEdge(
                    stableID: bottomID + ":rim", definition: bottomRim,
                    startPoint: feet[index],
                    midpoint: arc.center + arc.midDirection * innerRadius,
                    endPoint: feet[next(index)],
                    pcurve: { _, _ in
                        .constantV(v: bottomV0, uStart: bottomU0, uEnd: bottomU1) }),
                try primitives.circleEdge(
                    stableID: bottomID + ":end",
                    definition: try meridian(lowCenter, arc.endDirection),
                    startPoint: feet[next(index)],
                    midpoint: meridianPoint(
                        lowCenter, arc.endDirection, (bottomV0 + bottomV1) * 0.5),
                    endPoint: lowEnd,
                    pcurve: { _, _ in
                        .constantU(u: bottomU1, vStart: bottomV0, vEnd: bottomV1) }),
                try primitives.circleEdge(
                    stableID: bottomID + ":band", definition: lowBand,
                    startPoint: lowEnd,
                    midpoint: lowCenter + arc.midDirection * arc.radius,
                    endPoint: lowStart,
                    pcurve: { _, _ in
                        .constantV(v: bottomV1, uStart: bottomU1, uEnd: bottomU0) }),
                try primitives.circleEdge(
                    stableID: bottomID + ":start",
                    definition: try meridian(lowCenter, arc.startDirection),
                    startPoint: lowStart,
                    midpoint: meridianPoint(
                        lowCenter, arc.startDirection, (bottomV0 + bottomV1) * 0.5),
                    endPoint: feet[index],
                    pcurve: { _, _ in
                        .constantU(u: bottomU0, vStart: bottomV1, vEnd: bottomV0) })]))

            let topTorus = Surface3D.analytic(.torus(
                center: highCenter, axis: axis,
                majorRadius: innerRadius, minorRadius: radius))
            let topID = "prism-fillet:top:\(index)"
            let topU0 = try topTorus.parameterProjection(of: highStart, tolerance: tolerance).u
            let topU1 = topU0 + arc.sweep
            let topV0 = 0.0
            let topV1 = Double.pi * 0.5
            let topRim = AnalyticCurve3D.circle(
                center: arc.center + axis * height, normal: axis, radius: innerRadius)
            patches.append(patch(topID, topTorus, [
                try primitives.circleEdge(
                    stableID: topID + ":band", definition: highBand,
                    startPoint: highStart,
                    midpoint: highCenter + arc.midDirection * arc.radius,
                    endPoint: highEnd,
                    pcurve: { _, _ in .constantV(v: topV0, uStart: topU0, uEnd: topU1) }),
                try primitives.circleEdge(
                    stableID: topID + ":end",
                    definition: try meridian(highCenter, arc.endDirection),
                    startPoint: highEnd,
                    midpoint: meridianPoint(
                        highCenter, arc.endDirection, (topV0 + topV1) * 0.5),
                    endPoint: topFeet[next(index)],
                    pcurve: { _, _ in .constantU(u: topU1, vStart: topV0, vEnd: topV1) }),
                try primitives.circleEdge(
                    stableID: topID + ":rim", definition: topRim,
                    startPoint: topFeet[next(index)],
                    midpoint: arc.center + axis * height + arc.midDirection * innerRadius,
                    endPoint: topFeet[index],
                    pcurve: { _, _ in .constantV(v: topV1, uStart: topU1, uEnd: topU0) }),
                try primitives.circleEdge(
                    stableID: topID + ":start",
                    definition: try meridian(highCenter, arc.startDirection),
                    startPoint: topFeet[index],
                    midpoint: meridianPoint(
                        highCenter, arc.startDirection, (topV0 + topV1) * 0.5),
                    endPoint: highStart,
                    pcurve: { _, _ in .constantU(u: topU0, vStart: topV1, vEnd: topV0) })]))
        }

        // A corner that turns carries a vertical fillet between the two lateral faces and a sphere
        // at each end of it. A tangent seam turns by nothing and carries neither: the two cap
        // fillets already meet there on one shared circle.
        for index in 0..<count where corners[index].turn > 0 {
            let before = corners[index].inwardBefore * -1.0
            let after = corners[index].inwardAfter * -1.0
            // `(-inwardBefore) x (-inwardAfter) . axis` is `sin(turn)`, so the pair is
            // right-handed about the axis for every turn the profile admits.
            patches.append(try filletCylinder(
                "prism-fillet:corner:\(index)",
                lower: lowCenters[index], upper: highCenters[index],
                direction: axis, a: before, b: after, sweep: corners[index].turn))
            patches.append(try filletSphere(
                "prism-fillet:corner:bottom:\(index)",
                center: lowCenters[index], directions: [axis * -1.0, after, before]))
            patches.append(try filletSphere(
                "prism-fillet:corner:top:\(index)",
                center: highCenters[index], directions: [axis, before, after]))
        }

        return .init(
            featureID: featureID,
            bodyKind: .solid,
            shells: [.init(stableID: "prism-fillet:shell", patches: patches)]
        )
    }

    /// Every bound the surfaces need is checked before any of them is built, so a radius the
    /// domain cannot carry is refused here rather than failing partway through construction.
    private func validate(radius: Double, of profile: PrismFilletProfile) throws {
        guard radius.isFinite, radius > tolerance.distance,
              profile.height - 2.0 * radius > tolerance.distance else {
            throw invalid(
                "Prism fillet radius must be positive and below half the prism height.")
        }
        for index in profile.segments.indices {
            let segment = profile.segments[index]
            if segment.center != nil {
                // The arc's rim rides a torus whose center circle `radius - r` must clear its
                // tube `r`, exactly as a cylinder's does.
                guard segment.radius - 2.0 * radius > tolerance.distance else {
                    throw invalid(
                        "Prism fillet radius must stay below half the radius of every cap arc.")
                }
                continue
            }
            let start = profile.corners[index]
            let end = profile.corners[(index + 1) % profile.corners.count]
            let consumed = radius * (tan(start.turn * 0.5) + tan(end.turn * 0.5))
            guard (segment.end - segment.start).length - consumed > tolerance.distance else {
                throw invalid(
                    "Prism fillet radius must leave every cap segment a positive trimmed length.")
            }
        }
    }

    private func invalid(_ message: String) -> KernelError {
        .init(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: message)
    }
}
