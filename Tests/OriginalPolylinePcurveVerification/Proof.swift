#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif
import CADCore
@testable import CADGeometry
@testable import PolylinePcurveAdapters

@main struct PolylinePcurveProof {
    typealias S=OriginalPolylinePcurveSnapshot
    typealias F=OriginalExactScalarDomain
    struct Admission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var checkpoints=0
        let cancelAt: Int?
        init(work: Int=300_000_000, bytes: Int=1_073_741_824, value: Int=32, coefficient: Int=32, cancelAt: Int?=nil) throws {
            ledger = .init(limits:try .init(work:work,storageBytes:bytes,valueDepth:value,coefficientDepth:coefficient))
            self.cancelAt=cancelAt
        }
        mutating func checkpoint() throws(ExactScalarFailure) {
            checkpoints += 1
            if checkpoints==cancelAt { ledger.cancel() }
            try ledger.checkpoint()
        }
        mutating func consumeWork(_ n: Int) throws(ExactScalarFailure) { try ledger.consumeWork(n) }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes:bytes) }
        mutating func visitCell(axis: ExactScalarRootAxis,depth: Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
        mutating func admitDepth(value: Int,coefficient: Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
    }
    struct Failure: Error { let line: Int }
    nonisolated static func require(_ condition: Bool,line: Int = #line) throws { if !condition { throw Failure(line:line) } }
    nonisolated static func points() -> [SurfaceParameter] {
        [.init(u:0,v:0),.init(u:0,v:0),.init(u:1,v:1),.init(u:2,v:1),.init(u:1,v:1)]
    }
    nonisolated static func bind(_ points: [SurfaceParameter],using a: inout Admission) throws -> OriginalSourceBinding<S> {
        try DefaultOriginalSourceBindingIssuer(provider:OriginalPolylinePcurveSnapshotProvider(maximumValueDepth:32,maximumCoefficientDepth:32))
            .bind(.polyline(points),limits:.init(remainingSourceDepth:0),using:&a)
    }
    nonisolated static func equal(_ x: F.Value,_ y: F.Value,field: F,using a: inout Admission) throws {
        try require(field.compare(x,y,using:&a) == .equal)
    }
    nonisolated static func scalarCause(_ failure: OriginalSourceIssuanceFailure) throws -> ExactScalarFailure {
        switch failure {
        case .scalar(let error),.polynomial(.scalar(let error)): return error
        default: throw failure
        }
    }
    nonisolated static func sourceChecks() throws -> OriginalSourceBinding<S> {
        var p=points(),a=try Admission()
        let source=try bind(p,using:&a),s=source.original,f=s.originalField,r=s.originalPolynomials
        p[2] = .init(u:99,v:99)
        try require(s.originalCellCount==3 && s.originalPointIndex(at:0)==1 && s.originalPointIndex(at:1)==2 && s.originalPointIndex(at:2)==3)
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a),two=try f.integer(2,using:&a)
        let station=s.originalCellUpperBound(at:0)
        // sqrt(2)/(sqrt(2)+2) has polynomial t^2+2t-1, and is not a dyadic station.
        try equal(f.subtracting(f.adding(f.multiplying(station,station,using:&a),f.multiplying(two,station,using:&a),using:&a),one,using:&a),zero,field:f,using:&a)
        try require(f.compare(station,f.dividing(one,two,using:&a),using:&a) == .less)
        for i in 0..<3 {
            let index=s.originalPointIndex(at:i),original=points()
            for (t,point) in [(s.originalCellLowerBound(at:i),original[index]),(s.originalCellUpperBound(at:i),original[index+1])] {
                let h=s.originalCellHomogeneous(at:i)
                for axis in 0..<2 {
                    let actual=try r.evaluated(h[axis],at:[t],using:&a).value
                    try equal(actual,f.binary64(exactly:axis==0 ? point.u:point.v,using:&a),field:f,using:&a)
                }
                try equal(r.evaluated(h[2],at:[t],using:&a).value,zero,field:f,using:&a)
                try equal(r.evaluated(h[3],at:[t],using:&a).value,one,field:f,using:&a)
            }
        }
        let before=try r.differentiated(s.originalCellHomogeneous(at:0)[1],in:0,using:&a)
        let after=try r.differentiated(s.originalCellHomogeneous(at:1)[1],in:0,using:&a)
        try require(f.compare(r.evaluated(before,at:[station],using:&a).value,zero,using:&a) == .greater)
        try equal(r.evaluated(after,at:[station],using:&a).value,zero,field:f,using:&a)
        for fraction in [0.0,0.25,0.5,0.75,1.0] {
            let t=try f.binary64(exactly:fraction,using:&a)
            let actual=try s.original.parameter(atNormalizedFraction:fraction,tolerance:.standard)
            var found=false
            for i in 0..<s.originalCellCount {
                if try f.compare(t,s.originalCellLowerBound(at:i),using:&a) == .less { continue }
                if try f.compare(t,s.originalCellUpperBound(at:i),using:&a) == .greater { continue }
                found=true
                for axis in 0..<2 {
                    let value=try r.evaluated(s.originalCellHomogeneous(at:i)[axis],at:[t],using:&a).value
                    let enclosure=try ExactScalarNumericAccess.withAdmission(&a,inherited:value.depth) { usage in
                        try value.original.enclosure(maximumDepth:32,usage:&usage)
                    }.value
                    let coordinate=axis==0 ? actual.u:actual.v
                    try require(coordinate>=enclosure.lower-1e-12 && coordinate<=enclosure.upper+1e-12)
                }
            }
            try require(found)
        }
        let foreign=try F(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        do { _=try foreign.importing(station,using:&a);throw Failure(line:#line) }
        catch ExactScalarFailure.incompatibleDomain {}
        // Rational original coordinates remain explicitly importable from that field.
        try equal(foreign.importing(zero,using:&a),foreign.integer(0,using:&a),field:foreign,using:&a)
        print("PASS original irrational stations, closed segment laws, repeated points and foreign field")
        return source
    }
    nonisolated static func domains(_ source: OriginalSourceBinding<S>) throws {
        var a=try Admission()
        let sl=try OriginalSourceIssuanceLimits(remainingSourceDepth:0)
        let family=try DefaultOriginalFiniteRetainedCurveChartPreparer<S>().prepare(source:source,maximumCharts:3,limits:sl,using:&a)
        do { _=try DefaultOriginalFiniteRetainedCurveChartPreparer<S>().prepare(source:source,maximumCharts:2,limits:sl,using:&a);throw Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.chartLimit {}
        let l=try OriginalDomainIdentityLimits(source:sl,maximumTransportDepth:8,maximumCharts:3,maximumFamilies:1,maximumIdentityProofs:8)
        let issuer=DefaultOriginalRetainedCurveDomainIssuer<S>(),frame=try issuer.frame(family:family,limits:l,using:&a)
        let full=try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
        let f=family.field,join=source.original.originalCellUpperBound(at:0),zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
        try require(full.incident(at:[join],limits:l,using:&a).count==2)
        let next=source.original.originalCellUpperBound(at:1)
        try require(full.incident(at:[next],limits:l,using:&a).count==2)
        func interval(_ lo: F.Value,_ hi: F.Value,_ closed: Bool=true) throws -> ExactParameterInterval<F.Value> {
            try .checked(field:f,lower:.finite(lo),upper:.finite(hi),includesLower:closed,includesUpper:closed,depth:source.original.originalProofDepth,using:&a)
        }
        for kind in 0..<5 {
            let intervals: [ExactParameterInterval<F.Value>]
            if kind==0 { intervals=[try interval(join,join)] }
            else if kind==1 { intervals=[try interval(join,next,false)] }
            else if kind==2 { intervals=[try interval(zero,join),try interval(next,one)] }
            else if kind==3 { intervals=[] }
            else { let two=try f.integer(2,using:&a);intervals=[try interval(two,two)] }
            let cover=try issuer.issue(request:frame.selection(intervals:[intervals],limits:l,using:&a),family:family,limits:l,using:&a)
            try require(cover.incident(at:[join],limits:l,using:&a).count == (kind==0 || kind==2 ? 2:0))
            if kind>=3 { try require(cover.effective.isEmpty && cover.selectedMembers(limits:l,using:&a).isEmpty) }
        }
        var measured=try Admission();_=try full.incident(at:[join],limits:l,using:&measured)
        var exact=try Admission(work:measured.ledger.work,bytes:measured.ledger.storageBytes)
        _=try full.incident(at:[join],limits:l,using:&exact)
        var short=try Admission(work:measured.ledger.work-1)
        do { _=try full.incident(at:[join],limits:l,using:&short);throw Failure(line:#line) }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.work)) {}
        catch OriginalDomainIdentityFailure.domain(.scalar(.resourceLimit(.work))) {}
        var shortBytes=try Admission(bytes:measured.ledger.storageBytes-1)
        do { _=try full.incident(at:[join],limits:l,using:&shortBytes);throw Failure(line:#line) }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.storage)) {}
        catch OriginalDomainIdentityFailure.domain(.scalar(.resourceLimit(.storage))) {}
        for tick in [1,max(1,measured.checkpoints/2),measured.checkpoints] {
            var cancelled=try Admission(cancelAt:tick)
            do { _=try full.incident(at:[join],limits:l,using:&cancelled);throw Failure(line:#line) }
            catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
            catch OriginalDomainIdentityFailure.domain(.scalar(.cancelled)) {}
        }
        print("PASS actual retained charts/domain, all join incidents and exact request restriction")
    }
    nonisolated static func resources() throws {
        var baseline=try Admission();_=try bind(points(),using:&baseline)
        var exact=try Admission(work:baseline.ledger.work,bytes:baseline.ledger.storageBytes)
        _=try bind(points(),using:&exact)
        for kind in 0..<2 {
            var low=try Admission(work:kind==0 ? baseline.ledger.work-1:300_000_000,bytes:kind==1 ? baseline.ledger.storageBytes-1:1_073_741_824)
            do { _=try bind(points(),using:&low);throw Failure(line:#line) }
            catch let failure as OriginalSourceIssuanceFailure {
                guard case .resourceLimit(let resource)=try scalarCause(failure) else { throw failure }
                try require(resource == (kind==0 ? .work:.storage))
            }
        }
        for tick in [1,max(1,baseline.checkpoints/2),baseline.checkpoints] {
            var cancelled=try Admission(cancelAt:tick)
            do { _=try bind(points(),using:&cancelled);throw Failure(line:#line) }
            catch let failure as OriginalSourceIssuanceFailure {
                guard case .cancelled=try scalarCause(failure) else { throw failure }
            }
        }
        for bad in [[],[SurfaceParameter(u:0,v:0)],[.init(u:0,v:0),.init(u:0,v:0)],[.init(u:0,v:0),.init(u:.infinity,v:1)]] {
            var a=try Admission()
            do { _=try bind(bad,using:&a);throw Failure(line:#line) }
            catch is OriginalSourceIssuanceFailure {}
        }
        var depth=try Admission(coefficient:0)
        do { _=try bind(points(),using:&depth);throw Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.coefficientDepth)) {}
        print("PASS source exact work/bytes, one-less, depth, entry/intermediate/final cancel and invalid input")
    }
    static func main() {
        do { let source=try sourceChecks();try domains(source);try resources();print("PASS detached original polyline source lifetime and COW") }
        catch {
            #if !hasFeature(Embedded)
            print(error)
            #endif
            print("FAIL original polyline source/domain");exit(1)
        }
    }
}
