#if L1_ISOLATED_VERIFICATION
import L0
#endif

extension ExactPolynomialDomain {
    func productOrder<A: ExactScalarAdmission & ~Copyable>(_ a: ExactPolynomialProductIndex,
        _ b: ExactPolynomialProductIndex, rows: [ExactPolynomialTerm<Coefficient>],
        columns: [ExactPolynomialTerm<Coefficient>], _ usage: inout A
    ) throws -> Int {
        try usage.consumeWork(try ExactPolynomialAccess.count(variableCount, 1))
        // The per-axis maxima check precedes every heap operation, proving these sums fit.
        for axis in 0..<variableCount {
            let left = rows[a.row].powers[axis] + columns[a.column].powers[axis]
            let right = rows[b.row].powers[axis] + columns[b.column].powers[axis]
            if left != right { return left > right ? 1 : -1 }
        }
        return 0
    }
    func productPush<A: ExactScalarAdmission & ~Copyable>(_ node: ExactPolynomialProductIndex,
        rows: [ExactPolynomialTerm<Coefficient>], columns: [ExactPolynomialTerm<Coefficient>],
        heap: inout [ExactPolynomialProductIndex], cursors: inout [Int], chains: inout [Int],
        _ usage: inout A
    ) throws {
        try usage.consumeWork(1)
        cursors[node.row] = node.column; chains[node.row] = -1
        var destination = heap.count
        while destination > 0 {
            let parent = (destination - 1) / 2
            let order = try productOrder(heap[parent], node, rows: rows, columns: columns, &usage)
            if order == 0 {
                chains[node.row] = chains[heap[parent].row]; chains[heap[parent].row] = node.row
                return
            }
            if order > 0 { break }
            destination = parent
        }
        heap.append(node)
        var index = heap.count - 1
        while index > destination {
            try usage.consumeWork(1)
            let parent = (index - 1) / 2
            heap[index] = heap[parent]; index = parent
        }
        heap[destination] = node
    }
    func productPop<A: ExactScalarAdmission & ~Copyable>(rows: [ExactPolynomialTerm<Coefficient>],
        columns: [ExactPolynomialTerm<Coefficient>], heap: inout [ExactPolynomialProductIndex],
        _ usage: inout A
    ) throws -> ExactPolynomialProductIndex {
        try usage.consumeWork(1)
        let node = heap[0], last = heap.removeLast()
        if heap.isEmpty { return node }
        heap[0] = last
        var parent = 0
        while true {
            let child = try ExactPolynomialAccess.count(ExactPolynomialAccess.count(parent, parent), 1)
            if child >= heap.count { break }
            var greatest = child
            if child < heap.count - 1,
                try productOrder(heap[child + 1], heap[child], rows: rows, columns: columns, &usage) > 0 {
                greatest = child + 1
            }
            if try productOrder(heap[parent], heap[greatest], rows: rows, columns: columns, &usage) >= 0 { break }
            heap.swapAt(parent, greatest); parent = greatest
        }
        return node
    }
    func heapProduct<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Polynomial,
        _ rhs: borrowing Polynomial, _ usage: inout A
    ) throws -> Polynomial {
        let rows = lhs.termCount <= rhs.termCount ? lhs.terms : rhs.terms
        let columns = lhs.termCount <= rhs.termCount ? rhs.terms : lhs.terms
        try ExactPolynomialAccess.storage(ExactPolynomialAccess.count(variableCount, 2, multiply: true), Int.self, &usage)
        var rowMax = Array(repeating: 0, count: variableCount)
        var columnMax = Array(repeating: 0, count: variableCount)
        for term in rows {
            try usage.consumeWork(try ExactPolynomialAccess.count(variableCount, 1))
            for axis in 0..<variableCount { rowMax[axis] = max(rowMax[axis], term.powers[axis]) }
        }
        for term in columns {
            try usage.consumeWork(try ExactPolynomialAccess.count(variableCount, 1))
            for axis in 0..<variableCount { columnMax[axis] = max(columnMax[axis], term.powers[axis]) }
        }
        try usage.consumeWork(variableCount)
        for axis in 0..<variableCount { _ = try ExactPolynomialAccess.exponent(rowMax[axis], columnMax[axis]) }
        try ExactPolynomialAccess.storage(rows.count, ExactPolynomialProductIndex.self, &usage)
        var heap: [ExactPolynomialProductIndex] = []; heap.reserveCapacity(rows.count)
        try ExactPolynomialAccess.storage(ExactPolynomialAccess.count(rows.count, 2, multiply: true), Int.self, &usage)
        var cursors = Array(repeating: 0, count: rows.count), chains = Array(repeating: -1, count: rows.count)
        for row in rows.indices { try productPush(.init(row: row, column: 0), rows: rows,
            columns: columns, heap: &heap, cursors: &cursors, chains: &chains, &usage) }
        var result: [ExactPolynomialTerm<Coefficient>] = [], admittedCapacity = 0
        while !heap.isEmpty {
            let anchor = try productPop(rows: rows, columns: columns, heap: &heap, &usage)
            var sum = context.zero, firstProduct = true, head = anchor
            while true {
                var row = head.row
                while row >= 0 {
                    try usage.consumeWork(1)
                    let following = chains[row], column = cursors[row]
                    let product = try field.multiplying(rows[row].coefficient, columns[column].coefficient, using: &usage)
                    sum = try firstProduct ? product : field.adding(sum, product, using: &usage)
                    firstProduct = false
                    if column < columns.count - 1 { try productPush(.init(row: row, column: column + 1),
                        rows: rows, columns: columns, heap: &heap, cursors: &cursors, chains: &chains, &usage) }
                    row = following
                }
                guard let next = heap.first,
                    try productOrder(next, anchor, rows: rows, columns: columns, &usage) == 0 else { break }
                head = try productPop(rows: rows, columns: columns, heap: &heap, &usage)
            }
            if try field.sign(of: sum, using: &usage) == .zero { continue }
            if result.count == admittedCapacity {
                let next = admittedCapacity == 0 ? 1 : try ExactPolynomialAccess.count(admittedCapacity, admittedCapacity)
                // Cumulative storage admits the full new buffer, including copied retained slots.
                try ExactPolynomialAccess.storage(next, ExactPolynomialTerm<Coefficient>.self, &usage)
                result.reserveCapacity(next); admittedCapacity = next
            }
            var exponent = try powers(&usage)
            for axis in exponent.indices {
                exponent[axis] = rows[anchor.row].powers[axis] + columns[anchor.column].powers[axis]
            }
            result.append(.init(powers: exponent, coefficient: sum))
        }
        return try wrap(result, &usage)
    }
}
