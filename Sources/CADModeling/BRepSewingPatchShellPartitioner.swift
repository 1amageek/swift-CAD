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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try shells(patches: patches, stablePrefix: stablePrefix,
            tolerance: tolerance, using: &execution)
    }

    package func shells(
        patches: [BRepSewingFacePatch],
        stablePrefix: String,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> [BRepSewingShell] {
        try execution.consumeWork(1)
        try tolerance.validate()
        var stableIDs: Set<String> = []
        for patch in patches {
            try execution.consumeWork(1)
            for _ in patch.stableID.utf8 { try execution.consumeWork(1) }
            if !stableIDs.contains(patch.stableID) {
                try execution.retainStorage(count: 1, stride: MemoryLayout<String>.stride)
                stableIDs.insert(patch.stableID)
            }
        }
        guard patches.isEmpty == false,
              stablePrefix.isEmpty == false,
              stableIDs.count == patches.count else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Shell partitioning requires uniquely identified face patches."
            )
        }
        try execution.retainStorage(count: patches.count, stride: MemoryLayout<BRepSewingFacePatch>.stride)
        let sortedPatches = try patches.sorted {
            try execution.consumeWork(1)
            for _ in $0.stableID.utf8 { try execution.consumeWork(1) }
            for _ in $1.stableID.utf8 { try execution.consumeWork(1) }
            return $0.stableID < $1.stableID
        }
        // Every edge use joins the one use it is sewn to: its only partner on a manifold edge, or,
        // where solids touch along an edge, the next face around it across a material wedge.
        let fan = BRepSewingEdgeFan(tolerance: tolerance)
        try execution.retainStorage(count: sortedPatches.count, stride: MemoryLayout<Set<Int>>.stride)
        var adjacency = Array(repeating: Set<Int>(), count: sortedPatches.count)
        for group in try fan.groups(of: sortedPatches, using: &execution) where group.count >= 2 {
            let pairs = group.count == 2
                ? try singletonPair(group[0], group[1], using: &execution)
                : try materialWedgePairs(try fan.rays(group, patches: sortedPatches, using: &execution), tolerance: tolerance, using: &execution)
            for (first, second) in pairs where first.patchIndex != second.patchIndex {
                try execution.consumeWork(1)
                if !adjacency[first.patchIndex].contains(second.patchIndex) {
                    try execution.retainStorage(count: 1, stride: MemoryLayout<Int>.stride)
                    adjacency[first.patchIndex].insert(second.patchIndex)
                }
                if !adjacency[second.patchIndex].contains(first.patchIndex) {
                    try execution.retainStorage(count: 1, stride: MemoryLayout<Int>.stride)
                    adjacency[second.patchIndex].insert(first.patchIndex)
                }
            }
        }

        var visited: Set<Int> = []
        var components: [[BRepSewingFacePatch]] = []
        for start in sortedPatches.indices where visited.contains(start) == false {
            var indices: [Int] = []
            try execution.retainStorage(count: 1, stride: MemoryLayout<Int>.stride)
            var pending = [start]
            while let index = pending.popLast() {
                try execution.consumeWork(1)
                guard !visited.contains(index) else { continue }
                try execution.retainStorage(count: 1, stride: MemoryLayout<Int>.stride)
                visited.insert(index)
                try sewingAppend(index, to: &indices, using: &execution)
                try execution.retainStorage(count: adjacency[index].count, stride: MemoryLayout<Int>.stride)
                let neighbors = try adjacency[index].sorted { try execution.consumeWork(1); return $0 > $1 }
                for next in neighbors { try sewingAppend(next, to: &pending, using: &execution) }
            }
            try execution.retainStorage(count: indices.count, stride: MemoryLayout<Int>.stride)
            let ordered = try indices.sorted { try execution.consumeWork(1); return $0 < $1 }
            try execution.retainStorage(count: ordered.count, stride: MemoryLayout<BRepSewingFacePatch>.stride)
            let component = try ordered.map { try execution.consumeWork(1); return sortedPatches[$0] }
            try sewingAppend(component, to: &components, using: &execution)
        }
        try components.sort {
            try execution.consumeWork(1)
            for _ in ($0.first?.stableID ?? "").utf8 { try execution.consumeWork(1) }
            for _ in ($1.first?.stableID ?? "").utf8 { try execution.consumeWork(1) }
            return ($0.first?.stableID ?? "") < ($1.first?.stableID ?? "")
        }
        try execution.retainStorage(count: components.count, stride: MemoryLayout<BRepSewingShell>.stride)
        return try components.enumerated().map { index, component in
            try execution.consumeWork(1)
            for _ in stablePrefix.utf8 { try execution.consumeWork(1) }
            var remaining = index
            var digits = 1
            while remaining >= 10 {
                try execution.consumeWork(1)
                remaining /= 10
                digits += 1
            }
            let prefix = stablePrefix.utf8.count.addingReportingOverflow(1)
            let bytes = prefix.partialValue.addingReportingOverflow(digits)
            guard !prefix.overflow, !bytes.overflow else { throw ExactScalarFailure.countOverflow }
            try execution.retainStorage(bytes: bytes.partialValue)
            return BRepSewingShell(
                stableID: "\(stablePrefix):\(index)",
                patches: component
            )
        }
    }

    /// Consecutive rays that bound a material wedge (both faces' outward normals pointing out of
    /// it) belong to one solid.
    private func materialWedgePairs(
        _ rays: [BRepSewingEdgeFan.Ray],
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [(BRepSewingEdgeFan.Use, BRepSewingEdgeFan.Use)] {
        var pairs: [(BRepSewingEdgeFan.Use, BRepSewingEdgeFan.Use)] = []
        var paired = Set<Int>()
        for index in rays.indices {
            try execution.consumeWork(1)
            let next = (index + 1) % rays.count
            guard rays[index].frontFacesAfter == false, rays[next].frontFacesAfter else { continue }
            try execution.retainStorage(count: 2, stride: MemoryLayout<Int>.stride)
            guard paired.insert(index).inserted, paired.insert(next).inserted else {
                throw nonManifold(tolerance)
            }
            try sewingAppend((rays[index].use, rays[next].use), to: &pairs, using: &execution)
        }
        guard paired.count == rays.count else { throw nonManifold(tolerance) }
        return pairs
    }

    private func singletonPair(_ first: BRepSewingEdgeFan.Use, _ second: BRepSewingEdgeFan.Use,
        using execution: inout OriginalQueryExecution
    ) throws -> [(BRepSewingEdgeFan.Use, BRepSewingEdgeFan.Use)] {
        try execution.consumeWork(1)
        try execution.retainStorage(count: 1, stride: MemoryLayout<(BRepSewingEdgeFan.Use, BRepSewingEdgeFan.Use)>.stride)
        return [(first, second)]
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
