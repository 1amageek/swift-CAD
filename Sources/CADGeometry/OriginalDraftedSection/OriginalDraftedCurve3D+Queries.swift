import CADCore

extension OriginalDraftedCurve3D {
    package func derivatives(over parameters:ScalarInterval,throughOrder order:Int,
        tolerance:ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> IntervalVectorDerivativeJet {
        let q = try intervalTaylorJet(over:parameters,throughOrder:order,tolerance:tolerance,
            maximumSpanCount:maximumSpanCount,maximumSubdivisionDepth:maximumSubdivisionDepth,
            remainingSourceDepth:remainingSourceDepth,using:&execution)
        func axis(_ scalar:SurfaceAreaIntervalTaylorScalarJet) throws -> IntervalDerivativeJet {
            let count = order.addingReportingOverflow(1)
            guard !count.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original draft derivative dimensions overflow.") }
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count.partialValue, of: OutwardScalarInterval.self))
            var values:[OutwardScalarInterval] = []; values.reserveCapacity(count.partialValue)
            var factorial = OutwardScalarInterval.exact(1)
            for k in 0...order {
                try execution.consumeWork(1)
                if k > 0 { factorial = factorial * .exact(Double(k)) }
                values.append(try scalar.coefficient(k,0)*factorial)
            }
            return .init(derivatives:values)
        }
        return try .init(x:axis(q.x),y:axis(q.y),z:axis(q.z))
    }
}
