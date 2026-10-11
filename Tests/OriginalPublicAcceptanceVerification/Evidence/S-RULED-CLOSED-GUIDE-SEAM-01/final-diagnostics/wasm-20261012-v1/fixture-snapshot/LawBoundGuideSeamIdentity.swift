#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif
@testable import CallerAdapters
@testable import RuledObservationAdapters
#if GUIDE_SEAM_COMBINED_ACCEPTANCE
import GuideSeamPort
#endif

/// Exercises the additive identity theorem without resolving a chart-pair product.
#if !GUIDE_SEAM_COMBINED_ACCEPTANCE
@main
#endif
struct LawBoundGuideSeamIdentity {
    typealias F = OriginalExactScalarDomain
    typealias G = CallerAdapters.OriginalRetainedGuideCurveSnapshot
    typealias S = RuledObservationAdapters.OriginalRuledSurfaceSnapshot<G,G>
    typealias Q = OriginalRuledChartSelection<G,Int,G,Int,F>
    typealias Law = OriginalRationalChartReceipt<S,Q,F>
    typealias Declaration = OriginalRationalSourceBoundaryDeclaration<S,Q,Q,F>
    struct Admission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var checkpoints = 0
        let cancelAt: Int?
        init(depth:Int = 32,work:Int = 8_388_608,storageBytes:Int = 400_000_000,cancelAt:Int? = nil) throws {
            ledger = .init(limits:try .init(work:work,storageBytes:storageBytes,valueDepth:depth,coefficientDepth:depth))
            self.cancelAt = cancelAt
        }
        mutating func checkpoint() throws(ExactScalarFailure) {
            checkpoints += 1
            if checkpoints == cancelAt { throw .cancelled }
            try ledger.checkpoint()
        }
        mutating func consumeWork(_ n:Int) throws(ExactScalarFailure) { try checkpoint();try ledger.consumeWork(n) }
        mutating func retainStorage(bytes:Int) throws(ExactScalarFailure) { try checkpoint();try ledger.retainStorage(bytes:bytes) }
        mutating func visitCell(axis:ExactScalarRootAxis,depth:Int) throws(ExactScalarFailure) { try checkpoint();try ledger.visitCell(axis:axis,depth:depth) }
        mutating func admitDepth(value:Int,coefficient:Int) throws(ExactScalarFailure) { try checkpoint();try ledger.admitDepth(value:value,coefficient:coefficient) }
    }
    struct Failure: Error { let line: Int }
    static func require(_ condition:Bool,line:Int = #line) throws { if !condition { throw Failure(line:line) } }
    static func prepare(weighted:Bool = false,field:F? = nil,using a:inout Admission) throws
        -> (F,OriginalDomainIdentityLimits,OriginalParameterFrame<S,F>,[Law]) {
        let parent = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            func guide(_ z:Double) throws -> Curve3D {
                let vertices:[Point3D] = [.init(x:0,y:0,z:z),.init(x:1,y:0,z:z),.init(x:0,y:1,z:z),.init(x:0,y:0,z:z)]
                var spans:[OriginalCurveRootSpan3D] = []
                for i in 0..<3 {
                    let native = Curve3D.bSpline(.init(degree:1,knots:[0,0,1,1],controlPoints:[vertices[i],vertices[i+1]],weights:weighted && i == 0 ? [1,2]:[1,1]))
                    spans.append(try .init(source:native,start:.authored(0),end:.authored(1),nativeSpanIndex:1,
                        maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                        storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:4,remainingSourceDepth:0,maximumAlgebraicDepth:0))
                }
                let quarter = try ExactRationalCoefficient.one.divided(by:.originalDouble(4,usage:&usage),usage:&usage)
                let threeQuarters = try quarter.multiplied(by:.originalDouble(3,usage:&usage),usage:&usage)
                return .originalGuideTraversalChain(try .init(traversals:spans,stations:[.zero,quarter,threeQuarters,.one],
                    sourceSegmentOrdinals:[0,1,2],remainingSourceDepth:2,tolerance:.standard,usage:&usage))
            }
            return RuledSurface3D(startBoundary:try guide(0),endBoundary:try guide(1),uDomain:.closed(0,1))
        }.value
        let f:F
        if let field { f = field }
        else { f = try F(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a) }
        let limits = try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:3),maximumTransportDepth:32,
            maximumCharts:16,maximumFamilies:2,maximumIdentityProofs:8)
        let guide = CallerAdapters.OriginalRetainedGuideCurveSnapshotProvider(field:f,tolerance:.standard)
        let source = try DefaultOriginalSourceBindingIssuer(provider:RuledObservationAdapters.OriginalRuledSurfaceSnapshotProvider(first:guide,second:guide,tolerance:.standard))
            .bind(parent,limits:limits.source,using:&a)
        let first = try DefaultOriginalFiniteRetainedCurveChartPreparer<G>().prepare(source:source.original.firstBoundary,
            maximumCharts:4,limits:.init(remainingSourceDepth:2),using:&a)
        let second = try DefaultOriginalFiniteRetainedCurveChartPreparer<G>().prepare(source:source.original.secondBoundary,
            maximumCharts:4,limits:.init(remainingSourceDepth:2),using:&a)
        let laws = try DefaultOriginalFiniteRuledChartPreparer<S,Int,Int,F>().prepare(source:source,first:first.laws,
            second:second.laws,field:f,maximumCharts:16,limits:limits.source,using:&a)
        try require(laws.count == 7)
        let unit = try ExactParameterInterval.checked(field:f,lower:.finite(f.integer(0,using:&a)),upper:.finite(f.integer(1,using:&a)),depth:.zero,using:&a)
        let frame = try DefaultOriginalParameterTransporter<S,F>().frame(source:source,field:f,support:[[unit],[unit]],
            semantics:[.authoredScalar,.authoredScalar],limits:limits,using:&a)
        return (f,limits,frame,laws)
    }
    static func issue<I:OriginalLawBoundParameterIdentityIssuing>(_ issuer:I,
        declaration:OriginalRationalSourceBoundaryDeclaration<S,Q,Q,F>,scope:OriginalParameterSelection<S,F>,
        frame:OriginalParameterFrame<S,F>,gains:[F.Value],offsets:[F.Value],limits:OriginalDomainIdentityLimits,
        using a:inout Admission) throws -> OriginalParameterIdentity<S,F> where I.Source == S,I.Field == F {
        try issuer.declaredBoundary(declaration:declaration,scope:scope,rightFrame:frame,
            permutation:[0,1],gains:gains,offsets:offsets,limits:limits,using:&a)
    }
    static func scopedControls(_ declaration:Declaration,frame:OriginalParameterFrame<S,F>,
        scope:OriginalParameterSelection<S,F>,field f:F,limits:OriginalDomainIdentityLimits,
        using a:inout Admission) throws {
        let issuer = DefaultOriginalParameterIdentityIssuer<S,F>()
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
        let half = try f.dividing(one,f.integer(2,using:&a),using:&a)
        let threeQuarters = try f.dividing(f.integer(3,using:&a),f.integer(4,using:&a),using:&a)
        // The reversed V correspondence agrees at the midpoint, but not on the edge.
        do {
            _ = try issue(issuer,declaration:declaration,scope:scope,frame:frame,
                gains:[one,f.integer(-1,using:&a)],offsets:[one,one],limits:limits,using:&a)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.invalidIdentityProof {}
        let point = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(zero),depth:.zero,using:&a)
        let halfV = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(half),depth:.zero,using:&a)
        let restricted = try frame.selection(intervals:[[point],[halfV]],limits:limits,using:&a)
        let receipt = try issue(issuer,declaration:declaration,scope:restricted,frame:frame,
            gains:[one,one],offsets:[one,zero],limits:limits,using:&a)
        try require(issuer.decide(receipt,left:[zero,half],right:[one,half],limits:limits,using:&a) == .proven)
        try require(issuer.decide(receipt,left:[zero,threeQuarters],right:[one,threeQuarters],limits:limits,using:&a) == .notEstablished)
        var foreignAdmission = try Admission()
        // Isolate source ownership: a different exact-field context would reject
        // the coordinate image before the right-law owner check is reached.
        let (_,_,foreignFrame,foreignLaws) = try prepare(field:f,using:&foreignAdmission)
        let foreignRight = Declaration(left:declaration.left,right:foreignLaws[6],leftAxis:0,rightAxis:0,leftSide:.lower,rightSide:.upper)
        do {
            _ = try issue(issuer,declaration:foreignRight,scope:scope,frame:frame,
                gains:[one,one],offsets:[one,zero],limits:limits,using:&a)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.foreignOwner {}
        do {
            _ = try issue(issuer,declaration:declaration,scope:scope,frame:foreignFrame,
                gains:[one,one],offsets:[one,zero],limits:limits,using:&a)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.foreignOwner {}
        print("PASS midpoint-only V reversal refused; half-V proof excludes outside; foreign law/frame refused")
    }
    static func germControls(_ laws:[Law],using a:inout Admission) throws {
        // W=1 on each entire chart makes these homogeneous derivatives exact XYZ germs.
        for (law,expected) in [(laws[0],[4,0,0]),(laws[6],[0,-4,0])] {
            let ring = law.polynomials,f = law.field
            let one = try ring.constant(f.integer(1,using:&a),using:&a)
            try require(ring.isZero(ring.subtracting(law.denominator,one,using:&a),using:&a))
            for axis in 0..<3 {
                let derivative = try ring.differentiated(law.homogeneous[axis],in:0,using:&a)
                let constant = try ring.constant(f.integer(expected[axis],using:&a),using:&a)
                try require(ring.isZero(ring.subtracting(derivative,constant,using:&a),using:&a))
            }
        }
        print("PASS exact whole-chart U germs 4X and -4Y remain unequal; identity is positional only")
    }
    static func detachedReceipt() throws -> (F,OriginalDomainIdentityLimits,OriginalParameterIdentity<S,F>) {
        var a = try Admission()
        let (f,limits,frame,laws) = try prepare(using:&a)
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
        let point = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(zero),depth:.zero,using:&a)
        let unit = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(one),depth:.zero,using:&a)
        let scope = try frame.selection(intervals:[[point],[unit]],limits:limits,using:&a)
        let declaration = Declaration(left:laws[0],right:laws[6],leftAxis:0,rightAxis:0,leftSide:.lower,rightSide:.upper)
        let receipt = try issue(DefaultOriginalParameterIdentityIssuer<S,F>(),declaration:declaration,scope:scope,frame:frame,
            gains:[one,one],offsets:[one,zero],limits:limits,using:&a)
        return (f,limits,receipt)
    }
    static func lifetimeControls() throws {
        // All construction locals and their admission have left scope before this query.
        let (f,limits,receipt) = try detachedReceipt()
        var source = [receipt]
        let retained = source
        source.append(retained[0])
        try require(source.count == 2 && retained.count == 1)
        source.removeAll(keepingCapacity:false)
        var a = try Admission()
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
        let issuer = DefaultOriginalParameterIdentityIssuer<S,F>()
        try require(issuer.decide(retained[0],left:[zero,zero],right:[one,zero],limits:limits,using:&a) == .proven)
        try require(issuer.decide(retained[0],left:[zero,one],right:[one,one],limits:limits,using:&a) == .proven)
        print("PASS detached receipt and copied array retain original source/laws after caller mutation")
    }
    static func admissionControls(_ declaration:Declaration,frame:OriginalParameterFrame<S,F>,
        scope:OriginalParameterSelection<S,F>,field f:F,limits:OriginalDomainIdentityLimits,
        using a:inout Admission) throws {
        let issuer = DefaultOriginalParameterIdentityIssuer<S,F>()
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
        // Only issuer work/storage is measured: source, law, scope and map inputs already exist.
        var measured = try Admission()
        _ = try issue(issuer,declaration:declaration,scope:scope,frame:frame,
            gains:[one,one],offsets:[one,zero],limits:limits,using:&measured)
        let work = measured.ledger.work,storage = measured.ledger.storageBytes,checkpoints = measured.checkpoints
        try require(work > 0 && storage > 0 && checkpoints > 2)
        var exact = try Admission(work:work,storageBytes:storage)
        let receipt = try issue(issuer,declaration:declaration,scope:scope,frame:frame,
            gains:[one,one],offsets:[one,zero],limits:limits,using:&exact)
        try require(exact.ledger.work == work && exact.ledger.storageBytes == storage)
        try require(issuer.decide(receipt,left:[zero,zero],right:[one,zero],limits:limits,using:&a) == .proven)
        var shortWork = try Admission(work:work-1,storageBytes:storage)
        do {
            _ = try issue(issuer,declaration:declaration,scope:scope,frame:frame,
                gains:[one,one],offsets:[one,zero],limits:limits,using:&shortWork)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.work)) {}
        var shortStorage = try Admission(work:work,storageBytes:storage-1)
        do {
            _ = try issue(issuer,declaration:declaration,scope:scope,frame:frame,
                gains:[one,one],offsets:[one,zero],limits:limits,using:&shortStorage)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.storage)) {}
        for stop in [1,checkpoints/2,checkpoints] {
            var cancelled = try Admission(work:work,storageBytes:storage,cancelAt:stop)
            do {
                _ = try issue(issuer,declaration:declaration,scope:scope,frame:frame,
                    gains:[one,one],offsets:[one,zero],limits:limits,using:&cancelled)
                throw Failure(line:#line)
            } catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
            try require(cancelled.checkpoints == stop)
        }
#if hasFeature(Embedded)
        print("PASS issuer-only exact/one-less work/storage and entry/mid/final cancellation")
#else
        print("PASS issuer-only exact/one-less work/storage and entry/mid/final cancellation",work,storage,checkpoints)
#endif
    }
    static func nativeRegression() throws {
        var a = try Admission()
        let f = try F(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let limits = try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:3),maximumTransportDepth:32,
            maximumCharts:16,maximumFamilies:2,maximumIdentityProofs:8)
        func law(_ right:Bool) throws -> (OriginalParameterFrame<BSplineSurface3D,F>,OriginalRationalChartReceipt<BSplineSurface3D,OriginalBSplineChartSelection,F>) {
            let points:[[Point3D]] = right
                ? [[.init(x:1,y:0,z:0),.init(x:0,y:0,z:0)],[.init(x:1,y:-2,z:0),.init(x:0,y:-2,z:0)]]
                : [[.init(x:0,y:0,z:0),.init(x:1,y:0,z:0)],[.init(x:0,y:1,z:0),.init(x:1,y:1,z:0)]]
            let native = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],controlPoints:points,weights:[[1,1],[1,1]])
            let source = try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplineSurfaceSnapshotProvider(tolerance:.standard))
                .bind(native,limits:limits.source,using:&a)
            let space = try DefaultOriginalBSplineDomainIssuer<BSplineSurface3D,F>().prepare(source:source,field:f,limits:limits,using:&a)
            let receipt = try DefaultOriginalBSplineChartIssuer<BSplineSurface3D,F>().issue(source:source,
                chart:space.sourceCharts[0],field:f,limits:limits.source,using:&a)
            return (space.frame,receipt)
        }
        let (leftFrame,left) = try law(false),(rightFrame,right) = try law(true)
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
        let half = try f.dividing(one,f.integer(2,using:&a),using:&a)
        let point = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(zero),depth:.zero,using:&a)
        let unit = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(one),depth:.zero,using:&a)
        let scope = try leftFrame.selection(intervals:[[unit],[point]],limits:limits,using:&a)
        let declaration = OriginalSourceBoundaryDeclaration(left:left.chart,right:right.chart,leftAxis:1,rightAxis:1,leftSide:.lower,rightSide:.lower)
        let issuer = DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,F>()
        let receipt = try issuer.declaredBoundary(declaration:declaration,left:left,right:right,scope:scope,rightFrame:rightFrame,
            permutation:[0,1],gains:[f.integer(-1,using:&a),one],offsets:[one,zero],limits:limits,using:&a)
        try require(issuer.decide(receipt,left:[half,zero],right:[half,zero],limits:limits,using:&a) == .proven)
        try require(issuer.decide(receipt,left:[zero,zero],right:[one,zero],limits:limits,using:&a) == .proven)
        try require(issuer.decide(receipt,left:[one,zero],right:[zero,zero],limits:limits,using:&a) == .proven)
        do {
            _ = try issuer.declaredBoundary(declaration:declaration,left:left,right:right,scope:scope,rightFrame:rightFrame,
                permutation:[0,1],gains:[one,one],offsets:[zero,zero],limits:limits,using:&a)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.invalidIdentityProof {}
        print("PASS fresh actual Native old-overload whole-boundary success and midpoint-only false refusal")
    }
    static func run() throws {
        var a = try Admission()
        let (f,limits,frame,laws) = try prepare(using:&a)
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
        let unit = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(one),depth:.zero,using:&a)
        let point = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(zero),depth:.zero,using:&a)
        let scope = try frame.selection(intervals:[[point],[unit]],limits:limits,using:&a)
        let declaration = OriginalRationalSourceBoundaryDeclaration(left:laws[0],right:laws[6],leftAxis:0,rightAxis:0,leftSide:.lower,rightSide:.upper)
        let issuer = DefaultOriginalParameterIdentityIssuer<S,F>()
        let receipt = try issue(issuer,declaration:declaration,scope:scope,frame:frame,gains:[one,one],offsets:[one,zero],limits:limits,using:&a)
        try require(receipt.kind == .declaredSharedBoundary)
        for v in [zero,try f.dividing(one,f.integer(2,using:&a),using:&a),one] {
            let result = try issuer.decide(receipt,left:[zero,v],right:[one,v],limits:limits,using:&a)
            try require(result == .proven)
        }
        try require(issuer.decide(receipt,left:[one,zero],right:[zero,zero],limits:limits,using:&a) == .notEstablished)
        print("PASS actual same-parent closed-guide directed whole seam through generic capability; reverse remains outside scope")
        let quarter = try f.dividing(one,f.integer(4,using:&a),using:&a)
        let falseBoundary = OriginalRationalSourceBoundaryDeclaration(left:laws[0],right:laws[0],leftAxis:0,rightAxis:0,leftSide:.lower,rightSide:.upper)
        do {
            _ = try issue(issuer,declaration:falseBoundary,scope:scope,frame:frame,gains:[one,one],offsets:[quarter,zero],limits:limits,using:&a)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.invalidIdentityProof {}
        print("PASS false whole boundary rejected")
        try scopedControls(declaration,frame:frame,scope:scope,field:f,limits:limits,using:&a)
        try germControls(laws,using:&a)
        try lifetimeControls()
        try admissionControls(declaration,frame:frame,scope:scope,field:f,limits:limits,using:&a)
        try nativeRegression()
        var weightedAdmission = try Admission()
        let (wf,wl,wframe,weighted) = try prepare(weighted:true,using:&weightedAdmission)
        let wz = try wf.integer(0,using:&weightedAdmission),wo = try wf.integer(1,using:&weightedAdmission)
        let wp = try ExactParameterInterval.checked(field:wf,lower:.finite(wz),upper:.finite(wz),depth:.zero,using:&weightedAdmission)
        let ws = try ExactParameterInterval.checked(field:wf,lower:.finite(weighted[0].support[0].lower),upper:.finite(weighted[0].support[0].upper),depth:.zero,using:&weightedAdmission)
        let weightedScope = try wframe.selection(intervals:[[ws],[wp]],limits:wl,using:&weightedAdmission)
        let guarded = OriginalRationalSourceBoundaryDeclaration(left:weighted[0],right:weighted[0],leftAxis:1,rightAxis:1,leftSide:.lower,rightSide:.lower)
        do {
            _ = try issue(issuer,declaration:guarded,scope:weightedScope,frame:wframe,gains:[wo,wo],offsets:[wz,wz],limits:wl,using:&weightedAdmission)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.unsupportedSourceProof {}
        print("PASS actual weighted ruled nonconstant guard explicitly unsupported")
        // Inject only conservative admission history; original owners and all laws stay unchanged.
        // The actual polynomial laws have depth zero. Optional decision history
        // is checked separately: absence is not a stored zero-depth certificate.
        let inherited = 9
        for law in [laws[0],laws[6]] {
            if let depth = law.proofDepth {
                try require(depth.value == 0 && depth.coefficient == 0)
                print("PASS actual receipt explicitly retains zero decision depth")
            } else {
                try require(law.proofDepth == nil)
                print("PASS actual receipt has no additional retained decision history")
            }
            for group in [law.homogeneous,law.parameterTransport.numerators,law.parameterTransport.denominators] {
                for polynomial in group {
                    try require(polynomial.depth.value == 0 && polynomial.depth.coefficient == 0)
                }
            }
        }
        func retainingHistory(_ law:Law) throws -> Law {
            .init(chart:law.chart,field:law.field,polynomials:law.polynomials,homogeneous:law.homogeneous,
                support:law.support,parameterTransport:law.parameterTransport,periods:law.periods,
                proofDepth:try .init(value:inherited,coefficient:7))
        }
        let history = OriginalRationalSourceBoundaryDeclaration(left:try retainingHistory(laws[0]),right:try retainingHistory(laws[6]),
            leftAxis:0,rightAxis:0,leftSide:.lower,rightSide:.upper)
        let historyReceipt = try issue(issuer,declaration:history,scope:scope,frame:frame,gains:[one,one],offsets:[one,zero],limits:limits,using:&a)
        var tight = try Admission(depth:inherited-1)
        do {
            _ = try issue(issuer,declaration:history,scope:scope,frame:frame,gains:[one,one],offsets:[one,zero],limits:limits,using:&tight)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.valueDepth)) {
        } catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.coefficientDepth)) {}
        let reached = max(historyReceipt.evidenceDepth.value,historyReceipt.evidenceDepth.coefficient)
        try require(reached >= inherited)
        var reader = try Admission(depth:reached-1)
        do {
            _ = try issuer.decide(historyReceipt,left:[zero,zero],right:[one,zero],limits:limits,using:&reader)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.valueDepth)) {
        } catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.coefficientDepth)) {}
#if hasFeature(Embedded)
        print("PASS conservative injected history admitted before proof and retained for later query")
        print("PASS identity-only checks")
#else
        print("PASS conservative injected history admitted before proof and retained for later query",inherited,reached)
        print("PASS identity-only Native checks; work",a.ledger.work,"storage",a.ledger.storageBytes)
#endif
    }
    static func main() {
        do { try run() }
        catch {
#if hasFeature(Embedded)
            print("IDENTITY_STOP")
#else
            print("IDENTITY_STOP",error)
#endif
            exit(1)
        }
    }
}
