import CADCore

extension OriginalGuideTraversalChain3D {
    private struct Usage: RationalAlgebraAdmitting {
        let work: () throws -> Void
        let storage: ((Int) throws -> Void)?
        let geometricDepth: Int
        let algebraicDepth: Int
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0 else { throw GeometryConversionError.invalidInput("Original guide work is negative.") }
            for _ in 0..<count { try Task.checkCancellation(); try work() }
        }
        mutating func retainExactStorage(_ count: Int) throws {
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
            guard count >= 0, !bytes.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original guide storage bytes overflow.") }
            try storage?(bytes.partialValue)
        }
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= algebraicDepth else {
                throw GeometryConversionError.resourceLimitExceeded("Original guide exact scalar query exceeds its independent algebra depth.")
            }
            try consumeExactWork(1)
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            guard depth >= 0, depth <= algebraicDepth else {
                throw GeometryConversionError.resourceLimitExceeded("Original guide coefficient query exceeds its independent algebra depth.")
            }
            try consumeExactWork(1)
        }
    }

    private func selectedAlgebraDepth(_ requested: Int?) throws -> Int {
        guard requested.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Original guide selected algebra capability is outside zero through 32.")
        }
        return min(requested ?? maximumAlgebraicDepth, maximumAlgebraicDepth)
    }

    private func admitting(_ span: OriginalCurveRootSpan3D, selected: Int?,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)?) throws -> OriginalCurveRootSpan3D {
        guard let selected else { return span }
        return try span.admittingQueryAlgebra(selectedAlgebraDepth(selected), tolerance: tolerance,
            maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth),
            remainingSourceDepth: min(min(remainingSourceDepth, self.remainingSourceDepth)-1, span.remainingSourceDepth),
            consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    package func preparedFirstOrder(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> OriginalCurveFirstOrderJet {
        try validate(tolerance: tolerance)
        guard remainingSourceDepth > 0, maximumSpanCount > 0, maximumSubdivisionDepth >= 0 else {
            throw GeometryConversionError.invalidInput("Original guide first-order query lacks source capabilities.")
        }
        return try withoutActuallyEscaping(consumeWork) { work in
            var usage = Usage(work: work, storage: consumeStorage, geometricDepth: maximumSubdivisionDepth,
                algebraicDepth: try selectedAlgebraDepth(maximumAlgebraicDepth))
            let pieces = try selected(over: parameters, usage: &usage)
            guard pieces.count <= min(maximumSpanCount, self.maximumSpanCount) else {
                throw GeometryConversionError.resourceLimitExceeded("Original guide query exceeds its traversal cover admission.")
            }
            var position: IntervalVector3DBounds?, derivative: IntervalVector3DBounds?
            for piece in pieces {
                let retained = traversals[piece.index]
                let span = try admitting(retained, selected: maximumAlgebraicDepth,
                    tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
                    remainingSourceDepth: remainingSourceDepth, consumeWork: work, consumeStorage: consumeStorage)
                let original = try span.preparedFirstOrder(over: piece.local, tolerance: tolerance,
                    maximumSpanCount: min(maximumSpanCount, self.maximumSpanCount),
                    maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth),
                    remainingSourceDepth: min(min(remainingSourceDepth, self.remainingSourceDepth)-1, span.remainingSourceDepth),
                    consumeWork: work, consumeStorage: consumeStorage)
                let gain = try piece.inverseWidth.outwardInterval(usage: &usage)
                let d = IntervalVector3DBounds(x: original.firstDerivative.x*gain,
                    y: original.firstDerivative.y*gain, z: original.firstDerivative.z*gain)
                try usage.consumeExactWork(6)
                if let previous = position {
                    position = .init(x: previous.x.union(original.position.x), y: previous.y.union(original.position.y), z: previous.z.union(original.position.z))
                } else { position = original.position }
                if let previous = derivative {
                    derivative = .init(x: previous.x.union(d.x), y: previous.y.union(d.y), z: previous.z.union(d.z))
                } else { derivative = d }
            }
            guard let position, let derivative else { throw GeometryConversionError.invalidInput("Original guide first-order cover is empty.") }
            return .init(position: position, firstDerivative: derivative)
        }
    }

    package func intervalTaylorJet(over parameters: ScalarInterval, throughOrder order: Int,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int? = nil) throws -> SurfaceAreaIntervalTaylorVectorJet {
        try validate(tolerance: tolerance)
        guard (0...3).contains(order), maximumSpanCount > 0,
            maximumSubdivisionDepth >= 0, remainingSourceDepth > 0 else {
            throw GeometryConversionError.invalidInput("Original guide Taylor query requires admitted D0 through D3 source capabilities.")
        }
        return try withoutActuallyEscaping(consumeWork) { work in
            var usage = Usage(work: work, storage: consumeStorage, geometricDepth: maximumSubdivisionDepth,
                algebraicDepth: try selectedAlgebraDepth(maximumAlgebraicDepth))
            let pieces = try selected(over: parameters, usage: &usage)
            guard pieces.count <= min(maximumSpanCount, self.maximumSpanCount) else {
                throw GeometryConversionError.resourceLimitExceeded("Original guide Taylor cover exceeds caller admission.")
            }
            if pieces.count > 1, order > provenContinuityOrder {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Original guide aggregate jets
                // crossing nonrational/retained-algebraic joins need exact requested
                // derivative equality before a whole smooth jet is published.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original guide join has no admitted requested-order differential continuity.")
            }
            var result: SurfaceAreaIntervalTaylorVectorJet?
            for piece in pieces {
                let retained = traversals[piece.index]
                let span = try admitting(retained, selected: maximumAlgebraicDepth,
                    tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
                    remainingSourceDepth: remainingSourceDepth, consumeWork: work, consumeStorage: consumeStorage)
                let original = try span.intervalTaylorJet(over: piece.local, throughOrder: order,
                    tolerance: tolerance, consumeWork: work, maximumSpanCount: min(maximumSpanCount, self.maximumSpanCount),
                    remainingSourceDepth: min(min(remainingSourceDepth, self.remainingSourceDepth)-1, span.remainingSourceDepth),
                    consumeStorage: consumeStorage,
                    maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth))
                func axis(_ q: SurfaceAreaIntervalTaylorScalarJet,
                    previous: SurfaceAreaIntervalTaylorScalarJet?) throws -> SurfaceAreaIntervalTaylorScalarJet {
                    var output = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
                        tolerance: tolerance, consumeWork: work, consumeStorage: consumeStorage)
                    var gain = ExactRationalCoefficient.one
                    for k in 0...order {
                        if k > 0 { gain = try gain.multiplied(by: piece.inverseWidth, usage: &usage) }
                        let bound = try q.coefficient(k,0) * gain.outwardInterval(usage: &usage)
                        if let previous {
                            try output.set(previous.coefficient(k,0).union(bound), k, 0)
                        } else { try output.set(bound, k, 0) }
                    }
                    return output
                }
                result = try .init(x: axis(original.x, previous: result?.x),
                    y: axis(original.y, previous: result?.y), z: axis(original.z, previous: result?.z))
            }
            guard let result else { throw GeometryConversionError.invalidInput("Original guide Taylor cover is empty.") }
            return result
        }
    }

    package func derivatives(over parameters: ScalarInterval, throughOrder order: Int,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int? = nil) throws -> IntervalVectorDerivativeJet {
        let jet = try intervalTaylorJet(over: parameters, throughOrder: order, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        func axis(_ original: SurfaceAreaIntervalTaylorScalarJet) throws -> IntervalDerivativeJet {
            try OriginalCoefficientAllocation.reserve(count: order+1, of: OutwardScalarInterval.self, consumeStorage: consumeStorage)
            var result: [OutwardScalarInterval] = []; result.reserveCapacity(order+1)
            var factorial = OutwardScalarInterval.exact(1)
            for k in 0...order {
                try consumeWork()
                if k > 0 { factorial = factorial * .exact(Double(k)) }
                result.append(try original.coefficient(k,0)*factorial)
            }
            return .init(derivatives: result)
        }
        return try .init(x: axis(jet.x), y: axis(jet.y), z: axis(jet.z))
    }

    /// Retains every original one-sided piece without granting smooth joins.
    package func owningDerivativeJets(over parameters: ScalarInterval, throughOrder order: Int,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int? = nil) throws -> [OriginalGuideTraversalOwningJet] {
        try validate(tolerance: tolerance)
        guard (0...3).contains(order), remainingSourceDepth > 0, maximumSpanCount > 0,
            maximumSubdivisionDepth >= 0 else {
            throw GeometryConversionError.invalidInput("Original guide owning jets require admitted D0 through D3 capabilities.")
        }
        return try withoutActuallyEscaping(consumeWork) { work in
            var usage = Usage(work: work, storage: consumeStorage, geometricDepth: maximumSubdivisionDepth,
                algebraicDepth: try selectedAlgebraDepth(maximumAlgebraicDepth))
            let pieces = try selected(over: parameters, usage: &usage)
            guard pieces.count <= min(maximumSpanCount, self.maximumSpanCount) else {
                throw GeometryConversionError.resourceLimitExceeded("Original guide owning jet count exceeds caller admission.")
            }
            try RationalAlgebraStorage.retain(pieces.count, of: OriginalGuideTraversalOwningJet.self, usage: &usage)
            var result: [OriginalGuideTraversalOwningJet] = []; result.reserveCapacity(pieces.count)
            for piece in pieces {
                let retained = traversals[piece.index]
                let span = try admitting(retained, selected: maximumAlgebraicDepth,
                    tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
                    remainingSourceDepth: remainingSourceDepth, consumeWork: work, consumeStorage: consumeStorage)
                let original = try span.intervalTaylorJet(over: piece.local, throughOrder: order,
                    tolerance: tolerance, consumeWork: work,
                    maximumSpanCount: min(maximumSpanCount, self.maximumSpanCount),
                    remainingSourceDepth: min(min(remainingSourceDepth, self.remainingSourceDepth)-1, span.remainingSourceDepth),
                    consumeStorage: consumeStorage,
                    maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth))
                func axis(_ source: SurfaceAreaIntervalTaylorScalarJet) throws -> IntervalDerivativeJet {
                    try RationalAlgebraStorage.retain(order+1, of: OutwardScalarInterval.self, usage: &usage)
                    var derivatives: [OutwardScalarInterval] = []; derivatives.reserveCapacity(order+1)
                    var gain = ExactRationalCoefficient.one, factorial = OutwardScalarInterval.exact(1)
                    for k in 0...order {
                        if k > 0 {
                            gain = try gain.multiplied(by: piece.inverseWidth, usage: &usage)
                            factorial = factorial * .exact(Double(k))
                        }
                        try usage.consumeExactWork(2)
                        derivatives.append(try source.coefficient(k,0) * gain.outwardInterval(usage: &usage) * factorial)
                    }
                    return .init(derivatives: derivatives)
                }
                let a = try piece.lower.outwardInterval(usage: &usage), b = try piece.upper.outwardInterval(usage: &usage)
                result.append(try .init(traversalIndex: piece.index, exactLower: piece.lower, exactUpper: piece.upper,
                    parameters: .init(lower: max(0,a.lower), upper: min(1,b.upper)),
                    jet: .init(x: axis(original.x), y: axis(original.y), z: axis(original.z))))
            }
            return result
        }
    }

    package func hasSmoothNativeInterval(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> Bool {
        try validate(tolerance: tolerance)
        guard parameters.lower < parameters.upper, remainingSourceDepth > 0,
            maximumSpanCount > 0, maximumSubdivisionDepth >= 0,
            maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Original guide smoothness requires a positive admitted source interval.")
        }
        return try withoutActuallyEscaping(consumeWork) { work in
            var usage = Usage(work: work, storage: consumeStorage, geometricDepth: maximumSubdivisionDepth,
                algebraicDepth: min(maximumAlgebraicDepth ?? self.maximumAlgebraicDepth,self.maximumAlgebraicDepth))
            let pieces = try selected(over: parameters, usage: &usage)
            guard pieces.count <= min(maximumSpanCount, self.maximumSpanCount) else {
                throw GeometryConversionError.resourceLimitExceeded("Original guide smoothness cover exceeds its caller span admission.")
            }
            var positiveCount = 0
            for piece in pieces where piece.lower != piece.upper {
                positiveCount += 1
                let span = traversals[piece.index]
                guard try span.hasSmoothNativeInterval(over: piece.local, tolerance: tolerance,
                    maximumSpanCount: min(maximumSpanCount,self.maximumSpanCount),
                    maximumSubdivisionDepth: min(maximumSubdivisionDepth,self.maximumSubdivisionDepth),
                    remainingSourceDepth: min(min(remainingSourceDepth,self.remainingSourceDepth)-1,span.remainingSourceDepth),
                    consumeWork: work,consumeStorage: consumeStorage,
                    maximumAlgebraicDepth: usage.algebraicDepth) else { return false }
            }
            return positiveCount == 1 || (positiveCount > 1 && provenContinuityOrder >= 2)
        }
    }

    public func point(at parameter: Double, tolerance: ModelingTolerance) throws -> Point3D {
        let q = try intervalTaylorJet(over: .init(lower: parameter, upper: parameter), throughOrder: 0,
            tolerance: tolerance, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, consumeWork: {})
        let x = try q.x.coefficient(0,0), y = try q.y.coefficient(0,0), z = try q.z.coefficient(0,0)
        let candidate = Point3D(x:x.midpoint, y:y.midpoint, z:z.midpoint)
        guard IntervalVector3DBounds(x:x - .exact(candidate.x), y:y - .exact(candidate.y),
            z:z - .exact(candidate.z)).lengthUpperBound <= tolerance.distance else { throw GeometryConversionError.toleranceRejected }
        return candidate
    }
}
