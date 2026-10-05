import CADCore

/// Source-shaped upper bounds prepaid before unchanged legacy coefficient algorithms.
struct NativeSurfaceEmbeddingPreparationReservation {
    static func product(_ factors: [Int]) throws -> Int {
        var result = 1
        for factor in factors {
            guard factor >= 0 else { throw GeometryConversionError.invalidInput("Native preparation shape cannot be negative.") }
            let next = result.multipliedReportingOverflow(by: factor)
            guard !next.overflow else { throw GeometryConversionError.resourceLimitExceeded("Native preparation shape overflows.") }
            result = next.partialValue
        }
        return result
    }
    static func sum(_ values: [Int]) throws -> Int {
        var result = 0
        for value in values {
            guard value >= 0 else { throw GeometryConversionError.invalidInput("Native preparation count cannot be negative.") }
            let next = result.addingReportingOverflow(value)
            guard !next.overflow else { throw GeometryConversionError.resourceLimitExceeded("Native preparation count overflows.") }
            result = next.partialValue
        }
        return result
    }
    static func net(_ rows: [[Point3D]], admission: NativeSurfaceEmbeddingAdmission) throws -> Int {
        try admission.work(rows.count)
        var count = 0
        for row in rows { count = try sum([count, row.count]) }
        return count
    }
    static func point(_ surface: BSplineSurface3D, admission: NativeSurfaceEmbeddingAdmission) throws {
        let u = surface.uControlPointCount, v = surface.vControlPointCount
        let p = surface.uDegree + 1, q = surface.vDegree + 1
        let basis = try sum([product([u, p, p]), product([v, q, q])])
        try admission.work(sum([basis, product([u, v]), surface.uKnots.count, surface.vKnots.count]))
        try admission.storage(sum([product([u, p]), product([v, q]), u, v]))
    }
    static func basis(degree: Int, order: Int, count: Int,
        admission: NativeSurfaceEmbeddingAdmission) throws {
        // The legacy full basis recursively lowers order, then scans every
        // control index once per remaining degree. Every materialized row is paid.
        let rows = try sum([degree, 1]), width = try sum([count, order])
        let visits = try product([rows, width])
        try admission.work(visits)
        try admission.storage(visits)
    }
    static func split(rows: Int, columns: Int, axisSplits: Int,
        admission: NativeSurfaceEmbeddingAdmission) throws {
        let n = try product([rows, columns])
        // A de Casteljau line retains every triangular level. Two U and two V
        // restrictions bound trimming and full quadrants, including transposes.
        let levels = try sum([product([rows, columns, try sum([columns, 1])]) / 2,
                              product([columns, rows, try sum([rows, 1])]) / 2])
        try admission.work(sum([product([n, 8]), product([levels, axisSplits])]))
        try admission.storage(sum([product([n, 24]), product([levels, axisSplits, 4])]))
    }
    static func differential(_ patch: RationalBezierSurfacePatch3D, phase: Int,
        admission: NativeSurfaceEmbeddingAdmission) throws {
        let rows = patch.controlPoints.count, columns = patch.controlPoints[0].count
        let n = try product([rows, columns])
        let doubledRows = try sum([product([rows - 1, 2]), 1])
        let doubledColumns = try sum([product([columns - 1, 2]), 1])
        let doubled = try product([doubledRows, doubledColumns])
        switch phase {
        case 0:
            // Initial unit-weight attempt: six scalar cross products, possible
            // repeated stationary-factor division and its raw weight scan.
            try admission.work(sum([product([n, n, 6, 49]), product([n, sum([rows, columns]), 8])]))
            try admission.storage(sum([product([n, 32]), product([doubled, 12])]))
        case 1:
            // Only the actual failed unit branch reaches rational differential
            // preparation; no successful fast branch pays this second reserve.
            try admission.work(sum([product([n, n, 6, 49]), product([doubled, doubled, 6, 49]), product([n, 64])]))
            try admission.storage(sum([product([n, 48]), product([doubled, 48])]))
        default:
            try admission.work(product([n, 12])); try admission.storage(product([n, 20]))
        }
    }
}
