import CADCore
import HashTreeCollections
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
import SourceGeometryAdapters
@testable import NativeDomainAdapters
import NativeKernelAdapters
import CADTopology
import struct CADGeometry.BSplineCurve2D
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import enum CADGeometry.SurfaceParameterCurve
@testable import class CADGeometry.OriginalNativeBoundaryDomain

/// One actual public Native observation; refusal is not successful material clipping.
@main struct RationalQuadraticBoundaryObservation {
    typealias Fixture = M6ExactBoundaryFixtures
    typealias Base = ExactRationalScalarDomain
    typealias Field = Fixture.Field
    typealias Cells = ExactRealCellDomain<Base>
    enum Failure: Error { case assertion(Int) }
    static func require(_ condition: Bool, line: Int = #line) throws {
        guard condition else { throw Failure.assertion(line) }
    }
    static func pcurves() -> [SurfaceParameterCurve] {
        [.constantV(v: 0, uStart: 0, uEnd: 0.5),
         .constantU(u: 0.5, vStart: 0, vEnd: 0.25),
         .bSpline(BSplineCurve2D(degree: 2, knots: [0,0,0,1,1,1],
            controlPoints: [.init(x: 0.5,y: 0.25), .init(x: 0.25,y: 0.25), .init(x: 0,y: 0)],
            weights: [1,3,1]))]
    }
    static func checkMap(_ map: ExactParametricMap<Base>, surface: Bool,
        using a: inout ExactScalarLedger) throws {
        let cells = try Cells(retaining: map.original, using: &a), ring = cells.polynomials
        let field = try cells.coefficientField(of: map.original, using: &a)
        let zero = try ring.zero(using: &a), one = try ring.constant(field.integer(1, using: &a), using: &a)
        let u = try ring.variable(0, using: &a)
        let y = try ring.constant(field.dividing(field.integer(7, using: &a), field.integer(32, using: &a), using: &a), using: &a)
        let expected = surface ? [u, try ring.variable(1, using: &a), zero, one] : [u,y,zero,one]
        try require(map.parameterCount == (surface ? 2 : 1) && map.original.polynomials.count == 4)
        for index in expected.indices { try require(ring.equals(map.original.polynomials[index], expected[index], using: &a)) }
        for domain in map.original.domains {
            guard case .finite(let lo) = domain.lower, case .finite(let hi) = domain.upper else { throw Failure.assertion(#line) }
            try require(domain.includesLower && domain.includesUpper && !domain.isEmpty)
            try require(field.compare(lo, field.integer(0, using: &a), using: &a) == .equal)
            try require(field.compare(hi, field.integer(1, using: &a), using: &a) == .equal)
        }
    }
    static func oracle(_ partition: ExactRealCellPartition<Base>, selected: (ExactRealCellID<Base>) -> Bool,
        material: Bool, using a: inout ExactScalarLedger) throws -> [[ExactSign]] {
        let cells = try Cells(retaining: partition.source, using: &a), ring = cells.polynomials
        let field = try cells.coefficientField(of: partition.source, using: &a)
        let t = try ring.variable(0, using: &a), u = try ring.variable(1, using: &a), v = try ring.variable(2, using: &a)
        func constant(_ n: Int, _ d: Int = 1) throws -> ExactPolynomial<Field> {
            try ring.constant(field.dividing(field.integer(n, using: &a), field.integer(d, using: &a), using: &a), using: &a)
        }
        let one = try constant(1)
        var laws = [t, try ring.subtracting(t,one,using:&a), u, try ring.subtracting(u,one,using:&a),
            v, try ring.subtracting(v,one,using:&a), try ring.subtracting(u,t,using:&a),
            try ring.subtracting(v,constant(7,32),using:&a)]
        if material {
            laws.append(try ring.subtracting(t,constant(1,4),using:&a))
            laws.append(try ring.subtracting(t,constant(1,2),using:&a))
        }
        var proofs: [ExactRealCellSignInvariant<Base>] = []
        for law in laws {
            guard let proof = try cells.signInvariant(for:law,in:partition,using:&a) else { throw Failure.assertion(#line) }
            proofs.append(proof)
        }
        var signatures: [[ExactSign]] = [], count = 0
        for cell in partition.cells where cell.axis == 2 {
            let signs = try proofs.map { try cells.sign(of:$0,at:cell,using:&a) }
            let raw = signs[0] != .negative && signs[1] != .positive && signs[2] != .negative && signs[3] != .positive &&
                signs[4] != .negative && signs[5] != .positive && signs[6] == .zero && signs[7] == .zero
            let expected = raw && (!material || (signs[8] != .negative && signs[9] != .positive))
            try require(selected(cell) == expected)
            if expected { signatures.append(signs) }
            count += 1
        }
        try require(count > 0 && !signatures.isEmpty)
        print("WHOLE_ORACLE", material ? "refined" : "raw", "terminal", count, "selected", signatures.count)
        return signatures
    }
    static func successOracle(_ result: OriginalExactFaceClippedParameters, using a: inout ExactScalarLedger) throws {
        guard case .curveSurface(let raw) = result.parameters.boundary.source else { throw Failure.assertion(#line) }
        try require(raw.pieces.count == 1 && result.parameters.refinements.count == 1)
        let selected = raw.pieces[0].relation.selection
        _ = try oracle(selected.partition, selected: { selected.cells.contains($0) }, material:false, using:&a)
        let refined = result.parameters.refinements[0], pullback = refined.parameters.pullback, region = pullback.region
        try require(pullback.coordinateMap == [0,1,2])
        _ = try oracle(region.partition, selected: { cell in
            let indices = region.cells.indices.filter { region.cells[$0] == cell }
            return indices.count == 1 && region.included[indices[0]]
        }, material:true, using:&a)
        for index in region.cells.indices {
            let ordinal = pullback.sourceCellOrdinals[index]
            if region.included[index] { try require(selected.cells.indices.contains(ordinal)) }
            else { try require(ordinal == -1 && refined.boundarySpans[index].isEmpty) }
        }
        print("OBSERVED_COMPLETE_SUCCESS independent whole-cell tuple iff [t,t,7/32], t in [1/4,1/2]")
    }
    static func main() throws {
        var stage = "source"
        do {
            var a = try Fixture.ledger()
            let field = try Field.base(field:Base(),maximumExtensionLevel:10,using:&a)
            let surface = Fixture.plane(), curve = Fixture.line(y:7.0/32)
            let raw = try Fixture.raw(curve,surface,field,&a)
            try require(raw.pieces.count == 1)
            try checkMap(raw.pieces[0].relation.original.first,surface:false,using:&a)
            try checkMap(raw.pieces[0].relation.original.second,surface:true,using:&a)
            print("REACHED exact Native raw source; full authored closed TUV; C=(t,7/32,0); G=(u,v,0)")
            stage = "exact-validation"
            let owner = try Fixture.face(surface,[(.outer,pcurves())])
            try require(owner.0.validationLevel == .exact)
            let retained = owner.0.model.faces[owner.1]!
            try require(retained.loops.count == 1)
            let loop = owner.0.model.loops[retained.loops[0]]!
            try require(loop.role == .outer && loop.coedges.count == 3)
            for index in pcurves().indices {
                try require(loop.coedges[index].orientation == .forward && loop.coedges[index].surfaceParameterCurve == pcurves()[index])
            }
            print("REACHED exact validated face; original weighted quadratic pcurve retained unchanged")
            stage = "public-clip"
            print("CALL DefaultOriginalFaceBoundaryClipper.clip curveSurface closed once")
            let result = try Fixture.clip(.curveSurface(raw),owner,&a)
            stage = "success-oracle"
            try successOracle(result,using:&a)
        } catch let failure as NativeExactRelationFailure {
            print("OBSERVED_TYPED_STOP stage",stage,"cause",String(describing:failure))
            guard stage == "public-clip", case .unsupportedCoverage = failure else { throw failure }
            print("NO_CLIPPED_SUCCESS B-NATIVE-RATIONAL-QUADRATIC-CLOSED-01")
        } catch {
            print("OBSERVED_OTHER_STOP stage",stage,"cause",String(describing:error))
            throw error
        }
    }
}
