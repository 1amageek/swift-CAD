import CADCore
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
        var adjacency = Array(repeating: Set<Int>(), count: sortedPatches.count)
        for firstIndex in sortedPatches.indices {
            for secondIndex in sortedPatches.indices where secondIndex > firstIndex {
                if try shareBoundaryEdge(
                    sortedPatches[firstIndex],
                    sortedPatches[secondIndex],
                    tolerance: tolerance
                ) {
                    adjacency[firstIndex].insert(secondIndex)
                    adjacency[secondIndex].insert(firstIndex)
                }
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

    private func shareBoundaryEdge(
        _ first: BRepSewingFacePatch,
        _ second: BRepSewingFacePatch,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        for firstEdge in first.loops.flatMap(\.edges) {
            for secondEdge in second.loops.flatMap(\.edges) {
                if try edgesMatch(firstEdge, secondEdge, tolerance: tolerance) {
                    return true
                }
            }
        }
        return false
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
