import CADCore

/// Whole-cell source conditions borrowed from one complete immutable Native receipt.
struct OriginalBoundarySourceCover {
    enum Identifier: Sendable {
        case curveSurface(OriginalNativeCurveSurfaceRelation.CellIdentifier)
        case surfaceSurface(OriginalNativeSurfaceSurfaceRelations.CellIdentifier)
    }
    let conditions: [OriginalIntersectionCellCondition]
    let identifiers: [Identifier]
    let laws: [ExactIntersectionPolynomial]
    let systems: [OriginalRationalIntersectionSystem]
    let parameterDepth: Int
    let coefficientDepth: Int

    init<A: ExactScalarAdmission & ~Copyable>(_ source: OriginalNativeBoundaryDomain.Source, maximumDepth: Int,
        maximumCoefficientDepth: Int, usage: inout A) throws {
        try intersectionAlgebraStep(&usage)
        let partition: OriginalRationalIntersectionCells?
        var rawLaws: [ExactIntersectionPolynomial] = []
        var owners: [Identifier] = []
        var systems: [OriginalRationalIntersectionSystem] = []
        var depth = 0, coefficientDepth = 0
        switch source {
        case .curveSurface(let raw):
            partition = raw.partition
            for chart in raw.charts {
                try intersectionAlgebraStep(&usage)
                try RationalAlgebraStorage.retain(try rationalAlgebraCount(chart.system.equations.count, chart.system.denominatorGuards.count),
                    of: ExactIntersectionPolynomial.self, usage: &usage)
                for law in chart.system.equations { try intersectionAlgebraStep(&usage); rawLaws.append(law) }
                for law in chart.system.denominatorGuards { try intersectionAlgebraStep(&usage); rawLaws.append(law) }
            }
            try RationalAlgebraStorage.retain(raw.cells.count, of: Identifier.self, usage: &usage)
            try RationalAlgebraStorage.retain(raw.cells.count, of: OriginalRationalIntersectionSystem.self, usage: &usage)
            for cell in raw.cells {
                try intersectionAlgebraStep(&usage)
                guard raw.charts.indices.contains(cell.sourceChartIndex) else {
                    throw rationalAlgebraFailure("Original CS boundary cell has a foreign chart owner.")
                }
                systems.append(raw.charts[cell.sourceChartIndex].system)
                owners.append(.curveSurface(cell.identifier))
                for value in cell.sample {
                    try intersectionAlgebraStep(&usage)
                    depth = max(depth, value.inheritedDepth, value.original.context.depth)
                    coefficientDepth = max(coefficientDepth, value.inheritedCoefficientDepth, value.original.context.coefficientDepth)
                }
            }
        case .firstSurface(let raw), .secondSurface(let raw):
            partition = raw.coverage.partition
            switch raw.coverage {
            case .single(let proof):
                let system = proof.system
                try RationalAlgebraStorage.retain(try rationalAlgebraCount(system.equations.count, system.denominatorGuards.count),
                    of: ExactIntersectionPolynomial.self, usage: &usage)
                for law in system.equations { try intersectionAlgebraStep(&usage); rawLaws.append(law) }
                for law in system.denominatorGuards { try intersectionAlgebraStep(&usage); rawLaws.append(law) }
            case .common(let proof):
                try RationalAlgebraStorage.retain(proof.originalLaws.count, of: ExactIntersectionPolynomial.self, usage: &usage)
                for law in proof.originalLaws { try intersectionAlgebraStep(&usage); rawLaws.append(law) }
            }
            depth = try raw.retainedParameterDepth(usage: &usage)
            try RationalAlgebraStorage.retain(raw.cellCount, of: Identifier.self, usage: &usage)
            try RationalAlgebraStorage.retain(raw.cellCount, of: OriginalRationalIntersectionSystem.self, usage: &usage)
            for index in 0..<raw.cellCount {
                try intersectionAlgebraStep(&usage)
                let cell = try raw.cell(at: index); owners.append(.surfaceSurface(cell.identifier))
                switch raw.coverage {
                case .single(let proof): systems.append(proof.system)
                case .common(let proof):
                    guard let partition, partition.solutionCells.indices.contains(index) else {
                        throw rationalAlgebraFailure("Common SSI boundary cells lost their original chart cover.")
                    }
                    let chart = raw.coverage.chartIndex(cellIndex: partition.solutionCells[index])
                    guard proof.charts.indices.contains(chart) else { throw rationalAlgebraFailure("Common SSI boundary cell has a foreign chart owner.") }
                    systems.append(proof.charts[chart].system)
                }
                for value in cell.parameterSample {
                    try intersectionAlgebraStep(&usage)
                    depth = max(depth, value.inheritedDepth, value.original.context.depth)
                    coefficientDepth = max(coefficientDepth, value.inheritedCoefficientDepth, value.original.context.coefficientDepth)
                }
            }
        }
        guard depth <= maximumDepth, coefficientDepth <= maximumCoefficientDepth else {
            throw rationalAlgebraFailure("Boundary clipping cannot reset the original raw receipt's independent source depths.")
        }
        var conditions: [OriginalIntersectionCellCondition] = []
        if let partition {
            guard partition.coefficientVariableCount == 0, partition.solutionCells.count == owners.count else {
                throw rationalAlgebraFailure("Native clipping requires its full original parameter cell cover.")
            }
            try RationalAlgebraStorage.retain(owners.count, of: OriginalIntersectionCellCondition.self, usage: &usage)
            conditions.reserveCapacity(owners.count)
            for index in partition.solutionCells {
                try intersectionAlgebraStep(&usage)
                conditions.append(try .init(partition: partition, cellIndex: index, usage: &usage))
            }
        } else if !owners.isEmpty {
            throw rationalAlgebraFailure("An excluded Native product cannot publish selected boundary cells.")
        }
        self.conditions = conditions; identifiers = owners; laws = rawLaws; self.systems = systems
        parameterDepth = depth; self.coefficientDepth = coefficientDepth
    }
}
