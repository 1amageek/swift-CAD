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
        // Every edge use joins the one use it is sewn to: its only partner on a manifold edge, or,
        // where solids touch along an edge, the next face around it across a material wedge.
        let fan = BRepSewingEdgeFan(tolerance: tolerance)
        var adjacency = Array(repeating: Set<Int>(), count: sortedPatches.count)
        for group in try fan.groups(of: sortedPatches) where group.count >= 2 {
            let pairs = group.count == 2
                ? [(group[0], group[1])]
                : try materialWedgePairs(try fan.rays(group, patches: sortedPatches), tolerance: tolerance)
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

    /// Consecutive rays that bound a material wedge (both faces' outward normals pointing out of
    /// it) belong to one solid.
    private func materialWedgePairs(
        _ rays: [BRepSewingEdgeFan.Ray],
        tolerance: ModelingTolerance
    ) throws -> [(BRepSewingEdgeFan.Use, BRepSewingEdgeFan.Use)] {
        var pairs: [(BRepSewingEdgeFan.Use, BRepSewingEdgeFan.Use)] = []
        var paired = Set<Int>()
        for index in rays.indices {
            let next = (index + 1) % rays.count
            guard rays[index].frontFacesAfter == false, rays[next].frontFacesAfter else { continue }
            guard paired.insert(index).inserted, paired.insert(next).inserted else {
                throw nonManifold(tolerance)
            }
            pairs.append((rays[index].use, rays[next].use))
        }
        guard paired.count == rays.count else { throw nonManifold(tolerance) }
        return pairs
    }

    private func nonManifold(_ tolerance: ModelingTolerance) -> KernelError {
        KernelError(
            phase: .topology,
            code: .nonManifoldResult,
            tolerance: tolerance,
            message: "Faces meeting at one edge do not pair into solids around it."
        )
    }
}
