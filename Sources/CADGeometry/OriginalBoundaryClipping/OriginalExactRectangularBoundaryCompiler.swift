import CADCore

/// A complete four-edge law theorem; an enclosing box alone grants no authority.
struct OriginalExactRectangularBoundaryCompiler {
    typealias Base = ExactRationalScalarDomain
    typealias Compiler = OriginalExactBoundaryCompiler<Base>
    typealias Field = Compiler.Field
    typealias Polynomial = Compiler.Polynomial
    var compiler: Compiler
    let root: Int
    let spanRoots: [Int]
    let spans: [OriginalNativeBoundaryDomain.SpanReference]

    static func prepare<A: ExactScalarAdmission & ~Copyable>(boundary: OriginalExactNativeBoundaryDomain,
        part: OriginalExactBoundaryPart, scope: Compiler.NativeScope,
        selection: OriginalNativeBoundaryDomain.Selection, limits: OriginalDomainIdentityLimits, using a: inout A
    ) throws -> Self? {
        guard scope.replacements.isEmpty else { return nil }
        var c = try Compiler(part.relation,using:&a)
        let f = c.field, ring = c.cells.polynomials
        for loop in boundary.preparedLoops {
            guard loop.segments.count == 4,loop.segments.allSatisfy({ $0.quadratic == nil }) else { return nil }
        }
        let t = DefaultOriginalParameterTransporter<BSplineSurface3D,Field>()
        let forward = try t.inverse(part.surface.inverse,limits:limits,using:&a)
        let view = try t.affineCoordinates(of:forward,limits:limits,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Polynomial.self))
        var uv: [Polynomial] = []; uv.reserveCapacity(2)
        for axis in 0..<2 {
            try a.consumeWork(1)
            uv.append(try ring.adding(ring.scaled(ring.variable(part.uAxis+view.permutation[axis],using:&a),
                by:view.gains[axis],using:&a),ring.constant(view.offsets[axis],using:&a),using:&a))
        }
        let domains = part.relation.original.predicate.source.domains
        func known(_ p: Polynomial, _ relation: ExactRealCellSignRelation, using a: inout A) throws -> Bool? {
            var lo = try f.integer(0,using:&a), hi = lo
            for term in p.terms {
                try a.consumeWork(1)
                var axis: Int?
                for i in term.powers.indices where term.powers[i] != 0 {
                    try a.consumeWork(1)
                    guard term.powers[i] == 1,axis == nil else { return nil }; axis = i
                }
                guard let axis else { lo = try f.adding(lo,term.coefficient,using:&a); hi = try f.adding(hi,term.coefficient,using:&a); continue }
                guard domains.indices.contains(axis),!domains[axis].isEmpty,
                    case .finite(let lower) = domains[axis].lower,case .finite(let upper) = domains[axis].upper else { return nil }
                let positive = try f.sign(of:term.coefficient,using:&a) != .negative
                lo = try f.adding(lo,f.multiplying(term.coefficient,positive ? lower:upper,using:&a),using:&a)
                hi = try f.adding(hi,f.multiplying(term.coefficient,positive ? upper:lower,using:&a),using:&a)
            }
            let lower = try f.sign(of:lo,using:&a), upper = try f.sign(of:hi,using:&a)
            switch relation {
            case .equal: if lower == .zero && upper == .zero { return true }; if lower == .positive || upper == .negative { return false }
            case .notEqual: if lower == .positive || upper == .negative { return true }; if lower == .zero && upper == .zero { return false }
            case .greater: if lower == .positive { return true }; if upper != .positive { return false }
            case .greaterOrEqual: if lower != .negative { return true }; if upper == .negative { return false }
            case .less: if upper == .negative { return true }; if lower != .negative { return false }
            case .lessOrEqual: if upper != .positive { return true }; if lower == .positive { return false }
            }
            return nil
        }
        func cut(_ axis: Int,_ value: Field.Value,using a: inout A) throws -> Polynomial {
            try ring.subtracting(uv[axis],ring.constant(value,using:&a),using:&a)
        }
        func atom(_ p: Polynomial,_ relation: ExactRealCellSignRelation,compiler c: inout Compiler,using a: inout A) throws -> Int {
            if let value = try known(p,relation,using:&a) { return try c.node(.literal(value),&a) }
            return try c.atom(p,relation,&a)
        }
        var outer = try c.node(.literal(false),&a), inner = try c.node(.literal(false),&a)
        var anyBoundary = try c.node(.literal(false),&a), roots: [Int] = [], refs: [OriginalNativeBoundaryDomain.SpanReference] = []
        for loop in boundary.preparedLoops {
            let segments = loop.segments
            // All four authored straight laws and their directed connections prove the rectangle.
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Field.Value.self))
            var lower = segments[0].first, upper = lower
            for segment in segments {
                for axis in 0..<2 {
                    try a.consumeWork(1)
                    if try f.compare(segment.first[axis],lower[axis],using:&a) == .less { lower[axis] = segment.first[axis] }
                    if try f.compare(segment.first[axis],upper[axis],using:&a) == .greater { upper[axis] = segment.first[axis] }
                }
            }
            guard try f.compare(lower[0],upper[0],using:&a) == .less,
                try f.compare(lower[1],upper[1],using:&a) == .less else { return nil }
            var sides = 0
            for i in segments.indices {
                let segment = segments[i],next = segments[(i+1)%4]
                for axis in 0..<2 {
                    try a.consumeWork(1)
                    guard try f.compare(segment.last[axis],next.first[axis],using:&a) == .equal else { return nil }
                }
                let vertical = try f.compare(segment.first[0],segment.last[0],using:&a) == .equal
                let axis = vertical ? 0:1, tangent = 1-axis
                guard try f.compare(segment.first[axis],segment.last[axis],using:&a) == .equal else { return nil }
                let low = try f.compare(segment.first[axis],lower[axis],using:&a) == .equal
                let high = try f.compare(segment.first[axis],upper[axis],using:&a) == .equal
                guard low || high else { return nil }
                let firstLow = try f.compare(segment.first[tangent],lower[tangent],using:&a) == .equal
                guard try f.compare(segment.first[tangent],firstLow ? lower[tangent]:upper[tangent],using:&a) == .equal,
                    try f.compare(segment.last[tangent],firstLow ? upper[tangent]:lower[tangent],using:&a) == .equal else { return nil }
                let mask = 1 << (axis*2+(low ? 0:1)); guard sides & mask == 0 else { return nil }; sides |= mask
            }
            guard sides == 15 else { return nil }
            var closed = try c.node(.literal(true),&a), open = closed
            for axis in 0..<2 {
                let lp = try cut(axis,lower[axis],using:&a), up = try cut(axis,upper[axis],using:&a)
                closed = try c.and(c.and(closed,atom(lp,.greaterOrEqual,compiler:&c,using:&a),&a),atom(up,.lessOrEqual,compiler:&c,using:&a),&a)
                open = try c.and(c.and(open,atom(lp,.greater,compiler:&c,using:&a),&a),atom(up,.less,compiler:&c,using:&a),&a)
            }
            if loop.isInner { inner = try c.or(inner,open,&a) } else { outer = try c.or(outer,closed,&a) }
            for segment in segments {
                let vertical = try f.compare(segment.first[0],segment.last[0],using:&a) == .equal
                let axis = vertical ? 0:1,tangent = 1-axis
                let plane = try cut(axis,segment.first[axis],using:&a)
                let lp = try cut(tangent,lower[tangent],using:&a), up = try cut(tangent,upper[tangent],using:&a)
                let on: Int
                if try known(plane,.equal,using:&a) == false || known(lp,.greaterOrEqual,using:&a) == false || known(up,.lessOrEqual,using:&a) == false {
                    on = try c.node(.literal(false),&a)
                } else {
                    on = try c.and(c.and(atom(plane,.equal,compiler:&c,using:&a),atom(lp,.greaterOrEqual,compiler:&c,using:&a),&a),
                        atom(up,.lessOrEqual,compiler:&c,using:&a),&a)
                }
                anyBoundary = try c.or(anyBoundary,on,&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Int.self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalNativeBoundaryDomain.SpanReference.self))
                roots.append(on); refs.append(segment.reference)
            }
        }
        let closed = try c.and(outer,c.not(inner,&a),&a), root: Int
        switch selection {
        case .closed: root = closed
        case .strictInterior: root = try c.and(closed,c.not(anyBoundary,&a),&a)
        case .boundary: root = try c.and(closed,anyBoundary,&a)
        }
        try c.canonicalizeAtoms(using:&a)
        try a.checkpoint()
        return .init(compiler:c,root:root,spanRoots:roots,spans:refs)
    }
    func boundaryReferences<A: ExactScalarAdmission & ~Copyable>(in pullback: ExactRealCellPullback<Base>,using a: inout A)
        throws -> [[OriginalNativeBoundaryDomain.SpanReference]] {
        let region = pullback.region
        let cells = try ExactRealCellDomain<Base>(retaining:region.partition.source,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:compiler.laws.count,of:Int.self))
        var indices: [Int] = []; indices.reserveCapacity(compiler.laws.count)
        for law in compiler.laws {
            let imported = try cells.polynomials.importing(law,using:&a)
            var found: Int?
            for index in region.partition.source.polynomials.indices {
                try a.consumeWork(1)
                if try cells.polynomials.equals(imported,region.partition.source.polynomials[index],using:&a) { found = index; break }
            }
            guard let found else { throw NativeExactRelationFailure.invalidDomain }; indices.append(found)
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:region.cells.count,of:[OriginalNativeBoundaryDomain.SpanReference].self))
        var result: [[OriginalNativeBoundaryDomain.SpanReference]] = []; result.reserveCapacity(region.cells.count)
        for ordinal in region.cells.indices {
            var incident: [OriginalNativeBoundaryDomain.SpanReference] = []
            if region.included[ordinal] {
                for i in spanRoots.indices {
                    let program = try compiler.instructions(spanRoots[i],&a)
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:program.count,of:Bool.self))
                    var stack: [Bool] = []; stack.reserveCapacity(program.count)
                    for instruction in program {
                        try a.consumeWork(1)
                        switch instruction {
                        case .literal(let value):stack.append(value)
                        case .sign(let index,let relation):
                            let sign = region.cells[ordinal].signs[indices[index]]
                            let accepted: Bool
                            switch relation {
                            case .equal:accepted = sign == .zero
                            case .notEqual:accepted = sign != .zero
                            case .less:accepted = sign == .negative
                            case .lessOrEqual:accepted = sign != .positive
                            case .greater:accepted = sign == .positive
                            case .greaterOrEqual:accepted = sign != .negative
                            }
                            stack.append(accepted)
                        case .not:guard let value = stack.popLast() else { throw NativeExactRelationFailure.invalidDomain };stack.append(!value)
                        case .and,.or:
                            guard let right = stack.popLast(),let left = stack.popLast() else { throw NativeExactRelationFailure.invalidDomain }
                            if case .and = instruction { stack.append(left && right) } else { stack.append(left || right) }
                        }
                    }
                    guard stack.count == 1 else { throw NativeExactRelationFailure.invalidDomain }
                    if stack[0] { try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalNativeBoundaryDomain.SpanReference.self)); incident.append(spans[i]) }
                }
            }
            result.append(incident)
        }
        try a.checkpoint(); return result
    }
}
