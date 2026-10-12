#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalAnalyticCoordinateIssuer<S: OriginalAnalyticCoordinateReading,F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalAnalyticCoordinateIssuing {
    public typealias Source = S
    public typealias Field = F
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,field: borrowing F,
        limits: OriginalSourceIssuanceLimits,using a: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalAnalyticCoordinateLawReceipt<S,F> {
        try issue(source:source,field:field,mathematicalPi:nil,limits:limits,using:&a)
    }
    /// A supplied mathematical pi is only consumed by the source-level pi-capable
    /// overload. The intrinsic public issuer never accepts a guessed coefficient.
    func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,field f: borrowing F,
        mathematicalPi pi: F.Value?,limits: OriginalSourceIssuanceLimits,using a: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalAnalyticCoordinateLawReceipt<S,F> {
        do {
            try a.checkpoint(); try source.require(limits)
            let original = source.original,k = original.coordinateKind,n = k.arity
            let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
            let labelPeriod = try f.binary64(exactly:2 * Double.pi,using:&a)
            let quarter = try f.binary64(exactly:Double.pi * 0.5,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:12,of:F.Value.self))
            var matrix: [F.Value] = [],origin: [F.Value] = []
            for row in 0..<3 {
                try a.consumeWork(1); origin.append(try f.binary64(exactly:original.center(in:row),using:&a))
                for column in 0..<3 { try a.consumeWork(1); matrix.append(try f.binary64(exactly:original.frame(row:row,column:column),using:&a)) }
            }
            func productDifference(_ a0: Int,_ a1: Int,_ b0: Int,_ b1: Int) throws -> F.Value {
                try f.subtracting(f.multiplying(matrix[a0],matrix[a1],using:&a),f.multiplying(matrix[b0],matrix[b1],using:&a),using:&a)
            }
            let determinant = try f.adding(f.subtracting(f.multiplying(matrix[0],productDifference(4,8,5,7),using:&a),
                f.multiplying(matrix[1],productDifference(3,8,5,6),using:&a),using:&a),
                f.multiplying(matrix[2],productDifference(3,7,4,6),using:&a),using:&a)
            guard try f.sign(of:determinant,using:&a) != .zero else { throw OriginalSourceIssuanceFailure.invalidSource }
            let first = try f.binary64(exactly:original.firstMagnitude,using:&a)
            let second = try f.binary64(exactly:original.secondMagnitude,using:&a)
            guard try f.sign(of:first,using:&a) == .positive else { throw OriginalSourceIssuanceFailure.invalidSource }
            if k == .ellipse || k == .hyperbola || k == .torus {
                guard try f.sign(of:second,using:&a) == .positive else { throw OriginalSourceIssuanceFailure.invalidSource }
            }
            if k == .ellipse { guard try f.compare(first,second,using:&a) != .less else { throw OriginalSourceIssuanceFailure.invalidSource } }
            if k == .torus { guard try f.compare(first,second,using:&a) == .greater else { throw OriginalSourceIssuanceFailure.invalidSource } }
            if k == .cone {
                let angle = original.coneHalfAngle
                guard angle.isFinite,angle > 0,angle < Double.pi * 0.5 else { throw OriginalSourceIssuanceFailure.invalidSource }
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:n,of:OriginalSourceCoordinateAxis<F.Value>.self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:n,of:OriginalSourcePeriodReceipt<S,F>.self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:6,of:OriginalSourceCoordinateFunction<F.Value>.self))
            var axes: [OriginalSourceCoordinateAxis<F.Value>] = [],periods: [OriginalSourcePeriodReceipt<S,F>] = []
            var functions: [OriginalSourceCoordinateFunction<F.Value>] = []
            var gainValues: [F.Value] = [],offsetValues: [F.Value] = []
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2*n,of:F.Value.self))
            for axis in 0..<n {
                try a.consumeWork(1)
                var lower: F.Value? = nil,upper: F.Value? = nil
                if let value = original.finiteLowerBound(axis:axis) { lower = try f.binary64(exactly:value,using:&a) }
                if let value = original.finiteUpperBound(axis:axis) { upper = try f.binary64(exactly:value,using:&a) }
                var meaning: OriginalSourceParameterMeaning = .authoredScalar,gain = one,offset = zero,period = labelPeriod
                if k.isAngular(axis:axis) {
                    let map = original.angularMap(axis:axis); meaning = map.meaning
                    switch map {
                    case .intrinsic:
                        functions.append(.intrinsicCosine(axis:axis)); functions.append(.intrinsicSine(axis:axis))
                        if k == .sphere && axis == 1 { lower = try f.negated(quarter,using:&a); upper = quarter }
                    case .physicalRadians(let originalGain,let originalOffset):
                        guard let pi else { throw OriginalSourceIssuanceFailure.unsupportedCoefficientField }
                        gain = try OriginalSourceRationalImport.value(originalGain,field:f,using:&a)
                        offset = try OriginalSourceRationalImport.value(originalOffset,field:f,using:&a)
                        guard try f.sign(of:gain,using:&a) != .zero else { throw OriginalSourceIssuanceFailure.invalidSource }
                        let positiveGain = try f.sign(of:gain,using:&a) == .positive ? gain : f.negated(gain,using:&a)
                        period = try f.dividing(f.multiplying(f.integer(2,using:&a),pi,using:&a),positiveGain,using:&a)
                        functions.append(.physicalCosine(axis:axis,gain:gain,offset:offset)); functions.append(.physicalSine(axis:axis,gain:gain,offset:offset))
                        if k == .sphere && axis == 1 {
                            let half = try f.dividing(pi,f.integer(2,using:&a),using:&a)
                            let lo = try f.dividing(f.subtracting(f.negated(half,using:&a),offset,using:&a),gain,using:&a)
                            let hi = try f.dividing(f.subtracting(half,offset,using:&a),gain,using:&a)
                            if try f.compare(lo,hi,using:&a) == .less { lower = lo; upper = hi } else { lower = hi; upper = lo }
                        }
                    case .physicalRadianArc(let start,let end,let turns):
                        guard let pi else { throw OriginalSourceIssuanceFailure.unsupportedCoefficientField }
                        offset = try OriginalSourceRationalImport.value(start,field:f,using:&a)
                        let last = try OriginalSourceRationalImport.value(end,field:f,using:&a)
                        gain = try f.adding(f.subtracting(last,offset,using:&a),f.multiplying(f.integer(turns,using:&a),f.multiplying(f.integer(2,using:&a),pi,using:&a),using:&a),using:&a)
                        guard try f.sign(of:gain,using:&a) != .zero else { throw OriginalSourceIssuanceFailure.invalidSource }
                        let positiveGain = try f.sign(of:gain,using:&a) == .positive ? gain : f.negated(gain,using:&a)
                        period = try f.dividing(f.multiplying(f.integer(2,using:&a),pi,using:&a),positiveGain,using:&a)
                        lower = zero; upper = one
                        functions.append(.physicalCosine(axis:axis,gain:gain,offset:offset)); functions.append(.physicalSine(axis:axis,gain:gain,offset:offset))
                        if k == .sphere && axis == 1 {
                            let half = try f.dividing(pi,f.integer(2,using:&a),using:&a)
                            let endPhase = try f.adding(offset,gain,using:&a)
                            let negativeHalf = try f.negated(half,using:&a)
                            guard try f.compare(offset,negativeHalf,using:&a) != .less,try f.compare(offset,half,using:&a) != .greater,
                                try f.compare(endPhase,negativeHalf,using:&a) != .less,try f.compare(endPhase,half,using:&a) != .greater else { throw OriginalSourceIssuanceFailure.invalidSource }
                        }
                    }
                    if k.isPeriodic(axis:axis) {
                        let start = lower ?? zero
                        let anchor = try source.chart(axis,limits:limits,using:&a)
                        periods.append(.init(anchor:anchor,field:copy f,meaning:meaning,axis:axis,period:period,lower:start,upper:try f.adding(start,period,using:&a)))
                    }
                } else if k == .hyperbola {
                    functions.append(.hyperbolicCosine(axis:axis)); functions.append(.hyperbolicSine(axis:axis))
                } else { functions.append(.authoredCoordinate(axis:axis)) }
                if let lower,let upper { guard try f.compare(lower,upper,using:&a) != .greater else { throw OriginalSourceIssuanceFailure.invalidSource } }
                axes.append(.init(lower:lower,upper:upper,meaning:meaning)); gainValues.append(gain); offsetValues.append(offset)
            }
            if k == .cone { functions.append(.physicalConstantSine(radians:original.coneHalfAngle)); functions.append(.physicalConstantCosine(radians:original.coneHalfAngle)) }
            let ring = try ExactPolynomialDomain(field:copy f,variableCount:functions.count,using:&a)
            let c = try ring.variable(0,using:&a)
            let empty = try ring.zero(using:&a)
            let s = functions.count > 1 ? try ring.variable(1,using:&a) : empty
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:6,of:ExactPolynomial<F>.self))
            let local: [ExactPolynomial<F>]
            switch k {
            case .circle,.ellipse,.hyperbola: local = [try ring.scaled(c,by:first,using:&a),try ring.scaled(s,by:k == .circle ? first : second,using:&a),empty]
            case .parabola:
                let t = c
                local = [try ring.scaled(ring.multiplying(t,t,using:&a),by:f.dividing(one,f.multiplying(f.integer(4,using:&a),first,using:&a),using:&a),using:&a),t,empty]
            case .cylinder: local = [try ring.scaled(c,by:first,using:&a),try ring.scaled(s,by:first,using:&a),try ring.variable(2,using:&a)]
            case .cone:
                let v = try ring.variable(2,using:&a),sinAngle = try ring.variable(3,using:&a),cosAngle = try ring.variable(4,using:&a)
                let radial = try ring.multiplying(v,sinAngle,using:&a)
                local = [try ring.multiplying(radial,c,using:&a),try ring.multiplying(radial,s,using:&a),try ring.multiplying(v,cosAngle,using:&a)]
            case .sphere:
                let cv = try ring.variable(2,using:&a),sv = try ring.variable(3,using:&a)
                local = [try ring.scaled(ring.multiplying(cv,c,using:&a),by:first,using:&a),try ring.scaled(ring.multiplying(cv,s,using:&a),by:first,using:&a),try ring.scaled(sv,by:first,using:&a)]
            case .torus:
                let cv = try ring.variable(2,using:&a),sv = try ring.variable(3,using:&a)
                let radial = try ring.adding(ring.constant(first,using:&a),ring.scaled(cv,by:second,using:&a),using:&a)
                local = [try ring.multiplying(radial,c,using:&a),try ring.multiplying(radial,s,using:&a),try ring.scaled(sv,by:second,using:&a)]
            }
            var position: [ExactPolynomial<F>] = []
            for row in 0..<3 {
                var p = try ring.constant(origin[row],using:&a)
                for column in 0..<3 { try a.consumeWork(1); p = try ring.adding(p,ring.scaled(local[column],by:matrix[row*3+column],using:&a),using:&a) }
                position.append(p)
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:OriginalSourceCollapsedFiberReceipt<S,F>.self))
            var collapsed: [OriginalSourceCollapsedFiberReceipt<S,F>] = []
            if k == .cone {
                let anchor = try source.chart(0,limits:limits,using:&a)
                collapsed.append(.init(anchor:anchor,fixedAxis:1,fixedValue:zero,varyingAxis:0,position:origin))
            } else if k == .sphere {
                let map = original.angularMap(axis:1)
                for north in [false,true] {
                    let pole: F.Value
                    switch map {
                    case .intrinsic: pole = north ? quarter : try f.negated(quarter,using:&a)
                    default:
                        guard let pi else { throw OriginalSourceIssuanceFailure.unsupportedCoefficientField }
                        let half = try f.dividing(pi,f.integer(2,using:&a),using:&a)
                        pole = try f.dividing(f.subtracting(north ? half : f.negated(half,using:&a),offsetValues[1],using:&a),gainValues[1],using:&a)
                    }
                    if let lo = axes[1].lower,try f.compare(pole,lo,using:&a) == .less { continue }
                    if let hi = axes[1].upper,try f.compare(pole,hi,using:&a) == .greater { continue }
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:F.Value.self))
                    var xyz: [F.Value] = []
                    let signedRadius = north ? first : try f.negated(first,using:&a)
                    for row in 0..<3 { try a.consumeWork(1); xyz.append(try f.adding(origin[row],f.multiplying(matrix[row*3+2],signedRadius,using:&a),using:&a)) }
                    collapsed.append(.init(anchor:try source.chart(north ? 1 : -1,limits:limits,using:&a),fixedAxis:1,fixedValue:pole,varyingAxis:0,position:xyz))
                }
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalAnalyticCoordinateLawReceipt<S,F>.self))
            let result = OriginalAnalyticCoordinateLawReceipt(source:copy source,field:copy f,polynomials:ring,position:position,functions:functions,axes:axes,periods:periods,collapsedFibers:collapsed,frameDeterminant:determinant)
            try a.checkpoint(); return result
        } catch { throw .init(preserving:error) }
    }
}
