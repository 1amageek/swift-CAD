import CADCore
@testable import CADGeometry
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif

/// Reproduces the complete requested image binding before changing its consumer.
@main struct ImagePeriodicSelfAcceptance {
    typealias Common = NativeIdentityCompositionAcceptance
    typealias Base = OriginalExactScalarDomain
    typealias Source = OriginalParameterImageSnapshot<OriginalImageSurface3D,BSplineSurface3D>
    typealias Child = OriginalBSplineDomainCover<BSplineSurface3D,Base>
    static func main() {
        do {
            var a=try Common.ledger()
            let f=try Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
            let limits=try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:1),maximumTransportDepth:16,
                maximumCharts:64,maximumFamilies:2,maximumIdentityProofs:64)
            let xy:[(Double,Double)]=[(0,0),(1,0),(0,1),(0,0)]
            let native=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[-1,0,1,2,3,4],vKnots:[-1,0,1,2,3,4],
                controlPoints:xy.map { v in xy.map { u in .init(x:u.0,y:u.1+v.0,z:v.1) } },isUPeriodic:true,isVPeriodic:true)
            let image=try OriginalImageSurface3D(source:.bSpline(native),uGain:-1,vGain:1,uOffset:1,
                transform:.init(basisX:.unitX,basisY:.unitY,basisZ:.unitZ,translation:.zero),swapAxes:true,tolerance:.standard)
            let source=try DefaultOriginalSourceBindingIssuer(provider:OriginalParameterImageSurfaceSnapshotProvider(
                child:OriginalNativeSurfaceFamilySnapshotProvider(tolerance:.standard),tolerance:.standard))
                .bind(image,limits:limits.source,using:&a)
            let child=source.original.originalChild,issuer=DefaultOriginalBSplineDomainIssuer<BSplineSurface3D,Base>()
            let space=try issuer.prepare(source:child,field:f,limits:limits,using:&a)
            let childCover=try issuer.issue(space:space,request:space.frame.fullSelection(limits:limits,using:&a),limits:limits,using:&a)
            func interval(_ lo:Int,_ hi:Int) throws -> ExactParameterInterval<Base.Value> {
                try .checked(field:f,lower:.finite(f.integer(lo,using:&a)),upper:.finite(f.integer(hi,using:&a)),depth:.zero,using:&a)
            }
            let parent=try DefaultOriginalParameterImageDomainIssuer<Source,Child>().issue(source:source,child:childCover,
                requested:[[interval(-3,6)],[interval(-3,6)]],limits:limits,using:&a)
            try Common.require(parent.integerFamilyRank==2 && parent.templateCount==9)
            let one=try OriginalParameterCycle(exact:ExactRationalScalarDomain().integer(1,using:&a),using:&a)
            for axis in 0..<2 {
                let proof=try DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,Base>().periodic(cover:childCover,
                    from:childCover.effective,axis:axis,cycle:one,limits:limits,using:&a)
                let lifted=try DefaultOriginalAffineChildParameterIdentityIssuer<Source,Child>().lifted(proof,through:parent,limits:limits,using:&a)
                let view=try DefaultOriginalParameterIdentityIssuer<Source,Base>().relation(of:lifted,limits:limits,using:&a)
                guard case .affine(let p,let gains,let offsets)=view.constraints else { throw ExactScalarFailure.invalidEvidence }
                try Common.require(p==[0,1])
                for coordinate in 0..<2 {
                    try Common.require(try f.compare(gains[coordinate],f.integer(1,using:&a),using:&a) == .equal)
                    let expected=axis==0 ? (coordinate==1 ? 3:0):(coordinate==0 ? -3:0)
                    try Common.require(try f.compare(offsets[coordinate],f.integer(expected,using:&a),using:&a) == .equal)
                }
            }
            Common.marker("PASS actual image full request, two period3 source families and exact transported shifts")
            var children:[OriginalRationalChartReceipt<BSplineSurface3D,OriginalBSplineChartSelection,Base>]=[]
            for chart in space.sourceCharts {
                children.append(try DefaultOriginalBSplineChartIssuer<BSplineSurface3D,Base>().issue(source:child,
                    chart:chart,field:f,limits:limits.source,using:&a))
            }
            let laws=try DefaultOriginalFiniteParameterImageChartPreparer<Source,OriginalBSplineChartSelection,Base>()
                .prepare(source:source,children:children,field:f,maximumCharts:9,limits:limits.source,using:&a)
            _=try DefaultOriginalIssuedDomainBinder().bind(laws:laws,request:parent.effective,limits:limits,using:&a)
            Common.marker("UNEXPECTED finite fundamental cover accepted the complete multi-cycle request")
            exit(3)
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
