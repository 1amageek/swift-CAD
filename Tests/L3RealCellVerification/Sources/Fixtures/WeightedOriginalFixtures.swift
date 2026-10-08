import L0
import L1
import L2
import L3

/// The recorded L3 input with independently checked original-equation reductions.
public enum WeightedOriginalFixtures {
    public static func verify() throws {
        let maximumWork = 16_777_216
        // This is stricter than the existing public Cell-stride allowance.
        var a = ExactScalarLedger(limits: try .init(work: maximumWork,
            storageBytes: 1_073_741_824, valueDepth: 32, coefficientDepth: 32))
        let f = try CellFixtures.Field.base(field: CellFixtures.Base(),
            maximumExtensionLevel: Int.max, using: &a)
        let d = try CellFixtures.Domain(field: f, variableCount: 3, using: &a)
        let p = d.polynomials
        let t = try p.variable(0, using: &a), u = try p.variable(1, using: &a), v = try p.variable(2, using: &a)
        func integer(_ value: Int, _ a: inout ExactScalarLedger) throws -> CellFixtures.Polynomial {
            try p.constant(f.integer(value, using: &a), using: &a)
        }
        let one = try integer(1, &a), two = try integer(2, &a)
        let half = try f.dividing(f.integer(1, using: &a), f.integer(2, using: &a), using: &a)
        let quarter = try f.dividing(half, f.integer(2, using: &a), using: &a)
        let uv = try p.multiplying(u, v, using: &a)
        let w = try p.subtracting(p.adding(p.adding(one, p.scaled(u, by: half, using: &a), using: &a), v, using: &a),
            p.scaled(uv, by: f.dividing(f.integer(3, using: &a), f.integer(2, using: &a), using: &a), using: &a), using: &a)
        let x = try p.adding(p.subtracting(p.adding(integer(-2, &a), p.scaled(u, by: f.integer(5, using: &a), using: &a), using: &a),
            p.multiplying(two, v, using: &a), using: &a), uv, using: &a)
        let y = try p.subtracting(p.adding(p.subtracting(integer(-2, &a), u, using: &a),
            p.scaled(v, by: f.integer(6, using: &a), using: &a), using: &a), uv, using: &a)
        let curveX = try p.subtracting(p.multiplying(two, t, using: &a), one, using: &a)
        let equations = [try p.subtracting(p.multiplying(curveX, w, using: &a), x, using: &a),
            try p.subtracting(p.scaled(w, by: quarter, using: &a), y, using: &a),
            try p.multiplying(p.multiplying(curveX, curveX, using: &a), w, using: &a)]
        let r = try ExactRealRootDomain(field: f, using: &a)
        let closed = try r.domain(lower: .finite(f.integer(0, using: &a)),
            upper: .finite(f.integer(1, using: &a)), using: &a)
        // The original nonzero W guard justifies division before the square reduction.
        let square = try p.dividedExactly(equations[2], by: w, using: &a)
        let factor = try p.subtracting(t, p.constant(half, using: &a), using: &a)
        let squareIdentity = try p.scaled(p.multiplying(factor, factor, using: &a),
            by: f.integer(4, using: &a), using: &a)
        try CellFixtures.require(try p.equals(square, squareIdentity, using: &a))
        // In the ordered field, 4*factor^2 == 0 iff factor == 0. Check every
        // original = quotient*factor + remainder identity before using the reduction.
        var reduced: [CellFixtures.Polynomial] = []
        for original in equations + [one, w] {
            let division = try p.divided(original, by: factor, using: &a)
            try CellFixtures.require(try p.equals(original,
                p.adding(p.multiplying(division.quotient, factor, using: &a), division.remainder, using: &a), using: &a))
            reduced.append(division.remainder)
        }
        reduced.append(factor)
        try CellFixtures.require(try p.isZero(reduced[2], using: &a))
        let source = try d.bind(polynomials: reduced, domains: [closed, closed, closed], using: &a)
        let predicate = try d.predicate(instructions: [.sign(polynomial: 0, relation: .equal),
            .sign(polynomial: 1, relation: .equal), .and, .sign(polynomial: 2, relation: .equal), .and,
            .sign(polynomial: 3, relation: .notEqual), .and, .sign(polynomial: 4, relation: .notEqual), .and,
            .sign(polynomial: 5, relation: .equal), .and], for: source, using: &a)
        let partition: ExactRealCellPartition<CellFixtures.Base>
        do {
            partition = try d.decompose(source, limits: .init(maximumStoredCells: Int.max,
                maximumRootsPerStack: Int.max), using: &a)
        } catch {
            print("WEIGHTED original decomposition failed: \(error); work=\(a.work), storage=\(a.storageBytes), depths=\(a.valueDepth)/\(a.coefficientDepth)")
            throw error
        }
        let selected = try d.select(partition, matching: predicate, using: &a)
        try CellFixtures.require(selected.cells.count == 1 && selected.cells[0].dimension == 0)
        let sample = try d.sample(of: selected.cells[0], in: partition, using: &a)
        let sf = sample.field, coordinates = sample.coordinates
        try CellFixtures.require(try sf.compare(coordinates[0], sf.dividing(sf.integer(1, using: &a),
            sf.integer(2, using: &a), using: &a), using: &a) == .equal)
        let quadratic = try sf.adding(sf.subtracting(sf.multiplying(coordinates[1], coordinates[1], using: &a),
            sf.multiplying(sf.integer(15, using: &a), coordinates[1], using: &a), using: &a), sf.integer(8, using: &a), using: &a)
        try CellFixtures.require(try sf.sign(of: quadratic, using: &a) == .zero)
        let correspondence = try sf.subtracting(sf.adding(sf.multiplying(sf.integer(9, using: &a), coordinates[2], using: &a),
            sf.multiplying(sf.integer(4, using: &a), coordinates[1], using: &a), using: &a), sf.integer(7, using: &a), using: &a)
        try CellFixtures.require(try sf.sign(of: correspondence, using: &a) == .zero)
        try CellFixtures.require(partition.source.polynomials.count == 6 && partition.cells.count > selected.cells.count)
        print("PASS weighted source-equivalent CS full box: cells=\(partition.cells.count), work=\(a.work)/\(maximumWork), storage=\(a.storageBytes), depths=\(a.valueDepth)/\(a.coefficientDepth)")
    }
}
