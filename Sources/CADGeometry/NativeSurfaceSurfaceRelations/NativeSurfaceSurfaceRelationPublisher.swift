import CADCore

/// Publishes the existing complete original decomposition without numerical connectivity.
package struct NativeSurfaceSurfaceRelationPublisher {
    private struct PreparedGraph {
        let partition: OriginalRationalIntersectionCells
        let ideal: ExactIntersectionIdeal
    }
    package static func publish<B: RationalAlgebraAdmitting>(first: BSplineSurface3D,
        second: BSplineSurface3D, tolerance: ModelingTolerance,
        decomposition: OriginalRationalIntersectionDecomposition, maximumDepth: Int,
        inheritedParameterDepth: Int = 0, parentRelation: OriginalNativeSurfaceSurfaceRelations? = nil, usage: inout B) throws -> OriginalNativeSurfaceSurfaceRelations {
        try publish(first: first, second: second, tolerance: tolerance, coverage: .single(decomposition),
            maximumDepth: maximumDepth, inheritedParameterDepth: inheritedParameterDepth,
            parentRelation: parentRelation, usage: &usage)
    }

    package static func publish<B: RationalAlgebraAdmitting>(first: BSplineSurface3D,
        second: BSplineSurface3D, tolerance: ModelingTolerance,
        coverage: NativeSurfaceSurfaceCoverage, maximumDepth: Int,
        inheritedParameterDepth: Int = 0, parentRelation: OriginalNativeSurfaceSurfaceRelations? = nil,
        sourceMapProof: NativeSurfaceSurfaceChartInjectionProof? = nil, usage: inout B) throws -> OriginalNativeSurfaceSurfaceRelations {
        try intersectionAlgebraStep(&usage)
        if let sourceMapProof {
            guard case .common(let common) = coverage else { throw rationalAlgebraFailure("Source injection evidence requires genuine common coverage.") }
            try sourceMapProof.validate(charts: common.charts, usage: &usage)
        }
        guard let partition = coverage.partition else {
            try retainOwner(usage: &usage)
            try CurrentTaskCancellationChecker().checkCancellation()
            return try .init(first: first, second: second, tolerance: tolerance,
                coverage: coverage, graph: nil, conditions: [], images: [], inheritedParameterDepth: inheritedParameterDepth,
                parentRelation: parentRelation, sourceMapProof: sourceMapProof, usage: &usage)
        }
        try RationalAlgebraStorage.retain(partition.solutionCells.count, of: OriginalIntersectionCellCondition.self, usage: &usage)
        var conditions: [OriginalIntersectionCellCondition] = []; conditions.reserveCapacity(partition.solutionCells.count)
        for index in partition.solutionCells {
            conditions.append(try .init(partition: partition, cellIndex: index, usage: &usage))
        }
        try RationalAlgebraStorage.retain(conditions.count, of: [OriginalNativeSurfaceSurfaceRelations.ImageStratum].self, usage: &usage)
        var images = Array(repeating: [OriginalNativeSurfaceSurfaceRelations.ImageStratum](), count: conditions.count)
        let graph: OriginalRationalIntersectionCells?
        let graphIdeal: ExactIntersectionIdeal?
        let graphGuardedEquations: [OriginalGuardedIntersectionEquations]
        if sourceMapProof == nil && partition.solutionCells.contains(where: { partition.cells[$0].dimension > 0 }) {
            switch coverage {
            case .single(let decomposition):
                let prepared = try prepareGraph(decomposition: decomposition, conditions: conditions,
                    maximumDepth: maximumDepth, usage: &usage)
                graph = prepared.partition; graphIdeal = prepared.ideal; graphGuardedEquations = []
            case .common(let common):
                let prepared = try NativeSurfaceSurfaceCommonGraph.prepare(coverage: common, conditions: conditions,
                    maximumDepth: maximumDepth, usage: &usage)
                graph = prepared.partition; graphIdeal = prepared.ideal; graphGuardedEquations = prepared.guardedEquations
            }
            guard let graph else { throw rationalAlgebraFailure("Original SSI graph coverage was not retained.") }
            try RationalAlgebraStorage.retain(graph.solutionCells.count, of: Int.self, usage: &usage)
            try RationalAlgebraStorage.retain(conditions.count, of: Int.self, usage: &usage)
            var owners: [Int] = []; owners.reserveCapacity(graph.solutionCells.count)
            var imageCounts = Array(repeating: 0, count: conditions.count)
            for index in graph.solutionCells {
                try intersectionAlgebraStep(&usage)
                let cell = graph.cells[index]
                try RationalAlgebraStorage.retain(4, of: OriginalSingularFieldElement.self, usage: &usage)
                let parameters = Array(cell.coordinates[3...])
                var selected: Int?
                for ordinal in conditions.indices {
                    let source = partition.cells[conditions[ordinal].cellIndex]
                    let inherited = max(source.admissionDepth, cell.admissionDepth)
                    guard inherited <= maximumDepth else { throw rationalAlgebraFailure("SSI graph mapping cannot reset original cell depth.") }
                    var admission = OriginalSourceScalarAdmission(base: usage, maximumDepth: maximumDepth,
                        maximumCoefficientDepth: 0, originalParameterDepth: cell.context.depth,
                        originalCoefficientDepth: 0, inheritedParameterDepth: inherited,
                        inheritedCoefficientDepth: 0, parameterDepth: inherited, coefficientDepth: 0)
                    let available = try rationalAlgebraCount(cell.context.depth, maximumDepth - inherited)
                    let included: Bool
                    do { included = try conditions[ordinal].contains(context: cell.context,
                        coordinates: parameters, maximumDepth: available, usage: &admission) }
                    catch { usage = admission.base; throw error }
                    usage = admission.base
                    if included {
                        guard selected == nil else { throw rationalAlgebraFailure("An SSI graph cell belongs to two original UV cells.") }
                        selected = ordinal
                    }
                }
                guard let ordinal = selected else { throw rationalAlgebraFailure("An SSI graph cell has no original UV cell owner.") }
                owners.append(ordinal)
                imageCounts[ordinal] = try rationalAlgebraCount(imageCounts[ordinal], 1)
            }
            for ordinal in conditions.indices {
                try RationalAlgebraStorage.retain(imageCounts[ordinal], of: OriginalNativeSurfaceSurfaceRelations.ImageStratum.self, usage: &usage)
                images[ordinal].reserveCapacity(imageCounts[ordinal])
            }
            for (graphOrdinal, index) in graph.solutionCells.enumerated() {
                try intersectionAlgebraStep(&usage)
                let ordinal = owners[graphOrdinal], cell = graph.cells[index]
                var prefix = index
                while graph.stacks[graph.cells[prefix].stackIndex].axis > 2 {
                    guard let parent = graph.stacks[graph.cells[prefix].stackIndex].parentCell else {
                        throw rationalAlgebraFailure("An SSI graph cell lost its complete XYZ prefix.")
                    }
                    prefix = parent; try intersectionAlgebraStep(&usage)
                }
                let imageDimension = graph.cells[prefix].dimension
                guard imageDimension <= cell.dimension, imageDimension <= 2 else {
                    throw rationalAlgebraFailure("Original SSI graph image/fiber dimensions contradict a surface image.")
                }
                try RationalAlgebraStorage.retain(7, of: OriginalAlgebraicCoordinate.self, usage: &usage)
                var sample: [OriginalAlgebraicCoordinate] = []; sample.reserveCapacity(7)
                for value in cell.coordinates {
                    sample.append(.init(original: value, inheritedDepth: try rationalAlgebraCount(inheritedParameterDepth, cell.admissionDepth),
                        inheritedCoefficientDepth: cell.coefficientAdmissionDepth))
                }
                images[ordinal].append(.init(ordinal: index, parameterDimension: cell.dimension,
                    imageDimension: imageDimension, fiberDimension: cell.dimension - imageDimension, sample: sample))
            }
        } else {
            graph = nil; graphIdeal = nil; graphGuardedEquations = []
            for ordinal in conditions.indices {
                let cell = partition.cells[conditions[ordinal].cellIndex]
                if sourceMapProof != nil, cell.dimension > 2 {
                    throw rationalAlgebraFailure("An injective original surface chart cannot publish an image above dimension two.")
                }
                try RationalAlgebraStorage.retain(7, of: OriginalAlgebraicCoordinate.self, usage: &usage)
                var sample: [OriginalAlgebraicCoordinate] = []; sample.reserveCapacity(7)
                let source = coverage.firstLaw(cellIndex: conditions[ordinal].cellIndex)
                let weight = try value(source.homogeneous[3], cell: cell, maximumDepth: maximumDepth, usage: &usage)
                for axis in 0..<3 {
                    let position = try value(source.homogeneous[axis], cell: cell, maximumDepth: maximumDepth, usage: &usage)
                        .divided(by: weight, maximumDepth: maximumDepth, usage: &usage)
                    sample.append(.init(original: position, inheritedDepth: try rationalAlgebraCount(inheritedParameterDepth, cell.admissionDepth),
                        inheritedCoefficientDepth: cell.coefficientAdmissionDepth))
                }
                for value in cell.coordinates {
                    sample.append(.init(original: value, inheritedDepth: try rationalAlgebraCount(inheritedParameterDepth, cell.admissionDepth),
                        inheritedCoefficientDepth: cell.coefficientAdmissionDepth))
                }
                try RationalAlgebraStorage.retain(1, of: OriginalNativeSurfaceSurfaceRelations.ImageStratum.self, usage: &usage)
                images[ordinal].reserveCapacity(1)
                images[ordinal].append(.init(ordinal: conditions[ordinal].cellIndex, parameterDimension: cell.dimension,
                    imageDimension: cell.dimension, fiberDimension: 0, sample: sample))
            }
        }
        for ordinal in conditions.indices {
            let dimension = images[ordinal].reduce(0) { max($0, $1.parameterDimension) }
            guard !images[ordinal].isEmpty, dimension == partition.cells[conditions[ordinal].cellIndex].dimension else { throw rationalAlgebraFailure("An SSI graph omitted an entire selected original cell.") }
        }
        try retainOwner(usage: &usage)
        let result = try OriginalNativeSurfaceSurfaceRelations(first: first, second: second,
            tolerance: tolerance, coverage: coverage, graph: graph, graphIdeal: graphIdeal, graphGuardedEquations: graphGuardedEquations, conditions: conditions, images: images, inheritedParameterDepth: inheritedParameterDepth,
            parentRelation: parentRelation, sourceMapProof: sourceMapProof, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        return result
    }

    private static func prepareGraph<B: RationalAlgebraAdmitting>(decomposition: OriginalRationalIntersectionDecomposition,
        conditions: [OriginalIntersectionCellCondition], maximumDepth: Int, usage: inout B) throws -> PreparedGraph {
        guard let effective = decomposition.effectiveDomains else { throw rationalAlgebraFailure("SSI graph requires the complete effective original product.") }
        let system = decomposition.system, source = system.firstSurfaceSource
        try RationalAlgebraStorage.retain(4, of: Int.self, usage: &usage)
        let parameterAxes = [3,4,5,6]
        let count = try rationalAlgebraCount(decomposition.guardedEquations?.normalizedEquations.count ?? system.equations.count, 3)
        try RationalAlgebraStorage.retain(count, of: ExactIntersectionPolynomial.self, usage: &usage)
        var equations: [ExactIntersectionPolynomial] = []; equations.reserveCapacity(count)
        for equation in decomposition.guardedEquations?.normalizedEquations ?? system.equations {
            equations.append(try equation.remapped(to: 7, coordinates: parameterAxes, usage: &usage))
        }
        let weight = try ExactIntersectionPolynomial.embedding(source.homogeneous[3], variableCount: 7,
            uCoordinate: 3, vCoordinate: 4, usage: &usage)
        for axis in 0..<3 {
            let coordinate = try ExactIntersectionPolynomial.coordinate(variableCount: 7, at: axis, usage: &usage)
            let position = try ExactIntersectionPolynomial.embedding(source.homogeneous[axis], variableCount: 7,
                uCoordinate: 3, vCoordinate: 4, usage: &usage)
            equations.append(try coordinate.multiplied(by: weight, usage: &usage).subtracting(position, usage: &usage))
        }
        let ideal = try ExactIntersectionIdeal.prepare(equations: equations, variableCount: 7, usage: &usage)
        var witnessCapacity = 0
        for condition in conditions {
            try intersectionAlgebraStep(&usage)
            witnessCapacity = try rationalAlgebraCount(witnessCapacity, condition.polynomials.count)
        }
        try RationalAlgebraStorage.retain(witnessCapacity, of: ExactIntersectionPolynomial.self, usage: &usage)
        var witnesses: [ExactIntersectionPolynomial] = []; witnesses.reserveCapacity(witnessCapacity)
        for condition in conditions {
            for polynomial in condition.polynomials {
                let original = try polynomial.remapped(to: 7, coordinates: parameterAxes, usage: &usage)
                let mapped = try ExactIntersectionGroebnerBasis.reduced(original, by: ideal.reducedBasis, usage: &usage)
                if mapped.isZero || mapped.isConstant { continue }
                var duplicate = false
                for existing in witnesses {
                    if try existing.matches(mapped, usage: &usage) { duplicate = true; break }
                }
                if !duplicate {
                    witnesses.append(mapped)
                }
            }
        }
        try RationalAlgebraStorage.retain(system.denominatorGuards.count, of: ExactIntersectionPolynomial.self, usage: &usage)
        var guards: [ExactIntersectionPolynomial] = []; guards.reserveCapacity(system.denominatorGuards.count)
        for guardPolynomial in system.denominatorGuards {
            guards.append(try guardPolynomial.remapped(to: 7, coordinates: parameterAxes, usage: &usage))
        }
        try RationalAlgebraStorage.retain(7, of: OriginalRationalParameterDomain.self, usage: &usage)
        var domains: [OriginalRationalParameterDomain] = []; domains.reserveCapacity(7)
        for _ in 0..<3 { domains.append(try .init(lower: nil, upper: nil, usage: &usage)) }
        domains.append(contentsOf: effective)
        let partition = try OriginalRationalIntersectionCells.prepare(equations: ideal.reducedBasis, variableCount: 7,
            exactDomains: domains, partitionPolynomials: witnesses, nonzeroPolynomials: guards,
            thomEncoding: true, pruneExcludedPrefixes: true, maximumDepth: maximumDepth, usage: &usage)
        return .init(partition: partition,ideal: ideal)
    }

    private static func value<B: RationalAlgebraAdmitting>(_ polynomial: ExactBivariatePolynomial,
        cell: OriginalRationalIntersectionCells.Cell, maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        let embedded = try ExactIntersectionPolynomial.embedding(polynomial, variableCount: 4,
            uCoordinate: 0, vCoordinate: 1, usage: &usage)
        return try OriginalIntersectionFieldEvaluation.evaluated(embedded, context: cell.context,
            coordinates: cell.coordinates, maximumDepth: maximumDepth, usage: &usage)
    }
    private static func retainOwner<B: RationalAlgebraAdmitting>(usage: inout B) throws {
        try RationalAlgebraStorage.retainBytes(MemoryLayout<OriginalNativeSurfaceSurfaceRelations>.stride
            + 2 * MemoryLayout<BSplineSurface3D>.stride + MemoryLayout<ModelingTolerance>.stride
            + MemoryLayout<NativeSurfaceSurfaceCoverage>.stride
            + MemoryLayout<OriginalRationalIntersectionCells?>.stride + MemoryLayout<ExactIntersectionIdeal?>.stride + 10 * MemoryLayout<[Int]>.stride
            + MemoryLayout<[OriginalGuardedIntersectionEquations]>.stride
            + 2 * MemoryLayout<UInt>.stride + MemoryLayout<Int>.stride
            + MemoryLayout<OriginalNativeSurfaceSurfaceRelations?>.stride
            + MemoryLayout<NativeSurfaceSurfaceChartInjectionProof?>.stride, usage: &usage)
    }
}
