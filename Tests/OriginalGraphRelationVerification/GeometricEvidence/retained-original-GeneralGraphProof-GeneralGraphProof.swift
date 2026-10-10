import L0
import L1
import L2
import L3
import L4
import L5
import L6

@main enum GeneralGraphProof {
    enum Failure: Error { case incorrect }
    static func main() throws {
        typealias Base = OriginalExactScalarDomain
        typealias Field = ExactAlgebraicScalarDomain<Base>
        typealias Cells = ExactRealCellDomain<Base>
        var a = ExactScalarLedger(limits: try .init(work:80_000_000,storageBytes:700_000_000,valueDepth:32,coefficientDepth:32))
        let base = try Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let field = try Field.base(field:base,maximumExtensionLevel:32,using:&a)
        let cells = try Cells(field:field,variableCount:2,using:&a), ring = cells.polynomials
        let zero = try ring.zero(using:&a), one = try ring.constant(field.integer(1,using:&a),using:&a)
        let u = try ring.variable(0,using:&a), v = try ring.variable(1,using:&a)
        let x = try ring.adding(u,ring.multiplying(v,v,using:&a),using:&a)
        let roots = try ExactRealRootDomain(field:field,using:&a)
        let interval = try roots.domain(lower:.finite(field.integer(0,using:&a)),upper:.finite(field.integer(1,using:&a)),using:&a)
        let singleton = try roots.domain(lower:.finite(field.integer(0,using:&a)),upper:.finite(field.integer(0,using:&a)),using:&a)
        let first = try cells.bind(polynomials:[x,zero,zero,one],domains:[interval,singleton],using:&a)
        let second = try cells.bind(polynomials:[u,zero,zero,one],domains:[interval,singleton],using:&a)
        let domain = ExactParametricRelationDomain<Base,Cells,ExactRealTopology<Base>>(cells:Cells.self,topology:.init(cells:Cells.self))
        let left = try domain.graph(from:cells.predicate(instructions:[.literal(true)],for:first,using:&a),parameterCount:2,using:&a)
        let right = try domain.graph(from:cells.predicate(instructions:[.literal(true)],for:second,using:&a),parameterCount:2,using:&a)
        let cellLimits = try ExactRealCellLimits(maximumStoredCells:20_000,maximumRootsPerStack:100)
        let topologyLimits = try ExactRealTopologyLimits(maximumGeneratedCells:20_000,maximumRootsPerStack:100,maximumClosures:1000,maximumAttachmentPieces:20_000,maximumComponents:1000)
        let original = try domain.resolve(domain.compile(kind:.surfaceSurface,first:left,second:right,using:&a),cellLimits:cellLimits,topologyLimits:topologyLimits,using:&a)
        let limits = try ExactGeometricRelationLimits(cells:cellLimits,topology:topologyLimits,maximumStrata:1000,maximumProjectionSpans:1000)
        let resolver = DefaultExactGeometricGraphRelationResolver<Base>()
        let geometry = try resolver.resolve(original,limits:limits,using:&a)
        guard geometry.evidenceKind == .originalGraph, geometry.graph != nil,
            geometry.strata.contains(where:{$0.parameterDimension==1 && $0.imageDimension==1 && $0.fiberDimension==0}),
            geometry.strata.allSatisfy({$0.parameterDimension==$0.imageDimension && $0.fiberDimension==0}) else {throw Failure.incorrect}
        let xyz = ExactXYZ(field:field,x:try field.binary64(exactly:0.5,using:&a),y:try field.integer(0,using:&a),z:try field.integer(0,using:&a))
        let fiber = try resolver.fiber(at:.xyz(xyz),in:geometry,limits:limits,using:&a)
        guard fiber.components.count == 1, fiber.selection.cells.allSatisfy({$0.dimension==0}) else {throw Failure.incorrect}
        print("PASS general nonlinear XYZ graph pullback and exact station fiber work=\(a.work) storage=\(a.storageBytes)")
    }
}
