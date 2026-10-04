import Foundation
import CADCore
import CADGeometry
import CADTopology

/// Bridge Surface's walls for two curved sheets, each one untrimmed spline face: both sheets
/// continued past their boundaries (natural extension), and along each isoline running into a
/// sheet from its edge nearest the other sheet, the point where the continued sheets meet and the
/// contact `width` from it, measured along the isoline into the sheet. Each wall becomes its
/// continued surface from its far edge to its contact curve — cut back when the contact lies on
/// the sheet, carried on when it lies past the sheet's edge — so the bridge set back by the width
/// from where the sheets meet starts on each wall's own edge.
package struct CurvedSheetBridgeWalls {
    package struct Wall {
        package let patch: BRepSewingFacePatch
        /// The contact edge's middle, which finds it again once the wall is sewn.
        package let contactMiddle: Point3D
    }

    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// One sheet as this builder takes it: its face's spline, orientation, parameter box and the
    /// face's parents.
    private struct Sheet {
        let surface: BSplineSurface3D
        let orientation: Orientation
        let u: ClosedRange<Double>
        let v: ClosedRange<Double>
        let parents: [SubshapeID]
        /// The sense its loop winds in its parameters (+1 counterclockwise), which a wall keeps.
        let winding: Double

        func corners() -> [(Double, Double)] {
            [(u.lowerBound, v.lowerBound), (u.upperBound, v.lowerBound), (u.upperBound, v.upperBound), (u.lowerBound, v.upperBound)]
        }
    }

    /// A side of a sheet's parameter box: the parameter running along it, the other's value on it,
    /// and the sense (+1 or −1) of that other parameter running into the sheet.
    private struct Side {
        let alongU: Bool
        let boundary: Double
        let inward: Double
        let along: ClosedRange<Double>
        let far: Double

        func parameters(along a: Double, across c: Double) -> (u: Double, v: Double) {
            alongU ? (a, c) : (c, a)
        }
    }

    /// The two walls, or nil when either sheet is not one untrimmed spline face, or their
    /// continuations do not meet across every isoline of both sheets' nearest edges.
    package func walls(first: BodyID, second: BodyID, width: Double, featureID: FeatureID,
                       context: EvaluationContext) throws -> (first: Wall, second: Wall)? {
        guard let a = try sheet(first, context: context), let b = try sheet(second, context: context) else { return nil }
        // The sides nearest each other, by their middles.
        let sidesA = sides(of: a), sidesB = sides(of: b)
        var best: (Side, Side, Double)?
        for sideA in sidesA {
            let ma = try middle(of: sideA, on: a)
            for sideB in sidesB {
                let gap = (ma - (try middle(of: sideB, on: b))).length
                if best.map({ gap < $0.2 }) ?? true { best = (sideA, sideB, gap) }
            }
        }
        guard let (sideA, sideB, _) = best else { return nil }
        let extendedA = try continued(a), extendedB = try continued(b)
        guard let wallA = try wall(a, side: sideA, extended: extendedA, other: (b, sideB, extendedB), width: width,
                                   stableID: "bridgeSurface:wall:0", featureID: featureID),
              let wallB = try wall(b, side: sideB, extended: extendedB, other: (a, sideA, extendedA), width: width,
                                   stableID: "bridgeSurface:wall:1", featureID: featureID) else { return nil }
        return (wallA, wallB)
    }

    // MARK: - Sheets

    private func sheet(_ bodyID: BodyID, context: EvaluationContext) throws -> Sheet? {
        let model = context.brep
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        let faces = scope.references.compactMap { reference -> FaceID? in
            if case let .face(id) = reference { return id }
            return nil
        }
        guard faces.count == 1, let face = model.faces[faces[0]], face.loops.count == 1,
              case let .bSpline(surface)? = model.geometry.surfaces[face.surfaceID],
              let loop = model.loops[face.loops[0]], loop.coedges.count == 4,
              let u0 = surface.uKnots.first, let u1 = surface.uKnots.last, let v0 = surface.vKnots.first, let v1 = surface.vKnots.last else {
            return nil
        }
        // Untrimmed: its four corners are the spline's.
        let corners = try [(u0, v0), (u1, v0), (u1, v1), (u0, v1)].map { try Surface3D.bSpline(surface).point(u: $0.0, v: $0.1, tolerance: tolerance) }
        let vertices = try loop.coedges.map { coedge -> Point3D in
            guard let edge = model.edges[coedge.edgeID], let point = model.vertices[edge.startVertexID]?.point else {
                throw TopologyError.missingReference("A bridged sheet's edge is missing.")
            }
            return point
        }
        guard corners.allSatisfy({ corner in vertices.contains { $0.isApproximatelyEqual(to: corner, tolerance: tolerance.distance) } }) else {
            return nil
        }
        var area = 0.0
        let samples = try loop.coedges.flatMap { coedge -> [SurfaceParameter] in
            guard let pcurve = coedge.surfaceParameterCurve else { throw TopologyError.missingReference("A bridged sheet's edge has no trimming curve.") }
            return try (0..<8).map { try pcurve.parameter(atNormalizedFraction: Double($0) / 8, tolerance: tolerance) }
        }
        for (p, q) in zip(samples, samples.dropFirst() + samples.prefix(1)) { area += p.u * q.v - q.u * p.v }
        return Sheet(surface: surface, orientation: face.orientation, u: u0...u1, v: v0...v1,
                     parents: context.subshapeIDs(for: .face(faces[0])), winding: area >= 0 ? 1 : -1)
    }

    private func sides(of sheet: Sheet) -> [Side] {
        [Side(alongU: true, boundary: sheet.v.lowerBound, inward: 1, along: sheet.u, far: sheet.v.upperBound),
         Side(alongU: true, boundary: sheet.v.upperBound, inward: -1, along: sheet.u, far: sheet.v.lowerBound),
         Side(alongU: false, boundary: sheet.u.lowerBound, inward: 1, along: sheet.v, far: sheet.u.upperBound),
         Side(alongU: false, boundary: sheet.u.upperBound, inward: -1, along: sheet.v, far: sheet.u.lowerBound)]
    }

    private func middle(of side: Side, on sheet: Sheet) throws -> Point3D {
        let (u, v) = side.parameters(along: (side.along.lowerBound + side.along.upperBound) / 2, across: side.boundary)
        return try Surface3D.bSpline(sheet.surface).point(u: u, v: v, tolerance: tolerance)
    }

    /// The sheet's spline continued past all four boundaries by its own parameter spans. A
    /// single-span (Bézier) sheet is the same polynomial over the wider box, its control points
    /// blossomed there, so it keeps no knot inside; a sheet of several spans is joined to its
    /// natural extensions, its old end knots left inside.
    private func continued(_ sheet: Sheet) throws -> Surface3D {
        let spans = (u: sheet.u.upperBound - sheet.u.lowerBound, v: sheet.v.upperBound - sheet.v.lowerBound)
        let surface = sheet.surface
        guard Set(surface.uKnots).count == 2, Set(surface.vKnots).count == 2 else {
            return .bSpline(try BSplineSurfaceBoundaryExtender().continued(surface, by: spans, tolerance: tolerance))
        }
        /// A Bézier row's homogeneous control points over [a, b] re-expressed over [a', b'].
        func widened(_ row: [[Double]], from a: Double, _ b: Double, to a2: Double, _ b2: Double) -> [[Double]] {
            let degree = row.count - 1
            func blossom(_ arguments: [Double]) -> [Double] {
                var points = row
                for (level, argument) in arguments.enumerated() {
                    let t = (argument - a) / (b - a)
                    for index in 0..<(degree - level) {
                        points[index] = zip(points[index], points[index + 1]).map { $0 * (1 - t) + $1 * t }
                    }
                }
                return points[0]
            }
            return (0...degree).map { k in blossom(Array(repeating: a2, count: degree - k) + Array(repeating: b2, count: k)) }
        }
        // Homogeneous control points [v][u] -> (w x, w y, w z, w).
        var grid = surface.controlPoints.enumerated().map { j, row in
            row.enumerated().map { i, point -> [Double] in
                let w = surface.weights[j][i]
                return [point.x * w, point.y * w, point.z * w, w]
            }
        }
        let (u0, u1, v0, v1) = (sheet.u.lowerBound, sheet.u.upperBound, sheet.v.lowerBound, sheet.v.upperBound)
        let (nu0, nu1, nv0, nv1) = (u0 - spans.u, u1 + spans.u, v0 - spans.v, v1 + spans.v)
        grid = grid.map { widened($0, from: u0, u1, to: nu0, nu1) }
        let columns = (0..<grid[0].count).map { i in widened(grid.map { $0[i] }, from: v0, v1, to: nv0, nv1) }
        grid = (0..<columns[0].count).map { j in columns.map { $0[j] } }
        let points = grid.map { row in row.map { Point3D(x: $0[0] / $0[3], y: $0[1] / $0[3], z: $0[2] / $0[3]) } }
        let weights = grid.map { row in row.map { $0[3] } }
        let wide = BSplineSurface3D(uDegree: surface.uDegree, vDegree: surface.vDegree,
                                    uKnots: Array(repeating: nu0, count: surface.uDegree + 1) + Array(repeating: nu1, count: surface.uDegree + 1),
                                    vKnots: Array(repeating: nv0, count: surface.vDegree + 1) + Array(repeating: nv1, count: surface.vDegree + 1),
                                    controlPoints: points, weights: weights)
        try wide.validate(tolerance: tolerance)
        return .bSpline(wide)
    }

    // MARK: - Contacts

    /// Where the isoline at `a` of `side` meets the other continued sheet: its cross parameter on
    /// this sheet and the meeting's parameters on the other, Newton on A(a, c) = B(s, t) from `seed`.
    private func meeting(at a: Double, side: Side, on surface: Surface3D, other: Surface3D,
                         seed: (c: Double, s: Double, t: Double)) throws -> (c: Double, s: Double, t: Double)? {
        var (c, s, t) = seed
        for _ in 0..<64 {
            let (u, v) = side.parameters(along: a, across: c)
            let here = try surface.differentialGeometry(u: u, v: v, tolerance: tolerance)
            let there = try other.differentialGeometry(u: s, v: t, tolerance: tolerance)
            let f = here.position - there.position
            if f.length <= tolerance.distance * 1e-4 { return (c, s, t) }
            let dc = side.alongU ? here.tangentV : here.tangentU
            let (ds, dt) = (there.tangentU * -1, there.tangentV * -1)
            // Solve [dc ds dt] x = −f.
            let determinant = dc.dot(ds.cross(dt))
            guard abs(determinant) > 1e-30 else { return nil }
            let x = (f * -1).dot(ds.cross(dt)) / determinant
            let y = dc.dot((f * -1).cross(dt)) / determinant
            let z = dc.dot(ds.cross(f * -1)) / determinant
            (c, s, t) = (c + x, s + y, t + z)
            guard c.isFinite, s.isFinite, t.isFinite else { return nil }
        }
        return nil
    }

    /// The cross parameter `width` along the isoline at `a` from `start` into the sheet: the arc
    /// length by eight-point Gauss on the isoline's speed, Newton on it.
    private func contact(at a: Double, from start: Double, side: Side, on surface: Surface3D, width: Double) throws -> Double {
        func speed(_ c: Double) throws -> Double {
            let (u, v) = side.parameters(along: a, across: c)
            let jet = try surface.differentialGeometry(u: u, v: v, tolerance: tolerance)
            return (side.alongU ? jet.tangentV : jet.tangentU).length
        }
        let nodes = [-0.9602898564975363, -0.7966664774136267, -0.5255324099163290, -0.1834346424956498,
                     0.1834346424956498, 0.5255324099163290, 0.7966664774136267, 0.9602898564975363]
        let weights = [0.1012285362903763, 0.2223810344533745, 0.3137066458778873, 0.3626837833783620,
                       0.3626837833783620, 0.3137066458778873, 0.2223810344533745, 0.1012285362903763]
        func arc(_ c: Double) throws -> Double {
            var total = 0.0
            for (node, weight) in zip(nodes, weights) {
                total += weight * (try speed(start + (c - start) * (node + 1) / 2))
            }
            return abs(c - start) / 2 * total
        }
        var c = start + side.inward * width / max(try speed(start), 1e-300)
        for _ in 0..<32 {
            let error = try arc(c) - width
            if abs(error) <= tolerance.distance * 1e-4 { return c }
            c -= side.inward * error / max(try speed(c), 1e-300)
        }
        guard abs(try arc(c) - width) <= tolerance.distance / 8 else {
            throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                              message: "A Bridge Surface's contact could not be set the width from where the sheets meet.")
        }
        return c
    }

    // MARK: - Walls

    private func wall(_ sheet: Sheet, side: Side, extended: Surface3D,
                      other: (sheet: Sheet, side: Side, extended: Surface3D), width: Double,
                      stableID: String, featureID: FeatureID) throws -> Wall? {
        // The meeting along the middle isoline, sought from the boundary and the other sheet's
        // nearest side's middle, then carried along the side isoline by isoline.
        let middleA = (side.along.lowerBound + side.along.upperBound) / 2
        let otherMiddle = other.side.parameters(along: (other.side.along.lowerBound + other.side.along.upperBound) / 2,
                                                across: other.side.boundary)
        guard let first = try meeting(at: middleA, side: side, on: extended, other: other.extended,
                                      seed: (side.boundary, otherMiddle.u, otherMiddle.v)) else { return nil }
        let count = 32
        var meetings: [Double: (c: Double, s: Double, t: Double)] = [middleA: first]
        var seeds = (lower: first, upper: first)
        for step in 1...(count / 2) {
            let fraction = Double(step) / Double(count / 2)
            let (lower, upper) = (middleA - (middleA - side.along.lowerBound) * fraction, middleA + (side.along.upperBound - middleA) * fraction)
            guard let below = try meeting(at: lower, side: side, on: extended, other: other.extended, seed: seeds.lower),
                  let above = try meeting(at: upper, side: side, on: extended, other: other.extended, seed: seeds.upper) else { return nil }
            (meetings[lower], meetings[upper]) = (below, above)
            seeds = (below, above)
        }
        /// The contact's cross parameter at `a`, from the meeting found nearest it.
        func contactParameter(_ a: Double) throws -> Double {
            guard let nearest = meetings.min(by: { abs($0.key - a) < abs($1.key - a) })?.value,
                  let found = try meeting(at: a, side: side, on: extended, other: other.extended, seed: nearest) else {
                throw KernelError(phase: .geometry, code: .classificationFailure, featureID: featureID, tolerance: tolerance,
                                  message: "A Bridge Surface's sheets stop meeting along a wall's edge.")
            }
            // The meeting must lie on the continuation, not run off along the other sheet.
            return try contact(at: a, from: found.c, side: side, on: extended, width: width)
        }
        // The contact must stay between the meeting and the far edge.
        let middleContact = try contactParameter(middleA)
        guard (side.far - middleContact) * side.inward > tolerance.distance else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A bridged sheet does not reach the bridge's width from where the sheets meet.")
        }
        let parameterFitter = try SpatialCurveFitter(deviation: tolerance.distance / 64)
        let curveFitter = try SpatialCurveFitter(deviation: tolerance.distance / 8)
        func along(_ t: Double) -> Double { side.along.lowerBound + (side.along.upperBound - side.along.lowerBound) * t }
        // The contact's trimming curve and its edge.
        let contactPcurve = try parameterFitter.fitBSpline(breakpoints: [0, 1], tolerance: tolerance) { t in
            let a = along(t)
            let (u, v) = side.parameters(along: a, across: try contactParameter(a))
            return Point3D(x: u, y: v, z: 0)
        }.curve
        let contact2D = BSplineCurve2D(degree: contactPcurve.degree, knots: contactPcurve.knots,
                                       controlPoints: contactPcurve.controlPoints.map { Point2D(x: $0.x, y: $0.y) })
        let contactCurve = try curveFitter.fitBSpline(breakpoints: [0, 1], tolerance: tolerance) { t in
            let uv = try SurfaceParameterCurve.bSpline(contact2D).parameter(atNormalizedFraction: t, tolerance: self.tolerance)
            return try extended.point(u: uv.u, v: uv.v, tolerance: self.tolerance)
        }.curve
        let (contactStart, contactEnd) = (try contactParameter(side.along.lowerBound), try contactParameter(side.along.upperBound))
        /// An isoline of the continued surface between two parameter points, with its edge.
        func isoEdge(_ name: String, from p: (u: Double, v: Double), to q: (u: Double, v: Double)) throws -> BRepSewingEdge {
            let curve = try curveFitter.fitBSpline(breakpoints: [0, 1], tolerance: tolerance) { t in
                try extended.point(u: p.u + (q.u - p.u) * t, v: p.v + (q.v - p.v) * t, tolerance: self.tolerance)
            }.curve
            return BRepSewingEdge(stableID: "\(stableID):\(name)", curve: .bSpline(curve), startParameter: 0, endParameter: 1,
                                  startPoint: try extended.point(u: p.u, v: p.v, tolerance: tolerance),
                                  endPoint: try extended.point(u: q.u, v: q.v, tolerance: tolerance),
                                  surfaceParameterCurve: .polyline([SurfaceParameter(u: p.u, v: p.v), SurfaceParameter(u: q.u, v: q.v)]))
        }
        // The loop: the contact from the side's lower end to its upper, up the upper lateral to
        // the far edge, back along it, and down the lower lateral.
        let lowerContact = side.parameters(along: side.along.lowerBound, across: contactStart)
        let upperContact = side.parameters(along: side.along.upperBound, across: contactEnd)
        let upperFar = side.parameters(along: side.along.upperBound, across: side.far)
        let lowerFar = side.parameters(along: side.along.lowerBound, across: side.far)
        let contactEdge = BRepSewingEdge(stableID: "\(stableID):contact", curve: .bSpline(contactCurve), startParameter: 0, endParameter: 1,
                                         startPoint: try extended.point(u: lowerContact.u, v: lowerContact.v, tolerance: tolerance),
                                         endPoint: try extended.point(u: upperContact.u, v: upperContact.v, tolerance: tolerance),
                                         surfaceParameterCurve: .bSpline(contact2D))
        var edges = [contactEdge,
                     try isoEdge("upper", from: upperContact, to: upperFar),
                     try isoEdge("far", from: upperFar, to: lowerFar),
                     try isoEdge("lower", from: lowerFar, to: lowerContact)]
        // The wall's loop winds as the sheet's did.
        var area = 0.0
        let samples = try edges.flatMap { edge in
            try (0..<8).map { try edge.surfaceParameterCurve.parameter(atNormalizedFraction: Double($0) / 8, tolerance: tolerance) }
        }
        for (p, q) in zip(samples, samples.dropFirst() + samples.prefix(1)) { area += p.u * q.v - q.u * p.v }
        if (area >= 0 ? 1.0 : -1.0) != sheet.winding { edges = try edges.reversed().map(reversed) }
        let patch = BRepSewingFacePatch(stableID: stableID, surface: extended, orientation: sheet.orientation,
                                        loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: edges)],
                                        parentSubshapeIDs: sheet.parents)
        return Wall(patch: patch, contactMiddle: try contactCurve.point(at: 0.5, tolerance: tolerance))
    }

    private func reversed(_ edge: BRepSewingEdge) throws -> BRepSewingEdge {
        BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.endParameter, endParameter: edge.startParameter,
                       startPoint: edge.endPoint, endPoint: edge.startPoint,
                       surfaceParameterCurve: try edge.surfaceParameterCurve.reversed(tolerance: tolerance),
                       parentSubshapeIDs: edge.parentSubshapeIDs)
    }
}
