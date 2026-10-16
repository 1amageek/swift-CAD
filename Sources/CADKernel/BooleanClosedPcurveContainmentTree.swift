import CADCore
import CADGeometry
import CADTopology

struct BooleanClosedPcurveContainmentTree: Sendable {
    struct Node: Hashable, Sendable {
        let region: BooleanClosedPcurveRegion
        let parent: BooleanFaceSplitComponentReference?
        let children: [BooleanFaceSplitComponentReference]
    }

    let nodes: [BooleanFaceSplitComponentReference: Node]
    let roots: [BooleanFaceSplitComponentReference]

    init(
        regions: [BooleanClosedPcurveRegion],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try tolerance.validate()
        let references = try OriginalParameterQueryStorage.map(regions, using: &execution) { region, execution in region.reference }
        guard regions.isEmpty == false,
              try OriginalParameterQueryStorage.set(references, using: &execution).count == regions.count else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Closed pcurve containment requires unique component regions."
            )
        }
        for firstIndex in regions.indices {
            try execution.consumeWork(1)
            for secondIndex in regions.indices {
                try execution.consumeWork(1)
                guard secondIndex > firstIndex else { continue }
                guard try regions[firstIndex].boundaryIntersects(
                    regions[secondIndex],
                    tolerance: tolerance, using: &execution
                ) == false else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "Closed Boolean pcurve components intersect or touch on the same face."
                    )
                }
            }
        }

        var parents: [BooleanFaceSplitComponentReference: BooleanFaceSplitComponentReference] = [:]
        for child in regions {
            try execution.consumeWork(1)
            var containers: [BooleanClosedPcurveRegion] = []
            for candidate in regions {
                try execution.consumeWork(1)
                if candidate.reference != child.reference,
                   try candidate.containsStrictly(child.points[0], tolerance: tolerance, using: &execution) {
                    try OriginalParameterQueryStorage.append(candidate, to: &containers, using: &execution)
                }
            }
            var immediateContainers: [BooleanClosedPcurveRegion] = []
            for candidate in containers {
            try execution.consumeWork(1)
                var immediate = true
                for other in containers {
                    try execution.consumeWork(1)
                    guard other.reference != candidate.reference else { continue }
                    try execution.consumeWork(1)
                    if try !other.containsStrictly(candidate.points[0], tolerance: tolerance, using: &execution) {
                        immediate = false
                        break
                    }
                }
                if immediate { try OriginalParameterQueryStorage.append(candidate, to: &immediateContainers, using: &execution) }
            }
            guard immediateContainers.count <= 1 else {
                throw KernelError(phase: .classification, code: .classificationFailure, tolerance: tolerance,
                    message: "Closed pcurve containment did not produce a unique immediate parent.")
            }
            if let parent = immediateContainers.first {
                try OriginalParameterQueryStorage.set(parent.reference, for: child.reference, in: &parents, using: &execution)
            }
        }
        var children: [BooleanFaceSplitComponentReference: [BooleanFaceSplitComponentReference]] = [:]
        for (child, parent) in parents {
            try execution.consumeWork(1)
            var items = children[parent] ?? []
            try execution.retainKernelValues(count: items.count, stride: MemoryLayout<BooleanFaceSplitComponentReference>.stride)
            try OriginalParameterQueryStorage.append(child, to: &items, using: &execution)
            try OriginalParameterQueryStorage.set(items, for: parent, in: &children, using: &execution)
        }
        var nodes: [BooleanFaceSplitComponentReference: Node] = [:]
        var roots: [BooleanFaceSplitComponentReference] = []
        for region in regions {
            try execution.consumeWork(1)
            var items = children[region.reference] ?? []
            try execution.retainKernelValues(count: items.count, stride: MemoryLayout<BooleanFaceSplitComponentReference>.stride)
            try OriginalParameterQueryStorage.sort(&items, using: &execution) { $0 < $1 }
            try OriginalParameterQueryStorage.set(Node(region: region, parent: parents[region.reference], children: items), for: region.reference, in: &nodes, using: &execution)
            if parents[region.reference] == nil { try OriginalParameterQueryStorage.append(region.reference, to: &roots, using: &execution) }
        }
        try OriginalParameterQueryStorage.sort(&roots, using: &execution) { $0 < $1 }
        self.nodes = nodes
        self.roots = roots
    }

    func depth(
        of reference: BooleanFaceSplitComponentReference,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Int {
        try execution.consumeWork(1)
        var depth = 0
        var current = reference
        var visited: Set<BooleanFaceSplitComponentReference> = []
        while let parent = nodes[current]?.parent {
            guard try OriginalParameterQueryStorage.insert(current, in: &visited, using: &execution) else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Closed pcurve containment graph contains a parent cycle."
                )
            }
            let next = depth.addingReportingOverflow(1)
            guard !next.overflow else { throw ExactScalarFailure.countOverflow }
            depth = next.partialValue
            current = parent
        }
        return depth
    }
}
