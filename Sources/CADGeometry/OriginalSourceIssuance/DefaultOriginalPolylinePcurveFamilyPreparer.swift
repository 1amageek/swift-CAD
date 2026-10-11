import CADCore

/// Prepares each original once, extending only the explicit retained ancestor.
public struct DefaultOriginalPolylinePcurveFamilyPreparer: OriginalPolylinePcurveFamilyPreparing {
    public let maximumValueDepth: Int
    public let maximumCoefficientDepth: Int
    public init(maximumValueDepth: Int,maximumCoefficientDepth: Int) {
        self.maximumValueDepth=maximumValueDepth;self.maximumCoefficientDepth=maximumCoefficientDepth
    }
    public func prepare<A: ExactScalarAdmission & ~Copyable>(_ originals: borrowing [SurfaceParameterCurve],
        maximumCurves: Int,limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalPreparedPolylinePcurves {
        do {
            try admission.checkpoint();try admission.consumeWork(1)
            guard maximumCurves>=0,originals.count<=maximumCurves else { throw OriginalSourceIssuanceFailure.chartLimit }
            var field=try OriginalExactScalarDomain(maximumValueDepth:maximumValueDepth,
                maximumCoefficientDepth:maximumCoefficientDepth,using:&admission)
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:originals.count,of:OriginalSourceBinding<OriginalPolylinePcurveSnapshot>.self))
            var sources: [OriginalSourceBinding<OriginalPolylinePcurveSnapshot>]=[]
            sources.reserveCapacity(originals.count)
            for index in originals.indices {
                try admission.consumeWork(1)
                let source=try DefaultOriginalSourceBindingIssuer(provider:OriginalPolylinePcurveSnapshotProvider(field:field))
                    .bind(originals[index],limits:limits,using:&admission)
                sources.append(source);field=source.original.originalField
            }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalPreparedPolylinePcurves.self))
            let result=OriginalPreparedPolylinePcurves(sources:sources,field:field)
            try admission.checkpoint();return result
        } catch { throw .init(preserving:error) }
    }
}
