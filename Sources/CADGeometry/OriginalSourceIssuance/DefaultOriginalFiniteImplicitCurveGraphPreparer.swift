/// Supplies the actual single-cell graph, with exact checked forward host coordinates.
public struct DefaultOriginalFiniteImplicitCurveGraphPreparer: OriginalCompleteCurveGraphPreparing {
    public typealias Source = OriginalImplicitCurveSnapshot
    public typealias Evidence = OriginalImplicitCurveGraphEvidence
    public typealias Coverage = OriginalImplicitCurveGraphReduction
    typealias Field = OriginalExactScalarDomain
    typealias Polynomial = ExactPolynomial<Field>
    public init() {}

    public func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        field: OriginalExactScalarDomain, maximumCharts: Int, limits: OriginalSourceIssuanceLimits, using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalCompleteCurveGraphs<Source,Evidence,Coverage> {
        let retained = copy source
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&admission) { a in
                try a.checkpoint(); try retained.require(limits)
                guard maximumCharts >= 0 else { throw OriginalSourceIssuanceFailure.invalidChart }
                guard maximumCharts >= 1 else { throw OriginalSourceIssuanceFailure.chartLimit }
                guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                let original = retained.original
                // FIXME(INCOMPLETE_IMPLEMENTATION): The ordinary implicit CS source path
                // currently issues only a single triangular Native cell. General graph cells
                // require complete guarded correspondence before they can count as supplied.
                guard OriginalImplicitCurveSnapshotProvider.supports(.implicit(original.original)) else {
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                }
                try a.consumeWork(64)
                let children = try OriginalSourceIssuanceLimits(remainingSourceDepth: limits.remainingSourceDepth - 1)
                let native = DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>()
                let first = try native.prepare(source: original.first, field: field, maximumCharts: maximumCharts,
                    limits: children, using: &a)
                let second = try native.prepare(source: original.second, field: field, maximumCharts: maximumCharts,
                    limits: children, using: &a)
                guard first.laws.count == 1, second.laws.count == 1,
                    original.first.owns(first.laws[0].chart), original.second.owns(second.laws[0].chart) else {
                    throw OriginalSourceIssuanceFailure.foreignBinding
                }
                let f = field, ring = try ExactPolynomialDomain(field: f, variableCount: 5, using: &a)
                let parameterRing = try ExactPolynomialDomain(field: f, variableCount: 1, using: &a)
                let zero = try f.integer(0,using:&a), one = try f.integer(1,using:&a)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 5,of: Polynomial.self))
                var coordinates: [Polynomial] = []; coordinates.reserveCapacity(5)
                for axis in 0..<5 { coordinates.append(try ring.variable(axis,using:&a)) }

                func embed(_ p: Polynomial, firstHost: Bool) throws -> Polynomial {
                    guard p.variableCount == 2 else { throw OriginalSourceIssuanceFailure.invalidChart }
                    try a.admitDepth(value:p.depth.value,coefficient:p.depth.coefficient)
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:p.termCount,of:ExactPolynomialTerm<Field.Value>.self))
                    var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(p.termCount)
                    for term in p.terms {
                        try a.consumeWork(1)
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:5,of:Int.self))
                        let powers = firstHost ? [0,term.powers[0],term.powers[1],0,0]
                            : [0,0,0,term.powers[0],term.powers[1]]
                        terms.append(.init(powers:powers,coefficient:try f.importing(term.coefficient,using:&a)))
                    }
                    return try ring.polynomial(orderedTerms:terms,using:&a)
                }
                func constant(_ p: Polynomial) throws -> Field.Value? {
                    if p.terms.isEmpty { return zero }
                    guard p.termCount == 1 else { return nil }
                    for power in p.terms[0].powers { try a.consumeWork(1); if power != 0 { return nil } }
                    return try f.importing(p.terms[0].coefficient,using:&a)
                }
                func position(_ family: OriginalFiniteBSplineCharts<BSplineSurface3D>, firstHost: Bool) throws -> [Polynomial] {
                    let law = family.laws[0]
                    try law.admitProof(using:&a)
                    guard law.support.count == 2,law.homogeneous.count == 4,
                        law.parameterTransport.numerators.count == 2,law.parameterTransport.denominators.count == 2 else {
                        throw OriginalSourceIssuanceFailure.invalidChart
                    }
                    guard let weight = try constant(law.denominator),try f.sign(of:weight,using:&a) == .positive else {
                        throw OriginalSourceIssuanceFailure.unresolvedAuthority
                    }
                    for axis in 0..<2 {
                        let transport = law.parameterTransport
                        guard let divisor = try constant(transport.denominators[axis]),
                            try f.sign(of:divisor,using:&a) != .zero,
                            try law.polynomials.equals(transport.numerators[axis],
                                law.polynomials.scaled(law.polynomials.variable(axis,using:&a),by:divisor,using:&a),using:&a) else {
                            throw OriginalSourceIssuanceFailure.unresolvedAuthority
                        }
                    }
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Polynomial.self))
                    var result: [Polynomial] = []; result.reserveCapacity(4)
                    for p in law.homogeneous { result.append(try embed(p,firstHost:firstHost)) }
                    return result
                }
                let firstPosition = try position(first,firstHost:true)
                let secondPosition = try position(second,firstHost:false)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Polynomial.self))
                var equations: [Polynomial] = []; equations.reserveCapacity(4)
                for axis in 0..<3 {
                    equations.append(try ring.subtracting(
                        ring.multiplying(firstPosition[axis],secondPosition[3],using:&a),
                        ring.multiplying(secondPosition[axis],firstPosition[3],using:&a),using:&a))
                }
                let free = original.cell.parameterBox.firstV
                let offset = try f.binary64(exactly:free.lower,using:&a)
                let gain = try f.binary64(exactly:free.width,using:&a)
                guard try f.sign(of:gain,using:&a) == .positive,
                    try f.compare(f.adding(offset,gain,using:&a),f.binary64(exactly:free.upper,using:&a),using:&a) == .equal else {
                    throw OriginalSourceIssuanceFailure.unresolvedAuthority
                }
                equations.append(try ring.subtracting(coordinates[2],ring.adding(ring.constant(offset,using:&a),
                    ring.scaled(coordinates[0],by:gain,using:&a),using:&a),using:&a))

                // Each substitution is forced by one original equality, not an inverse fit.
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:5,of:Polynomial.self))
                var replacements = coordinates
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:5,of:Bool.self))
                var resolved = [true,false,false,false,false]
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:8,of:Int.self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Field.Value.self))
                var axes: [Int] = [], selected: [Int] = [], pivots: [Field.Value] = []
                axes.reserveCapacity(4); selected.reserveCapacity(4); pivots.reserveCapacity(4)
                for _ in 0..<4 {
                    for axis in 1..<5 where !resolved[axis] {
                        for equation in equations.indices {
                            try a.consumeWork(1)
                            let current = try ring.substituted(equations[equation],with:replacements,using:&a)
                            var pivot: Field.Value?, valid = true
                            for term in current.terms {
                                try a.consumeWork(5)
                                if term.powers[axis] == 0 {
                                    for other in 1..<5 where term.powers[other] != 0 { valid = false }
                                } else {
                                    if term.powers[axis] != 1 || term.powers[0] != 0 || pivot != nil { valid = false }
                                    for other in 1..<5 where other != axis && term.powers[other] != 0 { valid = false }
                                    pivot = term.coefficient
                                }
                                if !valid { break }
                            }
                            guard valid,let pivot,try f.sign(of:pivot,using:&a) != .zero else { continue }
                            try a.retainStorage(bytes:exactScalarPayloadBytes(count:current.termCount,of:ExactPolynomialTerm<Field.Value>.self))
                            var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(current.termCount)
                            for term in current.terms where term.powers[axis] == 0 {
                                try a.consumeWork(1)
                                terms.append(.init(powers:term.powers,
                                    coefficient:try f.dividing(f.negated(term.coefficient,using:&a),pivot,using:&a)))
                            }
                            replacements[axis] = try ring.polynomial(orderedTerms:terms,using:&a)
                            resolved[axis] = true; axes.append(axis); selected.append(equation); pivots.append(pivot)
                            break
                        }
                    }
                }
                guard axes.count == 4 else { throw OriginalSourceIssuanceFailure.unresolvedAuthority }
                for equation in equations {
                    guard try ring.isZero(ring.substituted(equation,with:replacements,using:&a),using:&a) else {
                        throw OriginalSourceIssuanceFailure.unresolvedAuthority
                    }
                }
                func project(_ p: Polynomial) throws -> Polynomial {
                    try a.admitDepth(value:p.depth.value,coefficient:p.depth.coefficient)
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:p.termCount,of:ExactPolynomialTerm<Field.Value>.self))
                    var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(p.termCount)
                    for term in p.terms {
                        try a.consumeWork(5)
                        guard term.powers[1] == 0,term.powers[2] == 0,term.powers[3] == 0,term.powers[4] == 0 else {
                            throw OriginalSourceIssuanceFailure.unresolvedAuthority
                        }
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Int.self))
                        terms.append(.init(powers:[term.powers[0]],coefficient:try f.importing(term.coefficient,using:&a)))
                    }
                    return try parameterRing.polynomial(orderedTerms:terms,using:&a)
                }
                // Bernstein controls give whole [0,1] bounds, including both endpoints.
                func range(_ p: Polynomial) throws -> OriginalSourceParameterInterval<Field.Value> {
                    let degree = try parameterRing.degree(of:p,in:0,using:&a) ?? 0
                    let count = degree.addingReportingOverflow(1)
                    guard !count.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:count.partialValue,of:Field.Value.self))
                    var powers = [Field.Value](repeating:zero,count:count.partialValue)
                    for term in p.terms { try a.consumeWork(1); powers[term.powers[0]] = term.coefficient }
                    var lower: Field.Value?, upper: Field.Value?
                    for index in 0...degree {
                        var value = zero, ratio = one
                        for power in 0...index {
                            try a.consumeWork(1)
                            value = try f.adding(value,f.multiplying(powers[power],ratio,using:&a),using:&a)
                            if power < index {
                                ratio = try f.dividing(f.multiplying(ratio,f.integer(index-power,using:&a),using:&a),
                                    f.integer(degree-power,using:&a),using:&a)
                            }
                        }
                        if let previous = lower { if try f.compare(value,previous,using:&a) == .less { lower = value } }
                        else { lower = value }
                        if let previous = upper { if try f.compare(value,previous,using:&a) == .greater { upper = value } }
                        else { upper = value }
                    }
                    guard let lower,let upper else { throw OriginalSourceIssuanceFailure.unresolvedAuthority }
                    return .init(lower:lower,upper:upper)
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Polynomial.self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:OriginalSourceParameterInterval<Field.Value>.self))
                var forward: [Polynomial] = [], ranges: [OriginalSourceParameterInterval<Field.Value>] = []
                forward.reserveCapacity(4); ranges.reserveCapacity(4)
                for axis in 1..<5 {
                    let p = try project(replacements[axis]); forward.append(p); ranges.append(try range(p))
                }
                // Four equalities, sixteen closed bounds, seven original denominator guards.
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:27,of:OriginalParametricGraphCondition<Field>.self))
                var conditions: [OriginalParametricGraphCondition<Field>] = []; conditions.reserveCapacity(27)
                for equation in equations { conditions.append(.init(equation,.equal)) }
                for axis in 0..<4 {
                    try a.consumeWork(1)
                    guard let coordinate = SurfaceIntersectionParameterCoordinate(rawValue:axis) else {
                        throw OriginalSourceIssuanceFailure.invalidChart
                    }
                    let bound = original.cell.parameterBox.interval(for:coordinate)
                    let lower = try f.binary64(exactly:bound.lower,using:&a)
                    let upper = try f.binary64(exactly:bound.upper,using:&a)
                    let host = axis < 2 ? first:second, hostAxis = axis % 2
                    let span = host.laws[0].support[hostAxis]
                    guard try f.compare(lower,upper,using:&a) == .less,
                        try f.compare(ranges[axis].lower,lower,using:&a) != .less,
                        try f.compare(ranges[axis].upper,upper,using:&a) != .greater,
                        try f.compare(ranges[axis].lower,span.lower,using:&a) != .less,
                        try f.compare(ranges[axis].upper,span.upper,using:&a) != .greater else {
                        throw OriginalSourceIssuanceFailure.unresolvedAuthority
                    }
                    conditions.append(.init(try ring.subtracting(coordinates[axis+1],ring.constant(lower,using:&a),using:&a),.nonnegative))
                    conditions.append(.init(try ring.subtracting(ring.constant(upper,using:&a),coordinates[axis+1],using:&a),.nonnegative))
                    conditions.append(.init(try ring.subtracting(coordinates[axis+1],ring.constant(span.lower,using:&a),using:&a),.nonnegative))
                    conditions.append(.init(try ring.subtracting(ring.constant(span.upper,using:&a),coordinates[axis+1],using:&a),.nonnegative))
                    conditions.append(.init(try embed(host.laws[0].parameterTransport.denominators[hostAxis],firstHost:axis<2),.notEqual))
                }
                conditions.append(.init(firstPosition[3],.notEqual)); conditions.append(.init(secondPosition[3],.notEqual))
                conditions.append(.init(try ring.constant(one,using:&a),.notEqual))

                // Original dependent-position Jacobian, in firstU/secondU/secondV order.
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:9,of:Polynomial.self))
                var matrix: [Polynomial] = []; matrix.reserveCapacity(9)
                for row in 0..<3 {
                    for column in 0..<3 {
                        let axis = column == 0 ? 1:column+2
                        matrix.append(try ring.differentiated(equations[row],in:axis,using:&a))
                    }
                }
                var determinant = try ring.zero(using:&a)
                for i in 0..<3 {
                    for j in 0..<3 where j != i {
                        for k in 0..<3 where k != i && k != j {
                            try a.consumeWork(1)
                            let term = try ring.multiplying(matrix[i],ring.multiplying(matrix[3+j],matrix[6+k],using:&a),using:&a)
                            let inversions = (i > j ? 1:0) + (i > k ? 1:0) + (j > k ? 1:0)
                            determinant = inversions % 2 == 0 ? try ring.adding(determinant,term,using:&a)
                                : try ring.subtracting(determinant,term,using:&a)
                        }
                    }
                }
                let jacobian = try project(ring.substituted(determinant,with:replacements,using:&a))
                guard let jacobianValue = try constant(jacobian),try f.sign(of:jacobianValue,using:&a) != .zero else {
                    throw OriginalSourceIssuanceFailure.unresolvedAuthority
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:8,of:Polynomial.self))
                var positionLaw: [Polynomial] = [], derivative: [Polynomial] = []
                positionLaw.reserveCapacity(4); derivative.reserveCapacity(4)
                for p in firstPosition {
                    let composed = try project(ring.substituted(p,with:replacements,using:&a))
                    positionLaw.append(composed)
                    derivative.append(try parameterRing.differentiated(composed,in:0,using:&a))
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Polynomial.self))
                let transport = OriginalRationalParameterTransport<Field>(numerators:[try parameterRing.variable(0,using:&a)],
                    denominators:[try parameterRing.constant(one,using:&a)])
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:5,of:Int.self))
                let layout = try OriginalParametricVariableLayout.checked(variableCount:5,parameters:[0],auxiliaries:[1,2,3,4],using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSourceParameterInterval<Field.Value>.self))
                let support = OriginalSourceParameterInterval(lower:zero,upper:one)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Evidence.self))
                let evidence = Evidence(source:retained,field:f,first:first,second:second,
                    graphPolynomials:ring,conditions:conditions,parameterPolynomials:parameterRing,freeOffset:offset,freeGain:gain,
                    forwardHostCoordinates:forward,forwardHomogeneous:positionLaw,forwardHomogeneousDerivative:derivative,
                    hostCoordinateRanges:ranges,eliminationAxes:axes,eliminationEquations:selected,eliminationPivots:pivots,
                    dependentJacobian:jacobian,proofDepth:try a.depth)
                typealias Graph = OriginalParametricGraphReceipt<Source,Field,Evidence>
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Bool.self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Graph.self))
                let originalGraph = Graph(source:retained,evidence:evidence,field:f,polynomials:ring,homogeneous:firstPosition,
                    support:[support],includesUpperBoundary:[true],layout:layout,conditions:conditions,
                    parameterTransport:transport,proofDepth:try a.depth)
                // The original equalities force these unique auxiliaries for every T.
                // Retain every substituted guard and the full original graph as the inverse proof.
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:conditions.count,of:OriginalParametricGraphCondition<Field>.self))
                var substitutedConditions: [OriginalParametricGraphCondition<Field>] = []
                substitutedConditions.reserveCapacity(conditions.count)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:conditions.count,of:OriginalSourceParameterInterval<Field.Value>.self))
                var conditionRanges: [OriginalSourceParameterInterval<Field.Value>] = []
                conditionRanges.reserveCapacity(conditions.count)
                for condition in originalGraph.conditions {
                    try a.consumeWork(1)
                    let reduced = try project(ring.substituted(condition.polynomial,with:replacements,using:&a))
                    substitutedConditions.append(.init(reduced,condition.relation))
                    conditionRanges.append(try range(reduced))
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:conditions.count,of:OriginalParametricGraphCondition<Field>.self))
                var reducedConditions: [OriginalParametricGraphCondition<Field>] = []
                reducedConditions.reserveCapacity(conditions.count)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:conditions.count,of:Int.self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:conditions.count,of:Int.self))
                var retainedOrdinals: [Int] = [], eliminatedOrdinals: [Int] = []
                retainedOrdinals.reserveCapacity(conditions.count); eliminatedOrdinals.reserveCapacity(conditions.count)
                for index in substitutedConditions.indices {
                    try a.consumeWork(1)
                    let condition = substitutedConditions[index]
                    if try Coverage.rangeProves(condition.relation,range:conditionRanges[index],field:f,zero:zero,using:&a) {
                        eliminatedOrdinals.append(index)
                    } else {
                        retainedOrdinals.append(index); reducedConditions.append(condition)
                    }
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Int.self))
                let reducedLayout = try OriginalParametricVariableLayout.checked(variableCount:1,parameters:[0],auxiliaries:[],using:&a)
                // positionLaw was obtained above by exact substitution in every original XYZW component.
                let graph = Graph(source:retained,evidence:evidence,field:f,polynomials:parameterRing,homogeneous:positionLaw,
                    support:originalGraph.support,includesUpperBoundary:originalGraph.includesUpperBoundary,
                    layout:reducedLayout,conditions:reducedConditions,parameterTransport:originalGraph.parameterTransport,
                    proofDepth:try a.depth)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:5,of:Polynomial.self))
                var originalCoordinates: [Polynomial] = []; originalCoordinates.reserveCapacity(5)
                originalCoordinates.append(transport.numerators[0])
                for p in forward { try a.consumeWork(1); originalCoordinates.append(p) }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Coverage.self))
                let reduction = Coverage(original:originalGraph,graph:graph,substitutedConditions:substitutedConditions,
                    conditionRanges:conditionRanges,retainedConditionOrdinals:retainedOrdinals,
                    eliminatedConditionOrdinals:eliminatedOrdinals,originalCoordinates:originalCoordinates,proofDepth:try a.depth)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalCompleteCurveGraphs<Source,Evidence,Coverage>.self))
                let result = OriginalCompleteCurveGraphs(source:retained,coverage:reduction,field:f,graphs:[graph],
                    support:support,proofDepth:try a.depth)
                try a.checkpoint(); return result
            }
        } catch { throw .init(preserving:error) }
    }
}
