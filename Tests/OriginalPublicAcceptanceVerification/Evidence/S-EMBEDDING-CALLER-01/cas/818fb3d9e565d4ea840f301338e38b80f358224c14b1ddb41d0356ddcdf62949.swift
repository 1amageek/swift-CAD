import CADCore
@testable import CADGeometry
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif

/// Exercises the actual Geometry caller with a value-owned word admission.
@main struct EmbeddingCallerAcceptance {
    struct Usage: RationalAlgebraAdmitting {
        var work = 0
        var words = 0
        var maximumValueVisit = 0
        var maximumCoefficientVisit = 0
        let workLimit: Int
        let wordLimit: Int
        let valueDepth: Int
        let coefficientDepth: Int
        let cancelAtWork: Int?
        init(work: Int = 80_000_000, words: Int = 268_435_456, valueDepth: Int = 32, coefficientDepth: Int = 32,
            cancelAtWork: Int? = nil) {
            workLimit=work;wordLimit=words;self.valueDepth=valueDepth;self.coefficientDepth=coefficientDepth
            self.cancelAtWork=cancelAtWork
        }
        mutating func consumeExactWork(_ count: Int) throws {
            let sum=work.addingReportingOverflow(count)
            guard count>=0,!sum.overflow,sum.partialValue<=workLimit else { throw ExactScalarFailure.resourceLimit(.work) }
            work=sum.partialValue
            if let cancelAtWork, work>=cancelAtWork { withUnsafeCurrentTask { $0?.cancel() } }
        }
        mutating func retainExactStorage(_ count: Int) throws {
            let sum=words.addingReportingOverflow(count)
            guard count>=0,!sum.overflow,sum.partialValue<=wordLimit else { throw ExactScalarFailure.resourceLimit(.storage) }
            words=sum.partialValue
        }
        mutating func visitExactCell(depth: Int) throws {
            maximumValueVisit=max(maximumValueVisit,depth)
            guard depth>=0,depth<=valueDepth else { throw ExactScalarFailure.resourceLimit(.valueDepth) }
            try consumeExactWork(1)
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            maximumCoefficientVisit=max(maximumCoefficientVisit,depth)
            guard depth>=0,depth<=coefficientDepth else { throw ExactScalarFailure.resourceLimit(.coefficientDepth) }
            try consumeExactWork(1)
        }
    }
    static func require(_ condition: Bool) throws { guard condition else { throw ExactScalarFailure.invalidEvidence } }
    static func coons() throws -> Surface3D {
        var a=ExactScalarLedger(limits:try .init(work:80_000_000,storageBytes:1_073_741_824,valueDepth:32,coefficientDepth:32))
        return try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let t=[0.0,0.5,1.0]
            let native=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,0.5,1,1],vKnots:[0,0,0.5,1,1],
                controlPoints:t.map { v in t.map { u in Point3D(x:u,y:v,z:0) } })
            func side(_ side: SurfaceParameterBoundary) throws -> OriginalCurveRootSpan3D {
                try OriginalSurfaceBoundarySourceIssuer().boundary(of:.bSpline(native),at:side,
                    maximumDepth:0,maximumSpanCount:4,tolerance:.standard,usage:&usage)
            }
            return Surface3D.procedural(.originalCoons(try .init(vMinimumBoundary:side(.vLower),
                vMaximumBoundary:side(.vUpper),uMinimumBoundary:side(.uLower),uMaximumBoundary:side(.uUpper),
                tolerance:.standard,usage:&usage)))
        }.value
    }
    static func fold() -> Surface3D {
        .bSpline(.init(uDegree:1,vDegree:1,uKnots:[0,0,0.5,1,1],vKnots:[0,0,1,1],
            controlPoints:[0.0,1.0].map { v in [0.0,1.0,0.0].map { x in Point3D(x:x,y:v,z:0) } }))
    }
    static func validate<V: SourceBoundedOriginalSurfaceEmbeddingValidating>(using validator: V,
        surface: Surface3D, upperU: Double = 1, sourceDepth: Int = 32, charts: Int = 65_536,
        usage: inout Usage) throws {
        try validator.validate(surface,over:.init(u:.init(lower:0,upper:upperU),v:.init(lower:0,upper:1)),
            maximumLocalSubdivisionDepth:14,maximumLocalCellCount:charts,maximumPairSubdivisionDepth:14,
            remainingSourceDepth:sourceDepth,tolerance:.standard,usage:&usage)
    }
    static func scalarFailure(_ error: any Error) -> ExactScalarFailure? {
        if let e=error as? ExactScalarFailure {
            if case .admissionRejected(let cause)=e { return scalarFailure(cause) }
            return e
        }
        if let e=error as? NativeExactRelationFailure {
            switch e {
            case .scalar(let cause): return cause
            case .geometry(let cause): return scalarFailure(cause)
            case .domain(let cause): return scalarFailure(cause)
            case .source(let cause): return scalarFailure(cause)
            case .root(let cause): return scalarFailure(cause)
            case .cell(let cause): return scalarFailure(cause)
            case .relation(let cause): return scalarFailure(cause)
            default: return nil
            }
        }
        if let e=error as? OriginalSourceIssuanceFailure {
            switch e {
            case .scalar(let cause): return scalarFailure(cause)
            case .sourceRejected(let cause): return scalarFailure(cause)
            default: return nil
            }
        }
        if let e=error as? OriginalDomainIdentityFailure {
            switch e {
            case .scalar(let cause): return scalarFailure(cause)
            case .operationRejected(let cause): return scalarFailure(cause)
            case .source(let cause): return scalarFailure(cause)
            default: return nil
            }
        }
        if let e=error as? ExactRealTopologyFailure {
            switch e {
            case .scalar(let cause): return scalarFailure(cause)
            case .root(let cause): return scalarFailure(cause)
            case .cell(let cause): return scalarFailure(cause)
            case .polynomial(let cause): return scalarFailure(cause)
            case .operationRejected(let cause): return scalarFailure(cause)
            default: return nil
            }
        }
        if let e=error as? ExactRealCellFailure {
            switch e {
            case .scalar(let cause): return scalarFailure(cause)
            case .root(let cause): return scalarFailure(cause)
            case .polynomial(let cause): return scalarFailure(cause)
            case .operationRejected(let cause): return scalarFailure(cause)
            default: return nil
            }
        }
        if let e=error as? ExactRealRootFailure {
            switch e {
            case .scalar(let cause): return scalarFailure(cause)
            case .polynomial(let cause): return scalarFailure(cause)
            case .operationRejected(let cause): return scalarFailure(cause)
            default: return nil
            }
        }
        if let e=error as? ExactPolynomialFailure {
            switch e {
            case .scalar(let cause): return scalarFailure(cause)
            case .operationRejected(let cause): return scalarFailure(cause)
            default: return nil
            }
        }
        return nil
    }
    static func resources(_ surface: Surface3D, onlyDepth: Bool = false) throws {
        let validator=DefaultOriginalSurfaceEmbeddingValidator()
        var baseline=Usage()
        try validate(using:validator,surface:surface,usage:&baseline)
        if onlyDepth {
#if !hasFeature(Embedded)
            print("DEPTH actual value/coefficient",baseline.maximumValueVisit,baseline.maximumCoefficientVisit)
#endif
            var exact=Usage(valueDepth:baseline.maximumValueVisit,coefficientDepth:baseline.maximumCoefficientVisit)
            try validate(using:validator,surface:surface,usage:&exact)
            for axis in [ExactScalarRootAxis.value,.coefficient] {
                let attained=axis == .value ? baseline.maximumValueVisit:baseline.maximumCoefficientVisit
                // Depth zero has no smaller admitted depth; prove exact acceptance.
                if attained==0 { continue }
                var rejected=Usage(valueDepth:axis == .value ? attained-1:baseline.maximumValueVisit,
                    coefficientDepth:axis == .coefficient ? attained-1:baseline.maximumCoefficientVisit)
                do { try validate(using:validator,surface:surface,usage:&rejected);throw ExactScalarFailure.invalidEvidence }
                catch {
                    guard let cause=scalarFailure(error),case .resourceLimit(let resource)=cause else { throw error }
                    try require(resource == (axis == .value ? .valueDepth:.coefficientDepth) && rejected.work>0)
                }
            }
            for (sourceDepth,charts) in [(0,65_536),(32,3)] {
                var rejected=Usage()
                do {
                    try validate(using:validator,surface:surface,sourceDepth:sourceDepth,charts:charts,usage:&rejected)
                    throw ExactScalarFailure.invalidEvidence
                } catch let e as OriginalSourceIssuanceFailure {
                    switch e { case .sourceDepthLimit,.chartLimit:break;default:throw e }
                } catch let e as OriginalDomainIdentityFailure {
                    switch e { case .sourceDepthLimit,.chartLimit:break;default:throw e }
                } catch let e as GeometryConversionError {
                    switch e { case .resourceLimitExceeded:break;default:throw e }
                }
            }
            print("PASS attained independent scalar depths and source/chart refusal")
            return
        }
        var exact=Usage(work:baseline.work,words:baseline.words)
        try validate(using:validator,surface:surface,usage:&exact)
        try require(exact.work==baseline.work && exact.words==baseline.words)
        for (work,words,expected) in [(baseline.work-1,baseline.words,ExactResource.work),
            (baseline.work,baseline.words-1,ExactResource.storage)] {
            var rejected=Usage(work:work,words:words)
            do { try validate(using:validator,surface:surface,usage:&rejected);throw ExactScalarFailure.invalidEvidence }
            catch {
                guard let cause=scalarFailure(error),case .resourceLimit(let resource)=cause else { throw error }
                try require(resource==expected && rejected.work>0 && rejected.words>0)
            }
        }
#if !hasFeature(Embedded)
        print("RESOURCE complete embedding work/words",baseline.work,baseline.words)
#endif
        print("PASS exact N/N-1 work/storage and value-admission writeback")
    }
    static func cancellation(_ surface: Surface3D) async throws {
        var baseline=Usage()
        let validator=DefaultOriginalSurfaceEmbeddingValidator()
        try validate(using:validator,surface:surface,usage:&baseline)
        for ordinal in [0,100,baseline.work] {
            let task=Task {
                var rejected=Usage(cancelAtWork:ordinal==0 ? nil:ordinal)
                if ordinal==0 { withUnsafeCurrentTask { $0?.cancel() } }
                do { try validate(using:validator,surface:surface,usage:&rejected);return false }
                catch {
                    let cancelled: Bool
                    if error is CancellationError { cancelled=true }
                    else if let cause=scalarFailure(error),case .cancelled=cause { cancelled=true }
                    else { cancelled=false }
                    return cancelled && (ordinal==0 ? rejected.work==0:rejected.work>0)
                }
            }
            try require(await task.value)
        }
        print("PASS entry/mid/last-callback cancellation and throwing value-admission writeback")
    }
    static func main() async throws {
        let mode=getenv("CAD_PROOF_GROUP").map { String(cString:$0) } ?? "caller"
        let surface=try coons(), validator=DefaultOriginalSurfaceEmbeddingValidator()
        if mode=="resources" { try resources(surface);return }
        if mode=="depth" { try resources(surface,onlyDepth:true);return }
        if mode=="cancel" { try await cancellation(surface);return }
        try require(mode=="caller" || mode=="red")
        var usage=Usage()
        try validate(using:validator,surface:surface,usage:&usage)
        try require(usage.work>0 && usage.words>0)
        if mode == "red" {
            // The old caller returns via bilinear/local proof without DI self receipts.
            try require(usage.work<1_000_000)
            print("PASS RED original Coons embedding returns before complete self-receipt consumption")
            return
        }
        try require(usage.work>1_000_000)
        var folded=Usage()
        do { try validate(using:validator,surface:fold(),usage:&folded);throw ExactScalarFailure.invalidEvidence }
        catch let error as KernelError { try require(error.code == .topologyFailure) }
        try require(folded.work>0 && folded.words>0)
        var partial=Usage()
        try validate(using:validator,surface:fold(),upperU:0.375,usage:&partial)
        var outside=Usage()
        do {
            try validate(using:validator,surface:fold(),upperU:1.125,usage:&outside)
            throw ExactScalarFailure.invalidEvidence
        } catch let error as KernelError { try require(error.code == .invalidInput) }
        print("PASS actual Geometry embedding consumes global exclusion, rejects fold and certifies exact partial request")
    }
}
