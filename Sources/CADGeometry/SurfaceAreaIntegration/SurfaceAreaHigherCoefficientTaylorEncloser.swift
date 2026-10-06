import CADCore

/// Requested-order preparation of one existing original native coefficient receipt.
struct SurfaceAreaHigherCoefficientTaylorEncloser: Sendable {
    let receipt: SurfaceAreaOriginalCoefficientReceipt
    let order: Int
    private let nets: [[[[OutwardScalarInterval]]]]
    private let translation: SurfaceAreaOffsetTranslationAuthority?
    private let denominatorHull: OutwardScalarInterval

    init(receipt: SurfaceAreaOriginalCoefficientReceipt, order: Int,
         translation: SurfaceAreaOffsetTranslationAuthority? = nil,
         consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws {
        self.receipt = receipt; self.order = order; self.translation = translation
        if let translation {
            guard translation.source == receipt.source,
                  translation.direction == .v ? receipt.rowCount == 2 : receipt.columnCount == 2 else {
                throw Self.failure(.invalidInput,receipt.tolerance,"Translation requires its original native coefficient tensor.")
            }
        }
        let rows = translation?.direction == .v ? 1 : receipt.rowCount
        let columns = translation?.direction == .u ? 1 : receipt.columnCount
        let side = order.addingReportingOverflow(1)
        let pairs = side.partialValue.multipliedReportingOverflow(by:side.partialValue)
        guard order >= 0, !side.overflow, !pairs.overflow,
              receipt.rowCount > 0, receipt.columnCount > 0 else {
            throw Self.failure(.resourceLimitExceeded,receipt.tolerance,"Higher native jet dimensions overflow or are empty.")
        }
        try Self.charge(pairs.partialValue,4,tolerance:receipt.tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
        try OriginalCoefficientAllocation.reserve(count: 4, of: [[[OutwardScalarInterval]]].self, consumeStorage: consumeStorage)
        var table: [[[[OutwardScalarInterval]]]] = []
        table.reserveCapacity(4)
        for _ in 0..<4 {
            try OriginalCoefficientAllocation.reserve(count: pairs.partialValue, of: [[OutwardScalarInterval]].self, consumeStorage: consumeStorage)
            table.append(Array(repeating: [[OutwardScalarInterval]](), count: pairs.partialValue))
        }
        let uWidth = OutwardScalarInterval.exact(receipt.baseDomain.u.upper) - .exact(receipt.baseDomain.u.lower)
        let vWidth = OutwardScalarInterval.exact(receipt.baseDomain.v.upper) - .exact(receipt.baseDomain.v.lower)
        guard uWidth.isFinite, vWidth.isFinite, uWidth.lower > 0, vWidth.lower > 0 else {
            throw Self.failure(.singularSystem,receipt.tolerance,"Higher native jet requires positive original span widths.")
        }
        var weightLower = Double.infinity, weightUpper = -Double.infinity
        for axis in 0..<4 {
            try Self.charge(rows,columns,tolerance:receipt.tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
            try Self.charge(rows,1,tolerance:receipt.tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
            try OriginalCoefficientAllocation.reserve(count: rows, of: [OutwardScalarInterval].self, consumeStorage: consumeStorage)
            var original: [[OutwardScalarInterval]] = []
            original.reserveCapacity(rows)
            for row in 0..<rows {
                try OriginalCoefficientAllocation.reserve(count: columns, of: OutwardScalarInterval.self, consumeStorage: consumeStorage)
                var values: [OutwardScalarInterval] = []
                values.reserveCapacity(columns)
                for column in 0..<columns {
                    let value = try receipt.coefficient(row:row,column:column)
                    switch axis {
                    case 0: values.append(value.x)
                    case 1: values.append(value.y)
                    case 2: values.append(value.z)
                    default:
                        values.append(value.weight)
                        weightLower = min(weightLower,value.weight.lower)
                        weightUpper = max(weightUpper,value.weight.upper)
                    }
                }
                original.append(values)
            }
            table[axis][0] = original
            for u in 0...order where translation?.varyingAxis != .v || u == 0 {
                if u > 0 {
                    table[axis][u*side.partialValue] = try Self.differentiated(table[axis][(u-1)*side.partialValue],
                        alongU:true,width:uWidth,tolerance:receipt.tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
                }
                if order-u > 0 && translation?.varyingAxis != .u { for v in 1...(order-u) {
                    table[axis][u*side.partialValue+v] = try Self.differentiated(table[axis][u*side.partialValue+v-1],
                        alongU:false,width:vWidth,tolerance:receipt.tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
                } }
            }
        }
        nets = table
        denominatorHull = .init(lower:weightLower,upper:weightUpper)
    }

    /// The freshly issued query receipt owns lift and one-sided containment.
    func intervalTaylorJet(using query: SurfaceAreaOriginalCoefficientReceipt,
                           consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaIntervalTaylorVectorJet {
        guard query.source == receipt.source, query.tolerance == receipt.tolerance,
              query.uSpanIndex == receipt.uSpanIndex, query.vSpanIndex == receipt.vSpanIndex,
              query.baseDomain == receipt.baseDomain else {
            throw Self.failure(.invalidInput,query.tolerance,"Higher native jet requires the original prepared coefficient owner.")
        }
        let side = order+1
        let activeAxis = translation?.varyingAxis ?? .both
        let u = translation?.direction == .u ? .exact(0)
            : try Self.normalized(query.baseQuery.u,in:query.baseDomain.u,tolerance:query.tolerance)
        let v = translation?.direction == .v ? .exact(0)
            : try Self.normalized(query.baseQuery.v,in:query.baseDomain.v,tolerance:query.tolerance)
        try OriginalCoefficientAllocation.reserve(count: 4, of: SurfaceAreaIntervalTaylorScalarJet.self, consumeStorage: consumeStorage)
        var fields: [SurfaceAreaIntervalTaylorScalarJet] = []
        fields.reserveCapacity(4)
        for axis in 0..<4 {
            var jet = try SurfaceAreaIntervalTaylorScalarJet(order:order,axis:activeAxis,tolerance:query.tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
            for total in 0...order { for i in 0...total where activeAxis.permits(i,total-i) {
                let j = total-i
                var value: OutwardScalarInterval
                if axis == 3, let weight = query.commonWeight ?? (denominatorHull.lower == denominatorHull.upper ? denominatorHull.lower : nil) {
                    value = .exact(total == 0 ? weight : 0)
                } else {
                    value = try Self.evaluated(nets[axis][i*side+j],u:u,v:v,
                        tolerance:query.tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
                }
                // Divide by exact integer factors rather than rounded factorials.
                if i > 1 { for factor in 2...i {
                    try consumeWork()
                    guard let next = value.divided(by:.exact(Double(factor))) else {
                        throw Self.failure(.resourceLimitExceeded,query.tolerance,"Higher native factorial scaling exceeded finite arithmetic.")
                    }; value = next
                } }
                if j > 1 { for factor in 2...j {
                    try consumeWork()
                    guard let next = value.divided(by:.exact(Double(factor))) else {
                        throw Self.failure(.resourceLimitExceeded,query.tolerance,"Higher native factorial scaling exceeded finite arithmetic.")
                    }; value = next
                } }
                try jet.set(value,i,j)
            } }
            fields.append(jet)
        }
        // Bernstein convexity bounds the denominator by the retained original
        // coefficient hull; preparation already paid each coefficient access.
        guard let denominator = try fields[3].coefficient(0,0).intersection(with:denominatorHull) else {
            throw Self.failure(.intersectionFailure,query.tolerance,"Higher native denominator lost its positive original weight hull.")
        }
        try fields[3].set(denominator,0,0)
        let inverse = try fields[3].reciprocal(consumeWork:consumeWork,consumeStorage:consumeStorage)
        try OriginalCoefficientAllocation.reserve(count: 3, of: SurfaceAreaIntervalTaylorScalarJet.self, consumeStorage: consumeStorage)
        var result: [SurfaceAreaIntervalTaylorScalarJet] = []
        result.reserveCapacity(3)
        for axis in 0..<3 {
            let origin = axis == 0 ? query.origin.x : axis == 1 ? query.origin.y : query.origin.z
            let constant: Double?
            switch axis {
            case 0: constant = translation?.constantRailCoordinates.0
            case 1: constant = translation?.constantRailCoordinates.1
            default: constant = translation?.constantRailCoordinates.2
            }
            if let constant {
                result.append(try .constant(.exact(constant),order:order,axis:activeAxis,
                    tolerance:query.tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage))
                continue
            }
            var value = try fields[axis].multiplied(by:inverse,consumeWork:consumeWork,consumeStorage:consumeStorage)
            try value.set(value.coefficient(0,0) + .exact(origin),0,0)
            result.append(value)
        }
        return SurfaceAreaIntervalTaylorVectorJet(x:result[0],y:result[1],z:result[2])
    }

    private static func differentiated(_ net: [[OutwardScalarInterval]], alongU: Bool,
        width: OutwardScalarInterval, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> [[OutwardScalarInterval]] {
        let rows = net.count, columns = net.first?.count ?? 0
        let degree = (alongU ? columns : rows)-1
        guard degree >= 0 else { throw failure(.invalidInput,tolerance,"Higher native derivative net is empty.") }
        if degree == 0 {
            // Exact derivative of a constant homogeneous Bernstein polynomial.
            try consumeWork()
            try OriginalCoefficientAllocation.reserve(count: 1, of: [OutwardScalarInterval].self, consumeStorage: consumeStorage)
            try OriginalCoefficientAllocation.reserve(count: 1, of: OutwardScalarInterval.self, consumeStorage: consumeStorage)
            return [[.exact(0)]]
        }
        guard let scale = OutwardScalarInterval.exact(Double(degree)).divided(by:width) else {
            throw failure(.resourceLimitExceeded,tolerance,"Higher native derivative scale is nonfinite.")
        }
        let newRows = alongU ? rows : rows-1, newColumns = alongU ? columns-1 : columns
        try charge(newRows,newColumns,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
        try charge(newRows,1,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
        try OriginalCoefficientAllocation.reserve(count: newRows, of: [OutwardScalarInterval].self, consumeStorage: consumeStorage)
        var result: [[OutwardScalarInterval]] = []
        result.reserveCapacity(newRows)
        for row in 0..<newRows {
            try OriginalCoefficientAllocation.reserve(count: newColumns, of: OutwardScalarInterval.self, consumeStorage: consumeStorage)
            var values: [OutwardScalarInterval] = []
            values.reserveCapacity(newColumns)
            for column in 0..<newColumns {
                let difference = alongU ? net[row][column+1]-net[row][column] : net[row+1][column]-net[row][column]
                try consumeWork()
                let value = difference*scale
                guard value.isFinite else { throw failure(.resourceLimitExceeded,tolerance,"Higher native finite differences overflow.") }
                values.append(value)
            }
            result.append(values)
        }
        return result
    }

    private static func normalized(_ query: ScalarInterval,in domain: ScalarInterval,
                                   tolerance: ModelingTolerance) throws -> OutwardScalarInterval {
        let width = OutwardScalarInterval.exact(domain.upper) - .exact(domain.lower)
        func endpoint(_ value: Double) throws -> OutwardScalarInterval {
            if value == domain.lower { return .exact(0) }
            if value == domain.upper { return .exact(1) }
            guard let result = (OutwardScalarInterval.exact(value) - .exact(domain.lower)).divided(by:width) else {
                throw failure(.resourceLimitExceeded,tolerance,"Higher native parameter normalization is nonfinite.")
            }
            return result
        }
        let lower = try endpoint(query.lower), upper = try endpoint(query.upper)
        guard query.lower >= domain.lower, query.upper <= domain.upper else {
            throw failure(.invalidInput,tolerance,"Higher native query extends outside its original coefficient domain.")
        }
        return .init(lower:max(0,lower.lower),upper:min(1,upper.upper))
    }

    private static func evaluated(_ net: [[OutwardScalarInterval]],u: OutwardScalarInterval,
        v: OutwardScalarInterval,tolerance: ModelingTolerance,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> OutwardScalarInterval {
        guard let columns = net.first?.count, columns > 0, !net.isEmpty else {
            throw failure(.invalidInput,tolerance,"Higher native evaluation net is empty.")
        }
        try charge(net.count,1,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
        try OriginalCoefficientAllocation.reserve(count: net.count, of: [OutwardScalarInterval].self, consumeStorage: consumeStorage)
        var rows: [[OutwardScalarInterval]] = []
        rows.reserveCapacity(net.count)
        for row in net {
            guard row.count == columns else {
                throw failure(.invalidInput,tolerance,"Higher native evaluation net is not rectangular.")
            }
            rows.append(try restricted(row,to:u,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage))
        }
        let retainedColumns = rows[0].count
        var lower = Double.infinity, upper = -Double.infinity
        for column in 0..<retainedColumns {
            try charge(rows.count,1,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
            try OriginalCoefficientAllocation.reserve(count: rows.count, of: OutwardScalarInterval.self, consumeStorage: consumeStorage)
            var values: [OutwardScalarInterval] = []
            values.reserveCapacity(rows.count)
            for row in rows { values.append(row[column]) }
            let controls = try restricted(values,to:v,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
            for value in controls {
                try consumeWork()
                lower = min(lower,value.lower); upper = max(upper,value.upper)
            }
        }
        let result = OutwardScalarInterval(lower:lower,upper:upper)
        guard result.isFinite else { throw failure(.resourceLimitExceeded,tolerance,"Higher native evaluation exceeded finite arithmetic.") }
        return result
    }

    /// Bernstein restriction retains the complete polynomial range, rather than
    /// independently varying both weights of a whole-box affine blend.
    private static func restricted(_ input: [OutwardScalarInterval],to parameter: OutwardScalarInterval,
        tolerance: ModelingTolerance,consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> [OutwardScalarInterval] {
        guard !input.isEmpty, parameter.isFinite, parameter.lower >= 0, parameter.upper <= 1 else {
            throw failure(.invalidInput,tolerance,"Higher native restriction needs a normalized closed interval.")
        }
        if input.count == 1 || parameter.lower == 0 && parameter.upper == 1 { return input }
        func subdivision(_ controls: [OutwardScalarInterval],at t: OutwardScalarInterval,
                         retainingLeft: Bool) throws -> [OutwardScalarInterval] {
            // Mutating the COW source makes a scratch copy; output owns one
            // boundary coefficient at each triangle level. Both are admitted.
            try charge(controls.count,2,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
            try OriginalCoefficientAllocation.reserve(count: controls.count, of: OutwardScalarInterval.self, consumeStorage: consumeStorage)
            try OriginalCoefficientAllocation.reserve(count: controls.count, of: OutwardScalarInterval.self, consumeStorage: consumeStorage)
            var scratch = controls
            var output = Array(repeating:OutwardScalarInterval.exact(0),count:controls.count)
            let last = controls.count-1
            output[retainingLeft ? 0 : last] = scratch[retainingLeft ? 0 : last]
            for remaining in stride(from:last,through:1,by:-1) {
                for index in 0..<remaining {
                    try Task.checkCancellation(); try consumeWork()
                    scratch[index] = scratch[index]*(.exact(1)-t)+scratch[index+1]*t
                }
                output[retainingLeft ? controls.count-remaining : remaining-1]
                    = scratch[retainingLeft ? 0 : remaining-1]
            }
            return output
        }
        if parameter.lower == parameter.upper {
            let left = try subdivision(input,at:.exact(parameter.lower),retainingLeft:true)
            try consumeWork()
            try OriginalCoefficientAllocation.reserve(count: 1, of: OutwardScalarInterval.self, consumeStorage: consumeStorage)
            return [left[left.count-1]]
        }
        var result = input
        if parameter.upper < 1 {
            result = try subdivision(result,at:.exact(parameter.upper),retainingLeft:true)
        }
        if parameter.lower > 0 {
            guard let fraction = OutwardScalarInterval.exact(parameter.lower)
                .divided(by:.exact(parameter.upper)) else {
                throw failure(.resourceLimitExceeded,tolerance,"Higher native restriction fraction is nonfinite.")
            }
            result = try subdivision(result,at:fraction,retainingLeft:false)
        }
        return result
    }

    private static func charge(_ a: Int,_ b: Int,tolerance: ModelingTolerance,
                               consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws {
        let count = a.multipliedReportingOverflow(by:b)
        guard !count.overflow, count.partialValue >= 0 else {
            throw failure(.resourceLimitExceeded,tolerance,"Higher native payload count overflows.")
        }
        for _ in 0..<count.partialValue { try Task.checkCancellation(); try consumeWork() }
    }

    private static func failure(_ code: KernelErrorCode,_ tolerance: ModelingTolerance,_ message: String) -> KernelError {
        KernelError(phase:.geometry,code:code,tolerance:tolerance,message:message)
    }
}
