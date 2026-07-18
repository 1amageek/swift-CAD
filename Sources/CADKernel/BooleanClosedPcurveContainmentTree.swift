import CADCore

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
    ) throws {
        try tolerance.validate()
        guard regions.isEmpty == false,
              Set(regions.map(\.reference)).count == regions.count else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Closed pcurve containment requires unique component regions."
            )
        }
        for firstIndex in regions.indices {
            for secondIndex in regions.indices where secondIndex > firstIndex {
                guard try regions[firstIndex].boundaryIntersects(
                    regions[secondIndex],
                    tolerance: tolerance
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
            let containers = try regions.filter { candidate in
                guard candidate.reference != child.reference,
                      candidate.absoluteArea > child.absoluteArea else {
                    return false
                }
                return try candidate.containsStrictly(
                    child.points[0],
                    tolerance: tolerance
                )
            }.sorted { lhs, rhs in
                if lhs.absoluteArea != rhs.absoluteArea {
                    return lhs.absoluteArea < rhs.absoluteArea
                }
                return lhs.reference < rhs.reference
            }
            if let parent = containers.first {
                parents[child.reference] = parent.reference
            }
        }

        var children: [BooleanFaceSplitComponentReference: [BooleanFaceSplitComponentReference]] = [:]
        for (child, parent) in parents {
            children[parent, default: []].append(child)
        }
        self.nodes = Dictionary(uniqueKeysWithValues: regions.map { region in
            let reference = region.reference
            return (reference, Node(
                region: region,
                parent: parents[reference],
                children: (children[reference] ?? []).sorted()
            ))
        })
        self.roots = regions.map(\.reference).filter {
            parents[$0] == nil
        }.sorted()
    }
}
