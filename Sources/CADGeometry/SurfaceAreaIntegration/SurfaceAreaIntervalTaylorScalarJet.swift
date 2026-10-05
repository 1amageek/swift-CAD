import CADCore
import Foundation

/// Factorial-scaled bivariate coefficients enclosing one entire original box.
struct SurfaceAreaIntervalTaylorScalarJet: Sendable {
    enum Axis: Sendable, Equatable {
        case both, u, v
        func permits(_ u: Int,_ v: Int) -> Bool {
            self == .both || self == .u && v == 0 || self == .v && u == 0
        }
        func combined(with other: Self) -> Self { self == other ? self : .both }
    }
    let order: Int
    let axis: Axis
    let tolerance: ModelingTolerance
    private var coefficients: [OutwardScalarInterval]

    init(order: Int, axis: Axis = .both, tolerance: ModelingTolerance, consumeWork: () throws -> Void) throws {
        let side = order.addingReportingOverflow(1)
        let count = side.partialValue.multipliedReportingOverflow(by:side.partialValue)
        guard order >= 0, !side.overflow, !count.overflow else {
            throw KernelError(phase:.geometry,code:.resourceLimitExceeded,tolerance:tolerance,
                message:"Interval Taylor coefficient dimensions overflow.")
        }
        self.order = order; self.axis = axis; self.tolerance = tolerance
        let slots = axis == .both ? count.partialValue : side.partialValue
        for _ in 0..<slots { try Task.checkCancellation(); try consumeWork() }
        coefficients = Array(repeating:.exact(0),count:slots)
    }

    func coefficient(_ u: Int,_ v: Int) throws -> OutwardScalarInterval {
        guard u >= 0, v >= 0, u <= order, v <= order-u else { throw invalidIndex() }
        guard axis.permits(u,v) else { return .exact(0) }
        return coefficients[axis == .both ? u*(order+1)+v : (axis == .u ? u : v)]
    }

    mutating func set(_ value: OutwardScalarInterval,_ u: Int,_ v: Int) throws {
        guard u >= 0, v >= 0, u <= order, v <= order-u else { throw invalidIndex() }
        guard value.isFinite else { throw failure(.resourceLimitExceeded,"Interval Taylor coefficient is nonfinite.") }
        guard axis.permits(u,v) else {
            guard value.lower == 0, value.upper == 0 else { throw invalidIndex() }
            return
        }
        coefficients[axis == .both ? u*(order+1)+v : (axis == .u ? u : v)] = value
    }

    static func constant(_ value: OutwardScalarInterval, order: Int, axis: Axis = .both,
                         tolerance: ModelingTolerance, consumeWork: () throws -> Void) throws -> Self {
        var result = try Self(order:order,axis:axis,tolerance:tolerance,consumeWork:consumeWork)
        try consumeWork()
        try result.set(value,0,0)
        return result
    }

    func adding(_ other: Self, consumeWork: () throws -> Void) throws -> Self {
        try validate(other)
        var result = try Self(order:order,axis:axis.combined(with:other.axis),tolerance:tolerance,consumeWork:consumeWork)
        for total in 0...order { for u in 0...total where result.axis.permits(u,total-u) {
            let v = total-u
            try consumeWork()
            try result.set(coefficient(u,v)+other.coefficient(u,v),u,v)
        } }
        return result
    }

    func subtracting(_ other: Self, consumeWork: () throws -> Void) throws -> Self {
        try adding(other.scaled(by:.exact(-1),consumeWork:consumeWork),consumeWork:consumeWork)
    }

    func scaled(by scale: OutwardScalarInterval, consumeWork: () throws -> Void) throws -> Self {
        var result = try Self(order:order,axis:axis,tolerance:tolerance,consumeWork:consumeWork)
        for total in 0...order { for u in 0...total where result.axis.permits(u,total-u) {
            let v = total-u
            try consumeWork()
            try result.set(coefficient(u,v)*scale,u,v)
        } }
        return result
    }

    func multiplied(by other: Self, consumeWork: () throws -> Void) throws -> Self {
        try validate(other)
        var result = try Self(order:order,axis:axis.combined(with:other.axis),tolerance:tolerance,consumeWork:consumeWork)
        for total in 0...order { for u in 0...total where result.axis.permits(u,total-u) {
            try Task.checkCancellation()
            let v = total-u
            var value = OutwardScalarInterval.exact(0)
            for i in 0...u { for j in 0...v {
                try consumeWork()
                value = try value+coefficient(i,j)*other.coefficient(u-i,v-j)
            } }
            try result.set(value,u,v)
        } }
        return result
    }

    func reciprocal(consumeWork: () throws -> Void) throws -> Self {
        guard let value = try OutwardScalarInterval.exact(1).divided(by:coefficient(0,0)) else {
            throw failure(.singularSystem,"Interval Taylor reciprocal denominator contains zero.")
        }
        var result = try Self(order:order,axis:axis,tolerance:tolerance,consumeWork:consumeWork)
        try consumeWork()
        try result.set(value,0,0)
        if order > 0 { for total in 1...order { for u in 0...total where result.axis.permits(u,total-u) {
            try Task.checkCancellation()
            let v = total-u
            var sum = OutwardScalarInterval.exact(0)
            for i in 0...u { for j in 0...v where i != 0 || j != 0 {
                try consumeWork()
                sum = try sum+coefficient(i,j)*result.coefficient(u-i,v-j)
            } }
            try result.set(-sum*value,u,v)
        } } }
        return result
    }

    func squareRoot(consumeWork: () throws -> Void) throws -> Self {
        let base = try coefficient(0,0)
        guard base.isFinite, base.lower > 0 else {
            throw failure(.singularSystem,"Interval Taylor square root has no certified positive value.")
        }
        let root = OutwardScalarInterval(lower:sqrt(base.lower).nextDown,upper:sqrt(base.upper).nextUp)
        guard let divisor = OutwardScalarInterval.exact(1).divided(by:root * .exact(2)) else {
            throw failure(.singularSystem,"Interval Taylor square root divisor contains zero.")
        }
        var result = try Self(order:order,axis:axis,tolerance:tolerance,consumeWork:consumeWork)
        try consumeWork()
        try result.set(root,0,0)
        if order > 0 { for total in 1...order { for u in 0...total where result.axis.permits(u,total-u) {
            try Task.checkCancellation()
            let v = total-u
            var sum = OutwardScalarInterval.exact(0)
            for i in 0...u { for j in 0...v
                where (i != 0 || j != 0) && (i != u || j != v) {
                try consumeWork()
                sum = try sum+result.coefficient(i,j)*result.coefficient(u-i,v-j)
            } }
            try result.set((coefficient(u,v)-sum)*divisor,u,v)
        } } }
        return result
    }

    func truncated(to requested: Int, consumeWork: () throws -> Void) throws -> Self {
        guard requested >= 0, requested <= order else { throw invalidIndex() }
        var result = try Self(order:requested,axis:axis,tolerance:tolerance,consumeWork:consumeWork)
        for total in 0...requested { for u in 0...total where result.axis.permits(u,total-u) {
            let v = total-u
            try consumeWork()
            try result.set(coefficient(u,v),u,v)
        } }
        return result
    }

    func differentiated(alongU: Bool, consumeWork: () throws -> Void) throws -> Self {
        guard order > 0 else { throw invalidIndex() }
        var result = try Self(order:order-1,axis:axis,tolerance:tolerance,consumeWork:consumeWork)
        for total in 0..<order { for u in 0...total where result.axis.permits(u,total-u) {
            let v = total-u
            try consumeWork()
            let value = try alongU ? coefficient(u+1,v) * .exact(Double(u+1))
                : coefficient(u,v+1) * .exact(Double(v+1))
            try result.set(value,u,v)
        } }
        return result
    }

    private func validate(_ other: Self) throws {
        guard order == other.order, tolerance == other.tolerance else {
            throw failure(.invalidInput,"Interval Taylor arithmetic requires one source order and tolerance.")
        }
    }

    private func invalidIndex() -> KernelError {
        failure(.invalidInput,"Interval Taylor operation requested an unavailable coefficient or order.")
    }

    private func failure(_ code: KernelErrorCode,_ message: String) -> KernelError {
        KernelError(phase:.geometry,code:code,tolerance:tolerance,message:message)
    }
}
