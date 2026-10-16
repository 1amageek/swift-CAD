import CADCore
import Synchronization
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

private enum SurfaceTaylorJetError: Error, Sendable {
    case invalidOrder(Int)
    case invalidCoefficientIndex(uOrder: Int, vOrder: Int, order: Int)
    case incompatibleOrders(first: Int, second: Int)
}

/// Shared snapshots use one synchronized buffer owner on every target. A scalar
/// writer first detaches shared storage, so copied jet values retain value semantics.
private final class SurfaceTaylorCoefficientStorage: Sendable {
    let values: Mutex<[Double]>
    init(_ values: [Double]) { self.values = Mutex(values) }
}

/// A finite bivariate Taylor expansion whose coefficients include factorial scaling.
///
/// The coefficient at `(uOrder, vOrder)` is the corresponding parameter
/// derivative divided by `uOrder! * vOrder!`. This representation makes product
/// and quotient composition exact up to the requested total order.
struct SurfaceTaylorScalarJet: Sendable {
    let order: Int
    private var storage: SurfaceTaylorCoefficientStorage

    static func + (lhs: SurfaceTaylorScalarJet, rhs: SurfaceTaylorScalarJet) throws -> SurfaceTaylorScalarJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try lhs.adding(rhs, using: &execution)
    }
    static func - (lhs: SurfaceTaylorScalarJet, rhs: SurfaceTaylorScalarJet) throws -> SurfaceTaylorScalarJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try lhs.subtracting(rhs, using: &execution)
    }
    static prefix func - (value: SurfaceTaylorScalarJet) throws -> SurfaceTaylorScalarJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try value.negated(using: &execution)
    }
    static func * (lhs: SurfaceTaylorScalarJet, rhs: SurfaceTaylorScalarJet) throws -> SurfaceTaylorScalarJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try lhs.multiplying(rhs, using: &execution)
    }
    init(order: Int, repeating value: Double = 0.0) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(order: order, repeating: value, using: &execution)
    }

    mutating func setCoefficient(
        _ value: Double,
        uOrder: Int,
        vOrder: Int
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try setCoefficient(value, uOrder: uOrder, vOrder: vOrder, using: &execution)
    }

    static func constant(
        _ value: Double,
        order: Int
    ) throws -> SurfaceTaylorScalarJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try constant(value, order: order, using: &execution)
    }

    static func parameterU(
        _ value: Double,
        order: Int
    ) throws -> SurfaceTaylorScalarJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameterU(value, order: order, using: &execution)
    }

    static func parameterV(
        _ value: Double,
        order: Int
    ) throws -> SurfaceTaylorScalarJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameterV(value, order: order, using: &execution)
    }

    static func sineOfParameterU(
        _ value: Double,
        order: Int
    ) throws -> SurfaceTaylorScalarJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try sineOfParameterU(value, order: order, using: &execution)
    }

    static func cosineOfParameterU(
        _ value: Double,
        order: Int
    ) throws -> SurfaceTaylorScalarJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try cosineOfParameterU(value, order: order, using: &execution)
    }

    static func sineOfParameterV(
        _ value: Double,
        order: Int
    ) throws -> SurfaceTaylorScalarJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try sineOfParameterV(value, order: order, using: &execution)
    }

    static func cosineOfParameterV(
        _ value: Double,
        order: Int
    ) throws -> SurfaceTaylorScalarJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try cosineOfParameterV(value, order: order, using: &execution)
    }











    func reciprocal(tolerance: ModelingTolerance) throws -> SurfaceTaylorScalarJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try reciprocal(tolerance: tolerance, using: &execution)
    }

    func squareRoot(tolerance: ModelingTolerance) throws -> SurfaceTaylorScalarJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try squareRoot(tolerance: tolerance, using: &execution)
    }

    func truncated(to requestedOrder: Int) throws -> SurfaceTaylorScalarJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try truncated(to: requestedOrder, using: &execution)
    }

    func partialU() throws -> SurfaceTaylorScalarJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try partialU(using: &execution)
    }

    func partialV() throws -> SurfaceTaylorScalarJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try partialV(using: &execution)
    }
    init<A: ExactScalarAdmission & ~Copyable>(order: Int, repeating value: Double = 0.0, using execution: inout A) throws {
        guard order >= 0, order <= 16 else {
            throw SurfaceTaylorJetError.invalidOrder(order)
        }
        try execution.consumeWork(1)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: (order + 1) * (order + 1), of: Double.self))
        self.order = order
        try execution.retainStorage(bytes: MemoryLayout<Mutex<[Double]>>.stride)
        storage = SurfaceTaylorCoefficientStorage(Array(
            repeating: value,
            count: (order + 1) * (order + 1)
        ))
    }

    subscript(uOrder: Int, vOrder: Int) -> Double {
        get {
            guard uOrder >= 0,
                  vOrder >= 0,
                  uOrder + vOrder <= order else {
                return 0.0
            }
            return storage.values.withLock { $0[uOrder * (order + 1) + vOrder] }
        }
    }

    mutating func setCoefficient<A: ExactScalarAdmission & ~Copyable>(
        _ value: Double,
        uOrder: Int,
        vOrder: Int
    , using execution: inout A) throws {
        guard uOrder >= 0,
              vOrder >= 0,
              uOrder + vOrder <= order else {
            throw SurfaceTaylorJetError.invalidCoefficientIndex(
                uOrder: uOrder,
                vOrder: vOrder,
                order: order
            )
        }
        try execution.consumeWork(1)
        if !isKnownUniquelyReferenced(&storage) {
            let count = storage.values.withLock { $0.count }
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Double.self))
            try execution.retainStorage(bytes: MemoryLayout<Mutex<[Double]>>.stride)
            let snapshot = storage.values.withLock { $0 }
            storage = SurfaceTaylorCoefficientStorage(snapshot)
        }
        storage.values.withLock { $0[uOrder * (order + 1) + vOrder] = value }
    }

    var value: Double {
        self[0, 0]
    }

    static func constant<A: ExactScalarAdmission & ~Copyable>(
        _ value: Double,
        order: Int
    , using execution: inout A) throws -> SurfaceTaylorScalarJet {
        var result = try SurfaceTaylorScalarJet(order: order, using: &execution)
        try result.setCoefficient(value, uOrder: 0, vOrder: 0, using: &execution)
        return result
    }

    static func parameterU<A: ExactScalarAdmission & ~Copyable>(
        _ value: Double,
        order: Int
    , using execution: inout A) throws -> SurfaceTaylorScalarJet {
        var result = try constant(value, order: order, using: &execution)
        if order > 0 {
            try result.setCoefficient(1.0, uOrder: 1, vOrder: 0, using: &execution)
        }
        return result
    }

    static func parameterV<A: ExactScalarAdmission & ~Copyable>(
        _ value: Double,
        order: Int
    , using execution: inout A) throws -> SurfaceTaylorScalarJet {
        var result = try constant(value, order: order, using: &execution)
        if order > 0 {
            try result.setCoefficient(1.0, uOrder: 0, vOrder: 1, using: &execution)
        }
        return result
    }

    static func sineOfParameterU<A: ExactScalarAdmission & ~Copyable>(
        _ value: Double,
        order: Int
    , using execution: inout A) throws -> SurfaceTaylorScalarJet {
        try parameterTrigonometricJet(value: value, order: order, sine: true, alongU: true, using: &execution)
    }

    static func cosineOfParameterU<A: ExactScalarAdmission & ~Copyable>(
        _ value: Double,
        order: Int
    , using execution: inout A) throws -> SurfaceTaylorScalarJet {
        try parameterTrigonometricJet(value: value, order: order, sine: false, alongU: true, using: &execution)
    }

    static func sineOfParameterV<A: ExactScalarAdmission & ~Copyable>(
        _ value: Double,
        order: Int
    , using execution: inout A) throws -> SurfaceTaylorScalarJet {
        try parameterTrigonometricJet(value: value, order: order, sine: true, alongU: false, using: &execution)
    }

    static func cosineOfParameterV<A: ExactScalarAdmission & ~Copyable>(
        _ value: Double,
        order: Int
    , using execution: inout A) throws -> SurfaceTaylorScalarJet {
        try parameterTrigonometricJet(value: value, order: order, sine: false, alongU: false, using: &execution)
    }

    func adding<A: ExactScalarAdmission & ~Copyable>(
        _ rhs: SurfaceTaylorScalarJet
    , using execution: inout A) throws -> SurfaceTaylorScalarJet {
        guard self.order == rhs.order else {
            throw SurfaceTaylorJetError.incompatibleOrders(
                first: self.order,
                second: rhs.order
            )
        }
        var result = try SurfaceTaylorScalarJet(order: self.order, using: &execution)
        for totalOrder in 0...self.order {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                try result.setCoefficient(
                    self[uOrder, vOrder] + rhs[uOrder, vOrder],
                    uOrder: uOrder,
                    vOrder: vOrder
                , using: &execution)
            }
        }
        return result
    }

    func subtracting<A: ExactScalarAdmission & ~Copyable>(_ rhs: SurfaceTaylorScalarJet, using execution: inout A) throws -> SurfaceTaylorScalarJet {
        let negative = try rhs.negated(using: &execution)
        return try adding(negative, using: &execution)
    }

    func dividing<A: ExactScalarAdmission & ~Copyable>(_ rhs: SurfaceTaylorScalarJet, tolerance: ModelingTolerance, using execution: inout A) throws -> SurfaceTaylorScalarJet {
        let inverse = try rhs.reciprocal(tolerance: tolerance, using: &execution)
        return try multiplying(inverse, using: &execution)
    }

    func negated<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> SurfaceTaylorScalarJet {
        var result = try SurfaceTaylorScalarJet(order: order, using: &execution)
        for totalOrder in 0...order {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                try result.setCoefficient(
                    -self[uOrder, vOrder],
                    uOrder: uOrder,
                    vOrder: vOrder
                , using: &execution)
            }
        }
        return result
    }

    func multiplying<A: ExactScalarAdmission & ~Copyable>(
        _ rhs: SurfaceTaylorScalarJet
    , using execution: inout A) throws -> SurfaceTaylorScalarJet {
        guard self.order == rhs.order else {
            throw SurfaceTaylorJetError.incompatibleOrders(
                first: self.order,
                second: rhs.order
            )
        }
        var result = try SurfaceTaylorScalarJet(order: self.order, using: &execution)
        for totalOrder in 0...self.order {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                var coefficient = 0.0
                for lhsUOrder in 0...uOrder {
                    for lhsVOrder in 0...vOrder {
                        try execution.consumeWork(1)
                        coefficient += self[lhsUOrder, lhsVOrder]
                            * rhs[uOrder - lhsUOrder, vOrder - lhsVOrder]
                    }
                }
                try result.setCoefficient(
                    coefficient,
                    uOrder: uOrder,
                    vOrder: vOrder
                , using: &execution)
            }
        }
        return result
    }

    func reciprocal<A: ExactScalarAdmission & ~Copyable>(tolerance: ModelingTolerance, using execution: inout A) throws -> SurfaceTaylorScalarJet {
        guard value.isFinite, abs(value) > Double.ulpOfOne else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: value,
                tolerance: tolerance,
                message: "A procedural surface Taylor quotient has a singular denominator."
            )
        }
        var result = try SurfaceTaylorScalarJet(order: order, using: &execution)
        try result.setCoefficient(1.0 / value, uOrder: 0, vOrder: 0, using: &execution)
        if order > 0 {
            for totalOrder in 1...order {
                for uOrder in 0...totalOrder {
                    let vOrder = totalOrder - uOrder
                    var accumulated = 0.0
                    for sourceUOrder in 0...uOrder {
                        for sourceVOrder in 0...vOrder {
                        try execution.consumeWork(1)
                            guard sourceUOrder + sourceVOrder > 0 else {
                                continue
                            }
                            accumulated += self[sourceUOrder, sourceVOrder]
                                * result[
                                    uOrder - sourceUOrder,
                                    vOrder - sourceVOrder
                                ]
                        }
                    }
                    try result.setCoefficient(
                        -accumulated / value,
                        uOrder: uOrder,
                        vOrder: vOrder
                    , using: &execution)
                }
            }
        }
        return result
    }

    func squareRoot<A: ExactScalarAdmission & ~Copyable>(tolerance: ModelingTolerance, using execution: inout A) throws -> SurfaceTaylorScalarJet {
        guard value.isFinite, value > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: value,
                tolerance: tolerance,
                message: "A procedural surface normal requires a positive finite squared magnitude."
            )
        }
        let root = sqrt(value)
        guard root.isFinite, root > Double.ulpOfOne else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: root,
                tolerance: tolerance,
                message: "A procedural surface normal is singular at the requested parameter."
            )
        }
        var result = try SurfaceTaylorScalarJet(order: order, using: &execution)
        try result.setCoefficient(root, uOrder: 0, vOrder: 0, using: &execution)
        if order > 0 {
            for totalOrder in 1...order {
                for uOrder in 0...totalOrder {
                    let vOrder = totalOrder - uOrder
                    var nonlinearTerms = 0.0
                    for leftUOrder in 0...uOrder {
                        for leftVOrder in 0...vOrder {
                        try execution.consumeWork(1)
                            let rightUOrder = uOrder - leftUOrder
                            let rightVOrder = vOrder - leftVOrder
                            let leftIsConstant = leftUOrder == 0 && leftVOrder == 0
                            let rightIsConstant = rightUOrder == 0 && rightVOrder == 0
                            guard !leftIsConstant, !rightIsConstant else {
                                continue
                            }
                            nonlinearTerms += result[leftUOrder, leftVOrder]
                                * result[rightUOrder, rightVOrder]
                        }
                    }
                    try result.setCoefficient(
                        (self[uOrder, vOrder] - nonlinearTerms) / (2.0 * root),
                        uOrder: uOrder,
                        vOrder: vOrder
                    , using: &execution)
                }
            }
        }
        return result
    }

    func truncated<A: ExactScalarAdmission & ~Copyable>(to requestedOrder: Int, using execution: inout A) throws -> SurfaceTaylorScalarJet {
        guard requestedOrder >= 0, requestedOrder <= order else {
            throw SurfaceTaylorJetError.invalidOrder(requestedOrder)
        }
        var result = try SurfaceTaylorScalarJet(order: requestedOrder, using: &execution)
        for totalOrder in 0...requestedOrder {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                try result.setCoefficient(
                    self[uOrder, vOrder],
                    uOrder: uOrder,
                    vOrder: vOrder
                , using: &execution)
            }
        }
        return result
    }

    func partialU<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> SurfaceTaylorScalarJet {
        guard order > 0 else {
            throw SurfaceTaylorJetError.invalidOrder(order - 1)
        }
        var result = try SurfaceTaylorScalarJet(order: order - 1, using: &execution)
        for totalOrder in 0..<order {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                try result.setCoefficient(
                    Double(uOrder + 1) * self[uOrder + 1, vOrder],
                    uOrder: uOrder,
                    vOrder: vOrder
                , using: &execution)
            }
        }
        return result
    }

    func partialV<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> SurfaceTaylorScalarJet {
        guard order > 0 else {
            throw SurfaceTaylorJetError.invalidOrder(order - 1)
        }
        var result = try SurfaceTaylorScalarJet(order: order - 1, using: &execution)
        for totalOrder in 0..<order {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                try result.setCoefficient(
                    Double(vOrder + 1) * self[uOrder, vOrder + 1],
                    uOrder: uOrder,
                    vOrder: vOrder
                , using: &execution)
            }
        }
        return result
    }

    private static func parameterTrigonometricJet<A: ExactScalarAdmission & ~Copyable>(
        value: Double,
        order: Int,
        sine: Bool,
        alongU: Bool
    , using execution: inout A) throws -> SurfaceTaylorScalarJet {
        var result = try SurfaceTaylorScalarJet(order: order, using: &execution)
        for derivativeOrder in 0...order {
            let phase = value + Double(derivativeOrder) * Double.pi * 0.5
            let derivative = sine ? sin(phase) : cos(phase)
            let coefficient = derivative / Double(surfaceFactorial(derivativeOrder))
            if alongU {
                try result.setCoefficient(
                    coefficient,
                    uOrder: derivativeOrder,
                    vOrder: 0
                , using: &execution)
            } else {
                try result.setCoefficient(
                    coefficient,
                    uOrder: 0,
                    vOrder: derivativeOrder
                , using: &execution)
            }
        }
        return result
    }
}

struct SurfaceTaylorVectorJet: Sendable {
    let x: SurfaceTaylorScalarJet
    let y: SurfaceTaylorScalarJet
    let z: SurfaceTaylorScalarJet

    static func + (lhs: SurfaceTaylorVectorJet, rhs: SurfaceTaylorVectorJet) throws -> SurfaceTaylorVectorJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try lhs.adding(rhs, using: &execution)
    }
    static func - (lhs: SurfaceTaylorVectorJet, rhs: SurfaceTaylorVectorJet) throws -> SurfaceTaylorVectorJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try lhs.subtracting(rhs, using: &execution)
    }
    static prefix func - (value: SurfaceTaylorVectorJet) throws -> SurfaceTaylorVectorJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try value.negated(using: &execution)
    }
    static func * (lhs: SurfaceTaylorVectorJet, rhs: SurfaceTaylorScalarJet) throws -> SurfaceTaylorVectorJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try lhs.multiplying(rhs, using: &execution)
    }
    static func constant(
        _ point: Point3D,
        order: Int
    ) throws -> SurfaceTaylorVectorJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try constant(point, order: order, using: &execution)
    }

    static func constant(
        _ vector: Vector3D,
        order: Int
    ) throws -> SurfaceTaylorVectorJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try constant(vector, order: order, using: &execution)
    }











    func dot(_ other: SurfaceTaylorVectorJet) throws -> SurfaceTaylorScalarJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try dot(other, using: &execution)
    }

    func cross(_ other: SurfaceTaylorVectorJet) throws -> SurfaceTaylorVectorJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try cross(other, using: &execution)
    }

    func normalized(tolerance: ModelingTolerance) throws -> SurfaceTaylorVectorJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try normalized(tolerance: tolerance, using: &execution)
    }

    func truncated(to requestedOrder: Int) throws -> SurfaceTaylorVectorJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try truncated(to: requestedOrder, using: &execution)
    }

    func partialU() throws -> SurfaceTaylorVectorJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try partialU(using: &execution)
    }

    func partialV() throws -> SurfaceTaylorVectorJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try partialV(using: &execution)
    }
    init(
        x: SurfaceTaylorScalarJet,
        y: SurfaceTaylorScalarJet,
        z: SurfaceTaylorScalarJet
    ) throws {
        guard x.order == y.order, y.order == z.order else {
            throw SurfaceTaylorJetError.incompatibleOrders(
                first: x.order,
                second: min(y.order, z.order)
            )
        }
        self.x = x
        self.y = y
        self.z = z
    }

    var order: Int {
        x.order
    }

    var value: Vector3D {
        Vector3D(x: x.value, y: y.value, z: z.value)
    }

    static func constant<A: ExactScalarAdmission & ~Copyable>(
        _ point: Point3D,
        order: Int
    , using execution: inout A) throws -> SurfaceTaylorVectorJet {
        try SurfaceTaylorVectorJet(
            x: .constant(point.x, order: order, using: &execution),
            y: .constant(point.y, order: order, using: &execution),
            z: .constant(point.z, order: order, using: &execution)
        )
    }

    static func constant<A: ExactScalarAdmission & ~Copyable>(
        _ vector: Vector3D,
        order: Int
    , using execution: inout A) throws -> SurfaceTaylorVectorJet {
        try SurfaceTaylorVectorJet(
            x: .constant(vector.x, order: order, using: &execution),
            y: .constant(vector.y, order: order, using: &execution),
            z: .constant(vector.z, order: order, using: &execution)
        )
    }

    func adding<A: ExactScalarAdmission & ~Copyable>(_ rhs: SurfaceTaylorVectorJet, using execution: inout A) throws -> SurfaceTaylorVectorJet {
        try SurfaceTaylorVectorJet(x: x.adding(rhs.x, using: &execution),
            y: y.adding(rhs.y, using: &execution), z: z.adding(rhs.z, using: &execution))
    }

    func subtracting<A: ExactScalarAdmission & ~Copyable>(_ rhs: SurfaceTaylorVectorJet, using execution: inout A) throws -> SurfaceTaylorVectorJet {
        let negative = try rhs.negated(using: &execution)
        return try adding(negative, using: &execution)
    }

    func negated<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> SurfaceTaylorVectorJet {
        try SurfaceTaylorVectorJet(x: x.negated(using: &execution),
            y: y.negated(using: &execution), z: z.negated(using: &execution))
    }

    func multiplying<A: ExactScalarAdmission & ~Copyable>(_ rhs: SurfaceTaylorScalarJet, using execution: inout A) throws -> SurfaceTaylorVectorJet {
        try SurfaceTaylorVectorJet(x: x.multiplying(rhs, using: &execution),
            y: y.multiplying(rhs, using: &execution), z: z.multiplying(rhs, using: &execution))
    }

    func dividing<A: ExactScalarAdmission & ~Copyable>(_ rhs: SurfaceTaylorScalarJet, tolerance: ModelingTolerance, using execution: inout A) throws -> SurfaceTaylorVectorJet {
        let inverse = try rhs.reciprocal(tolerance: tolerance, using: &execution)
        return try multiplying(inverse, using: &execution)
    }

    func dot<A: ExactScalarAdmission & ~Copyable>(_ other: SurfaceTaylorVectorJet, using execution: inout A) throws -> SurfaceTaylorScalarJet {
        let first = try x.multiplying(other.x, using: &execution)
        let second = try y.multiplying(other.y, using: &execution)
        let sum = try first.adding(second, using: &execution)
        let third = try z.multiplying(other.z, using: &execution)
        return try sum.adding(third, using: &execution)
    }

    func cross<A: ExactScalarAdmission & ~Copyable>(_ other: SurfaceTaylorVectorJet, using execution: inout A) throws -> SurfaceTaylorVectorJet {
        let firstX = try y.multiplying(other.z, using: &execution)
        let secondX = try z.multiplying(other.y, using: &execution)
        let resultX = try firstX.subtracting(secondX, using: &execution)
        let firstY = try z.multiplying(other.x, using: &execution)
        let secondY = try x.multiplying(other.z, using: &execution)
        let resultY = try firstY.subtracting(secondY, using: &execution)
        let firstZ = try x.multiplying(other.y, using: &execution)
        let secondZ = try y.multiplying(other.x, using: &execution)
        let resultZ = try firstZ.subtracting(secondZ, using: &execution)
        return try SurfaceTaylorVectorJet(x: resultX, y: resultY, z: resultZ)
    }

    func normalized<A: ExactScalarAdmission & ~Copyable>(tolerance: ModelingTolerance, using execution: inout A) throws -> SurfaceTaylorVectorJet {
        let squaredLength = try dot(self, using: &execution)
        let length = try squaredLength.squareRoot(tolerance: tolerance, using: &execution)
        let reciprocalLength = try length.reciprocal(tolerance: tolerance, using: &execution)
        return try multiplying(reciprocalLength, using: &execution)
    }

    func truncated<A: ExactScalarAdmission & ~Copyable>(to requestedOrder: Int, using execution: inout A) throws -> SurfaceTaylorVectorJet {
        try SurfaceTaylorVectorJet(
            x: x.truncated(to: requestedOrder, using: &execution),
            y: y.truncated(to: requestedOrder, using: &execution),
            z: z.truncated(to: requestedOrder, using: &execution)
        )
    }

    func partialU<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> SurfaceTaylorVectorJet {
        try SurfaceTaylorVectorJet(
            x: x.partialU(using: &execution),
            y: y.partialU(using: &execution),
            z: z.partialU(using: &execution)
        )
    }

    func partialV<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> SurfaceTaylorVectorJet {
        try SurfaceTaylorVectorJet(
            x: x.partialV(using: &execution),
            y: y.partialV(using: &execution),
            z: z.partialV(using: &execution)
        )
    }

    func derivative(uOrder: Int, vOrder: Int) -> Vector3D {
        let scale = Double(surfaceFactorial(uOrder) * surfaceFactorial(vOrder))
        return Vector3D(
            x: x[uOrder, vOrder] * scale,
            y: y[uOrder, vOrder] * scale,
            z: z[uOrder, vOrder] * scale
        )
    }
}

extension Surface3D {
    func taylorJet(u: Double, v: Double, throughOrder order: Int,
        tolerance: ModelingTolerance) throws -> SurfaceTaylorVectorJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try taylorJet(u: u, v: v, throughOrder: order, tolerance: tolerance, using: &execution)
    }

    func taylorJet(
        u: Double,
        v: Double,
        throughOrder order: Int,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceTaylorVectorJet {
        try execution.consumeWork(1)
        guard order >= 0, order <= 16 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: Double(order),
                tolerance: tolerance,
                message: "Surface Taylor evaluation supports total derivative order zero through sixteen."
            )
        }
        try validate(tolerance: tolerance, using: &execution)
        guard try uDomain.contains(u, tolerance: tolerance),
              try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        switch self {
        case let .plane(plane):
            let basis = try plane.parameterBasis(tolerance: tolerance)
            let origin = try SurfaceTaylorVectorJet.constant(plane.origin, order: order, using: &execution)
            let uDirection = try SurfaceTaylorVectorJet.constant(basis.u, order: order, using: &execution)
            let vDirection = try SurfaceTaylorVectorJet.constant(basis.v, order: order, using: &execution)
            let parameterU = try SurfaceTaylorScalarJet.parameterU(u, order: order, using: &execution)
            let parameterV = try SurfaceTaylorScalarJet.parameterV(v, order: order, using: &execution)
            return try origin.adding(uDirection.multiplying(parameterU, using: &execution), using: &execution).adding(vDirection.multiplying(parameterV, using: &execution), using: &execution)
        case let .cylinder(cylinder):
            let basis = try circleOrthonormalBasis(
                cylinder.axis,
                tolerance: tolerance
            )
            let uDirection = try SurfaceTaylorVectorJet.constant(basis.u, order: order, using: &execution)
            let vDirection = try SurfaceTaylorVectorJet.constant(basis.v, order: order, using: &execution)
            let cosineU = try SurfaceTaylorScalarJet.cosineOfParameterU(u, order: order, using: &execution)
            let sineU = try SurfaceTaylorScalarJet.sineOfParameterU(u, order: order, using: &execution)
            let radial = try uDirection.multiplying(cosineU, using: &execution).adding(vDirection.multiplying(sineU, using: &execution), using: &execution)
            let origin = try SurfaceTaylorVectorJet.constant(cylinder.origin, order: order, using: &execution)
            let radius = try SurfaceTaylorScalarJet.constant(cylinder.radius, order: order, using: &execution)
            let axis = try SurfaceTaylorVectorJet.constant(cylinder.axis, order: order, using: &execution)
            let parameterV = try SurfaceTaylorScalarJet.parameterV(v, order: order, using: &execution)
            return try origin.adding(radial.multiplying(radius, using: &execution), using: &execution).adding(axis.multiplying(parameterV, using: &execution), using: &execution)
        case let .analytic(surface):
            return try surface.taylorJet(
                u: u,
                v: v,
                throughOrder: order,
                tolerance: tolerance
            , using: &execution)
        case let .bSpline(surface):
            return try surface.taylorJet(
                u: u,
                v: v,
                throughOrder: order,
                tolerance: tolerance
            , using: &execution)
        case let .procedural(surface):
            return try surface.taylorJet(
                u: u,
                v: v,
                throughOrder: order,
                tolerance: tolerance
            , using: &execution)
        }
    }
}

private extension AnalyticSurface3D {
    func taylorJet(
        u: Double,
        v: Double,
        throughOrder order: Int,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceTaylorVectorJet {
        try execution.consumeWork(1)
        let parameterU = try SurfaceTaylorScalarJet.parameterU(u, order: order, using: &execution)
        let parameterV = try SurfaceTaylorScalarJet.parameterV(v, order: order, using: &execution)
        let sineU = try SurfaceTaylorScalarJet.sineOfParameterU(u, order: order, using: &execution)
        let cosineU = try SurfaceTaylorScalarJet.cosineOfParameterU(u, order: order, using: &execution)
        let sineV = try SurfaceTaylorScalarJet.sineOfParameterV(v, order: order, using: &execution)
        let cosineV = try SurfaceTaylorScalarJet.cosineOfParameterV(v, order: order, using: &execution)
        switch self {
        case let .plane(origin, normal):
            let basis = try OriginalStoredPlaneBasis.basis(normal,tolerance:tolerance)
            let originJet = try SurfaceTaylorVectorJet.constant(origin, order: order, using: &execution)
            let uDirection = try SurfaceTaylorVectorJet.constant(basis.u, order: order, using: &execution)
            let vDirection = try SurfaceTaylorVectorJet.constant(basis.v, order: order, using: &execution)
            return try originJet.adding(uDirection.multiplying(parameterU, using: &execution), using: &execution).adding(vDirection.multiplying(parameterV, using: &execution), using: &execution)
        case let .cylinder(origin, axis, radius):
            let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
            let uDirection = try SurfaceTaylorVectorJet.constant(basis.u, order: order, using: &execution)
            let vDirection = try SurfaceTaylorVectorJet.constant(basis.v, order: order, using: &execution)
            let radial = try uDirection.multiplying(cosineU, using: &execution).adding(vDirection.multiplying(sineU, using: &execution), using: &execution)
            let originJet = try SurfaceTaylorVectorJet.constant(origin, order: order, using: &execution)
            let radiusJet = try SurfaceTaylorScalarJet.constant(radius, order: order, using: &execution)
            let axisJet = try SurfaceTaylorVectorJet.constant(axis, order: order, using: &execution)
            return try originJet.adding(radial.multiplying(radiusJet, using: &execution), using: &execution).adding(axisJet.multiplying(parameterV, using: &execution), using: &execution)
        case let .cone(apex, axis, halfAngle):
            let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
            let uDirection = try SurfaceTaylorVectorJet.constant(basis.u, order: order, using: &execution)
            let vDirection = try SurfaceTaylorVectorJet.constant(basis.v, order: order, using: &execution)
            let radial = try uDirection.multiplying(cosineU, using: &execution).adding(vDirection.multiplying(sineU, using: &execution), using: &execution)
            let apexJet = try SurfaceTaylorVectorJet.constant(apex, order: order, using: &execution)
            let axisJet = try SurfaceTaylorVectorJet.constant(axis, order: order, using: &execution)
            let axialScale = try parameterV.multiplying(SurfaceTaylorScalarJet.constant(cos(halfAngle), order: order, using: &execution), using: &execution)
            let radialScale = try parameterV.multiplying(SurfaceTaylorScalarJet.constant(sin(halfAngle), order: order, using: &execution), using: &execution)
            return try apexJet.adding(axisJet.multiplying(axialScale, using: &execution), using: &execution).adding(radial.multiplying(radialScale, using: &execution), using: &execution)
        case let .sphere(center, radius):
            let basis = try analyticOrthonormalBasis(.unitZ, tolerance: tolerance)
            let uDirection = try SurfaceTaylorVectorJet.constant(basis.u, order: order, using: &execution)
            let vDirection = try SurfaceTaylorVectorJet.constant(basis.v, order: order, using: &execution)
            let sphereCosineU = try CanonicalSphereAngularPhase.candidateTaylor(at: u, alongU: true, cosine: true, order: order, using: &execution)
            let sphereSineU = try CanonicalSphereAngularPhase.candidateTaylor(at: u, alongU: true, cosine: false, order: order, using: &execution)
            let sphereCosineV = try CanonicalSphereAngularPhase.candidateTaylor(at: v, alongU: false, cosine: true, order: order, using: &execution)
            let sphereSineV = try CanonicalSphereAngularPhase.candidateTaylor(at: v, alongU: false, cosine: false, order: order, using: &execution)
            let radial = try uDirection.multiplying(sphereCosineU, using: &execution).adding(vDirection.multiplying(sphereSineU, using: &execution), using: &execution)
            let vertical = try SurfaceTaylorVectorJet.constant(.unitZ, order: order, using: &execution)
            let direction = try radial.multiplying(sphereCosineV, using: &execution).adding(vertical.multiplying(sphereSineV, using: &execution), using: &execution)
            let centerJet = try SurfaceTaylorVectorJet.constant(center, order: order, using: &execution)
            let radiusJet = try SurfaceTaylorScalarJet.constant(radius, order: order, using: &execution)
            return try centerJet.adding(direction.multiplying(radiusJet, using: &execution), using: &execution)
        case let .torus(center, axis, majorRadius, minorRadius):
            let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
            let uDirection = try SurfaceTaylorVectorJet.constant(basis.u, order: order, using: &execution)
            let vDirection = try SurfaceTaylorVectorJet.constant(basis.v, order: order, using: &execution)
            let radial = try uDirection.multiplying(cosineU, using: &execution).adding(vDirection.multiplying(sineU, using: &execution), using: &execution)
            let majorRadiusJet = try SurfaceTaylorScalarJet.constant(
                majorRadius,
                order: order
            , using: &execution)
            let minorRadiusJet = try SurfaceTaylorScalarJet.constant(
                minorRadius,
                order: order
            , using: &execution)
            let radialDistance = try majorRadiusJet.adding(minorRadiusJet.multiplying(cosineV, using: &execution), using: &execution)
            let centerJet = try SurfaceTaylorVectorJet.constant(center, order: order, using: &execution)
            let axisJet = try SurfaceTaylorVectorJet.constant(axis, order: order, using: &execution)
            return try centerJet.adding(radial.multiplying(radialDistance, using: &execution), using: &execution)
                .adding(axisJet.multiplying(minorRadiusJet.multiplying(sineV, using: &execution), using: &execution), using: &execution)
        }
    }
}

private extension BSplineSurface3D {
    struct TaylorHomogeneousDerivative {
        let vector: Vector3D
        let weight: Double
    }

    func taylorJet(
        u: Double,
        v: Double,
        throughOrder order: Int,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceTaylorVectorJet {
        try execution.consumeWork(1)
        let clampedU = try basisParameter(u, direction: .u, tolerance: tolerance)
        let clampedV = try basisParameter(v, direction: .v, tolerance: tolerance)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: order + 1, of: [Double].self))
        let uBasis = try (0...order).map { derivativeOrder in
            try BSplineBasis.derivativeValues(
                parameter: clampedU,
                degree: uDegree,
                derivativeOrder: derivativeOrder,
                knots: uKnots,
                count: uControlPointCount
            , using: &execution)
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: order + 1, of: [Double].self))
        let vBasis = try (0...order).map { derivativeOrder in
            try BSplineBasis.derivativeValues(
                parameter: clampedV,
                degree: vDegree,
                derivativeOrder: derivativeOrder,
                knots: vKnots,
                count: vControlPointCount
            , using: &execution)
        }
        let dimension = order + 1
        func key(_ uOrder: Int, _ vOrder: Int) -> Int {
            uOrder * dimension + vOrder
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: (order + 1) * (order + 2) / 2, of: (Int,TaylorHomogeneousDerivative).self))
        var homogeneous: [Int: TaylorHomogeneousDerivative] = [:]
        for totalOrder in 0...order {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                var vector = Vector3D.zero
                var weight = 0.0
                for vIndex in 0..<vControlPointCount {
                    for uIndex in 0..<uControlPointCount {
                        try execution.consumeWork(1)
                        let basisValue = uBasis[uOrder][uIndex]
                            * vBasis[vOrder][vIndex]
                        guard basisValue != 0.0 else {
                            continue
                        }
                        let controlWeight = weights[vIndex][uIndex]
                        let coefficient = basisValue * controlWeight
                        let point = controlPoints[vIndex][uIndex]
                        vector = vector + Vector3D(
                            x: point.x,
                            y: point.y,
                            z: point.z
                        ) * coefficient
                        weight += coefficient
                    }
                }
                homogeneous[key(uOrder, vOrder)] = TaylorHomogeneousDerivative(
                    vector: vector,
                    weight: weight
                )
            }
        }
        guard let base = homogeneous[key(0, 0)],
              base.weight.isFinite,
              base.weight > Double.ulpOfOne else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: homogeneous[key(0, 0)]?.weight,
                tolerance: tolerance,
                message: "Rational B-spline Taylor evaluation requires a positive finite weight."
            )
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: (order + 1) * (order + 2) / 2, of: (Int,Vector3D).self))
        var euclidean: [Int: Vector3D] = [:]
        for totalOrder in 0...order {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                guard let source = homogeneous[key(uOrder, vOrder)] else {
                    throw KernelError(
                        phase: .geometry,
                        code: .invalidInput,
                        tolerance: tolerance,
                        message: "A required homogeneous Taylor derivative is missing."
                    )
                }
                var numerator = source.vector
                for weightUOrder in 0...uOrder {
                    for weightVOrder in 0...vOrder {
                        try execution.consumeWork(1)
                        guard weightUOrder + weightVOrder > 0 else {
                            continue
                        }
                        guard let weightDerivative = homogeneous[
                            key(weightUOrder, weightVOrder)
                        ]?.weight,
                        let lowerDerivative = euclidean[
                            key(
                                uOrder - weightUOrder,
                                vOrder - weightVOrder
                            )
                        ] else {
                            throw KernelError(
                                phase: .geometry,
                                code: .invalidInput,
                                tolerance: tolerance,
                                message: "Rational Taylor derivative recurrence is incomplete."
                            )
                        }
                        let coefficient = Double(
                            surfaceBinomial(uOrder, weightUOrder)
                                * surfaceBinomial(vOrder, weightVOrder)
                        )
                        numerator = numerator
                            - lowerDerivative * (coefficient * weightDerivative)
                    }
                }
                let derivative = numerator / base.weight
                guard derivative.isFinite else {
                    throw KernelError(
                        phase: .geometry,
                        code: .resourceLimitExceeded,
                        tolerance: tolerance,
                        message: "Rational B-spline Taylor evaluation exceeded the finite numeric range."
                    )
                }
                euclidean[key(uOrder, vOrder)] = derivative
            }
        }

        var x = try SurfaceTaylorScalarJet(order: order, using: &execution)
        var y = try SurfaceTaylorScalarJet(order: order, using: &execution)
        var z = try SurfaceTaylorScalarJet(order: order, using: &execution)
        for totalOrder in 0...order {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                guard let derivative = euclidean[key(uOrder, vOrder)] else {
                    continue
                }
                let scale = Double(
                    surfaceFactorial(uOrder) * surfaceFactorial(vOrder)
                )
                try x.setCoefficient(
                    derivative.x / scale,
                    uOrder: uOrder,
                    vOrder: vOrder
                , using: &execution)
                try y.setCoefficient(
                    derivative.y / scale,
                    uOrder: uOrder,
                    vOrder: vOrder
                , using: &execution)
                try z.setCoefficient(
                    derivative.z / scale,
                    uOrder: uOrder,
                    vOrder: vOrder
                , using: &execution)
            }
        }
        return try SurfaceTaylorVectorJet(x: x, y: y, z: z)
    }
}

private func surfaceFactorial(_ value: Int) -> Int {
    guard value > 1 else {
        return 1
    }
    return (2...value).reduce(1, *)
}

private func surfaceBinomial(_ n: Int, _ k: Int) -> Int {
    guard k >= 0, k <= n else {
        return 0
    }
    let effectiveK = min(k, n - k)
    guard effectiveK > 0 else {
        return 1
    }
    var result = 1
    for index in 1...effectiveK {
        result = result * (n - effectiveK + index) / index
    }
    return result
}
