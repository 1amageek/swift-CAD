#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

extension DefaultExactGeometricGraphRelationResolver {
    func affineRow<A: ExactScalarAdmission & ~Copyable>(_ law: Polynomial, count: Int,
        placement: [Int]?, field: Field, _ a: inout A) throws -> [Field.Value]? {
        try ExactGeometryAccess.storage(count, Field.Value.self, &a)
        let zero = try field.integer(0, using: &a)
        var row = Array(repeating: zero, count: count)
        for term in law.terms {
            var variable: Int? = nil
            for i in term.powers.indices {
                try a.consumeWork(1)
                if term.powers[i] == 0 { continue }
                guard term.powers[i] == 1, variable == nil else { return nil }
                variable = i
            }
            if let variable {
                let index = placement?[variable] ?? variable
                guard index >= 0, index < count else { throw ExactGeometricRelationFailure.invalidSourceBinding }
                row[index] = try field.adding(row[index], field.importing(term.coefficient, using: &a), using: &a)
            }
        }
        return row
    }
    func activeAffineRows<A: ExactScalarAdmission & ~Copyable>(_ cell: ExactRealCellID<Base>, count: Int,
        field: Field, _ a: inout A) throws -> [[Field.Value]]? {
        var rows: [[Field.Value]] = []
        var current: ExactRealCellID<Base>? = cell
        while let prefix = current, prefix.axis != nil {
            let laws = prefix.projectionLaws, signs = prefix.projectionSigns
            guard laws.count == signs.count else { throw ExactGeometricRelationFailure.invalidCoverage }
            for index in laws.indices {
                try a.consumeWork(1)
                guard let row = try affineRow(laws[index], count: count, placement: nil, field: field, &a) else { return nil }
                if signs[index] == .zero {
                    try ExactGeometryAccess.storage(1, [Field.Value].self, &a); rows.append(row)
                }
            }
            current = prefix.parent
        }
        return rows
    }
    func rank<A: ExactScalarAdmission & ~Copyable>(_ input: [[Field.Value]], count: Int,
        field: Field, depth: inout ExactScalarDepth, _ a: inout A) throws -> Int {
        // The immutable input is shared. The elimination matrix is necessary new
        // scratch; account both its row handles and the COW row payloads.
        try ExactGeometryAccess.storage(input.count, [Field.Value].self, &a)
        for _ in input { try ExactGeometryAccess.storage(count, Field.Value.self, &a) }
        var matrix = input, pivot = 0
        for column in 0..<count {
            var found: Int? = nil
            for row in pivot..<matrix.count {
                try a.consumeWork(1)
                if try field.sign(of: matrix[row][column], using: &a) != .zero { found = row; break }
            }
            guard let found else { continue }
            matrix.swapAt(pivot, found)
            let divisor = matrix[pivot][column]
            for row in (pivot + 1)..<matrix.count {
                let factor = try field.dividing(matrix[row][column], divisor, using: &a)
                depth = try .init(value: max(depth.value, factor.depth.value), coefficient: max(depth.coefficient, factor.depth.coefficient))
                for index in column..<count {
                    try a.consumeWork(1)
                    let product = try field.multiplying(factor, matrix[pivot][index], using: &a)
                    let value = try field.subtracting(matrix[row][index], product, using: &a)
                    depth = try .init(value: max(depth.value, product.depth.value, value.depth.value), coefficient: max(depth.coefficient, product.depth.coefficient, value.depth.coefficient))
                    matrix[row][index] = value
                }
            }
            pivot += 1
            if pivot == matrix.count { break }
        }
        return pivot
    }
    func affineStrata<A: ExactScalarAdmission & ~Copyable>(_ relation: ExactParametricGraphRelation<Base>,
        components: [Int], limits: ExactGeometricRelationLimits, _ a: inout A)
        throws -> (records: [ExactGeometricStratumRecord], depth: ExactScalarDepth)? {
        let source = relation.original
        let firstPosition = try parameterPosition(source.first, &a)
        let secondPosition = try parameterPosition(source.second, &a)
        let parameterOnly = firstPosition || secondPosition
        let graph = !firstPosition && secondPosition ? source.second : source.first
        let placement = !firstPosition && secondPosition ? source.secondCoordinates : source.firstCoordinates
        let cells = try Cells(retaining: source.predicate.source, using: &a)
        let field = try cells.coefficientField(of: source.predicate.source, using: &a)
        let n = parameterOnly ? source.parameterCount : source.predicate.source.variableCount
        let weight = graph.predicate.source.polynomials[3]
        for term in weight.terms { for power in term.powers { try a.consumeWork(1); if power != 0 { return nil } } }
        try ExactGeometryAccess.storage(3, [Field.Value].self, &a)
        var xyz: [[Field.Value]] = []
        for i in 0..<3 {
            guard let row = try affineRow(graph.predicate.source.polynomials[i], count: n, placement: placement, field: field, &a) else { return nil }
            xyz.append(row)
        }
        let projected = relation.selection
        guard projected.cells.count <= limits.maximumStrata else { throw ExactGeometricRelationFailure.resultLimit }
        try ExactGeometryAccess.storage(projected.cells.count, ExactGeometricStratumRecord.self, &a)
        var records: [ExactGeometricStratumRecord] = []; records.reserveCapacity(projected.cells.count)
        var depth = relation.depth
        for i in projected.cells.indices {
            guard let parameterRows = try activeAffineRows(projected.cells[i], count: n, field: field, &a),
                let lifts = relation.projection.liftedCells(forProjectedOrdinal: i), !lifts.isEmpty else { return nil }
            if parameterOnly {
                let baseRank = try rank(parameterRows, count: n, field: field, depth: &depth, &a)
                guard n - baseRank == projected.cells[i].dimension else { return nil }
                try ExactGeometryAccess.storage(try ExactGeometryAccess.add(parameterRows.count, 3), [Field.Value].self, &a)
                var imageRows: [[Field.Value]] = []; imageRows.reserveCapacity(parameterRows.count + 3)
                for row in parameterRows { try a.consumeWork(1); imageRows.append(row) }
                for row in xyz { try a.consumeWork(1); imageRows.append(row) }
                let image = try rank(imageRows, count: n, field: field, depth: &depth, &a) - baseRank
                guard image >= 0, image <= projected.cells[i].dimension else { throw ExactGeometricRelationFailure.invalidSourceBinding }
                records.append(.init(ordinal: records.count, sourceComponentOrdinal: components[i], parameterDimension: projected.cells[i].dimension,
                    imageDimension: image, fiberDimension: projected.cells[i].dimension - image))
                continue
            }
            var image: Int? = nil
            for lift in lifts {
                guard let liftRows = try activeAffineRows(lift, count: n, field: field, &a) else { return nil }
                let capacity = try ExactGeometryAccess.add(parameterRows.count, liftRows.count)
                try ExactGeometryAccess.storage(try ExactGeometryAccess.add(capacity, max(source.parameterCount, 3)), [Field.Value].self, &a)
                var hull: [[Field.Value]] = []; hull.reserveCapacity(capacity + max(source.parameterCount, 3))
                for row in parameterRows { try a.consumeWork(1); hull.append(row) }
                for row in liftRows { try a.consumeWork(1); hull.append(row) }
                let baseRank = try rank(hull, count: n, field: field, depth: &depth, &a)
                for parameter in 0..<source.parameterCount {
                    try ExactGeometryAccess.storage(n, Field.Value.self, &a)
                    var row = Array(repeating: try field.integer(0, using: &a), count: n)
                    row[parameter] = try field.integer(1, using: &a); hull.append(row)
                }
                let parameterRank = try rank(hull, count: n, field: field, depth: &depth, &a) - baseRank
                guard parameterRank == projected.cells[i].dimension else { return nil }
                hull.removeLast(source.parameterCount)
                for row in xyz { try a.consumeWork(1); hull.append(row) }
                let imageRank = try rank(hull, count: n, field: field, depth: &depth, &a) - baseRank
                guard imageRank >= 0, imageRank <= parameterRank else { throw ExactGeometricRelationFailure.invalidSourceBinding }
                if let image { guard image == imageRank else { throw ExactGeometricRelationFailure.invalidCoverage } }
                image = imageRank
            }
            guard let image else { throw ExactGeometricRelationFailure.invalidCoverage }
            records.append(.init(ordinal: records.count, sourceComponentOrdinal: components[i], parameterDimension: projected.cells[i].dimension,
                imageDimension: image, fiberDimension: projected.cells[i].dimension - image))
        }
        return (records, depth)
    }
}
