import Foundation
import CADCore
import CADGeometry
import CADTopology

/// Chooses how removed faces collapse for `FaceRemovalHealer`: Delete Face's faces, and the
/// fillets Remove Fillets finds.
///
/// A fillet is a face on a cylinder, a torus or a sphere no wider than the largest radius asked
/// for, meeting two kept faces tangentially along two of its edges (a strip, which collapses
/// onto their meeting), or lying where fillets meet with no kept face beside it tangentially (a
/// corner, which collapses to a point). Its convexity is whether its centre of curvature lies in
/// the material.
///
/// A deleted face that is not a fillet is tried each way it could collapse — dropping the holes
/// it leaves, onto the meeting of each pair of faces across two of its edges, and to a point —
/// and the healed solid that validates and changes the volume least is kept.
package struct FaceRemovalPlanner: Sendable {
    package enum Convexity: Sendable {
        case any, convex, concave
    }

    package init() {}

    /// The most combinations of collapses tried for faces deleted together.
    private static let maximumCombinations = 256

    /// The fillets of the body no wider than `maximumRadius` (any, when nil) of the asked
    /// convexity, and how each collapses.
    package func fillets(
        of bodyID: BodyID,
        maximumRadius: Double?,
        convexity: Convexity,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [FaceID: FaceRemovalHealer.Collapse] {
        let topology = try Topology(bodyID: bodyID, model: model)
        var candidates: [FaceID: (radius: Double, convex: Bool)] = [:]
        for faceID in topology.faces {
            guard let blend = try blendRadius(of: faceID, model: model, tolerance: tolerance),
                  maximumRadius.map({ blend.radius <= $0 + tolerance.distance }) ?? true else { continue }
            candidates[faceID] = blend
        }
        var plan: [FaceID: FaceRemovalHealer.Collapse] = [:]
        for (faceID, blend) in candidates.sorted(by: { $0.key < $1.key }) {
            let smooth = try topology.edges(of: faceID).filter { edgeID in
                guard let other = topology.otherFace(of: edgeID, than: faceID), candidates[other] == nil else { return false }
                return try meetsTangentially(faceID, other, along: edgeID, model: model, tolerance: tolerance)
            }
            let supports = Set(smooth.compactMap { topology.otherFace(of: $0, than: faceID) })
            if smooth.count == 2, supports.count == 2 {
                guard matches(blend.convex, convexity) else { continue }
                plan[faceID] = .toEdge(first: smooth[0], second: smooth[1])
            } else if smooth.isEmpty, try topology.edges(of: faceID).allSatisfy({ edgeID in
                topology.otherFace(of: edgeID, than: faceID).map { candidates[$0] != nil } ?? false
            }) {
                guard matches(blend.convex, convexity) else { continue }
                plan[faceID] = .toPoint
            }
        }
        // A corner goes with the strips around it: one whose strips are all kept goes too.
        for (faceID, collapse) in plan where collapse == .toPoint {
            let around = try topology.edges(of: faceID).compactMap { topology.otherFace(of: $0, than: faceID) }
            if around.contains(where: { plan[$0] == nil }) { plan.removeValue(forKey: faceID) }
        }
        return plan
    }

    /// Heals the body over `faces`: fillets among them collapse as fillets; each other face is
    /// tried every way it could collapse, the one that validates and changes the volume least
    /// kept; faces that touch go together as a hole, else by the best combination of their
    /// collapses healed at once, else one at a time.
    package func heal(
        removing faces: Set<FaceID>,
        bodyID: BodyID,
        featureID: FeatureID,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        let topology = try Topology(bodyID: bodyID, model: model)
        guard faces.isSubset(of: Set(topology.faces)) else {
            throw failure(.missingReference, featureID, tolerance, "A deleted face does not belong to the body.")
        }
        let fillets = try self.fillets(of: bodyID, maximumRadius: nil, convexity: .any, model: model, tolerance: tolerance)
            .filter { faces.contains($0.key) }
        // Faces other than fillets gather into clusters of faces that touch.
        var clusters: [[FaceID]] = []
        var pending = faces.subtracting(fillets.keys)
        while let seed = pending.min() {
            var cluster = [seed]
            pending.remove(seed)
            var index = 0
            while index < cluster.count {
                for edgeID in try topology.edges(of: cluster[index]) {
                    if let other = topology.otherFace(of: edgeID, than: cluster[index]), pending.remove(other) != nil { cluster.append(other) }
                }
                index += 1
            }
            clusters.append(cluster.sorted())
        }
        if fillets.isEmpty == false {
            try FaceRemovalHealer().heal(fillets, bodyID: bodyID, featureID: featureID, model: &model, tolerance: tolerance)
        }
        for cluster in clusters where cluster.count > 1 {
            // The faces of a hole go together, dropping the loops they leave; faces that touch
            // otherwise go one at a time, each the first of those left that heals alone (the
            // faces around a healed face keep their identities as they regrow over it).
            var dropped = model
            do {
                try FaceRemovalHealer().heal(Dictionary(uniqueKeysWithValues: cluster.map { ($0, .dropsHoles) }),
                                             bodyID: bodyID, featureID: featureID, model: &dropped, tolerance: tolerance)
                try ExactFacePcurveBuilder().populateMissingPcurves(in: &dropped, tolerance: tolerance)
                try dropped.validate(level: .volumetric, tolerance: tolerance)
                model = dropped
                continue
            } catch {
                // Not a hole: the faces collapse together below.
            }
            // Every combination of the ways each face could collapse, healed at once (chamfers
            // meeting at a mitre each collapse onto their edge together), the one that validates
            // and changes the volume least kept.
            let options = try cluster.map { try collapses(of: $0, bodyID: bodyID, model: model) }
            let combinations = options.reduce(1) { $0 * $1.count }
            if combinations <= Self.maximumCombinations {
                let before = try model.volume(of: bodyID, tolerance: tolerance)
                var best: (model: BRepModel, change: Double)?
                for combination in 0..<combinations {
                    var plan: [FaceID: FaceRemovalHealer.Collapse] = [:]
                    var rest = combination
                    for (faceID, choices) in zip(cluster, options) {
                        plan[faceID] = choices[rest % choices.count]
                        rest /= choices.count
                    }
                    var trial = model
                    do {
                        try FaceRemovalHealer().heal(plan, bodyID: bodyID, featureID: featureID, model: &trial, tolerance: tolerance)
                        try ExactFacePcurveBuilder().populateMissingPcurves(in: &trial, tolerance: tolerance)
                        try trial.validate(level: .volumetric, tolerance: tolerance)
                        let change = abs(try trial.volume(of: bodyID, tolerance: tolerance) - before)
                        if best.map({ change < $0.change }) ?? true { best = (trial, change) }
                    } catch {
                        // A combination that fails to heal is not how the faces collapse; the
                        // faces are healed one at a time when none does.
                    }
                }
                if let best {
                    model = best.model
                    continue
                }
            }
            var remaining = cluster
            while remaining.isEmpty == false {
                var healed: (index: Int, model: BRepModel)?
                var lastFailure: (any Error)?
                for (index, faceID) in remaining.enumerated() {
                    do {
                        healed = (index, try healedAlone(faceID, bodyID: bodyID, featureID: featureID, model: model, tolerance: tolerance))
                        break
                    } catch {
                        lastFailure = error
                    }
                }
                guard let healed else {
                    throw lastFailure ?? failure(.topologyFailure, featureID, tolerance, "The faces around deleted faces do not meet over them.")
                }
                model = healed.model
                remaining.remove(at: healed.index)
            }
        }
        for faceID in clusters.filter({ $0.count == 1 }).flatMap({ $0 }) {
            model = try healedAlone(faceID, bodyID: bodyID, featureID: featureID, model: model, tolerance: tolerance)
        }
    }

    /// The body healed over one face: each way it could collapse tried, the one that validates and
    /// changes the volume least kept.
    private func healedAlone(_ faceID: FaceID, bodyID: BodyID, featureID: FeatureID, model: BRepModel,
                             tolerance: ModelingTolerance) throws -> BRepModel {
        let before = try model.volume(of: bodyID, tolerance: tolerance)
        var best: (model: BRepModel, change: Double)?
        var lastFailure: (any Error)?
        for collapse in try collapses(of: faceID, bodyID: bodyID, model: model) {
            var trial = model
            do {
                try FaceRemovalHealer().heal([faceID: collapse], bodyID: bodyID, featureID: featureID, model: &trial, tolerance: tolerance)
                try ExactFacePcurveBuilder().populateMissingPcurves(in: &trial, tolerance: tolerance)
                try trial.validate(level: .volumetric, tolerance: tolerance)
                let change = abs(try trial.volume(of: bodyID, tolerance: tolerance) - before)
                if best.map({ change < $0.change }) ?? true { best = (trial, change) }
            } catch {
                // Each way the face could collapse is a candidate; one that fails to heal is
                // not the way the face collapses, and the failure is reported when none heals.
                lastFailure = error
            }
        }
        guard let best else {
            throw lastFailure ?? failure(.topologyFailure, featureID, tolerance, "The faces around a deleted face do not meet over it.")
        }
        return best.model
    }

    /// Every way a face could collapse: dropping the holes it leaves, onto the meeting of the
    /// faces across each pair of its edges that do not touch, and to a point.
    private func collapses(of faceID: FaceID, bodyID: BodyID, model: BRepModel) throws -> [FaceRemovalHealer.Collapse] {
        let topology = try Topology(bodyID: bodyID, model: model)
        let edges = try topology.edges(of: faceID)
        var result: [FaceRemovalHealer.Collapse] = [.dropsHoles]
        for (i, first) in edges.enumerated() {
            for second in edges[(i + 1)...] {
                guard let a = model.edges[first], let b = model.edges[second],
                      Set([a.startVertexID, a.endVertexID]).isDisjoint(with: [b.startVertexID, b.endVertexID]),
                      let firstSide = topology.otherFace(of: first, than: faceID),
                      let secondSide = topology.otherFace(of: second, than: faceID), firstSide != secondSide else { continue }
                result.append(.toEdge(first: first, second: second))
            }
        }
        result.append(.toPoint)
        return result
    }

    /// The radius of a face on a cylinder, torus or sphere, and whether its centre of curvature
    /// lies in the material; nil for any other face.
    private func blendRadius(of faceID: FaceID, model: BRepModel, tolerance: ModelingTolerance) throws -> (radius: Double, convex: Bool)? {
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("A face is missing.")
        }
        let radius: Double
        let center: (Point3D) throws -> Point3D
        switch surface {
        case let .cylinder(cylinder):
            radius = cylinder.radius
            let axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
            center = { cylinder.origin + axis * ($0 - cylinder.origin).dot(axis) }
        case let .analytic(.cylinder(origin, axis, value)):
            radius = value
            let unit = try axis.normalized(tolerance: tolerance.distance)
            center = { origin + unit * ($0 - origin).dot(unit) }
        case let .analytic(.sphere(sphereCenter, value)):
            radius = value
            center = { _ in sphereCenter }
        case let .analytic(.torus(torusCenter, axis, major, minor)):
            radius = minor
            let unit = try axis.normalized(tolerance: tolerance.distance)
            center = { point in
                let offset = point - torusCenter
                let radial = offset - unit * offset.dot(unit)
                return torusCenter + (try radial.normalized(tolerance: tolerance.distance)) * major
            }
        default:
            return nil
        }
        // At a point of the face, the outward side points away from the centre of a convex fillet.
        guard let loopID = face.loops.first, let point = try model.orderedPoints(for: loopID).first else { return nil }
        let foot = try SurfaceFootResolver().foot(of: point, on: surface, tolerance: tolerance)
        let outward = face.orientation == .forward ? foot.normal : foot.normal * -1
        return (radius, outward.dot(foot.point - (try center(foot.point))) > 0)
    }

    /// Whether two faces meet with one tangent plane along the middle of their shared edge.
    private func meetsTangentially(_ a: FaceID, _ b: FaceID, along edgeID: EdgeID, model: BRepModel, tolerance: ModelingTolerance) throws -> Bool {
        guard let edge = model.edges[edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim,
              let first = model.faces[a], let second = model.faces[b],
              let firstSurface = model.geometry.surfaces[first.surfaceID], let secondSurface = model.geometry.surfaces[second.surfaceID] else {
            throw TopologyError.missingReference("An edge's geometry is missing.")
        }
        let middle = try curve.point(at: (trim.startParameter + trim.endParameter) / 2, tolerance: tolerance)
        let feet = SurfaceFootResolver()
        let n1 = try feet.foot(of: middle, on: firstSurface, tolerance: tolerance).normal
        let n2 = try feet.foot(of: middle, on: secondSurface, tolerance: tolerance).normal
        return n1.cross(n2).length <= max(tolerance.angle, 1e-7)
    }

    private func matches(_ convex: Bool, _ convexity: Convexity) -> Bool {
        switch convexity {
        case .any: true
        case .convex: convex
        case .concave: !convex
        }
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: code == .topologyFailure ? .topology : .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }

    /// The faces of a body and the faces on either side of its edges.
    private struct Topology {
        let faces: [FaceID]
        let facesOfEdge: [EdgeID: [FaceID]]
        let model: BRepModel

        init(bodyID: BodyID, model: BRepModel) throws {
            let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
            faces = scope.references.compactMap { reference -> FaceID? in
                guard case let .face(id) = reference else { return nil }
                return id
            }.sorted()
            var facesOfEdge: [EdgeID: [FaceID]] = [:]
            for faceID in faces {
                for loopID in model.faces[faceID]?.loops ?? [] {
                    for coedge in model.loops[loopID]?.coedges ?? [] { facesOfEdge[coedge.edgeID, default: []].append(faceID) }
                }
            }
            self.facesOfEdge = facesOfEdge
            self.model = model
        }

        func edges(of faceID: FaceID) throws -> [EdgeID] {
            guard let face = model.faces[faceID] else { throw TopologyError.missingReference("A face is missing.") }
            return face.loops.flatMap { model.loops[$0]?.coedges.map(\.edgeID) ?? [] }
        }

        func otherFace(of edgeID: EdgeID, than faceID: FaceID) -> FaceID? {
            facesOfEdge[edgeID]?.first { $0 != faceID }
        }
    }
}
