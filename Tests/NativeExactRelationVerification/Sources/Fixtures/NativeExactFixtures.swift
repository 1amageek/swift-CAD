import CADCore
import CADGeometry

public enum NativeExactFixtures {
    typealias Base = ExactRationalScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Cells = ExactRealCellDomain<Base>
    typealias RelationDomain = ExactParametricRelationDomain<Base, Cells, ExactRealTopology<Base>>
    enum Failure: Error { case invalidEvidence }
    static func require(_ condition: Bool) throws { if !condition { throw Failure.invalidEvidence } }
    static func ledger(work: Int = 80_000_000, bytes: Int = 1_073_741_824, depth: Int = 32) throws -> ExactScalarLedger {
        .init(limits: try .init(work: work, storageBytes: bytes, valueDepth: depth, coefficientDepth: depth))
    }
    static func cells(_ maximum: Int = 20000) throws -> ExactRealCellLimits {
        try .init(maximumStoredCells: maximum, maximumRootsPerStack: 100)
    }
    static func topology(_ components: Int = 1000) throws -> ExactRealTopologyLimits {
        try .init(maximumGeneratedCells: 20000, maximumRootsPerStack: 100,
            maximumClosures: 20000, maximumAttachmentPieces: 100000, maximumComponents: components)
    }
    static func plane(z: Double = 0) -> BSplineSurface3D {
        .init(uDegree: 1, vDegree: 1, uKnots: [0,0,1,1], vKnots: [0,0,1,1],
            controlPoints: [[.init(x:0,y:0,z:z),.init(x:1,y:0,z:z)],
                [.init(x:0,y:1,z:z),.init(x:1,y:1,z:z)]])
    }
    static func curve(_ z: [Double], weights: [Double]? = nil) -> BSplineCurve3D {
        let degree = z.count - 1
        return .init(degree: degree, knots: Array(repeating:0,count:degree+1)+Array(repeating:1,count:degree+1),
            controlPoints: z.map { .init(x:0.25,y:0.5,z:$0) }, weights: weights)
    }
    static func cs<R: NativeExactCurveSurfaceResolving, A: ExactScalarAdmission & ~Copyable>(
        _ resolver: R, _ c: BSplineCurve3D, _ s: BSplineSurface3D = plane(), range: ScalarInterval? = nil,
        box: SurfaceParameterBox? = nil, cellCount: Int = 20000, components: Int = 1000, degree: Int = 3,
        using a: inout A) throws -> NativeExactParametricRelation {
        try resolver.exactParameterRelation(curve: c, surface: s, curveRange: range, surfaceDomain: box,
            tolerance: .standard, maximumPolynomialDegree: degree, maximumExtensionLevel: 10,
            cellLimits: cells(cellCount), topologyLimits: topology(components), using: &a)
    }
    static func member(_ fractions: [(Int,Int)], _ result: NativeExactParametricRelation,
        expected: Bool, _ a: inout ExactScalarLedger) throws {
        let f=result.coefficientField
        let c=try Cells(retaining: result.relation.original.predicate.source, using: &a)
        var values: [Field.Value]=[]
        for (n,d) in fractions { values.append(try f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a)) }
        let point=try c.point(field:f,coordinates:values,using:&a)
        let resolver=RelationDomain(cells:Cells.self,topology:.init(cells:Cells.self))
        try require(try resolver.contains(point,in:result.relation,rootLimits:.init(maximumRoots:100),using:&a) == expected)
    }
    public static func verifyCS() throws {
        let resolver=DefaultCurveSurfaceIntersector()
        for mode in 0..<8 {
            var a=try ledger(work:8_388_608)
            var source=curve(mode == 1 ? [1,-1,1] : mode == 3 ? [0,0] : mode == 7 ? [0,1] : [-1,1], weights:mode == 0 ? [1,2]:nil)
            let range: ScalarInterval? = mode == 4 ? try .init(lower:2,upper:3) : mode == 5 ? try .init(lower:0.5,upper:0.5) : nil
            let s=plane(z:mode == 2 ? 2:0)
            let box: SurfaceParameterBox? = mode == 6 ? .init(u:try .init(lower:0.3,upper:1),v:try .init(lower:0,upper:1)):nil
            let result=try cs(resolver,source,s,range:range,box:box,using:&a)
            source.controlPoints.removeAll()
            if case .curveSurface(let retained,_,_,_)=result.source { try require(!retained.controlPoints.isEmpty) }
            else { throw Failure.invalidEvidence }
            if mode == 2 || mode == 4 || mode == 6 {
                try require(result.relation.selection.cells.isEmpty && result.relation.components.count == 0)
                try member([(1,2),(1,4),(1,2)],result,expected:false,&a)
            } else if mode == 3 {
                try require(result.relation.components.count == 1)
                try require(result.relation.selection.cells.contains { $0.dimension == 1 })
                try member([(1,2),(1,4),(1,2)],result,expected:true,&a)
            } else {
                try require(result.relation.selection.cells.count == 1 && result.relation.components.count == 1)
                try member([(mode == 7 ? 0:1,mode == 0 ? 3:2),(1,4),(1,2)],result,expected:true,&a)
            }
            print("PASS Native CS case \(mode) work=\(a.work) bytes=\(a.storageBytes)")
        }
        // Two distinct source UV tuples at one XYZ must both remain selected.
        let folded=BSplineSurface3D(uDegree:2,vDegree:1,uKnots:[0,0,0,1,1,1],vKnots:[0,0,1,1],
            controlPoints:[[.init(x:1,y:0,z:0),.init(x:-1,y:0,z:0),.init(x:1,y:0,z:0)],
                [.init(x:1,y:1,z:0),.init(x:-1,y:1,z:0),.init(x:1,y:1,z:0)]])
        var a=try ledger(work:8_388_608);let result=try cs(resolver,curve([-1,1]),folded,using:&a)
        try require(result.relation.selection.cells.count == 2 && result.relation.components.count == 2)
        try member([(1,2),(1,4),(1,2)],result,expected:true,&a)
        try member([(1,2),(3,4),(1,2)],result,expected:true,&a)
        print("PASS Native distinct UV work=\(a.work) bytes=\(a.storageBytes)")
    }
    static func ssi<R: NativeExactSurfaceSurfaceResolving>(_ r:R, _ first:BSplineSurface3D,
        _ second:BSplineSurface3D, _ a:inout ExactScalarLedger) throws -> NativeExactParametricRelation {
        try r.exactParameterRelation(first:first,second:second,firstDomain:nil,secondDomain:nil,
            tolerance:.standard,maximumPolynomialDegree:3,maximumExtensionLevel:10,
            cellLimits:cells(),topologyLimits:topology(),using:&a)
    }
    public static func verifySSI() throws {
        let perpendicular=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[[.init(x:0,y:0.5,z:0),.init(x:1,y:0.5,z:0)],
                [.init(x:0,y:0.5,z:1),.init(x:1,y:0.5,z:1)]])
        for mode in 0..<3 {
            var a=try ledger()
            let result=try ssi(DefaultSurfaceSurfaceIntersector(),plane(),mode == 0 ? perpendicular:plane(z:mode == 1 ? 0:1),&a)
            if mode == 2 { try require(result.relation.selection.cells.isEmpty) }
            else {
                try require(result.relation.components.count == 1)
                try require(result.relation.selection.cells.contains { $0.dimension == (mode == 0 ? 1:2) })
                try member(mode == 0 ? [(1,2),(1,2),(1,2),(0,1)]:[(1,2),(1,2),(1,2),(1,2)],result,expected:true,&a)
            }
            print("PASS Native SSI case \(mode) work=\(a.work) bytes=\(a.storageBytes)")
        }
        let folded=BSplineSurface3D(uDegree:2,vDegree:1,uKnots:[-1,-1,-1,1,1,1],vKnots:[-1,-1,1,1],
            controlPoints:[[.init(x:1,y:-1,z:0),.init(x:-1,y:-1,z:0),.init(x:1,y:-1,z:0)],
                [.init(x:1,y:1,z:0),.init(x:-1,y:1,z:0),.init(x:1,y:1,z:0)]])
        var a=try ledger();let result=try ssi(DefaultSurfaceSurfaceIntersector(),folded,folded,&a)
        try require(result.relation.selection.cells.count == 45 && result.relation.components.count == 1)
        try require(result.relation.components.incidence.attachments.count == 108)
        try member([(1,1),(0,1),(-1,1),(0,1)],result,expected:true,&a)
        try member([(1,1),(0,1),(0,1),(0,1)],result,expected:false,&a)
        print("PASS Native folded SSI cells=45 attachments=108 work=\(a.work) bytes=\(a.storageBytes)")
    }
    public static func verifyFailures() throws {
        for mode in 0..<7 {
            var a=try ledger(work:mode == 0 ? 0:80_000_000,bytes:mode == 1 ? 0:1_073_741_824)
            if mode == 2 { a.cancel() }
            var c=curve([-1,1])
            if mode == 5 { c.isPeriodic=true }
            if mode == 6 { c.weights=[1,-1] }
            do {
                _=try cs(DefaultCurveSurfaceIntersector(),c,cellCount:mode == 3 ? 0:20000,
                    components:mode == 4 ? 0:1000,using:&a)
                throw Failure.invalidEvidence
            } catch is NativeExactRelationFailure { }
        }
        var a=try ledger()
        do { _=try cs(DefaultCurveSurfaceIntersector(),curve([-1,1]),degree:0,using:&a);throw Failure.invalidEvidence }
        catch NativeExactRelationFailure.invalidDegree { }
        var shallow=try ledger(depth:0)
        do { _=try cs(DefaultCurveSurfaceIntersector(),curve([-0.5,-0.5,0.5]),using:&shallow);throw Failure.invalidEvidence }
        catch is NativeExactRelationFailure { }
        let multispan=BSplineCurve3D(degree:1,knots:[0,0,0.5,1,1],controlPoints:[
            .init(x:0.25,y:0.5,z:-1),.init(x:0.25,y:0.5,z:0),.init(x:0.25,y:0.5,z:1)])
        do { _=try cs(DefaultCurveSurfaceIntersector(),multispan,using:&a);throw Failure.invalidEvidence }
        catch NativeExactRelationFailure.unsupportedCoverage { }
        for empty in [false,true] {
            var measured=try FinalPublicationAdmission()
            _=try cs(DefaultCurveSurfaceIntersector(),curve(empty ? [1,2]:[-1,1]),using:&measured)
            var cancelled=try FinalPublicationAdmission(cancellingCall:measured.storageCalls)
            do { _=try cs(DefaultCurveSurfaceIntersector(),curve(empty ? [1,2]:[-1,1]),using:&cancelled);throw Failure.invalidEvidence }
            catch NativeExactRelationFailure.scalar(.cancelled) { }
            try require(cancelled.storageCalls == measured.storageCalls)
        }
        print("PASS Native atomic limits/input/cancel and final point/empty cancellation")
    }
}
