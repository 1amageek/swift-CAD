import CADCore
@testable import CADGeometry
import ImagePeriodicSelfPort
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif

/// Complete symbolic self product of the original periodic image, without a cycle window.
@main struct ImagePeriodicSelfAcceptance {
    typealias Common = NativeIdentityCompositionAcceptance
    typealias Base = ExactRationalScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Source = OriginalParameterImageSnapshot<OriginalImageSurface3D,BSplineSurface3D>
    typealias Child = OriginalBSplineDomainCover<BSplineSurface3D,Field>
    typealias Parent = OriginalAffineChildDomainCover<Source,Child>
    typealias Identity = OriginalParameterIdentity<Source,Field>
    typealias Raw = NativeExactSymbolicRelationFamily<BSplineSurface3D,BSplineSurface3D>
    typealias Result = OriginalAffinePeriodicSelfContacts<Source>
    enum Failure:Error { case assertion(Int),unexpectedSuccess }
    nonisolated static func require(_ test:Bool,_ line:Int = #line) throws {
        guard test else { Common.metric("FAIL S-IMAGE-PERIOD-01",[line]);throw Failure.assertion(line) }
    }
    nonisolated static func limits() throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:1),maximumTransportDepth:16,maximumCharts:64,maximumFamilies:2,maximumIdentityProofs:64)
    }
    nonisolated static func interval(_ lo:Int,_ hi:Int,_ f:Field,_ a:inout ExactScalarLedger) throws -> ExactParameterInterval<Field.Value> {
        try .checked(field:f,lower:.finite(f.integer(lo,using:&a)),upper:.finite(f.integer(hi,using:&a)),depth:.zero,using:&a)
    }
    nonisolated static func prepare(_ a:inout ExactScalarLedger) throws -> (Raw,Parent,[Identity]) {
        let f=try Field.base(field:Base(),maximumExtensionLevel:32,using:&a),l=try limits()
        let xy:[(Double,Double)]=[(0,0),(1,0),(0,1),(0,0)]
        let native=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[-1,0,1,2,3,4],vKnots:[-1,0,1,2,3,4],
            controlPoints:xy.map { v in xy.map { u in .init(x:u.0,y:u.1+v.0,z:v.1) } },isUPeriodic:true,isVPeriodic:true)
        let image=try OriginalImageSurface3D(source:.bSpline(native),uGain:-1,vGain:1,uOffset:1,
            transform:.init(basisX:.unitX,basisY:.unitY,basisZ:.unitZ,translation:.zero),swapAxes:true,tolerance:.standard)
        let source=try DefaultOriginalSourceBindingIssuer(provider:OriginalParameterImageSurfaceSnapshotProvider(
            child:OriginalNativeSurfaceFamilySnapshotProvider(tolerance:.standard),tolerance:.standard))
            .bind(image,limits:l.source,using:&a)
        let issuer=DefaultOriginalBSplineDomainIssuer<BSplineSurface3D,Field>()
        let space=try issuer.prepare(source:source.original.originalChild,field:f,limits:l,using:&a)
        let child=try issuer.issue(space:space,request:space.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
        let parent=try DefaultOriginalParameterImageDomainIssuer<Source,Child>().issue(source:source,child:child,
            requested:[[interval(-3,6,f,&a)],[interval(-3,6,f,&a)]],limits:l,using:&a)
        let ids=DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,Field>()
        var proofs:[Identity]=[]
        for i in -3...3 { for j in -3...3 where i != 0 || j != 0 {
            var components:[OriginalParameterIdentity<BSplineSurface3D,Field>]=[]
            for (axis,index) in [(0,i),(1,j)] where index != 0 {
                let cycle=try OriginalParameterCycle(exact:Base().integer(index,using:&a),using:&a)
                components.append(try ids.periodic(cover:child,from:child.effective,axis:axis,cycle:cycle,limits:l,using:&a))
            }
            let proof=try components.count==1 ? components[0]:ids.compose(components[0],components[1],limits:l,using:&a)
            proofs.append(try DefaultOriginalAffineChildParameterIdentityIssuer<Source,Child>().lifted(proof,through:parent,limits:l,using:&a))
        } }
        let raw=try DefaultSurfaceSurfaceIntersector().exactParameterRelationFamily(first:child,second:child,domainLimits:l,
            maximumMaps:9,maximumPairs:81,cellLimits:Common.cellLimits(),topologyLimits:Common.topologyLimits(),using:&a)
        Common.metric("METRIC preparation work/storage",[a.work,a.storageBytes])
        return (raw,parent,proofs)
    }
    nonisolated static func query<A:ExactScalarAdmission & ~Copyable>(_ raw:Raw,_ parent:Parent,_ identities:[Identity],_ a:inout A) throws -> Result {
        try DefaultOriginalAffinePeriodicSelfContactQuery<Source>().contacts(in:raw,over:parent,excluding:identities,limits:limits(),using:&a)
    }
    nonisolated static func oracle(_ result:Result,_ a:inout ExactScalarLedger) throws {
        let raw=result.raw,l=try limits(),f=result.parent.support.frame.scalarField
        try require(raw.templates.count==81 && result.templateOrdinals==0..<81 && result.identities.count==49)
        try require(raw.first.integerFamilyRank==2 && raw.second.integerFamilyRank==2 && result.parent.integerFamilyRank==2)
        let transport=try DefaultOriginalParameterTransporter<Source,Field>().affineCoordinates(of:result.childCoordinates,limits:l,using:&a)
        try require(transport.permutation==[1,0])
        for axis in 0..<2 {
            try require(try f.compare(transport.gains[axis],f.integer(axis==0 ? 1:-1,using:&a),using:&a) == .equal)
            try require(try f.compare(transport.offsets[axis],f.integer(axis==0 ? 0:1,using:&a),using:&a) == .equal)
        }
        for period in raw.first.space.periods { try require(try f.compare(period.period,f.integer(3,using:&a),using:&a) == .equal) }
        var shifts:[[Int]]=[]
        for view in result.identities {
            guard case .affine(let p,let gains,let offsets)=view.constraints else { throw Failure.assertion(#line) }
            try require(p==[0,1]);var matched:[Int]?
            for i in -3...3 { for j in -3...3 {
                if try f.compare(offsets[0],f.integer(-3*j,using:&a),using:&a) == .equal && f.compare(offsets[1],f.integer(3*i,using:&a),using:&a) == .equal { matched=[-3*j,3*i] }
            } }
            guard let shift=matched else { throw Failure.assertion(#line) };try require(!shifts.contains(shift));shifts.append(shift)
            for axis in 0..<2 {
                try require(try f.compare(gains[axis],f.integer(1,using:&a),using:&a) == .equal)
                for (scope,isRight) in [(view.left,false),(view.right,true)] {
                    try require(scope.axes[axis].intervalCount==1)
                    let interval=scope.axes[axis].intervals.first!
                    guard case .finite(let lo)=interval.lower,case .finite(let hi)=interval.upper else { throw Failure.assertion(#line) }
                    let lower=max(-3,-3-shift[axis])+(isRight ? shift[axis]:0)
                    let upper=min(6,6-shift[axis])+(isRight ? shift[axis]:0)
                    try require(interval.includesLower && interval.includesUpper)
                    try require(try f.compare(lo,f.integer(lower,using:&a),using:&a) == .equal && f.compare(hi,f.integer(upper,using:&a),using:&a) == .equal)
                }
            }
        }
        try require(shifts.count==49)
        var terminals=0,selected=0
        for (ordinal,template) in raw.templates.enumerated() {
            try require(template.firstTemplate==ordinal/9 && template.secondTemplate==ordinal%9)
            let partition=template.fundamental.relation.selection.partition
            let c=try ExactRealCellDomain<Base>(retaining:partition.source,using:&a),r=c.polynomials,field=try c.coefficientField(of:partition.source,using:&a)
            func triangle(_ axis:Int,_ span:Int) throws -> (ExactPolynomial<Field>,ExactPolynomial<Field>) {
                let t=try r.variable(axis,using:&a),zero=try r.zero(using:&a)
                func k(_ n:Int) throws -> ExactPolynomial<Field> { try r.constant(field.integer(n,using:&a),using:&a) }
                switch span {
                case 1:return(t,zero)
                case 2:return(try r.subtracting(k(2),t,using:&a),try r.subtracting(t,k(1),using:&a))
                case 3:return(zero,try r.subtracting(k(3),t,using:&a))
                default:throw Failure.assertion(#line)
                }
            }
            let spans=template.fundamental.first.law.chart.selection.spans+template.fundamental.second.law.chart.selection.spans
            try require(spans.count==4)
            for axis in 0..<4 {
                guard case .finite(let lo)=partition.source.domains[axis].lower,case .finite(let hi)=partition.source.domains[axis].upper else { throw Failure.assertion(#line) }
                try require(try field.compare(lo,field.integer(spans[axis]-1,using:&a),using:&a) == .equal && field.compare(hi,field.integer(spans[axis],using:&a),using:&a) == .equal)
            }
            let (ax,ay)=try triangle(0,spans[0]),(bx,by)=try triangle(1,spans[1]),(cx,cy)=try triangle(2,spans[2]),(dx,dy)=try triangle(3,spans[3])
            let equalities=[try r.subtracting(ax,cx,using:&a),try r.subtracting(r.adding(ay,bx,using:&a),r.adding(cy,dx,using:&a),using:&a),try r.subtracting(by,dy,using:&a)]
            let proofs=try equalities.map { law -> ExactRealCellSignInvariant<Base>? in
                if try r.isZero(law,using:&a) { return nil }
                guard let proof=try c.signInvariant(for:law,in:partition,using:&a) else { throw Failure.assertion(#line) };return proof
            }
            for cell in partition.cells where cell.axis==3 {
                terminals+=1;var expected=true
                for proof in proofs { if let proof { if try c.sign(of:proof,at:cell,using:&a) != .zero { expected=false } } }
                try require(template.fundamental.relation.selection.cells.contains(cell)==expected)
                if expected { selected+=1 }
            }
        }
        Common.metric("METRIC complete81 raw terminals/selected",[terminals,selected])
        Common.marker("PASS complete81 symbolic raw equality and49 exact scoped parent shifts")
    }
    static func main() {
        do {
            var a=try Common.ledger();let (raw,parent,identities)=try prepare(&a)
            var q=try Common.ledger();let result=try query(raw,parent,identities,&q)
            Common.metric("METRIC preparedQueryBoundary",[q.work,q.storageBytes])
            var proof=try Common.ledger();try oracle(result,&proof)
        } catch {
#if !hasFeature(Embedded)
            print("OBSERVED STOP S-IMAGE-PERIOD-01",error)
#else
            Common.marker("OBSERVED STOP S-IMAGE-PERIOD-01")
#endif
            fflush(nil);exit(2)
        }
    }
}
