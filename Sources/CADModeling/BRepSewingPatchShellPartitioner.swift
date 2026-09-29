import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct BRepSewingPatchShellPartitioner {
    package init() {}

    package func shells(
        patches: [BRepSewingFacePatch],
        stablePrefix: String,
        tolerance: ModelingTolerance
    ) throws -> [BRepSewingShell] {
        try tolerance.validate()
        guard patches.isEmpty == false,
              stablePrefix.isEmpty == false,
              Set(patches.map(\.stableID)).count == patches.count else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Shell partitioning requires uniquely identified face patches."
            )
        }
        let sortedPatches = patches.sorted { $0.stableID < $1.stableID }
        // Every edge use joins the one use it is sewn to: its only partner on a manifold edge, or
        // its radial neighbour across a material wedge where solids touch along an edge.
        var groups: [[EdgeUse]] = []
        for (patchIndex, patch) in sortedPatches.enumerated() {
            for edge in patch.loops.flatMap(\.edges) {
                let use = EdgeUse(patchIndex: patchIndex, edge: edge)
                if let groupIndex = try groups.firstIndex(where: { try edgesMatch($0[0].edge, edge, tolerance: tolerance) }) {
                    groups[groupIndex].append(use)
                } else {
                    groups.append([use])
                }
            }
        }
        var adjacency = Array(repeating: Set<Int>(), count: sortedPatches.count)
        for group in groups where group.count >= 2 {
            let pairs = group.count == 2
                ? [(group[0], group[1])]
                : try radialPairs(group, patches: sortedPatches, tolerance: tolerance)
            for (first, second) in pairs where first.patchIndex != second.patchIndex {
                adjacency[first.patchIndex].insert(second.patchIndex)
                adjacency[second.patchIndex].insert(first.patchIndex)
            }
        }

        var visited: Set<Int> = []
        var components: [[BRepSewingFacePatch]] = []
        for start in sortedPatches.indices where visited.contains(start) == false {
            var indices: [Int] = []
            var pending = [start]
            while let index = pending.popLast() {
                guard visited.insert(index).inserted else { continue }
                indices.append(index)
                pending.append(contentsOf: adjacency[index].sorted(by: >))
            }
            components.append(indices.sorted().map { sortedPatches[$0] })
        }
        components.sort {
            ($0.first?.stableID ?? "") < ($1.first?.stableID ?? "")
        }
        return components.enumerated().map { index, component in
            BRepSewingShell(
                stableID: "\(stablePrefix):\(index)",
                patches: component
            )
        }
    }

    private struct EdgeUse {
        let patchIndex: Int
        let edge: BRepSewingEdge
    }

    /// Pairs the uses of one edge where more than two faces meet: around the edge each face is a
    /// ray from the edge into its interior, and consecutive rays that bound a material wedge (both
    /// faces' outward normals pointing out of it) belong to one solid, so they are sewn together.
    private func radialPairs(
        _ uses: [EdgeUse],
        patches: [BRepSewingFacePatch],
        tolerance: ModelingTolerance
    ) throws -> [(EdgeUse, EdgeUse)] {
        struct Ray {
            let use: EdgeUse
            let angle: Double
            let materialAfter: Bool
        }
        var axis: Vector3D?
        var reference: (Vector3D, Vector3D)?
        var rays: [Ray] = []
        for use in uses {
            let patch = patches[use.patchIndex]
            let frame = try edgeFrame(use.edge, on: patch, tolerance: tolerance)
            let t = axis ?? frame.direction
            axis = t
            // The face's interior lies to the left of its loops about its outward normal.
            let inward = frame.normal.cross(frame.direction)
            let radial = inward - t * inward.dot(t)
            let r = try radial.normalized(tolerance: tolerance.distance)
            let basis = reference ?? (r, t.cross(r))
            reference = basis
            let angle = atan2(r.dot(basis.1), r.dot(basis.0))
            let turning = t.cross(r)
            var normalized = angle < 0 ? angle + 2 * .pi : angle
            if normalized > 2 * .pi - tolerance.angle * 1e3 { normalized = 0 }
            rays.append(Ray(use: use, angle: normalized, materialAfter: frame.normal.dot(turning) < 0))
        }
        // Faces lying on each other leave the edge at one angle: the one closing the wedge before
        // them comes first.
        rays.sort { lhs, rhs in
            if abs(lhs.angle - rhs.angle) > tolerance.angle * 1e3 { return lhs.angle < rhs.angle }
            return lhs.materialAfter == false && rhs.materialAfter
        }
        var pairs: [(EdgeUse, EdgeUse)] = []
        var paired = Set<Int>()
        for index in rays.indices {
            let next = (index + 1) % rays.count
            guard rays[index].materialAfter, rays[next].materialAfter == false else { continue }
            guard paired.insert(index).inserted, paired.insert(next).inserted else {
                throw nonManifold(tolerance)
            }
            pairs.append((rays[index].use, rays[next].use))
        }
        guard paired.count == rays.count else { throw nonManifold(tolerance) }
        return pairs
    }

    /// The outward normal and the traversal direction of an edge use at its middle.
    private func edgeFrame(
        _ edge: BRepSewingEdge,
        on patch: BRepSewingFacePatch,
        tolerance: ModelingTolerance
    ) throws -> (normal: Vector3D, direction: Vector3D) {
        let middle = try edge.surfaceParameterCurve.parameter(atNormalizedFraction: 0.5, tolerance: tolerance)
        let before = try edge.surfaceParameterCurve.parameter(atNormalizedFraction: 0.49, tolerance: tolerance)
        let after = try edge.surfaceParameterCurve.parameter(atNormalizedFraction: 0.51, tolerance: tolerance)
        let geometric = try patch.surface.normal(u: middle.u, v: middle.v, tolerance: tolerance)
            .normalized(tolerance: tolerance.distance)
        let normal = patch.orientation == .forward ? geometric : geometric * -1.0
        let direction = try (patch.surface.point(u: after.u, v: after.v, tolerance: tolerance)
            - patch.surface.point(u: before.u, v: before.v, tolerance: tolerance))
            .normalized(tolerance: tolerance.distance * 1e-6)
        return (normal, direction)
    }

    private func nonManifold(_ tolerance: ModelingTolerance) -> KernelError {
        KernelError(
            phase: .topology,
            code: .nonManifoldResult,
            tolerance: tolerance,
            message: "Faces meeting at one edge do not pair into solids around it."
        )
    }

    private func edgesMatch(
        _ first: BRepSewingEdge,
        _ second: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let sameDirection = first.startPoint.isApproximatelyEqual(
            to: second.startPoint,
            tolerance: tolerance.distance
        ) && first.endPoint.isApproximatelyEqual(
            to: second.endPoint,
            tolerance: tolerance.distance
        )
        let reversedDirection = first.startPoint.isApproximatelyEqual(
            to: second.endPoint,
            tolerance: tolerance.distance
        ) && first.endPoint.isApproximatelyEqual(
            to: second.startPoint,
            tolerance: tolerance.distance
        )
        guard sameDirection || reversedDirection else { return false }
        let firstSamples = try samples(first, tolerance: tolerance)
        var secondSamples = try samples(second, tolerance: tolerance)
        if reversedDirection {
            secondSamples.reverse()
        }
        return zip(firstSamples, secondSamples).allSatisfy {
            $0.isApproximatelyEqual(to: $1, tolerance: tolerance.distance)
        }
    }

    private func samples(
        _ edge: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        try (0...4).map { index in
            let fraction = Double(index) / 4.0
            let parameter = edge.startParameter
                + (edge.endParameter - edge.startParameter) * fraction
            return try edge.curve.point(at: parameter, tolerance: tolerance)
        }
    }
}
