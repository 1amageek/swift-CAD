import Darwin
import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
import PublicLiftPlanePort

@main struct RetainedLiftPlaneProof {
    nonisolated static func run() throws {
        var a = try PolylineLiftProof.Admission(work:8_388_608)
        let host = try PolylineAtlasLiftProof.shape(multi:true,using:&a).0
        let input = SurfaceLiftCurve3D(surface:.procedural(.originalCoons(host)),parameterCurve:.polyline(PolylineLiftProof.points()))
        let limits = try PolylineLiftProof.limits()
        let pcurve = try DefaultOriginalSourceBindingIssuer(provider:PolylineLiftAdapters.OriginalPolylinePcurveSnapshotProvider(maximumValueDepth:32,maximumCoefficientDepth:32))
            .bind(input.parameterCurve,limits:limits.source,using:&a)
        let f = pcurve.original.originalField
        let family = try PolylineAtlasLiftProof.prepared(PolylineLiftAdapters.OriginalCoonsAtlasSnapshotProvider(field:f,tolerance:.standard),input:input,pcurve:pcurve,using:&a)
        typealias Source = OriginalPolylineRetainedAtlasLiftSnapshot<OriginalCoonsAtlasSnapshot>
        let issuer = DefaultOriginalRetainedSurfaceLiftDomainIssuer<Source>()
        let frame = try issuer.frame(family:family,limits:limits,using:&a)
        let lift = try issuer.issue(request:frame.fullSelection(limits:limits,using:&a),family:family,limits:limits,using:&a)
        if CommandLine.arguments.contains("compiler") {
            let reducer = PolylineLiftAdapters.DefaultOriginalPolynomialSurfaceLiftGraphReducer<Source>()
            let reduced = try reducer.reduce(family.graphs[0],limits:limits.source,using:&a).graph
            let quarter = try f.binary64(exactly:0.25,using:&a)
            let interval = try ExactParameterInterval.checked(field:f,lower:.finite(quarter),upper:.finite(quarter),
                includesLower:true,includesUpper:true,depth:quarter.depth,using:&a)
            let request = try frame.selection(intervals:[[interval]],limits:limits,using:&a)
            let field = try PublicLiftPlane.ExactAlgebraicScalarDomain.base(field:f,maximumExtensionLevel:32,using:&a)
            let difference = try reduced.polynomials.subtracting(reduced.polynomials.variable(0,using:&a),
                reduced.polynomials.constant(quarter,using:&a),using:&a)
            for excluded in [false,true] {
                var conditions = reduced.conditions
                conditions.append(OriginalParametricGraphCondition(difference,excluded ? .notEqual:.equal))
                let original = PolylineLiftAdapters.OriginalPolynomialSurfaceLiftGraphReduction<Source>.Graph(
                    source:reduced.source,evidence:reduced.evidence,field:reduced.field,polynomials:reduced.polynomials,
                    homogeneous:reduced.homogeneous,support:reduced.support,includesUpperBoundary:reduced.includesUpperBoundary,
                    layout:reduced.layout,conditions:conditions,parameterTransport:reduced.parameterTransport,proofDepth:reduced.proofDepth)
                let binding = try DefaultOriginalParametricGraphDomainBinder().bind(graph:original,request:request,limits:limits,using:&a)
                let compiled = try PublicLiftPlane.DefaultOriginalIssuedGraphCompiler<Source,OriginalSurfaceLiftGraphEvidence<Source>>()
                    .compile(binding:binding,field:field,limits:limits,using:&a)
                let predicate = compiled.graph.predicate
                try PolylineLiftProof.require(compiled.graph.parameterCount == 1 && compiled.graph.variableCount == 1)
                for polynomial in predicate.source.polynomials {
                    for term in polynomial.terms { try PolylineLiftProof.require(term.powers.allSatisfy { $0 == 0 }) }
                }
                let cells = try PublicLiftPlane.ExactRealCellDomain<OriginalExactScalarDomain>(retaining:predicate.source,using:&a)
                let partition = try cells.decompose(predicate.source,limits:.init(maximumStoredCells:32,maximumRootsPerStack:32),using:&a)
                let selection = try cells.select(partition,matching:predicate,using:&a)
                try PolylineLiftProof.require(selection.cells.count == (excluded ? 0:1))
            }
            print("PASS singleton compiler: original parameter retained; all laws constant on scope; false guard excludes, true guard selects")
            return
        }
        if CommandLine.arguments.contains("reduction") {
            let reducer = PolylineLiftAdapters.DefaultOriginalPolynomialSurfaceLiftGraphReducer<Source>()
            let station = pcurve.original.originalCellUpperBound(at:0)
            let probes = [try f.integer(0,using:&a),try f.binary64(exactly:0.25,using:&a),station,
                try f.binary64(exactly:0.5,using:&a),try f.binary64(exactly:0.75,using:&a),try f.integer(1,using:&a)]
            var selected = 0, stationIncidents = 0, endpointIncidents = 0
            for original in family.graphs {
                let reduced = try reducer.reduce(original,limits:limits.source,using:&a)
                try PolylineLiftProof.require(reduced.graph.layout.variableCount == 1 && reduced.graph.layout.auxiliaries.isEmpty)
                try PolylineLiftProof.require(reduced.graph.conditions.count == original.conditions.count)
                for t in probes {
                    let coordinates = try reduced.originalCoordinates.map { try reduced.graph.polynomials.evaluated($0,at:[t],using:&a).value }
                    let expected = try original.admits(coordinates,limits:limits.source,using:&a)
                    let actual = try reduced.graph.admits([t],limits:limits.source,using:&a)
                    try PolylineLiftProof.require(expected == actual)
                    if actual {
                        selected += 1
                        if try f.compare(t,station,using:&a) == .equal { stationIncidents += 1 }
                        if try f.compare(t,f.integer(1,using:&a),using:&a) == .equal { endpointIncidents += 1 }
                        for axis in 0..<4 {
                            let left = try original.polynomials.evaluated(original.homogeneous[axis],at:coordinates,using:&a).value
                            let right = try reduced.graph.polynomials.evaluated(reduced.graph.homogeneous[axis],at:[t],using:&a).value
                            try PolylineLiftProof.require(f.compare(left,right,using:&a) == .equal)
                        }
                    }
                }
            }
            try PolylineLiftProof.require(stationIncidents == 8 && endpointIncidents == 4)
            let original = family.graphs[0]
            var probe = try PolylineLiftProof.Admission(work:8_388_608)
            let retained = try reducer.reduce(original,limits:limits.source,using:&probe)
            let work = probe.ledger.work,bytes = probe.ledger.storageBytes,checkpoints = probe.checkpoints
            var exact = try PolylineLiftProof.Admission(work:work,bytes:bytes)
            _ = try reducer.reduce(original,limits:limits.source,using:&exact)
            for mode in 0..<4 {
                var limited = try PolylineLiftProof.Admission(work:mode == 0 ? work-1:work,
                    bytes:mode == 1 ? bytes-1:bytes,cancelAt:mode == 2 ? 1:mode == 3 ? checkpoints:nil)
                do { _ = try reducer.reduce(original,limits:limits.source,using:&limited);throw ExactScalarFailure.invalidEvidence }
                catch let failure as OriginalSourceIssuanceFailure {
                    let cause = try PolylineLiftProof.scalarCause(failure)
                    switch (mode,cause) {
                    case (0,.resourceLimit(.work)),(1,.resourceLimit(.storage)),(2,.cancelled),(3,.cancelled):break
                    default:throw failure
                    }
                }
            }
            let invalid = PolylineLiftAdapters.OriginalPolynomialSurfaceLiftGraphReduction<Source>.Graph(
                source:original.source,evidence:original.evidence,field:original.field,polynomials:original.polynomials,
                homogeneous:original.homogeneous,support:original.support,includesUpperBoundary:original.includesUpperBoundary,
                layout:original.layout,conditions:original.conditions.filter { if case .equal = $0.relation { return false }; return true },
                parameterTransport:original.parameterTransport,proofDepth:original.proofDepth)
            var rejection = try PolylineLiftProof.Admission(work:8_388_608)
            do { _ = try reducer.reduce(invalid,limits:limits.source,using:&rejection);throw ExactScalarFailure.invalidEvidence }
            catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
            var later = try PolylineLiftProof.Admission(work:8_388_608)
            let zero = try f.integer(0,using:&later)
            try PolylineLiftProof.require(retained.graph.admits([zero],limits:limits.source,using:&later))
            print("INCIDENTS",stationIncidents,endpointIncidents,"missing equality rejected")
            print("PASS source reduction only: 12 charts, 72 tuple/guard comparisons,",selected,"admitted tuples; exact/one-less work",work,"bytes",bytes,"entry/final cancel")
            return
        }
        let plane = Surface3D.plane(.init(origin:.init(x:0.5,y:0,z:0),normal:.unitX))
        let source = try DefaultOriginalSourceBindingIssuer(provider:OriginalPlaneSnapshotProvider(tolerance:.standard))
            .bind(plane,limits:limits.source,using:&a)
        let one = try f.integer(1,using:&a)
        let basis = try DefaultOriginalPlaneBasisIssuer<OriginalPlaneSnapshot,OriginalExactScalarDomain>().issue(source:source,field:f,firstLength:one,normalLength:one,limits:limits.source,using:&a)
        let domain = DefaultOriginalPlaneDomainIssuer<OriginalPlaneSnapshot,OriginalExactScalarDomain>()
        let planeFrame = try domain.frame(basis:basis,limits:limits,using:&a)
        let planeCover = try domain.issue(request:planeFrame.fullSelection(limits:limits,using:&a),basis:basis,limits:limits,using:&a)
        let field = try PublicLiftPlane.ExactAlgebraicScalarDomain.base(field:f,maximumExtensionLevel:32,using:&a)
        let target = try PublicLiftPlane.DefaultOriginalPlaneGraphCompiler<OriginalPlaneSnapshot>().compile(cover:planeCover,field:field,limits:limits,using:&a)
        print("PREPARED",lift.templateCount,"work",a.ledger.work,"bytes",a.ledger.storageBytes)
        let geometry = try PublicLiftPlane.ExactGeometricRelationLimits(cells:.init(maximumStoredCells:Int.max,maximumRootsPerStack:Int.max),topology:.init(maximumGeneratedCells:Int.max,maximumRootsPerStack:Int.max,maximumClosures:Int.max,maximumAttachmentPieces:Int.max,maximumComponents:Int.max),maximumStrata:Int.max,maximumProjectionSpans:Int.max)
        func query(_ selected: OriginalRetainedSurfaceLiftDomainCover<Source>,maximumPoints:Int=4096,
            using usage:inout PolylineLiftProof.Admission) throws -> PublicLiftPlanePort.CurveSurfaceIntersectionResult {
            try DefaultCurveSurfaceIntersector().intersectionResult(lift:selected,plane:target,maximumPairs:32,
                limits:limits,geometryLimits:geometry,maximumPoints:maximumPoints,using:&usage)
        }
        if CommandLine.arguments.contains("resources") {
            var measured = try PolylineLiftProof.Admission(work:8_388_608)
            let retained = try query(lift,using:&measured)
            let work = measured.ledger.work,bytes = measured.ledger.storageBytes,checkpoints = measured.checkpoints
            var exact = try PolylineLiftProof.Admission(work:work,bytes:bytes)
            _ = try query(lift,using:&exact)
            for mode in 0..<5 {
                var limited = try PolylineLiftProof.Admission(work:mode == 0 ? work-1:work,
                    bytes:mode == 1 ? bytes-1:bytes,cancelAt:mode == 2 ? 1:mode == 3 ? checkpoints:nil)
                do { _ = try query(lift,maximumPoints:mode == 4 ? 11:4096,using:&limited);throw ExactScalarFailure.invalidEvidence }
                catch {
                    let published = PublicLiftPlane.NativeExactGeometryPublicationFailure.published(error,tolerance:.standard)
                    if mode == 2 || mode == 3 { try PolylineLiftProof.require(published is CancellationError) }
                    else { guard let failure = published as? KernelError else { throw published };try PolylineLiftProof.require(failure.code == .resourceLimitExceeded) }
                }
            }
            guard let receipt = retained.originalIssuedGeometricRelation else { throw ExactScalarFailure.invalidEvidence }
            var later = try PolylineLiftProof.Admission(work:8_388_608)
            try PolylineLiftProof.require(receipt.exactPoints[0].local.witness.field.sign(of:receipt.exactPoints[0].firstParameters[0],using:&later) == .positive)
            try PolylineLiftProof.require(receipt.exactPoints.count == 12)
            print("PASS prepared public resources: exact/one-less work",work,"bytes",bytes,"entry/final cancel, point limit, independent later admission")
            return
        }
        if CommandLine.arguments.contains("selections") {
            let station = pcurve.original.originalCellUpperBound(at:0)
            let half = try f.binary64(exactly:0.5,using:&a),one = try f.integer(1,using:&a)
            let bounds = [(half,one,true,true,4),(station,one,false,false,0),(station,station,true,true,8),
                (try f.integer(2,using:&a),try f.integer(3,using:&a),true,true,0)]
            for (lower,upper,closedLower,closedUpper,count) in bounds {
                let interval = try ExactParameterInterval.checked(field:f,lower:.finite(lower),upper:.finite(upper),
                    includesLower:closedLower,includesUpper:closedUpper,
                    depth:.init(value:max(lower.depth.value,upper.depth.value),coefficient:max(lower.depth.coefficient,upper.depth.coefficient)),using:&a)
                let selected = try issuer.issue(request:frame.selection(intervals:[[interval]],limits:limits,using:&a),family:family,limits:limits,using:&a)
                var usage = try PolylineLiftProof.Admission(work:8_388_608)
                let result = try query(selected,using:&usage)
                guard let receipt = result.originalIssuedGeometricRelation else { throw ExactScalarFailure.invalidEvidence }
                try PolylineLiftProof.require(receipt.exactPoints.count == count && receipt.isEmpty == (count == 0))
                try PolylineLiftProof.require(!receipt.hasPositiveDimensionalSolutions)
            }
            print("PASS prepared public selections: final root only, both endpoints open, exact irrational singleton, whole-support exclusion")
            return
        }
        let result = try query(lift,using:&a)
        guard let relation = result.originalIssuedGeometricRelation else { throw ExactScalarFailure.invalidEvidence }
        try PolylineLiftProof.require(result.representation == .exactRelation && !relation.isEmpty && !relation.hasPositiveDimensionalSolutions)
        var station = 0, endpoint = 0
        for point in relation.exactPoints {
            let q = point.local.witness.field
            try PolylineLiftProof.require(point.firstParameters.count == 1 && point.secondParameters.count == 2)
            let t = point.firstParameters[0]
            let one = try q.integer(1,using:&a),two = try q.integer(2,using:&a),half = try q.dividing(one,two,using:&a),zero = try q.integer(0,using:&a)
            if try q.compare(t,one,using:&a) == .equal { endpoint += 1 }
            else {
                try PolylineLiftProof.require(q.sign(of:t,using:&a) == .positive)
                try PolylineLiftProof.require(q.sign(of:q.subtracting(q.adding(q.multiplying(t,t,using:&a),q.multiplying(two,t,using:&a),using:&a),one,using:&a),using:&a) == .zero)
                station += 1
            }
            guard let sourceCoordinates = point.originalFirstCoordinates else { throw ExactScalarFailure.invalidEvidence }
            try PolylineLiftProof.require(sourceCoordinates.count == 3)
            try PolylineLiftProof.require(q.compare(sourceCoordinates[1],half,using:&a) == .equal && q.compare(sourceCoordinates[2],half,using:&a) == .equal)
            try PolylineLiftProof.require(q.compare(sourceCoordinates[0],t,using:&a) == .equal)
            try PolylineLiftProof.require(q.compare(point.secondParameters[0],zero,using:&a) == .equal)
            try PolylineLiftProof.require(q.compare(point.secondParameters[1],q.negated(half,using:&a),using:&a) == .equal)
            try PolylineLiftProof.require(q.compare(point.position.x,half,using:&a) == .equal)
            try PolylineLiftProof.require(q.compare(point.position.y,half,using:&a) == .equal)
            try PolylineLiftProof.require(q.compare(point.position.z,zero,using:&a) == .equal)
        }
        try PolylineLiftProof.require(station == 8 && endpoint == 4)
        print("PASS retained public lift/whole-plane", "station incidents",station,"endpoint incidents",endpoint,"work",a.ledger.work,"bytes",a.ledger.storageBytes)
    }
    static func main() {
        do { try run() }
        catch { print("FAIL retained lift/plane",error); exit(1) }
    }
}
