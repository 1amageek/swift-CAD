import CADCore

/// Indexed minors retain the differential rank of the original equations, including multiplicities.
package struct ExactIntersectionJacobian: Sendable {
    package struct Minor: Sendable {
        package let rows: [Int]
        package let columns: [Int]
        package let polynomial: ExactIntersectionPolynomial
        package var order: Int { rows.count }
    }
    package let equations: [ExactIntersectionPolynomial]
    package let variableCount: Int
    package let entries: [[ExactIntersectionPolynomial]]
    package let minors: [Minor]

    private init(equations: [ExactIntersectionPolynomial], variableCount: Int,
        entries: [[ExactIntersectionPolynomial]], minors: [Minor]) {
        self.equations = equations; self.variableCount = variableCount
        self.entries = entries; self.minors = minors
    }

    package static func prepare<B: RationalAlgebraAdmitting>(equations: [ExactIntersectionPolynomial],
        variableCount: Int, usage: inout B) throws -> Self {
        guard (1...5).contains(variableCount) else {
            throw rationalAlgebraFailure("Original Jacobian requires a bound coordinate ring.")
        }
        try intersectionAlgebraStep(&usage)
        try RationalAlgebraStorage.retain(equations.count, of: [ExactIntersectionPolynomial].self, usage: &usage)
        let slots = try rationalAlgebraCount(equations.count, variableCount, multiply: true)
        try RationalAlgebraStorage.retain(slots, of: ExactIntersectionPolynomial.self, usage: &usage)
        var entries: [[ExactIntersectionPolynomial]] = []; entries.reserveCapacity(equations.count)
        for equation in equations {
            try intersectionAlgebraStep(&usage)
            guard equation.variableCount == variableCount else {
                throw rationalAlgebraFailure("Original Jacobian equations do not share their bound ring.")
            }
            var row: [ExactIntersectionPolynomial] = []; row.reserveCapacity(variableCount)
            for axis in 0..<variableCount { row.append(try equation.differentiated(at: axis, usage: &usage)) }
            entries.append(row)
        }
        var minors: [Minor] = []
        let maximumOrder = min(variableCount, equations.count)
        if maximumOrder > 0 {
            for order in 1...maximumOrder {
                let rows = try combinations(count: equations.count, order: order, usage: &usage)
                let columns = try combinations(count: variableCount, order: order, usage: &usage)
                for selectedRows in rows {
                    for selectedColumns in columns {
                        try intersectionAlgebraStep(&usage)
                        let size = try rationalAlgebraCount(order, order, multiply: true)
                        try RationalAlgebraStorage.retain(size, of: ExactIntersectionPolynomial.self, usage: &usage)
                        var matrix: [ExactIntersectionPolynomial] = []; matrix.reserveCapacity(size)
                        for row in selectedRows {
                            for column in selectedColumns {
                                try intersectionAlgebraStep(&usage)
                                matrix.append(entries[row][column])
                            }
                        }
                        let polynomial = try ExactIntersectionDeterminant.evaluate(&matrix, size: order,
                            variableCount: variableCount, usage: &usage)
                        try RationalAlgebraStorage.retain(1, of: Minor.self, usage: &usage)
                        minors.append(Minor(rows: selectedRows, columns: selectedColumns, polynomial: polynomial))
                    }
                }
            }
        }
        return Self(equations: equations, variableCount: variableCount, entries: entries, minors: minors)
    }

    private static func combinations<B: RationalAlgebraAdmitting>(count: Int, order: Int,
        usage: inout B) throws -> [[Int]] {
        guard order > 0, order <= count else {
            throw rationalAlgebraFailure("Original minor combinations require valid dimensions.")
        }
        try RationalAlgebraStorage.retain(order, of: Int.self, usage: &usage)
        var indices: [Int] = []; indices.reserveCapacity(order)
        for index in 0..<order { try intersectionAlgebraStep(&usage); indices.append(index) }
        var result: [[Int]] = []
        while true {
            try intersectionAlgebraStep(&usage)
            try RationalAlgebraStorage.retain(1, of: [Int].self, usage: &usage)
            try RationalAlgebraStorage.retain(order, of: Int.self, usage: &usage)
            result.append(indices)
            var position = order - 1
            while indices[position] == count - order + position {
                try intersectionAlgebraStep(&usage)
                if position == 0 { return result }
                position -= 1
            }
            indices[position] += 1
            for later in (position + 1)..<order {
                try intersectionAlgebraStep(&usage)
                indices[later] = indices[later - 1] + 1
            }
        }
    }
}
