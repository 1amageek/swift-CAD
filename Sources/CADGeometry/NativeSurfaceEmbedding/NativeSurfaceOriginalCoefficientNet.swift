import CADCore

/// Original homogeneous Bernstein cover restricted with outward exact-real stations.
struct NativeSurfaceOriginalCoefficientNet: Sendable {
    let controls: [[IntervalHomogeneousSurfaceControl]]
    let workingDomain: SurfaceParameterBox

    init<A: ExactScalarAdmission & ~Copyable>(chart: NativeSurfaceOriginalCellChart, over working: SurfaceParameterBox,
        using execution: inout A) throws {
        let box = try chart.nativeBox(over: working)
        let receipt = try chart.law.native.originalCoefficientReceipt(overClosedBox: box,
            on: chart.law.source, tolerance: chart.law.tolerance, using: &execution)
        let count = try NativeSurfaceEmbeddingPreparationReservation.product([receipt.rowCount, receipt.columnCount])
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: IntervalHomogeneousSurfaceControl.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: receipt.rowCount, of: [IntervalHomogeneousSurfaceControl].self))
        var net: [[IntervalHomogeneousSurfaceControl]] = []
        net.reserveCapacity(receipt.rowCount)
        for row in 0..<receipt.rowCount {
            var values: [IntervalHomogeneousSurfaceControl] = []
            values.reserveCapacity(receipt.columnCount)
            for column in 0..<receipt.columnCount {
                try execution.consumeWork(1)
                let value = try receipt.coefficient(row: row, column: column)
                // Receipt XYZ is relative to its original source origin.
                values.append(.init(x: value.x + .exact(receipt.origin.x) * value.weight,
                    y: value.y + .exact(receipt.origin.y) * value.weight,
                    z: value.z + .exact(receipt.origin.z) * value.weight, weight: value.weight))
            }
            net.append(values)
        }
        func fraction(_ query: Double, _ domain: ScalarInterval) throws -> OutwardScalarInterval {
            if query == domain.lower { return .exact(0) }
            if query == domain.upper { return .exact(1) }
            guard let value = (OutwardScalarInterval.exact(query) - .exact(domain.lower))
                .divided(by: .exact(domain.upper) - .exact(domain.lower)), value.isFinite else {
                throw GeometryConversionError.resourceLimitExceeded("Original Bernstein restriction has no finite native fraction.")
            }
            return .init(lower: max(0, value.lower), upper: min(1, value.upper))
        }
        let u0 = try fraction(receipt.baseQuery.u.lower, receipt.baseDomain.u)
        let u1 = try fraction(receipt.baseQuery.u.upper, receipt.baseDomain.u)
        let v0 = try fraction(receipt.baseQuery.v.lower, receipt.baseDomain.v)
        let v1 = try fraction(receipt.baseQuery.v.upper, receipt.baseDomain.v)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: receipt.rowCount, of: [IntervalHomogeneousSurfaceControl].self))
        net = try net.map { try Self.restrict($0, from: u0, to: u1, using: &execution) }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: IntervalHomogeneousSurfaceControl.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: receipt.columnCount, of: [IntervalHomogeneousSurfaceControl].self))
        var transposed: [[IntervalHomogeneousSurfaceControl]] = []
        transposed.reserveCapacity(receipt.columnCount)
        for column in 0..<receipt.columnCount {
            var values: [IntervalHomogeneousSurfaceControl] = []
            values.reserveCapacity(receipt.rowCount)
            for row in 0..<receipt.rowCount { try execution.consumeWork(1); values.append(net[row][column]) }
            transposed.append(try Self.restrict(values, from: v0, to: v1, using: &execution))
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: IntervalHomogeneousSurfaceControl.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: receipt.rowCount, of: [IntervalHomogeneousSurfaceControl].self))
        var result: [[IntervalHomogeneousSurfaceControl]] = []
        result.reserveCapacity(receipt.rowCount)
        for row in 0..<receipt.rowCount {
            var values: [IntervalHomogeneousSurfaceControl] = []
            values.reserveCapacity(receipt.columnCount)
            for column in 0..<receipt.columnCount { try execution.consumeWork(1); values.append(transposed[column][row]) }
            result.append(values)
        }
        if chart.swapsAxes {
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: IntervalHomogeneousSurfaceControl.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: receipt.columnCount, of: [IntervalHomogeneousSurfaceControl].self))
            result = try (0..<receipt.columnCount).map { column in
                try (0..<receipt.rowCount).map { row in try execution.consumeWork(1); return result[row][column] }
            }
        }
        if chart.reversesU {
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: IntervalHomogeneousSurfaceControl.self))
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: result.count, of: [IntervalHomogeneousSurfaceControl].self))
            result = try result.map { row in try execution.consumeWork(row.count); return Array(row.reversed()) }
        }
        if chart.reversesV {
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: result.count, of: [IntervalHomogeneousSurfaceControl].self)); try execution.consumeWork(result.count)
            result = Array(result.reversed())
        }
        controls = result; workingDomain = working
    }

    private static func restrict<A: ExactScalarAdmission & ~Copyable>(_ original: [IntervalHomogeneousSurfaceControl],
        from lower: OutwardScalarInterval, to upper: OutwardScalarInterval,
        using execution: inout A) throws -> [IntervalHomogeneousSurfaceControl] {
        if lower.lower == 0, lower.upper == 0, upper.lower == 1, upper.upper == 1 { return original }
        let tail: [IntervalHomogeneousSurfaceControl]
        if lower.lower == 0, lower.upper == 0 { tail = original }
        else { tail = try split(original, at: lower, using: &execution).1 }
        if upper.lower == 1, upper.upper == 1 { return tail }
        guard let fraction = (upper - lower).divided(by: .exact(1) - lower), fraction.isFinite else {
            throw GeometryConversionError.resourceLimitExceeded("Original Bernstein closed restriction has an unresolved positive tail.")
        }
        return try split(tail, at: .init(lower: max(0, fraction.lower), upper: min(1, fraction.upper)), using: &execution).0
    }

    private static func split<A: ExactScalarAdmission & ~Copyable>(_ original: [IntervalHomogeneousSurfaceControl],
        at station: OutwardScalarInterval, using execution: inout A) throws
        -> ([IntervalHomogeneousSurfaceControl], [IntervalHomogeneousSurfaceControl]) {
        guard !original.isEmpty, station.lower >= 0, station.upper <= 1 else {
            throw GeometryConversionError.invalidInput("Original Bernstein split needs a closed original unit station.")
        }
        let count = original.count
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: try exactScalarCount(count, 2, multiply: true), of: IntervalHomogeneousSurfaceControl.self))
        var level = original
        var first: [IntervalHomogeneousSurfaceControl] = [], last: [IntervalHomogeneousSurfaceControl] = []
        first.reserveCapacity(count); last.reserveCapacity(count)
        first.append(original[0]); last.append(original[count - 1])
        while level.count > 1 {
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: level.count - 1, of: IntervalHomogeneousSurfaceControl.self))
            var next: [IntervalHomogeneousSurfaceControl] = []
            next.reserveCapacity(level.count - 1)
            for index in 0..<(level.count - 1) {
                try execution.consumeWork(1)
                let a = level[index].scaled(by: .exact(1) - station), b = level[index + 1].scaled(by: station)
                next.append(.init(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z, weight: a.weight + b.weight))
            }
            first.append(next[0]); last.append(next[next.count - 1]); level = next
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: IntervalHomogeneousSurfaceControl.self))
        return (first, Array(last.reversed()))
    }
}
