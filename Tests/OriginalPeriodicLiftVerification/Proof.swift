import L0
import L1
import SourceIssuer

@main struct PeriodicLiftProof {
    struct Source: OriginalSurfaceLiftSourceReading {
        let originalSurface: OriginalSourceBinding<NativeSnapshot>
        let originalPcurve: OriginalSourceBinding<NativeSnapshot>
    }
    struct Provider: OriginalSourceSnapshotting {
        func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Source,
            limits: OriginalSourceIssuanceLimits,using a: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<Source> {
            do { try a.checkpoint();try a.consumeWork(1);return .init(original:copy input,sourceDepth:1) }
            catch { throw .scalar(error) }
        }
    }
    static func main() throws { try run() }
    nonisolated static func family(two: Bool=false,nonmonotone: Bool=false,constant: Double?=nil) throws -> OriginalPeriodicNativeSurfaceLiftGraphs<Source> {
        var a=try LiftAdmission();let l=try OriginalSourceIssuanceLimits(remainingSourceDepth:8)
        let xy:[[Double]]=[[0,0],[1,0],[0,1],[0,0]],yz=two ? xy:[[0,0],[0,1]]
        var controls:[[Double]]=[]
        for v in yz { for u in xy { controls.append([u[0],u[1]+v[0],v[1]]) } }
        let native=NativeInput(degrees:[1,1],knots:[[-1,0,1,2,3,4],two ? [-1,0,1,2,3,4]:[0,0,1,1]],
            counts:[4,yz.count],controls:controls,weights:Array(repeating:1,count:controls.count),periodic:[true,two])
        let uv=constant.map { [$0,$0] } ?? (nonmonotone ? [-3.0,6.0,-3.0]:[-3.0,6.0])
        let p=NativeInput(degrees:[nonmonotone ? 2:1],knots:[nonmonotone ? [2,2,2,4,4,4]:[2,2,4,4]],counts:[uv.count],
            controls:uv.map { [$0,two ? $0:0.5,0] },weights:Array(repeating:1,count:uv.count),periodic:[false])
        let binder=DefaultOriginalSourceBindingIssuer(provider:NativeProvider())
        let surface=try binder.bind(native,limits:l,using:&a),pcurve=try binder.bind(p,limits:l,using:&a)
        let source=try DefaultOriginalSourceBindingIssuer(provider:Provider()).bind(Source(originalSurface:surface,originalPcurve:pcurve),limits:l,using:&a)
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let s=try DefaultOriginalBSplineFundamentalChartPreparer<NativeSnapshot>().prepare(source:surface,field:f,maximumCharts:32,limits:l,using:&a)
        let c=try DefaultOriginalFiniteBSplineChartPreparer<NativeSnapshot>().prepare(source:pcurve,field:f,maximumCharts:32,limits:l,using:&a)
        return try DefaultOriginalPeriodicNativeSurfaceLiftGraphPreparer<Source>().prepare(source:source,surface:s,pcurve:c,maximumCharts:32,limits:l,using:&a)
    }
    nonisolated static func run() throws {
        for two in [false,true] {
            try LiftChecks.run(family(two:two),twoAxes:two)
            try LiftChecks.run(family(two:two,nonmonotone:true),twoAxes:two,nonmonotone:true)
            try LiftChecks.run(family(two:two,constant:3),twoAxes:two,constant:true)
        }
        try LiftChecks.preparation(family(),foreign:family())
        try LiftChecks.huge(family(constant:3*Double(sign:.plus,exponent:96,significand:1)))
        print("PASS independent periodic lift source family")
    }
}
