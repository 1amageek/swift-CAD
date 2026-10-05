import CADCore

extension OriginalGuideEndpointConnectorCurve3D {
    private func vectorDerivatives(_ jet: SurfaceAreaIntervalTaylorVectorJet, order: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)?) throws -> IntervalVectorDerivativeJet {
        func axis(_ q: SurfaceAreaIntervalTaylorScalarJet) throws -> IntervalDerivativeJet {
            try OriginalCoefficientAllocation.reserve(count:order+1,of:OutwardScalarInterval.self,consumeStorage:consumeStorage)
            var result:[OutwardScalarInterval] = []; result.reserveCapacity(order+1)
            var factorial = OutwardScalarInterval.exact(1)
            for k in 0...order {
                try consumeWork()
                if k > 0 { factorial = factorial * .exact(Double(k)) }
                result.append(try q.coefficient(k,0)*factorial)
            }
            return .init(derivatives:result)
        }
        return try .init(x:axis(jet.x),y:axis(jet.y),z:axis(jet.z))
    }

    package func derivatives(over parameters:ScalarInterval,throughOrder order:Int,
        tolerance:ModelingTolerance,maximumSpanCount:Int,maximumSubdivisionDepth:Int,
        remainingSourceDepth:Int,consumeWork:()throws->Void,
        consumeStorage:((Int)throws->Void)? = nil, maximumAlgebraicDepth:Int? = nil) throws -> IntervalVectorDerivativeJet {
        guard (0...3).contains(order) else {
            throw GeometryConversionError.invalidInput("Original guide derivative query requires D0 through D3.")
        }
        return try vectorDerivatives(intervalTaylorJet(over:parameters,throughOrder:order,tolerance:tolerance,
            maximumSpanCount:maximumSpanCount,maximumSubdivisionDepth:maximumSubdivisionDepth,
            remainingSourceDepth:remainingSourceDepth,consumeWork:consumeWork,consumeStorage:consumeStorage,
            maximumAlgebraicDepth:maximumAlgebraicDepth),
            order:order,consumeWork:consumeWork,consumeStorage:consumeStorage)
    }

    package func owningDerivativeJets(over parameters:ScalarInterval,throughOrder order:Int,
        tolerance:ModelingTolerance,maximumSpanCount:Int,maximumSubdivisionDepth:Int,
        remainingSourceDepth:Int,consumeWork:()throws->Void,
        consumeStorage:((Int)throws->Void)? = nil, maximumAlgebraicDepth:Int? = nil) throws -> [OriginalGuideTraversalOwningJet] {
        try validate(tolerance:tolerance)
        guard (0...3).contains(order),remainingSourceDepth > 0 else {
            throw GeometryConversionError.invalidInput("Original guide owning correction requires admitted derivative order and source descent.")
        }
        let admittedSource = try admittingQuerySource(maximumAlgebraicDepth:maximumAlgebraicDepth,
            tolerance:tolerance,maximumSubdivisionDepth:maximumSubdivisionDepth,remainingSourceDepth:remainingSourceDepth,
            consumeWork:consumeWork,consumeStorage:consumeStorage)
        guard admittedSource.start == .authored(0),admittedSource.end == .authored(1),
            case .originalGuideTraversalChain(let chain) = admittedSource.source else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Nonidentity RootSpan charts
            // need their exact mapped owning cover before this correction can
            // publish one-sided derivative pieces. Whole interval hulls cannot
            // replace the original guide's source partition.
            throw KernelError(phase:.geometry,code:.unsupportedCapability,tolerance:tolerance,
                message:"Original guide correction lacks its identity aggregate owning chart.")
        }
        let original = try chain.owningDerivativeJets(over:parameters,throughOrder:order,tolerance:tolerance,
            maximumSpanCount:min(maximumSpanCount,self.maximumSpanCount),
            maximumSubdivisionDepth:min(maximumSubdivisionDepth,self.maximumSubdivisionDepth),
            remainingSourceDepth:min(min(remainingSourceDepth,self.remainingSourceDepth)-1,chain.remainingSourceDepth),
            consumeWork:consumeWork,consumeStorage:consumeStorage,maximumAlgebraicDepth:maximumAlgebraicDepth)
        try OriginalCoefficientAllocation.reserve(count:original.count,of:OriginalGuideTraversalOwningJet.self,
            consumeStorage:consumeStorage)
        var result:[OriginalGuideTraversalOwningJet] = []; result.reserveCapacity(original.count)
        for piece in original {
            func axis(_ q:IntervalDerivativeJet) throws -> SurfaceAreaIntervalTaylorScalarJet {
                var scalar = try SurfaceAreaIntervalTaylorScalarJet(order:order,axis:.u,tolerance:tolerance,
                    consumeWork:consumeWork,consumeStorage:consumeStorage)
                var factorial = OutwardScalarInterval.exact(1)
                for k in 0...order {
                    try consumeWork()
                    if k > 0 { factorial = factorial * .exact(Double(k)) }
                    guard let coefficient = q.derivatives[k].divided(by:factorial) else {
                        throw GeometryConversionError.invalidInput("Original guide factorial conversion lost its positive denominator.")
                    }
                    try scalar.set(coefficient,k,0)
                }
                return scalar
            }
            let raw = try SurfaceAreaIntervalTaylorVectorJet(x:axis(piece.jet.x),y:axis(piece.jet.y),z:axis(piece.jet.z))
            let jet = try corrected(raw,over:piece.parameters,throughOrder:order,tolerance:tolerance,
                consumeWork:consumeWork,consumeStorage:consumeStorage)
            result.append(try .init(traversalIndex:piece.traversalIndex,exactLower:piece.exactLower,
                exactUpper:piece.exactUpper,parameters:piece.parameters,
                jet:vectorDerivatives(jet,order:order,consumeWork:consumeWork,consumeStorage:consumeStorage)))
        }
        return result
    }

    package func hasSmoothNativeInterval(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> Bool {
        try validate(tolerance: tolerance)
        guard parameters.lower < parameters.upper, parameters.lower >= 0, parameters.upper <= 1,
            maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth > 0 else {
            throw GeometryConversionError.invalidInput("Original corrected guide smoothness requires its positive normalized interval and independent capabilities.")
        }
        let admitted = try admittingQuerySource(maximumAlgebraicDepth: maximumAlgebraicDepth,
            tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
        return try admitted.hasSmoothNativeInterval(over: parameters, tolerance: tolerance,
            maximumSpanCount: min(maximumSpanCount, self.maximumSpanCount),
            maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth),
            remainingSourceDepth: min(min(remainingSourceDepth, self.remainingSourceDepth)-1, source.remainingSourceDepth),
            consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
    }

    public func point(at parameter:Double,tolerance:ModelingTolerance) throws -> Point3D {
        let value = try preparedFirstOrder(over:.init(lower:parameter,upper:parameter),tolerance:tolerance,
            maximumSpanCount:maximumSpanCount,maximumSubdivisionDepth:maximumSubdivisionDepth,
            remainingSourceDepth:remainingSourceDepth,consumeWork:{}).position
        let candidate = Point3D(x:value.x.midpoint,y:value.y.midpoint,z:value.z.midpoint)
        guard IntervalVector3DBounds(x:value.x - .exact(candidate.x),y:value.y - .exact(candidate.y),
            z:value.z - .exact(candidate.z)).lengthUpperBound <= tolerance.distance else {
            throw GeometryConversionError.toleranceRejected
        }
        return candidate
    }
}
