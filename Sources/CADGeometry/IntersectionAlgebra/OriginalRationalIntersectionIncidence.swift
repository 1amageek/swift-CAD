import CADCore

/// Whole-cell closure incidence retains any required subdivision of the target stratum.
package struct OriginalRationalIntersectionIncidence: Sendable {
    package struct Attachment: Sendable {
        package let sourceCellIndex: Int
        package let targetCellIndex: Int
        package let closureIndex: Int
        package let refinedTargetCellIndex: Int
    }
    package let partition: OriginalRationalIntersectionCells
    package let closures: [OriginalIntersectionCellClosure]
    package let attachments: [Attachment]

    private init(partition: OriginalRationalIntersectionCells, closures: [OriginalIntersectionCellClosure], attachments: [Attachment]) {
        self.partition = partition; self.closures = closures; self.attachments = attachments
    }

    package func connectedComponents<B: RationalAlgebraAdmitting>(usage: inout B) throws -> OriginalRationalParameterComponents {
        try .prepare(incidence: self, usage: &usage)
    }

    package static func prepare<B: RationalAlgebraAdmitting>(partition: OriginalRationalIntersectionCells,
        allowAffineClosureProofs: Bool = true, maximumDepth: Int, usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        guard partition.tower.hasThomEncoding else {
            throw rationalAlgebraFailure("Incidence requires derivative-closed original cell identity.")
        }
        try RationalAlgebraStorage.retain(partition.solutionCells.count, of: OriginalIntersectionCellCondition.self, usage: &usage)
        var conditions: [OriginalIntersectionCellCondition] = []
        conditions.reserveCapacity(partition.solutionCells.count)
        for index in partition.solutionCells {
            conditions.append(try .init(partition: partition, cellIndex: index, usage: &usage))
        }
        var closures: [OriginalIntersectionCellClosure] = [], attachments: [Attachment] = []
        for source in partition.solutionCells {
            try intersectionAlgebraStep(&usage)
            let closure = try OriginalIntersectionCellClosure.prepare(partition: partition, cellIndex: source,
                allowAffineProofs: allowAffineClosureProofs, maximumDepth: maximumDepth, usage: &usage)
            let closureIndex = closures.count
            let freePartition = closure.freePartition
            for index in closure.includedCells {
                try intersectionAlgebraStep(&usage)
                let cell = freePartition.cells[index]
                var selected: Int?
                switch closure.proof {
                case .point, .finiteBranch, .affineCell:
                    for target in conditions {
                        try intersectionAlgebraStep(&usage)
                        if target.cellIndex == index { selected = index; break }
                    }
                case .quantified:
                    for target in conditions {
                        if try target.contains(context: cell.context, coordinates: cell.coordinates,
                            maximumDepth: maximumDepth, usage: &usage) {
                            guard selected == nil else {
                                throw rationalAlgebraFailure("A closure subdivision belongs to two distinct original cells.")
                            }
                            selected = target.cellIndex
                        }
                    }
                }
                // Closure points outside the selected original equations/domain,
                // including excluded denominator loci, grant no attachment.
                if let target = selected {
                    try RationalAlgebraStorage.retain(1, of: Attachment.self, usage: &usage)
                    attachments.append(Attachment(sourceCellIndex: source, targetCellIndex: target,
                        closureIndex: closureIndex, refinedTargetCellIndex: index))
                }
            }
            try RationalAlgebraStorage.retain(1, of: OriginalIntersectionCellClosure.self, usage: &usage)
            closures.append(closure)
        }
        return Self(partition: partition, closures: closures, attachments: attachments)
    }
}
