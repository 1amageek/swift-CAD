import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Draft Face's Grow for a planar face whose re-solve in place runs into another wall: the
/// material between the face's old plane and its drafted plane, as a prism along the pivot line,
/// united with the body as the drafted face moves out of it.
///
/// In the section square to the pivot line the prism is the wedge at the pivot between the old
/// face and the drafted face, bounded by what Grow lets the drafted face reach:
///
/// | Grow   | Wedge bounded by                                   | Along the pivot line |
/// |--------|----------------------------------------------------|----------------------|
/// | Moving | the body's far extent along the face (its bottom)  | the body's extent    |
/// | Fixed  | the body's extents along the face and across it    | the face's extent    |
///
/// The wedge also takes a thin column of the body's own material behind the old face, so no face
/// of the wedge lies on the old face's plane: the exact Boolean cannot yet unite a tool face that
/// covers a body face and runs on into the body's inside. The column is certified to cross no
/// face of the body, which leaves the union unchanged.
package struct FaceDraftGrowWedgeBuilder {
    package struct Wedge: Sendable {
        /// The prism's section, a convex polygon in the plane square to `axis` through its base.
        package var polygon: [Point3D]
        package var axis: Vector3D
        package var length: Double
    }

    package struct Face: Sendable {
        package var faceID: FaceID
        package var outward: Vector3D
        package var normal: Vector3D
        package var draftedNormal: Vector3D
        /// A point on the pivot line, where the face's plane crosses the neutral plane.
        package var pivot: Point3D
        package var axis: Vector3D
        package var pull: Vector3D

        package init(faceID: FaceID, outward: Vector3D, normal: Vector3D, draftedNormal: Vector3D, pivot: Point3D, axis: Vector3D, pull: Vector3D) {
            self.faceID = faceID
            self.outward = outward
            self.normal = normal
            self.draftedNormal = draftedNormal
            self.pivot = pivot
            self.axis = axis
            self.pull = pull
        }
    }

    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The wedge to unite with the body for `face` under `grow`, or nil when Grow's wedge does not
    /// cover it: a face not starting at the pivot line on one side of it, or one moving into the
    /// body.
    package func wedge(for face: Face, grow: FaceEditGrow, bodyID: BodyID, model: BRepModel, featureID: FeatureID) throws -> Wedge? {
        let axis = try face.axis.normalized(tolerance: tolerance.distance)
        let pull = try (face.pull - axis * face.pull.dot(axis)).normalized(tolerance: tolerance.distance)
        let across = axis.cross(pull)
        guard let topology = model.faces[face.faceID] else { throw TopologyError.missingReference("A drafted face is missing.") }
        let facePoints = try topology.loops.flatMap { try model.orderedPoints(for: $0) }
        // The direction into the face from the pivot line, and the same for the drafted face.
        var into = try face.normal.cross(axis).normalized(tolerance: tolerance.distance)
        let reach = facePoints.map { ($0 - face.pivot).dot(into) }
        guard let far = reach.max(by: { abs($0) < abs($1) }) else { return nil }
        if far < 0 { into = into * -1 }
        let distances = facePoints.map { ($0 - face.pivot).dot(into) }
        guard let nearest = distances.min(), let farthest = distances.max(),
              abs(nearest) <= tolerance.distance, farthest > tolerance.distance else { return nil }
        var draftedInto = try face.draftedNormal.cross(axis).normalized(tolerance: tolerance.distance)
        if draftedInto.dot(into) < 0 { draftedInto = draftedInto * -1 }
        let adds = (draftedInto - into).dot(face.outward) > 0

        // Section coordinates about the pivot: (across, pull).
        func section(_ point: Point3D) -> (Double, Double) {
            let offset = point - face.pivot
            return (offset.dot(across), offset.dot(pull))
        }
        func inSection(_ vector: Vector3D) -> (Double, Double) { (vector.dot(across), vector.dot(pull)) }
        let alongFace = { (points: [Point3D]) -> ClosedRange<Double> in
            let values = points.map { ($0 - face.pivot).dot(axis) }
            return values.min()!...values.max()!
        }

        // FIXME(INCOMPLETE_IMPLEMENTATION): Grow None (the drafted face meeting only its own
        // neighbours and poking out past a wall) and a drafted face moving into the body (a wedge
        // taken off) are refused here, so the caller rethrows the re-solve's topology failure.
        // Production path: FaceDraftFeatureEvaluator's grow fallback. Complete when the exact
        // Boolean unites a tool face lying on a body face that runs on into the body's inside,
        // verified by a notch wall drafted 70° under None and by a wall drafted -70° under Moving.
        // The same Boolean limit fails Moving's union with a classification error when the body
        // runs on past the drafted face along the pivot line (the pivot line then lies inside a
        // body face); complete when a notch over half a block's length ramps the whole block.
        guard grow != .none, adds else { return nil }
        let bodyPoints = try straightEdgedBodyPoints(bodyID: bodyID, model: model, featureID: featureID)
        guard bodyPoints.isEmpty == false else { return nil }
        // The face runs away from the pull or along it; the wedge reaches the body's far side
        // that way.
        let depth = pull.dot(into) < 0 ? pull * -1 : pull
        let rates = [into.dot(depth), draftedInto.dot(depth)]
        guard let slowest = rates.min(), slowest > tolerance.angle else {
            throw failure(.unsupportedCapability, featureID, "A face drafted level with the neutral plane cannot grow to the body's far side.")
        }
        let deepest = bodyPoints.map { ($0 - face.pivot).dot(depth) }.max()!
        guard deepest > tolerance.distance else { return nil }
        let length = 2 * deepest / slowest
        var polygon = [(0.0, 0.0), inSection(into * length), inSection(draftedInto * length)]
        let (_, depthSign) = inSection(depth)
        polygon = clip(polygon, normal: (0, depthSign), limit: deepest)
        let span: ClosedRange<Double>
        if grow == .fixed {
            let acrossValues = bodyPoints.map { section($0).0 }
            polygon = clip(polygon, normal: (1, 0), limit: acrossValues.max()!)
            polygon = clip(polygon, normal: (-1, 0), limit: -acrossValues.min()!)
            span = alongFace(facePoints)
        } else {
            span = alongFace(bodyPoints)
        }
        // The clipped wedge starts at the pivot and runs down the old face's line first.
        guard polygon.count >= 3, span.upperBound - span.lowerBound > tolerance.distance,
              hypot(polygon[0].0, polygon[0].1) <= tolerance.distance else { return nil }
        let (intoAcross, intoPull) = inSection(into)
        let wallReach = polygon[1].0 * intoAcross + polygon[1].1 * intoPull
        guard abs(polygon[1].0 * intoPull - polygon[1].1 * intoAcross) <= tolerance.distance, wallReach > tolerance.distance else { return nil }
        let outward = try (face.outward - axis * face.outward.dot(axis)).normalized(tolerance: tolerance.distance)
        guard let thickness = try backingThickness(
            pivot: face.pivot, outward: outward, into: into, axis: axis, reach: wallReach, span: span,
            bodyID: bodyID, model: model, featureID: featureID
        ) else { return nil }
        let (outAcross, outPull) = inSection(outward * -thickness)
        polygon.insert(contentsOf: [(outAcross, outPull), (polygon[1].0 + outAcross, polygon[1].1 + outPull)], at: 1)
        let base = face.pivot + axis * span.lowerBound
        return Wedge(
            polygon: withoutStraightCorners(polygon).map { base + across * $0.0 + pull * $0.1 },
            axis: axis,
            length: span.upperBound - span.lowerBound
        )
    }

    /// A thickness for the column behind the old face — from the pivot `reach` along the face, over
    /// `span` along the pivot line — that no face of the body crosses, so the column lies in the
    /// body's material; nil when no such thickness is found.
    private func backingThickness(
        pivot: Point3D, outward: Vector3D, into: Vector3D, axis: Vector3D, reach: Double, span: ClosedRange<Double>,
        bodyID: BodyID, model: BRepModel, featureID: FeatureID
    ) throws -> Double? {
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        var outlines: [[Point3D]] = []
        for case let .face(faceID) in scope.references {
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("A body face is missing.")
            }
            guard try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance) != nil else {
                throw failure(.unsupportedCapability, featureID, "Grow Moving and Fixed reach only bodies with planar faces.")
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("A body loop is missing.") }
                if loop.role == .outer { outlines.append(try model.orderedPoints(for: loopID)) }
            }
        }
        var thickness = min(reach, span.upperBound - span.lowerBound) / 4
        for _ in 0..<16 {
            let bounds: [(Vector3D, Double, Double)] = [
                (outward, -thickness, 0), (into, 0, reach), (axis, span.lowerBound, span.upperBound),
            ]
            let crosses = outlines.contains { outline in
                var points = outline
                for (direction, low, high) in bounds {
                    points = clip(points, keeping: { ($0 - pivot).dot(direction) - (low + tolerance.distance) })
                    points = clip(points, keeping: { (high - tolerance.distance) - ($0 - pivot).dot(direction) })
                }
                return points.count >= 3
            }
            if crosses == false { return thickness }
            thickness /= 2
        }
        return nil
    }

    /// The polygon cut to where `keeping` is not negative.
    private func clip(_ polygon: [Point3D], keeping: (Point3D) -> Double) -> [Point3D] {
        var result: [Point3D] = []
        for k in polygon.indices {
            let (a, b) = (polygon[k], polygon[(k + 1) % polygon.count])
            let (sa, sb) = (keeping(a), keeping(b))
            if sa >= 0 { result.append(a) }
            if (sa < 0) != (sb < 0) {
                result.append(a + (b - a) * (sa / (sa - sb)))
            }
        }
        return result
    }

    /// The polygon without corners where it runs straight on.
    private func withoutStraightCorners(_ polygon: [(Double, Double)]) -> [(Double, Double)] {
        polygon.indices.compactMap { k in
            let (previous, point, next) = (polygon[(k + polygon.count - 1) % polygon.count], polygon[k], polygon[(k + 1) % polygon.count])
            let turn = (point.0 - previous.0) * (next.1 - point.1) - (point.1 - previous.1) * (next.0 - point.0)
            return abs(turn) <= tolerance.distance * tolerance.distance ? nil : point
        }
    }

    /// The body's vertices, which bound it exactly when every edge is straight.
    private func straightEdgedBodyPoints(bodyID: BodyID, model: BRepModel, featureID: FeatureID) throws -> [Point3D] {
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        var points: [Point3D] = []
        for reference in scope.references {
            switch reference {
            case let .edge(edgeID):
                guard let edge = model.edges[edgeID] else { throw TopologyError.missingReference("A body edge is missing.") }
                switch model.geometry.curves[edge.curveID] {
                case .line, .analytic(.line): break
                default:
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Grow Moving and Fixed bound the drafted
                    // face's wedge by the body's extents taken from its vertices, exact only for
                    // straight-edged bodies, so a body with a curved edge is refused here.
                    // Production path: FaceDraftFeatureEvaluator's grow fallback. Complete when a
                    // curved body's exact extent along a direction bounds the wedge, verified by a
                    // drafted wall growing into a body with a curved edge.
                    throw failure(.unsupportedCapability, featureID, "Grow Moving and Fixed reach only bodies with straight edges.")
                }
            case let .vertex(vertexID):
                guard let point = model.vertices[vertexID]?.point else { throw TopologyError.missingReference("A body vertex is missing.") }
                points.append(point)
            default:
                break
            }
        }
        return points
    }

    /// The convex polygon cut to the half-plane `normal · p ≤ limit`.
    private func clip(_ polygon: [(Double, Double)], normal: (Double, Double), limit: Double) -> [(Double, Double)] {
        func side(_ p: (Double, Double)) -> Double { normal.0 * p.0 + normal.1 * p.1 - limit }
        var result: [(Double, Double)] = []
        for k in polygon.indices {
            let (a, b) = (polygon[k], polygon[(k + 1) % polygon.count])
            let (sa, sb) = (side(a), side(b))
            if sa <= tolerance.distance { result.append(a) }
            if (sa < -tolerance.distance && sb > tolerance.distance) || (sa > tolerance.distance && sb < -tolerance.distance) {
                let t = sa / (sa - sb)
                result.append((a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t))
            }
        }
        // Drop corners repeated by a cut through a corner.
        var distinct: [(Double, Double)] = []
        for point in result where distinct.last.map({ hypot($0.0 - point.0, $0.1 - point.1) > tolerance.distance }) ?? true {
            distinct.append(point)
        }
        if let first = distinct.first, let last = distinct.last, distinct.count > 1, hypot(first.0 - last.0, first.1 - last.1) <= tolerance.distance {
            distinct.removeLast()
        }
        return distinct
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
