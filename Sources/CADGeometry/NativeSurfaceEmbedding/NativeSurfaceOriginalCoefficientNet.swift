import CADCore

/// Original homogeneous Bernstein cover restricted with outward exact-real stations.
struct NativeSurfaceOriginalCoefficientNet: Sendable {
    let controls: [[IntervalHomogeneousSurfaceControl]]
    let workingDomain: SurfaceParameterBox

    init(chart: NativeSurfaceOriginalCellChart, over working: SurfaceParameterBox,
        admission: NativeSurfaceEmbeddingAdmission) throws {
        let box = try chart.nativeBox(over: working)
        let receipt = try chart.law.native.originalCoefficientReceipt(overClosedBox: box,
            on: chart.law.source, tolerance: chart.law.tolerance, consumeWork: { try admission.work(1) })
        let count = try NativeSurfaceEmbeddingPreparationReservation.product([receipt.rowCount, receipt.columnCount])
        try admission.storage(NativeSurfaceEmbeddingPreparationReservation.sum([count, receipt.rowCount]))
        var net: [[IntervalHomogeneousSurfaceControl]] = []
        net.reserveCapacity(receipt.rowCount)
        for row in 0..<receipt.rowCount {
            var values: [IntervalHomogeneousSurfaceControl] = []
            values.reserveCapacity(receipt.columnCount)
            for column in 0..<receipt.columnCount {
                try admission.work(1)
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
        try admission.storage(receipt.rowCount)
        net = try net.map { try Self.restrict($0, from: u0, to: u1, admission: admission) }
        try admission.storage(NativeSurfaceEmbeddingPreparationReservation.sum([count, receipt.columnCount]))
        var transposed: [[IntervalHomogeneousSurfaceControl]] = []
        for column in 0..<receipt.columnCount {
            var values: [IntervalHomogeneousSurfaceControl] = []
            values.reserveCapacity(receipt.rowCount)
            for row in 0..<receipt.rowCount { try admission.work(1); values.append(net[row][column]) }
            transposed.append(try Self.restrict(values, from: v0, to: v1, admission: admission))
        }
        try admission.storage(NativeSurfaceEmbeddingPreparationReservation.sum([count, receipt.rowCount]))
        var result: [[IntervalHomogeneousSurfaceControl]] = []
        for row in 0..<receipt.rowCount {
            var values: [IntervalHomogeneousSurfaceControl] = []
            values.reserveCapacity(receipt.columnCount)
            for column in 0..<receipt.columnCount { try admission.work(1); values.append(transposed[column][row]) }
            result.append(values)
        }
        if chart.swapsAxes {
            try admission.storage(NativeSurfaceEmbeddingPreparationReservation.sum([count, receipt.columnCount]))
            result = try (0..<receipt.columnCount).map { column in
                try (0..<receipt.rowCount).map { row in try admission.work(1); return result[row][column] }
            }
        }
        if chart.reversesU {
            try admission.storage(NativeSurfaceEmbeddingPreparationReservation.sum([count, result.count]))
            result = try result.map { row in try admission.work(row.count); return Array(row.reversed()) }
        }
        if chart.reversesV {
            try admission.storage(result.count); try admission.work(result.count)
            result = Array(result.reversed())
        }
        controls = result; workingDomain = working
    }

    private static func restrict(_ original: [IntervalHomogeneousSurfaceControl],
        from lower: OutwardScalarInterval, to upper: OutwardScalarInterval,
        admission: NativeSurfaceEmbeddingAdmission) throws -> [IntervalHomogeneousSurfaceControl] {
        if lower.lower == 0, lower.upper == 0, upper.lower == 1, upper.upper == 1 { return original }
        let tail: [IntervalHomogeneousSurfaceControl]
        if lower.lower == 0, lower.upper == 0 { tail = original }
        else { tail = try split(original, at: lower, admission: admission).1 }
        if upper.lower == 1, upper.upper == 1 { return tail }
        guard let fraction = (upper - lower).divided(by: .exact(1) - lower), fraction.isFinite else {
            throw GeometryConversionError.resourceLimitExceeded("Original Bernstein closed restriction has an unresolved positive tail.")
        }
        return try split(tail, at: .init(lower: max(0, fraction.lower), upper: min(1, fraction.upper)), admission: admission).0
    }

    private static func split(_ original: [IntervalHomogeneousSurfaceControl],
        at station: OutwardScalarInterval, admission: NativeSurfaceEmbeddingAdmission) throws
        -> ([IntervalHomogeneousSurfaceControl], [IntervalHomogeneousSurfaceControl]) {
        guard !original.isEmpty, station.lower >= 0, station.upper <= 1 else {
            throw GeometryConversionError.invalidInput("Original Bernstein split needs a closed original unit station.")
        }
        let count = original.count
        try admission.storage(NativeSurfaceEmbeddingPreparationReservation.product([count, 3]))
        var level = original, first = [original[0]], last = [original[count - 1]]
        first.reserveCapacity(count); last.reserveCapacity(count)
        while level.count > 1 {
            try admission.storage(level.count - 1)
            var next: [IntervalHomogeneousSurfaceControl] = []
            next.reserveCapacity(level.count - 1)
            for index in 0..<(level.count - 1) {
                try admission.work(1)
                let a = level[index].scaled(by: .exact(1) - station), b = level[index + 1].scaled(by: station)
                next.append(.init(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z, weight: a.weight + b.weight))
            }
            first.append(next[0]); last.append(next[next.count - 1]); level = next
        }
        try admission.storage(count)
        return (first, Array(last.reversed()))
    }
}
