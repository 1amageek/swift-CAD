import CADCore
import CADGeometry
import CADIR

/// Composes the retained source descriptor with the exact Geometry coefficient owner.
enum IndependentSTEPAngularLaw {
    static func coordinateLaw(source: IndependentShapeAngularSource?, units: UnitSystem,
        usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> IndependentShapeAngularSource.CoordinateLaw {
        if let source { return try source.originalCoordinateLaw(maximumSourceDepth: usage.limits.maximumNesting, using: &execution) }
        try usage.charge(work: 1, using: &execution)
        return units.angle == .degree ? .canonicalGain(.ratio(numerator: Double.pi, denominator: 180)) : .physicalRadians(.one)
    }
    static func equivalent(_ lhs: IndependentShapeAngularSource.CoordinateLaw,
        _ rhs: IndependentShapeAngularSource.CoordinateLaw, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Bool {
        switch (lhs, rhs) {
        case let (.canonicalGain(a), .canonicalGain(b)): return try a.isEquivalent(to: b, usage: &execution)
        case let (.physicalRadians(a), .physicalRadians(b)): return try a.subtracting(b, usage: &execution).isZero
        default: return false
        }
    }
    static func gain(source: IndependentShapeAngularSource?, units: UnitSystem,
        usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> OriginalParameterGain {
        if let source { return try source.originalParameterGain(maximumSourceDepth: usage.limits.maximumNesting, using: &execution) }
        try usage.charge(work: 1, using: &execution)
        return units.angle == .degree ? .ratio(numerator: Double.pi, denominator: 180) : .binary(1)
    }
    static func usesAngularCoordinates(curve: Curve3D, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Bool {
        var curve = curve
        var depth = 0
        while true {
            depth += 1; try execution.admitSourceDepth(depth); try execution.consumeRecords(1); try execution.consumeWork(1)
            switch curve {
            case .originalAngularTransport(let image): curve = image.source
            case .parameterImage(let image): curve = image.source
            case .affineImage(let image): curve = image.source
            case .originalAffineWord(let image): curve = image.source
            case .rigidImage(let image): curve = image.source
            case .circle, .analytic(.circle), .analytic(.ellipse): return true
            default: return false
            }
        }
    }
    static func usesAngularCoordinates(surface: Surface3D, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Bool {
        var surface = surface
        var depth = 0
        while true {
            depth += 1; try execution.admitSourceDepth(depth); try execution.consumeRecords(1); try execution.consumeWork(1)
            switch surface {
            case .procedural(.originalAngularTransport(let image)): surface = image.source
            case .procedural(.originalImage(let image)): surface = image.source
            case .procedural(.originalAffineWord(let image)): surface = image.source
            case .procedural(.offset(let offset)): surface = offset.source
            case .cylinder, .analytic(.cylinder), .analytic(.cone), .analytic(.sphere), .analytic(.torus): return true
            default: return false
            }
        }
    }
    static func equivalent(_ lhs: OriginalParameterGain, _ rhs: OriginalParameterGain,
        usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Bool {
        try lhs.isEquivalent(to: rhs, usage: &execution)
    }
}
