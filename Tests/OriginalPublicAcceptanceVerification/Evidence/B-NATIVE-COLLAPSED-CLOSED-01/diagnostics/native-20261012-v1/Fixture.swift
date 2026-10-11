import CADCore
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
import NativeDomainAdapters
import NativeKernelAdapters
import CADTopology
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
@testable import class CADGeometry.OriginalNativeBoundaryDomain

/// Complete authored TUV and material-incidence oracle for one collapsed Native cell.
@main struct NativeCollapsedBoundaryAcceptance {
    typealias Fixture = M6ExactBoundaryFixtures
    typealias Base = ExactRationalScalarDomain
    typealias Field = Fixture.Field
    typealias Cells = ExactRealCellDomain<Base>
    typealias Raw = Fixture.Raw
    typealias Result = OriginalExactFaceClippedParameters
    enum Failure: Error { case assertion(Int), unexpectedSuccess }

    static func require(_ condition: Bool, line: Int = #line) throws {
        guard condition else {
#if !hasFeature(Embedded)
            print("FAIL B-NATIVE-COLLAPSED-CLOSED-01 assertion", line)
#else
            print("FAIL B-NATIVE-COLLAPSED-CLOSED-01 assertion")
#endif
            throw Failure.assertion(line)
        }
    }

    static func inputs() -> (BSplineCurve3D, BSplineSurface3D) {
        let curve = BSplineCurve3D(degree: 1, knots: [0,0,1,1],
            controlPoints: [.init(x: 0,y: 0,z: 0), .init(x: 0,y: 0,z: 0)])
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0,0,1,1], vKnots: [0,0,1,1], controlPoints: [
                [.init(x: 0,y: 0,z: 0), .init(x: 0,y: 0,z: 0)],
                [.init(x: 0,y: 1,z: 0), .init(x: 1,y: 1,z: 0)]])
        return (curve, surface)
    }

    static func checkMap(_ map: ExactParametricMap<Base>, surface: Bool,
        using a: inout ExactScalarLedger) throws {
        let cells = try Cells(retaining: map.original, using: &a), ring = cells.polynomials
        let field = try cells.coefficientField(of: map.original, using: &a)
        let zero = try ring.zero(using: &a)
        let one = try ring.constant(field.integer(1, using: &a), using: &a)
        let u = try ring.variable(0, using: &a)
        let expected: [ExactPolynomial<Field>]
        if surface {
            let v = try ring.variable(1, using: &a)
            expected = [try ring.multiplying(u, v, using: &a), v, zero, one]
        } else { expected = [zero, zero, zero, one] }
        try require(map.parameterCount == (surface ? 2 : 1) && map.original.polynomials.count == 4)
        for index in expected.indices {
            try require(ring.equals(map.original.polynomials[index], expected[index], using: &a))
        }
        for domain in map.original.domains {
            guard case .finite(let lo) = domain.lower, case .finite(let hi) = domain.upper else {
                throw Failure.assertion(#line)
            }
            try require(domain.includesLower && domain.includesUpper && !domain.isEmpty)
            try require(field.compare(lo, field.integer(0, using: &a), using: &a) == .equal)
            try require(field.compare(hi, field.integer(1, using: &a), using: &a) == .equal)
        }
    }

    static func checkInput(_ raw: Raw, using a: inout ExactScalarLedger) throws {
        try require(raw.pieces.count == 1)
        let piece = raw.pieces[0], source = piece.relation.original
        try require(source.kind == .curveSurface && source.firstParameters == 0..<1 && source.secondParameters == 1..<3)
        try checkMap(source.first, surface: false, using: &a)
        try checkMap(source.second, surface: true, using: &a)
        let left = try DefaultOriginalParameterTransporter<BSplineCurve3D, Field>()
            .affineCoordinates(of: piece.first.inverse, limits: Fixture.limits(), using: &a)
        let right = try DefaultOriginalParameterTransporter<BSplineSurface3D, Field>()
            .affineCoordinates(of: piece.second.inverse, limits: Fixture.limits(), using: &a)
        try require(left.permutation == [0] && right.permutation == [0,1])
        for transport in [left.gains, right.gains] {
            for value in transport { try require(raw.first.space.frame.scalarField.compare(value,
                raw.first.space.frame.scalarField.integer(1, using: &a), using: &a) == .equal) }
        }
        for transport in [left.offsets, right.offsets] {
            for value in transport { try require(raw.first.space.frame.scalarField.sign(of: value, using: &a) == .zero) }
        }
        print("PASS B-NATIVE-COLLAPSED-CLOSED-01 exact source laws, closed full TUV and authored transport")
    }

    static func invariants(_ partition: ExactRealCellPartition<Base>, material: Bool,
        using a: inout ExactScalarLedger) throws -> (Cells, [ExactRealCellSignInvariant<Base>]) {
        try require(partition.source.variableCount == 3)
        let cells = try Cells(retaining: partition.source, using: &a), ring = cells.polynomials
        let field = try cells.coefficientField(of: partition.source, using: &a)
        let coordinates = try (0..<3).map { try ring.variable($0, using: &a) }
        let one = try ring.constant(field.integer(1, using: &a), using: &a)
        var laws = [coordinates[0], try ring.subtracting(coordinates[0], one, using: &a),
            coordinates[1], try ring.subtracting(coordinates[1], one, using: &a),
            coordinates[2], try ring.subtracting(coordinates[2], one, using: &a)]
        if material {
            for numerator in [1,3] {
                let bound = try field.dividing(field.integer(numerator, using: &a), field.integer(4, using: &a), using: &a)
                laws.append(try ring.subtracting(coordinates[1], ring.constant(bound, using: &a), using: &a))
            }
        }
        var proofs: [ExactRealCellSignInvariant<Base>] = []
        for (index, law) in laws.enumerated() {
            guard let proof = try cells.signInvariant(for: law, in: partition, using: &a) else {
#if !hasFeature(Embedded)
                print("FAIL B-NATIVE-COLLAPSED-CLOSED-01 missing independent whole-cell invariant", material, index)
#endif
                throw Failure.assertion(#line)
            }
            proofs.append(proof)
        }
        return (cells, proofs)
    }

    static func rawOracle(_ raw: Raw, using a: inout ExactScalarLedger) throws {
        try checkInput(raw, using: &a)
        let selected = raw.pieces[0].relation.selection
        let (cells, proofs) = try invariants(selected.partition, material: false, using: &a)
        var checked = 0, included = 0, maximumDimension = -1
        for cell in selected.partition.cells where cell.axis == 2 {
            let signs = try proofs.map { try cells.sign(of: $0, at: cell, using: &a) }
            let expected = signs[0] != .negative && signs[1] != .positive &&
                signs[2] != .negative && signs[3] != .positive && signs[4] == .zero
            try require(selected.cells.contains(cell) == expected)
            checked += 1
            if expected { included += 1; maximumDimension = max(maximumDimension, cell.dimension) }
        }
        try require(checked > 0 && included == selected.cells.count && maximumDimension == 2)
#if !hasFeature(Embedded)
        print("METRIC rawTerminal", checked, "rawSelected", included)
#endif
        print("PASS B-NATIVE-COLLAPSED-CLOSED-01 independent raw whole-cell iff all(t,u,0), t/u in closed unit intervals")
    }

    static func retainedOracle(_ result: Result, using a: inout ExactScalarLedger) throws {
        guard case .curveSurface(let raw) = result.parameters.boundary.source else { throw Failure.assertion(#line) }
        try require(result.parameters.selection == .closed && result.parameters.refinements.count == raw.pieces.count)
        try require(result.loops.count == 1 && result.loops[0].role == .outer && result.loops[0].coedges.count == 4)
        let expectedPcurves = Fixture.rectangle(0.25, 0.75)
        for index in expectedPcurves.indices {
            let coedge = result.loops[0].coedges[index]
            try require(coedge.orientation == .forward && coedge.surfaceParameterCurve == expectedPcurves[index])
        }
        try require(result.original.model.faces[result.faceID]?.loops == result.loops.map(\.id))
        try rawOracle(raw, using: &a)
        let refined = result.parameters.refinements[0], pullback = refined.parameters.pullback, region = pullback.region
        let original = raw.pieces[0].relation.selection.cells
        try require(pullback.coordinateMap == [0,1,2] && region.coordinateCount == 3)
        try require(pullback.source.cells.count == original.count)
        for index in original.indices { try require(pullback.source.cells[index] == original[index]) }
        try require(region.cells.count == region.included.count && region.cells.count == pullback.sourceCellOrdinals.count &&
            region.cells.count == refined.boundarySpans.count)
        let (cells, proofs) = try invariants(region.partition, material: true, using: &a)
        var checked = 0, included = 0, bottom = 0, left = 0, right = 0, maximumDimension = -1
        for cell in region.partition.cells where cell.axis == 2 {
            let indices = region.cells.indices.filter { region.cells[$0] == cell }
            try require(indices.count == 1)
            let index = indices[0]
            let signs = try proofs.map { try cells.sign(of: $0, at: cell, using: &a) }
            let expected = signs[0] != .negative && signs[1] != .positive &&
                signs[2] != .negative && signs[3] != .positive && signs[4] == .zero &&
                signs[6] != .negative && signs[7] != .positive
            try require(region.included[index] == expected)
            let ordinal = pullback.sourceCellOrdinals[index]
            try require(expected ? original.indices.contains(ordinal) : ordinal == -1)
            var expectedSpans: [OriginalNativeBoundaryDomain.SpanReference] = []
            if expected {
                expectedSpans.append(.init(loopOrdinal: 0, curveOrdinal: 0, segmentOrdinal: 0)); bottom += 1
                if signs[6] == .zero { expectedSpans.append(.init(loopOrdinal: 0, curveOrdinal: 3, segmentOrdinal: 0)); left += 1 }
                if signs[7] == .zero { expectedSpans.append(.init(loopOrdinal: 0, curveOrdinal: 1, segmentOrdinal: 0)); right += 1 }
                included += 1; maximumDimension = max(maximumDimension, cell.dimension)
            }
            let actual = refined.boundarySpans[index]
            try require(actual.count == expectedSpans.count && expectedSpans.allSatisfy { actual.contains($0) })
            checked += 1
        }
        try require(checked == region.cells.count && included > 0 && bottom == included && left > 0 && right > 0 && maximumDimension == 2)
#if !hasFeature(Embedded)
        print("METRIC refinedTerminal", checked, "refinedSelected", included, "bottom", bottom, "left", left, "right", right)
#endif
        print("PASS B-NATIVE-COLLAPSED-CLOSED-01 independent refined whole-cell iff, all ordinals and bottom/corner incidents")
    }

    static func prepare() throws -> (Result, Int) {
        var a = try Fixture.ledger()
        let field = try Field.base(field: Base(), maximumExtensionLevel: 10, using: &a)
        let (curve, surface) = inputs()
        let raw = try Fixture.raw(curve, surface, field, &a)
        let face = try Fixture.face(surface, [(.outer, Fixture.rectangle(0.25, 0.75))])
        var query = try BoundaryPublicationAdmission()
        let result = try Fixture.clip(.curveSurface(raw), face, &query)
        try require(result.faceID == face.1)
        print("PASS B-NATIVE-COLLAPSED-CLOSED-01 actual Native CS and validated Kernel closed clipper")
        return (result, query.storageCalls)
    }

    static func controls(_ retained: Result, finalStorageCall: Int) throws {
        let source = retained.parameters.boundary.source
        let owner = (retained.original, retained.faceID)
        for mode in 0..<3 {
            var a = try Fixture.ledger(work: mode == 0 ? 0 : 80_000_000, bytes: mode == 1 ? 0 : 1_073_741_824)
            if mode == 2 { a.cancel() }
            do { _ = try Fixture.clip(source, owner, &a); throw Failure.unexpectedSuccess }
            catch let failure as NativeExactRelationFailure {
                let published = NativeExactGeometryPublicationFailure.published(failure, tolerance: .standard)
                if mode == 2 { try require(published is CancellationError) }
                else { try require((published as? KernelError)?.code == .resourceLimitExceeded) }
            }
        }
        var final = try BoundaryPublicationAdmission(cancellingCall: finalStorageCall)
        do { _ = try Fixture.clip(source, owner, &final); throw Failure.unexpectedSuccess }
        catch NativeExactRelationFailure.scalar(.cancelled) {}
        print("PASS B-NATIVE-COLLAPSED-CLOSED-01 entry/final cancellation and zero work/storage cause preservation")
        var a = try Fixture.ledger()
        let field = try Field.base(field: Base(), maximumExtensionLevel: 10, using: &a)
        let (curve, surface) = inputs()
        let outside = try Fixture.interval(2, 2, field, &a)
        let empty = try Fixture.raw(curve, surface, field, curveSelection: [[outside]], &a)
        try require(empty.pieces.isEmpty)
        let result = try Fixture.clip(.curveSurface(empty), owner, &a)
        try require(result.parameters.refinements.isEmpty && result.loops.count == 1)
        try require(!Fixture.contains(result, [Fixture.value(1,2,field,&a), Fixture.value(1,2,field,&a), Fixture.value(0,1,field,&a)], &a))
        print("PASS B-NATIVE-COLLAPSED-CLOSED-01 complete empty out-of-support request retained by actual Kernel clipper")
    }

    nonisolated static func main() throws {
        let (retained, finalStorageCall) = try prepare()
        var a = try Fixture.ledger()
        try retainedOracle(retained, using: &a)
        print("PASS B-NATIVE-COLLAPSED-CLOSED-01 complete oracle after construction/source scope release")
        try controls(retained, finalStorageCall: finalStorageCall)
        print("PASS B-NATIVE-COLLAPSED-CLOSED-01 complete cell; oracle image dimension 0 / original-coordinate fiber dimension 2")
    }
}
