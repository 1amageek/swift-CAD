import CADCore
@testable import CADGeometry
import Synchronization
#if canImport(Darwin)
import Darwin
#else
import WASILibc
#endif

/// Uses Geometry's existing concrete word callback port to avoid fixture-only specialization.
@main struct EmbeddingCallerSharedAdmission {
    final class Counter: Sendable {
        struct State: Sendable { var work=0;var words=0 }
        let state=Mutex(State())
        let workLimit: Int
        let wordLimit: Int
        let cancelAt: Int?
        init(work: Int=80_000_000,words: Int=268_435_456,cancelAt: Int?=nil) {
            workLimit=work;wordLimit=words;self.cancelAt=cancelAt
        }
        func work(_ n: Int) throws {
            let cancelled=try state.withLock { value in
                let sum=value.work.addingReportingOverflow(n)
                guard n>=0,!sum.overflow,sum.partialValue<=workLimit else { throw ExactScalarFailure.resourceLimit(.work) }
                value.work=sum.partialValue
                return cancelAt.map { value.work >= $0 } ?? false
            }
            if cancelled { withUnsafeCurrentTask { $0?.cancel() } }
        }
        func retain(_ n: Int) throws {
            try state.withLock { value in
                let sum=value.words.addingReportingOverflow(n)
                guard n>=0,!sum.overflow,sum.partialValue<=wordLimit else { throw ExactScalarFailure.resourceLimit(.storage) }
                value.words=sum.partialValue
            }
        }
        var snapshot: State { state.withLock { $0 } }
        func usage() -> OriginalRelationUsage {
            .init(consumeWork:{ try self.work($0) },retainStorage:{ try self.retain($0) },
                visitCell:{ guard $0>=0,$0<=32 else { throw ExactScalarFailure.resourceLimit(.valueDepth) };try self.work(1) },
                visitCoefficientCell:{ guard $0>=0,$0<=32 else { throw ExactScalarFailure.resourceLimit(.coefficientDepth) };try self.work(1) })
        }
    }
    static func require(_ value: Bool) throws { guard value else { throw ExactScalarFailure.invalidEvidence } }
    static func coons() throws -> Surface3D {
        var usage=Counter().usage()
        let t=[0.0,0.5,1.0]
        let native=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,0.5,1,1],vKnots:[0,0,0.5,1,1],
            controlPoints:t.map { v in t.map { u in Point3D(x:u,y:v,z:0) } })
        func side(_ side: SurfaceParameterBoundary) throws -> OriginalCurveRootSpan3D {
            try OriginalSurfaceBoundarySourceIssuer().boundary(of:.bSpline(native),at:side,
                maximumDepth:0,maximumSpanCount:4,tolerance:.standard,usage:&usage)
        }
        return .procedural(.originalCoons(try .init(vMinimumBoundary:side(.vLower),
            vMaximumBoundary:side(.vUpper),uMinimumBoundary:side(.uLower),uMaximumBoundary:side(.uUpper),
            tolerance:.standard,usage:&usage)))
    }
    static func fold() -> Surface3D {
        .bSpline(.init(uDegree:1,vDegree:1,uKnots:[0,0,0.5,1,1],vKnots:[0,0,1,1],
            controlPoints:[0.0,1.0].map { v in [0.0,1.0,0.0].map { x in Point3D(x:x,y:v,z:0) } }))
    }
    static func validate(_ surface: Surface3D,_ counter: Counter,upperU: Double=1) throws {
        var usage=counter.usage()
        try DefaultOriginalSurfaceEmbeddingValidator().validate(surface,
            over:.init(u:.init(lower:0,upper:upperU),v:.init(lower:0,upper:1)),
            maximumLocalSubdivisionDepth:14,maximumLocalCellCount:65_536,maximumPairSubdivisionDepth:14,
            remainingSourceDepth:32,tolerance:.standard,usage:&usage)
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
    static func main() async throws {
        let mode=getenv("CAD_PROOF_GROUP").map { String(cString:$0) } ?? "caller"
        let surface=try coons()
        if mode=="cancel" {
            let baseline=Counter();try validate(surface,baseline)
            for ordinal in [0,100,baseline.snapshot.work] {
                let task=Task {
                    let counter=Counter(cancelAt:ordinal==0 ? nil:ordinal)
                    if ordinal==0 { withUnsafeCurrentTask { $0?.cancel() } }
                    do { try validate(surface,counter);return false }
                    catch {
                        let cancelled: Bool
                        if error is CancellationError { cancelled=true }
                        else if let cause=scalarFailure(error),case .cancelled=cause { cancelled=true }
                        else { cancelled=false }
                        return cancelled && (ordinal==0 ? counter.snapshot.work==0:counter.snapshot.work>0)
                    }
                }
                try require(await task.value)
            }
            print("PASS shared callback admission entry/mid/final cancellation")
            return
        }
        if mode=="resources" {
            let baseline=Counter();try validate(surface,baseline)
            let n=baseline.snapshot
            let exact=Counter(work:n.work,words:n.words);try validate(surface,exact)
            try require(exact.snapshot.work==n.work && exact.snapshot.words==n.words)
            for (counter,expected) in [(Counter(work:n.work-1,words:n.words),ExactResource.work),
                (Counter(work:n.work,words:n.words-1),ExactResource.storage)] {
                do { try validate(surface,counter);throw ExactScalarFailure.invalidEvidence }
                catch {
                    guard let cause=scalarFailure(error),case .resourceLimit(let resource)=cause else { throw error }
                    try require(resource==expected && counter.snapshot.work>0 && counter.snapshot.words>0)
                }
            }
            print("PASS shared callback full-square N/N-1 work/storage with preserved causes")
            return
        }
        try require(mode=="caller")
        let counter=Counter();try validate(surface,counter)
        try require(counter.snapshot.work>1_000_000 && counter.snapshot.words>0)
        let rejected=Counter()
        do { try validate(fold(),rejected);throw ExactScalarFailure.invalidEvidence }
        catch let e as KernelError { try require(e.code == .topologyFailure) }
        try require(rejected.snapshot.work>0 && rejected.snapshot.words>0)
        try validate(fold(),Counter(),upperU:0.375)
        do { try validate(fold(),Counter(),upperU:1.125);throw ExactScalarFailure.invalidEvidence }
        catch let e as KernelError { try require(e.code == .invalidInput) }
        print("PASS shared callback actual embedding Coons exclusion, fold rejection and exact request")
    }
}
