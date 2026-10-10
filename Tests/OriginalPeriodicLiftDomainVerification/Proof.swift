import L0
import L1
import DI0
import SourceIssuer
import DI

@main struct PeriodicLiftDomainProof {
    static func main() throws { try run() }
    nonisolated static func family(two: Bool=false,multi: Bool=false,huge: Bool=false) throws -> OriginalPeriodicNativeSurfaceLiftGraphs<PeriodicLiftProof.Source> {
        let base=try PeriodicLiftProof.family(two:two)
        if !multi && !huge { return base }
        var a=try LiftAdmission();let l=try OriginalSourceIssuanceLimits(remainingSourceDepth:8)
        let giant=3*Double(sign:.plus,exponent:96,significand:1)
        let values=huge ? [giant,giant]:[-3.0,0,6]
        let p=NativeInput(degrees:[1],knots:[huge ? [0,0,1,1]:[0,0,1,3,3]],counts:[values.count],
            controls:values.map { [$0,two ? (huge ? -$0:$0):0.5,0] },weights:Array(repeating:1,count:values.count),periodic:[false])
        let pcurve=try DefaultOriginalSourceBindingIssuer(provider:NativeProvider()).bind(p,limits:l,using:&a)
        let source=try DefaultOriginalSourceBindingIssuer(provider:PeriodicLiftProof.Provider()).bind(
            PeriodicLiftProof.Source(originalSurface:base.surface.source,originalPcurve:pcurve),limits:l,using:&a)
        let pc=try DefaultOriginalFiniteBSplineChartPreparer<NativeSnapshot>().prepare(source:pcurve,field:base.field,maximumCharts:32,limits:l,using:&a)
        return try DefaultOriginalPeriodicNativeSurfaceLiftGraphPreparer<PeriodicLiftProof.Source>().prepare(source:source,surface:base.surface,pcurve:pc,maximumCharts:32,limits:l,using:&a)
    }
    nonisolated static func detachedSource() throws -> OriginalPeriodicNativeSurfaceLiftChartOccurrence<PeriodicLiftProof.Source> {
        let original=try family(two:true)
        var a=try LiftAdmission();let f=original.field
        let tuple=[try f.binary64(exactly:0.5,using:&a),try f.binary64(exactly:1.5,using:&a),try f.binary64(exactly:1.5,using:&a)]
        return try DomainChecks.detached(original,tuple:tuple)
    }
    nonisolated static func run() throws {
        for two in [false,true] {
            try DomainChecks.run(family(two:two),twoAxes:two)
            try DomainChecks.run(family(two:two,multi:true),twoAxes:two,multi:true)
            try DomainChecks.run(PeriodicLiftProof.family(two:two,nonmonotone:true),twoAxes:two,nonmonotone:true)
            try DomainChecks.run(PeriodicLiftProof.family(two:two,constant:3),twoAxes:two,constant:true)
            try DomainChecks.huge(family(two:two,huge:true),twoAxes:two)
        }
        try DomainChecks.resources(family(),foreign:family())
        let retained=try detachedSource()
        var a=try LiftAdmission();let f=retained.family.field
        let tuple=[try f.binary64(exactly:0.5,using:&a),try f.binary64(exactly:1.5,using:&a),try f.binary64(exactly:1.5,using:&a)]
        try retained.relation.admitProof(limits:DomainChecks.limits(),using:&a)
        try LiftChecks.require(retained.relation.graph.admits(tuple,limits:DomainChecks.limits().source,using:&a))
        print("PASS returned occurrence after original source, family and prepared cover scopes end")
        print("PASS independent periodic lift source/domain/binder composition")
    }
}
