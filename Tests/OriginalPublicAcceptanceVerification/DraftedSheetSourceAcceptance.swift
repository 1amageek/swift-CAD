import CADCore
@testable import CADGeometry

/// Checks the actual forward weighted generator, nonzero angle and complete projected product.
@main struct DraftedSheetSourceAcceptance {
    static func require(_ value:Bool) throws { guard value else { throw ExactScalarFailure.invalidEvidence } }
    static func scalarFailure(_ error: any Error) -> ExactScalarFailure? {
        if let failure = error as? ExactScalarFailure { return failure }
        if let failure = error as? OriginalSourceIssuanceFailure {
            switch failure {
            case .scalar(let cause): return scalarFailure(cause)
            case .sourceRejected(let cause): return scalarFailure(cause)
            default: return nil
            }
        }
        if let failure = error as? OriginalDomainIdentityFailure {
            switch failure {
            case .scalar(let cause): return scalarFailure(cause)
            case .operationRejected(let cause): return scalarFailure(cause)
            case .source(let cause): return scalarFailure(cause)
            default: return nil
            }
        }
        if let failure = error as? ExactPolynomialFailure {
            switch failure {
            case .scalar(let cause): return scalarFailure(cause)
            case .operationRejected(let cause): return scalarFailure(cause)
            default: return nil
            }
        }
        return nil
    }
    static func main() throws {
        var a=ExactScalarLedger(limits:try .init(work:8_388_608,storageBytes:8_388_608,valueDepth:32,coefficientDepth:32))
        let wall=try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let native=BSplineCurve3D(degree:1,knots:[0,0,1,1],controlPoints:[.origin,.init(x:1,y:0,z:0)],weights:[1,2])
            let generator=try OriginalCurveRootSpan3D(source:.bSpline(native),start:.authored(0),end:.authored(1),nativeSpanIndex:1,
                maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:20,tolerance:.standard,
                storageByteStride:4,usage:&usage,maximumSpanCount:2,remainingSourceDepth:20,maximumAlgebraicDepth:32)
            let start=try OriginalDraftedCurve3D(generator:generator,normal:.unitZ,axis:.unitZ,pull:.unitZ,
                height:0,angle:1e-12,remainingSourceDepth:20,tolerance:.standard,usage:&usage)
            return try OriginalDraftedRuledSurface3D(start:start,endHeight:2,remainingSourceDepth:20,tolerance:.standard,usage:&usage)
        }.value
        let limits=try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:3),maximumTransportDepth:32,
            maximumCharts:2,maximumFamilies:2,maximumIdentityProofs:2)
        var proofAdmission=ExactScalarLedger(limits:try .init(work:8_388_608,storageBytes:8_388_608,valueDepth:32,coefficientDepth:32))
        let result=try OriginalDraftedSelfExclusion.prepare(wall,limits:limits,maximumPairs:4,using:&proofAdmission)
        let cost=(proofAdmission.work,proofAdmission.storageBytes,proofAdmission.valueDepth,proofAdmission.coefficientDepth)
        try require(wall.remainingSourceDepth==20 && result.family.source.sourceDepth==3)
        try require(result.original==wall && result.original.start.angle==1e-12)
        try require(result.raw.count==1 && result.family.graphs.count==1)
        let symbolic=result.raw[0]
        try require(symbolic.kind == .surfaceSurface && symbolic.parameterCount==4)
        let projection=result.family
        let graph=projection.graphs[0].original.graph,ring=graph.polynomials,field=graph.field
        let u=try ring.variable(0,using:&a),v=try ring.variable(1,using:&a)
        let one=try ring.constant(field.integer(1,using:&a),using:&a)
        let two=try ring.constant(field.integer(2,using:&a),using:&a)
        let denominator=try ring.adding(one,u,using:&a)
        let x=try ring.multiplying(two,u,using:&a),z=try ring.multiplying(two,v,using:&a)
        try require(ring.equals(ring.multiplying(graph.homogeneous[0],denominator,using:&a),
            ring.multiplying(x,graph.homogeneous[3],using:&a),using:&a))
        try require(ring.equals(graph.homogeneous[1],ring.multiplying(z,graph.homogeneous[3],using:&a),using:&a))
#if !hasFeature(Embedded)
        print("PROOF COST",cost.0,cost.1,"DEPTH",cost.2,cost.3)
#endif
        print("PASS actual nonzero drafted source, exact X/Z oracle, complete symbolic diagonal exclusion under8MiB")
        var exact=ExactScalarLedger(limits:try .init(work:cost.0,storageBytes:cost.1,valueDepth:cost.2,coefficientDepth:cost.3))
        let detached=try OriginalDraftedSelfExclusion.prepare(wall,limits:limits,maximumPairs:4,using:&exact)
        try require(exact.work==cost.0 && exact.storageBytes==cost.1 && detached.original==wall)
        for resource in [ExactResource.work,.storage] {
            var rejected=ExactScalarLedger(limits:try .init(work:cost.0-(resource == .work ? 1:0),
                storageBytes:cost.1-(resource == .storage ? 1:0),valueDepth:32,coefficientDepth:32))
            do {
                _ = try OriginalDraftedSelfExclusion.prepare(wall,limits:limits,maximumPairs:4,using:&rejected)
                throw ExactScalarFailure.invalidEvidence
            } catch {
                guard let failure=scalarFailure(error),case .resourceLimit(let actual)=failure else { throw error }
                try require(actual==resource)
            }
        }
        var sourceRejected=ExactScalarLedger(limits:try .init(work:8_388_608,storageBytes:8_388_608,valueDepth:32,coefficientDepth:32))
        let tooShallow=try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:2),maximumTransportDepth:32,
            maximumCharts:2,maximumFamilies:2,maximumIdentityProofs:2)
        do {
            _ = try OriginalDraftedSelfExclusion.prepare(wall,limits:tooShallow,maximumPairs:4,using:&sourceRejected)
            throw ExactScalarFailure.invalidEvidence
        } catch let failure as OriginalSourceIssuanceFailure {
            guard case .sourceDepthLimit=failure else { throw failure }
        }
        var cancelled=ExactScalarLedger(limits:try .init(work:8_388_608,storageBytes:8_388_608,valueDepth:32,coefficientDepth:32))
        cancelled.cancel()
        do {
            _ = try OriginalDraftedSelfExclusion.prepare(wall,limits:limits,maximumPairs:4,using:&cancelled)
            throw ExactScalarFailure.invalidEvidence
        } catch let failure as ExactScalarFailure {
            guard case .cancelled=failure else { throw failure }
        }
        try require(cancelled.work==0 && detached.original.start.angle==1e-12)
        print("PASS exact N/N-1 work/storage, original source depth3 versus retained ceiling20, cancellation and detached owner")
    }
}
