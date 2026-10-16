import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

/// Factorial-scaled bivariate coefficients enclosing one entire original box.
package struct SurfaceAreaIntervalTaylorScalarJet: Sendable {
    enum Axis: Sendable, Equatable {
        case both, u, v
        func permits(_ u: Int,_ v: Int) -> Bool {
            self == .both || self == .u && v == 0 || self == .v && u == 0
        }
        func combined(with other: Self) -> Self { self == other ? self : .both }
    }
    package let order: Int
    let axis: Axis
    package let tolerance: ModelingTolerance
    private var coefficients: [OutwardScalarInterval]

    init<A: ExactScalarAdmission & ~Copyable>(order: Int, axis: Axis = .both, tolerance: ModelingTolerance, using execution: inout A) throws {
        let side = order.addingReportingOverflow(1)
        let count = side.partialValue.multipliedReportingOverflow(by:side.partialValue)
        guard order >= 0, !side.overflow, !count.overflow else {
            throw KernelError(phase:.geometry,code:.resourceLimitExceeded,tolerance:tolerance,
                message:"Interval Taylor coefficient dimensions overflow.")
        }
        self.order = order; self.axis = axis; self.tolerance = tolerance
        let slots = axis == .both ? count.partialValue : side.partialValue
        for _ in 0..<slots { try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1) }
        try OriginalCoefficientAllocation.reserve(count: slots, of: OutwardScalarInterval.self, using: &execution)
        coefficients = Array(repeating:.exact(0),count:slots)
    }

    private init(order: Int, axis: Axis, tolerance: ModelingTolerance,
        sharing coefficients: [OutwardScalarInterval]) {
        self.order = order; self.axis = axis; self.tolerance = tolerance
        self.coefficients = coefficients
    }

    /// Shares immutable coefficients while changing calculation metadata only.
    package func retagTolerance(to tolerance: ModelingTolerance) throws -> Self {
        try tolerance.validate()
        return .init(order: order, axis: axis, tolerance: tolerance, sharing: coefficients)
    }

    /// Admits the actual COW coefficient payload before changing a constant.
    package func replacingConstant<A: ExactScalarAdmission & ~Copyable>(_ value: OutwardScalarInterval,
        using execution: inout A) throws -> Self {
        for _ in coefficients { try execution.consumeWork(1) }
        try OriginalCoefficientAllocation.reserve(count: coefficients.count,
            of: OutwardScalarInterval.self, using: &execution)
        var result = self
        try result.set(value, 0, 0)
        return result
    }

    package func coefficient(_ u: Int,_ v: Int) throws -> OutwardScalarInterval {
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

    static func constant<A: ExactScalarAdmission & ~Copyable>(_ value: OutwardScalarInterval, order: Int, axis: Axis = .both,
                         tolerance: ModelingTolerance, using execution: inout A) throws -> Self {
        var result = try Self(order:order,axis:axis,tolerance:tolerance,using: &execution)
        try execution.consumeWork(1)
        try result.set(value,0,0)
        return result
    }

    func adding<A: ExactScalarAdmission & ~Copyable>(_ other: Self, using execution: inout A) throws -> Self {
        try validate(other)
        var result = try Self(order:order,axis:axis.combined(with:other.axis),tolerance:tolerance,using: &execution)
        for total in 0...order { for u in 0...total where result.axis.permits(u,total-u) {
            let v = total-u
            try execution.consumeWork(1)
            try result.set(coefficient(u,v)+other.coefficient(u,v),u,v)
        } }
        return result
    }

    func subtracting<A: ExactScalarAdmission & ~Copyable>(_ other: Self, using execution: inout A) throws -> Self {
        try adding(other.scaled(by:.exact(-1),using: &execution),using: &execution)
    }

    func scaled<A: ExactScalarAdmission & ~Copyable>(by scale: OutwardScalarInterval, using execution: inout A) throws -> Self {
        var result = try Self(order:order,axis:axis,tolerance:tolerance,using: &execution)
        for total in 0...order { for u in 0...total where result.axis.permits(u,total-u) {
            let v = total-u
            try execution.consumeWork(1)
            try result.set(coefficient(u,v)*scale,u,v)
        } }
        return result
    }

    func multiplied<A: ExactScalarAdmission & ~Copyable>(by other: Self, using execution: inout A) throws -> Self {
        try validate(other)
        var result = try Self(order:order,axis:axis.combined(with:other.axis),tolerance:tolerance,using: &execution)
        for total in 0...order { for u in 0...total where result.axis.permits(u,total-u) {
            try CurrentTaskCancellationChecker().checkCancellation()
            let v = total-u
            var value = OutwardScalarInterval.exact(0)
            for i in 0...u { for j in 0...v {
                try execution.consumeWork(1)
                value = try value+coefficient(i,j)*other.coefficient(u-i,v-j)
            } }
            try result.set(value,u,v)
        } }
        return result
    }

    func reciprocal<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> Self {
        guard let value = try OutwardScalarInterval.exact(1).divided(by:coefficient(0,0)) else {
            throw failure(.singularSystem,"Interval Taylor reciprocal denominator contains zero.")
        }
        var result = try Self(order:order,axis:axis,tolerance:tolerance,using: &execution)
        try execution.consumeWork(1)
        try result.set(value,0,0)
        if order > 0 { for total in 1...order { for u in 0...total where result.axis.permits(u,total-u) {
            try CurrentTaskCancellationChecker().checkCancellation()
            let v = total-u
            var sum = OutwardScalarInterval.exact(0)
            for i in 0...u { for j in 0...v where i != 0 || j != 0 {
                try execution.consumeWork(1)
                sum = try sum+coefficient(i,j)*result.coefficient(u-i,v-j)
            } }
            try result.set(-sum*value,u,v)
        } } }
        return result
    }

    func squareRoot<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> Self {
        let base = try coefficient(0,0)
        guard base.isFinite, base.lower > 0 else {
            throw failure(.singularSystem,"Interval Taylor square root has no certified positive value.")
        }
        let root = OutwardScalarInterval(lower:sqrt(base.lower).nextDown,upper:sqrt(base.upper).nextUp)
        guard let divisor = OutwardScalarInterval.exact(1).divided(by:root * .exact(2)) else {
            throw failure(.singularSystem,"Interval Taylor square root divisor contains zero.")
        }
        var result = try Self(order:order,axis:axis,tolerance:tolerance,using: &execution)
        try execution.consumeWork(1)
        try result.set(root,0,0)
        if order > 0 { for total in 1...order { for u in 0...total where result.axis.permits(u,total-u) {
            try CurrentTaskCancellationChecker().checkCancellation()
            let v = total-u
            var sum = OutwardScalarInterval.exact(0)
            for i in 0...u { for j in 0...v
                where (i != 0 || j != 0) && (i != u || j != v) {
                try execution.consumeWork(1)
                sum = try sum+result.coefficient(i,j)*result.coefficient(u-i,v-j)
            } }
            try result.set((coefficient(u,v)-sum)*divisor,u,v)
        } } }
        return result
    }

    func truncated<A: ExactScalarAdmission & ~Copyable>(to requested: Int, using execution: inout A) throws -> Self {
        guard requested >= 0, requested <= order else { throw invalidIndex() }
        var result = try Self(order:requested,axis:axis,tolerance:tolerance,using: &execution)
        for total in 0...requested { for u in 0...total where result.axis.permits(u,total-u) {
            let v = total-u
            try execution.consumeWork(1)
            try result.set(coefficient(u,v),u,v)
        } }
        return result
    }

    func differentiated<A: ExactScalarAdmission & ~Copyable>(alongU: Bool, using execution: inout A) throws -> Self {
        guard order > 0 else { throw invalidIndex() }
        var result = try Self(order:order-1,axis:axis,tolerance:tolerance,using: &execution)
        for total in 0..<order { for u in 0...total where result.axis.permits(u,total-u) {
            let v = total-u
            try execution.consumeWork(1)
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
