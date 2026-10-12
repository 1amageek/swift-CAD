/// Consumes a source-proved affine plane section and solves only its remaining parameter.
struct DefaultOriginalRollingPlaneSectionResolver {
    typealias Base = OriginalExactScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Polynomial = ExactPolynomial<Field>
    func resolve<S: OriginalRollingBallChildSourceReading,E: Sendable,C: Sendable,P: OriginalPlaneSourceReading,
        A: ExactScalarAdmission & ~Copyable>(surface: OriginalIssuedGraphFamily<S,OriginalRollingBallGraphReduction<S,E>,OriginalRollingBallGraphFamilyCoverage<S,E,C>>,
        plane: OriginalIssuedPlaneGraph<P>, planeFirst: Bool, maximumPieces: Int,
        limits: OriginalDomainIdentityLimits, cellLimits: ExactRealCellLimits, using a: inout A)
        throws -> OriginalRollingPlaneGeometricRelations {
        try a.checkpoint(); try surface.admitProof(limits:limits,using:&a); try plane.admitProof(limits:limits,using:&a)
        guard maximumPieces >= 0, surface.graphs.count <= maximumPieces else { throw ExactScalarFailure.resourceLimit(.work) }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:(OriginalIssuedGraphFamily<S,OriginalRollingBallGraphReduction<S,E>,OriginalRollingBallGraphFamilyCoverage<S,E,C>>,OriginalIssuedPlaneGraph<P>).self))
        let owner: any Sendable = (surface,plane)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:surface.graphs.count,of:OriginalSurfacePlaneSection.self))
        var pieces: [OriginalSurfacePlaneSection] = []; pieces.reserveCapacity(surface.graphs.count)
        var previousPartition: ExactRealCellPartition<Base>?
        for (index,prepared) in surface.graphs.enumerated() {
            try a.consumeWork(1)
            let g = prepared.original.graph, f = g.field, r = g.polynomials, basis = plane.original.law
            var equation = try r.constant(f.integer(0,using:&a),using:&a)
            for axis in 0..<3 {
                let difference = try r.subtracting(g.homogeneous[axis],r.scaled(g.homogeneous[3],by:basis.origin[axis],using:&a),using:&a)
                equation = try r.adding(equation,r.scaled(difference,by:basis.normal[axis],using:&a),using:&a)
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): The ordinary rolling/plane SSI path
            // accepts only a checked affine-U section. General plane sections must
            // retain complete multivariate coverage before this restriction is removed.
            let division = try r.divided(equation,by:g.homogeneous[3],using:&a)
            guard try r.isZero(division.remainder,using:&a) else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            var gain = try f.integer(0,using:&a), offset = gain
            for term in division.quotient.terms {
                try a.consumeWork(1)
                guard term.powers[1] == 0, term.powers[0] <= 1 else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                if term.powers[0] == 0 { offset = try f.adding(offset,term.coefficient,using:&a) }
                else { gain = try f.adding(gain,term.coefficient,using:&a) }
            }
            guard try f.sign(of:gain,using:&a) != .zero else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            let originalU = try f.dividing(f.negated(offset,using:&a),gain,using:&a)
            let field = prepared.field, u = try field.importingBase(originalU,using:&a)
            let cells = try ExactRealCellDomain<Base>(field:field,variableCount:1,using:&a), ring = cells.polynomials
            let old = prepared.graph.predicate.source
            func specialize(_ law: Polynomial) throws -> Polynomial {
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:law.termCount,of:ExactPolynomialTerm<Field.Value>.self))
                var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(law.termCount)
                for term in law.terms {
                    try a.consumeWork(1)
                    var coefficient = term.coefficient
                    for _ in 0..<term.powers[0] { coefficient = try field.multiplying(coefficient,u,using:&a) }
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Int.self))
                    terms.append(.init(powers:[term.powers[1]],coefficient:coefficient))
                }
                return try ring.polynomial(terms:terms,using:&a)
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:old.polynomials.count,of:Polynomial.self))
            var laws: [Polynomial] = []; laws.reserveCapacity(old.polynomials.count)
            for law in old.polynomials { laws.append(try specialize(law)) }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Polynomial.self))
            let position = Array(laws.prefix(4))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:prepared.graph.predicate.instructions.count+2,of:ExactRealCellInstruction.self))
            var program = prepared.graph.predicate.instructions
            var inside = true
            if case .finite(let lower) = old.domains[0].lower {
                let order = try field.compare(u,lower,using:&a)
                if order == .less || order == .equal && !old.domains[0].includesLower { inside = false }
            }
            if case .finite(let upper) = old.domains[0].upper {
                let order = try field.compare(u,upper,using:&a)
                if order == .greater || order == .equal && !old.domains[0].includesUpper { inside = false }
            }
            program.append(.literal(inside)); program.append(.and)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Polynomial.self))
            var planeUV: [Polynomial] = []; planeUV.reserveCapacity(2)
            for coordinate in 0..<2 {
                let direction = coordinate == 0 ? basis.u:basis.v
                var value = try ring.constant(field.integer(0,using:&a),using:&a)
                for axis in 0..<3 {
                    let difference = try ring.subtracting(position[axis],ring.scaled(position[3],by:field.importingBase(basis.origin[axis],using:&a),using:&a),using:&a)
                    value = try ring.adding(value,ring.scaled(difference,by:field.importingBase(direction[axis],using:&a),using:&a),using:&a)
                }
                planeUV.append(value)
                try append(.literal(false),to:&program,&a)
                for interval in plane.original.effective.axes[coordinate].intervals where !interval.isEmpty {
                    try append(.literal(true),to:&program,&a)
                    for side in 0..<2 {
                        let bound = side == 0 ? interval.lower:interval.upper
                        guard case .finite(let scalar) = bound else { continue }
                        let constant = try field.importingBase(scalar,using:&a)
                        let scaled = try ring.scaled(position[3],by:constant,using:&a)
                        let difference = try side == 0 ? ring.subtracting(value,scaled,using:&a):ring.subtracting(scaled,value,using:&a)
                        let slot = laws.count; try append(difference,to:&laws,&a)
                        let denominatorSlot = laws.count; try append(position[3],to:&laws,&a)
                        let closed = side == 0 ? interval.includesLower:interval.includesUpper
                        // Keep the denominator sign branches factored; no degree-four product is needed.
                        try append(.sign(polynomial:denominatorSlot,relation:.greater),to:&program,&a)
                        try append(.sign(polynomial:slot,relation:closed ? .greaterOrEqual:.greater),to:&program,&a)
                        try append(.and,to:&program,&a)
                        try append(.sign(polynomial:denominatorSlot,relation:.less),to:&program,&a)
                        try append(.sign(polynomial:slot,relation:closed ? .lessOrEqual:.less),to:&program,&a)
                        try append(.and,to:&program,&a)
                        try append(.or,to:&program,&a)
                        try append(.and,to:&program,&a)
                    }
                    try append(.or,to:&program,&a)
                }
                try append(.and,to:&program,&a)
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactRealRootInterval<Field.Value>.self))
            let source = try cells.bind(polynomials:laws,domains:[old.domains[1]],using:&a)
            let predicate = try cells.predicate(instructions:program,for:source,using:&a)
            // Position laws are forward output, not sign-invariance requests.
            // Solve only atoms used by the retained predicate, preserving their exact program.
            var guards: [Polynomial] = [], instructions: [ExactRealCellInstruction] = []
            for instruction in program {
                try a.consumeWork(1)
                guard case .sign(let index,var relation) = instruction else {
                    try append(instruction,to:&instructions,&a); continue
                }
                let law = laws[index]
                if law.terms.isEmpty || law.terms.count == 1 && law.terms[0].powers[0] == 0 {
                    let sign = try law.terms.first.map { try field.sign(of:$0.coefficient,using:&a) } ?? .zero
                    try append(.literal(relation.accepts(sign)),to:&instructions,&a); continue
                }
                let normalized = try ring.normalized(law,using:&a)
                let leading = law.terms[0].coefficient
                guard try ring.equals(law,ring.scaled(normalized,by:leading,using:&a),using:&a) else {
                    throw ExactGeometricRelationFailure.invalidCoverage
                }
                if try field.sign(of:leading,using:&a) == .negative {
                    switch relation {
                    case .less:relation = .greater
                    case .lessOrEqual:relation = .greaterOrEqual
                    case .greater:relation = .less
                    case .greaterOrEqual:relation = .lessOrEqual
                    case .equal,.notEqual:break
                    }
                }
                var slot: Int?
                for i in guards.indices { if try ring.equals(guards[i],normalized,using:&a) { slot = i; break } }
                if slot == nil { slot = guards.count; try append(normalized,to:&guards,&a) }
                try append(.sign(polynomial:slot!,relation:relation),to:&instructions,&a)
            }
            func equal(_ lhs: Polynomial,_ rhs: Polynomial) throws -> Bool {
                guard lhs.terms.count == rhs.terms.count else { return false }
                for i in lhs.terms.indices {
                    try a.consumeWork(1)
                    guard lhs.terms[i].powers == rhs.terms[i].powers,
                        try field.compare(lhs.terms[i].coefficient,rhs.terms[i].coefficient,using:&a) == .equal else { return false }
                }
                return true
            }
            func sameDomain(_ lhs: ExactRealRootInterval<Field.Value>,_ rhs: ExactRealRootInterval<Field.Value>) throws -> Bool {
                guard lhs.includesLower == rhs.includesLower,lhs.includesUpper == rhs.includesUpper else { return false }
                func sameBound(_ x: ExactRealRootBound<Field.Value>,_ y: ExactRealRootBound<Field.Value>) throws -> Bool {
                    switch (x,y) {
                    case (.negativeInfinity,.negativeInfinity),(.positiveInfinity,.positiveInfinity):return true
                    case (.finite(let x),.finite(let y)):return try field.compare(x,y,using:&a) == .equal
                    default:return false
                    }
                }
                return try sameBound(lhs.lower,rhs.lower) && sameBound(lhs.upper,rhs.upper)
            }
            var reused = false
            if let previousPartition, previousPartition.source.polynomials.count == guards.count,
                try sameDomain(previousPartition.source.domains[0],old.domains[1]) {
                reused = true
                for i in guards.indices {
                    if try !equal(guards[i],previousPartition.source.polynomials[i]) { reused = false; break }
                }
            }
            let partition: ExactRealCellPartition<Base>
            if reused,let previousPartition {
                try a.admitDepth(value:previousPartition.depth.value,coefficient:previousPartition.depth.coefficient)
                partition = previousPartition
            } else {
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactRealRootInterval<Field.Value>.self))
                let selectedSource = try cells.bind(polynomials:guards,domains:[old.domains[1]],using:&a)
                partition = try cells.decompose(selectedSource,limits:cellLimits,using:&a)
            }
            previousPartition = partition
            let selectionDomain = try ExactRealCellDomain<Base>(retaining:partition.source,using:&a)
            let selectedPredicate = try selectionDomain.predicate(instructions:instructions,for:partition.source,using:&a)
            let selected = try selectionDomain.select(partition,matching:selectedPredicate,using:&a)
            let solver = ExactParametricRelationDomain<Base,ExactRealCellDomain<Base>,ExactRealTopology<Base>>(cells:ExactRealCellDomain<Base>.self,topology:.init(cells:ExactRealCellDomain<Base>.self))
            let graph = try solver.graph(from:predicate,parameterCount:1,using:&a)
            let map = try DefaultExactGeometricGraphRelationResolver<Base>().mapEvidence(graph,&a)
            guard map.constant || map.finite else { throw ExactGeometricRelationFailure.invalidCoverage }
            let coordinates = g.evidence.originalCoordinates
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:coordinates.count,of:Polynomial.self))
            var lift: [Polynomial] = []; lift.reserveCapacity(coordinates.count)
            let oldRing = try ExactPolynomialDomain(field:field,variableCount:2,using:&a)
            for law in coordinates {
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:law.termCount,of:ExactPolynomialTerm<Field.Value>.self))
                var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(law.termCount)
                for term in law.terms {
                    try a.consumeWork(1); terms.append(.init(powers:term.powers,coefficient:try field.importingBase(term.coefficient,using:&a)))
                }
                lift.append(try specialize(oldRing.polynomial(terms:terms,using:&a)))
            }
            pieces.append(.init(templateOrdinal:surface.coverage.graphTemplates[index],planeFirst:planeFirst,selection:selected,
                polynomials:ring,originalCoordinates:lift,homogeneous:position,planeNumerators:planeUV,
                derivativeNumerators:map.proofs,isConstant:map.constant,owner:owner))
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalRollingPlaneGeometricRelations.self))
        let result = OriginalRollingPlaneGeometricRelations(owner:owner,surfacePlaneSections:pieces)
        try a.checkpoint(); return result
    }
    private func append<T,A: ExactScalarAdmission & ~Copyable>(_ value: T,to array: inout [T],_ a: inout A) throws {
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:T.self)); array.append(value)
    }
}
