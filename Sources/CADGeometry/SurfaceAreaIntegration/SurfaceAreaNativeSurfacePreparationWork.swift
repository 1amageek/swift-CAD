import CADCore

/// Precharges the existing original surface preparation graph before it allocates.
/// The quantity is scalar coefficient slots and scalar recurrence transitions,
/// separate from the public input control-point count and native phase charges.
struct SurfaceAreaNativeSurfacePreparationWork {
    static func admit(_ surface: BSplineSurface3D, tolerance: ModelingTolerance,
                      consumeWork: () throws -> Void) throws {
        func charge(_ a: Int, _ b: Int = 1) throws {
            let count = a.multipliedReportingOverflow(by:b)
            guard !count.overflow, count.partialValue >= 0 else {
                throw KernelError(phase:.geometry,code:.resourceLimitExceeded,tolerance:tolerance,
                    message:"Original native surface preparation storage or work overflows.")
            }
            for _ in 0..<count.partialValue { try Task.checkCancellation(); try consumeWork() }
        }
        let u = surface.uDegree.addingReportingOverflow(1)
        let v = surface.vDegree.addingReportingOverflow(1)
        guard !u.overflow, !v.overflow, u.partialValue > 0, v.partialValue > 0 else {
            throw KernelError(phase:.geometry,code:.resourceLimitExceeded,tolerance:tolerance,
                message:"Original native surface preparation degree overflows.")
        }
        let columns = u.partialValue, rows = v.partialValue
        func net(_ rows: Int, _ columns: Int) throws {
            try charge(rows,columns)
            for _ in 0..<4 { try charge(rows,columns) }
        }
        func thirdNets(_ rows: Int, _ columns: Int) throws {
            for total in 1...3 { for du in 0...total {
                let dv = total-du
                // The production derivative graph retains a single zero row or
                // column when finite-degree homogeneous derivatives vanish.
                let r = max(1,rows-dv), c = max(1,columns-du)
                try net(r,c)
            } }
        }
        func basis(degree: Int, span: Int, knots: [Double]) throws {
            try charge(degree+1)
            if degree > 0 { for p in 1...degree {
                try charge(degree+1,p+1)
                let start = span-p
                for offset in 0...p {
                    let i = start+offset
                    if knots[i+p] > knots[i] { try charge(p+1) }
                    if knots[i+p+1] > knots[i+1] { try charge(p+1) }
                }
            } }
            try charge(degree+1) // Returned derivative-row owners.
        }
        let single = !surface.isUPeriodic && !surface.isVPeriodic
            && surface.uControlPointCount == columns && surface.vControlPointCount == rows
            && surface.uKnots.prefix(columns).allSatisfy { $0 == surface.uKnots[surface.uDegree] }
            && surface.uKnots.suffix(columns).allSatisfy { $0 == surface.uKnots[surface.uControlPointCount] }
            && surface.vKnots.prefix(rows).allSatisfy { $0 == surface.vKnots[surface.vDegree] }
            && surface.vKnots.suffix(rows).allSatisfy { $0 == surface.vKnots[surface.vControlPointCount] }
        if single {
            try net(rows,columns)
            try thirdNets(rows,columns)
            // Existing single-patch polynomial-coordinate tightening can retain
            // up to one axis-coalesced net for each Cartesian coordinate. Charge
            // the concrete retained dimensions selected by its original tests.
            for coordinate in 0..<3 {
                func value(_ point: Point3D) -> Double {
                    switch coordinate { case 0: return point.x; case 1: return point.y; default: return point.z }
                }
                var allUnit = true, sameRows = true, constantRows = true
                var constantWeightRows = true, sameCoordinateRows = true
                for row in surface.controlPoints.indices { for column in surface.controlPoints[row].indices {
                    // Admit this classifier's five reads and the lower owner's
                    // five concrete predicate passes (early exits may use fewer).
                    // This bound follows the actual branch graph, not degree caps.
                    try charge(5)
                    try charge(5)
                    let weight = surface.weights[row][column]
                    allUnit = allUnit && weight == 1
                    sameRows = sameRows && weight == surface.weights[0][column]
                    constantRows = constantRows && value(surface.controlPoints[row][column]) == value(surface.controlPoints[row][0])
                    constantWeightRows = constantWeightRows && weight == surface.weights[row][0]
                    sameCoordinateRows = sameCoordinateRows && value(surface.controlPoints[row][column]) == value(surface.controlPoints[0][column])
                } }
                if allUnit { continue }
                let r: Int, c: Int
                if sameRows && constantRows { r = rows; c = 1 }
                else if constantWeightRows && sameCoordinateRows { r = 1; c = columns }
                else { continue }
                try charge(r,c) // Axis-coalesced point owners.
                try net(r,c)
                try thirdNets(r,c)
            }
            return
        }
        // Native span-index arrays and the original common-weight scan are
        // existing lower allocations/reads, admitted once for the whole source.
        try charge(surface.uControlPointCount-surface.uDegree)
        try charge(surface.vControlPointCount-surface.vDegree)
        try charge(surface.vControlPointCount,surface.uControlPointCount)
        for vi in surface.vDegree..<surface.vControlPointCount where surface.vKnots[vi] < surface.vKnots[vi+1] {
            for ui in surface.uDegree..<surface.uControlPointCount where surface.uKnots[ui] < surface.uKnots[ui+1] {
                try charge(1) // Retained original native patch owner.
                try basis(degree:surface.uDegree,span:ui,knots:surface.uKnots)
                try basis(degree:surface.vDegree,span:vi,knots:surface.vKnots)
                try net(rows,columns) // Homogeneous derivative matrix.
                for _ in 0..<rows { for _ in 0..<columns {
                    for _ in 0..<4 { try charge(rows,columns) }
                } }
                try net(rows,columns) // Copy-on-write Bernstein matrix.
                for j in 0..<rows { for i in 0..<columns {
                    for q in 0...j {
                        try charge(q)
                        for p in 0...i { try charge(p); try charge(4) }
                    }
                } }
                try thirdNets(rows,columns)
            }
        }
    }
}
