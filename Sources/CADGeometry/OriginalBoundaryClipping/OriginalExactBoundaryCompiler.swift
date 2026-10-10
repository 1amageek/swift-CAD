#if NATIVE_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
import SourceGeometryAdapters
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import enum CADGeometry.SurfaceParameterCurve
@testable import class CADGeometry.OriginalNativeBoundaryDomain
#endif

import CADCore

/// Query-local exact winding compilation in the retained L5 parameter ring.
struct OriginalExactBoundaryCompiler {
    typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    typealias Polynomial = ExactPolynomial<Field>
    enum Node { case literal(Bool),sign(Int,ExactRealCellSignRelation),not(Int),and(Int,Int),or(Int,Int) }
    struct Segment {
        let first: [Field.Value],last: [Field.Value]
        let reference: OriginalNativeBoundaryDomain.SpanReference
    }
    let cells: ExactRealCellDomain<ExactRationalScalarDomain>
    let field: Field
    var laws: [Polynomial] = []
    private var nodes: [Node] = []
    private var boundaryNodes: [Int] = []
    private var references: [OriginalNativeBoundaryDomain.SpanReference] = []

    init<A: ExactScalarAdmission & ~Copyable>(_ raw: ExactParametricRelation<ExactRationalScalarDomain>,using a: inout A) throws {
        cells = try .init(retaining:raw.original.predicate.source,using:&a)
        field = try cells.coefficientField(of:raw.original.predicate.source,using:&a)
    }
    init<A: ExactScalarAdmission & ~Copyable>(field: Field,using a: inout A) throws {
        self.field = field;cells = try .init(field:field,variableCount:2,using:&a)
    }
    func validate<A: ExactScalarAdmission & ~Copyable>(_ loops: [OriginalNativeBoundaryDomain.Loop],using a: inout A) throws {
        for (index,loop) in loops.enumerated() { _ = try segments(loop,ordinal:index,&a) }
    }
    mutating func node<A: ExactScalarAdmission & ~Copyable>(_ value: Node,_ a: inout A) throws -> Int {
        try a.consumeWork(1)
        guard !nodes.count.addingReportingOverflow(1).overflow else { throw ExactScalarFailure.countOverflow }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Node.self))
        nodes.append(value);return nodes.count-1
    }
    mutating func and<A: ExactScalarAdmission & ~Copyable>(_ left: Int,_ right: Int,_ a: inout A) throws -> Int {
        if left == right { return left }
        if case .literal(let value) = nodes[left] { return value ? right:left }
        if case .literal(let value) = nodes[right] { return value ? left:right }
        return try node(.and(left,right),&a)
    }
    mutating func or<A: ExactScalarAdmission & ~Copyable>(_ left: Int,_ right: Int,_ a: inout A) throws -> Int {
        if left == right { return left }
        if case .literal(let value) = nodes[left] { return value ? left:right }
        if case .literal(let value) = nodes[right] { return value ? right:left }
        return try node(.or(left,right),&a)
    }
    mutating func not<A: ExactScalarAdmission & ~Copyable>(_ index: Int,_ a: inout A) throws -> Int {
        if case .literal(let value) = nodes[index] { return try node(.literal(!value),&a) }
        return try node(.not(index),&a)
    }
    mutating func atom<A: ExactScalarAdmission & ~Copyable>(_ law: Polynomial,_ sign: ExactRealCellSignRelation,_ a: inout A) throws -> Int {
        for index in laws.indices {
            try a.consumeWork(1)
            if try cells.polynomials.equals(law,laws[index],using:&a) { return try node(.sign(index,sign),&a) }
        }
        guard !laws.count.addingReportingOverflow(1).overflow else { throw ExactScalarFailure.countOverflow }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Polynomial.self))
        laws.append(law);return try node(.sign(laws.count-1,sign),&a)
    }
    private func scalar<A: ExactScalarAdmission & ~Copyable>(_ value: Double,_ a: inout A) throws -> Field.Value {
        try field.importingBase(ExactRationalScalarDomain().binary64(exactly:value,using:&a),using:&a)
    }
    private func point<A: ExactScalarAdmission & ~Copyable>(_ u: Double,_ v: Double,_ a: inout A) throws -> [Field.Value] {
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Field.Value.self))
        return [try scalar(u,&a),try scalar(v,&a)]
    }
    private func segments<A: ExactScalarAdmission & ~Copyable>(_ loop: OriginalNativeBoundaryDomain.Loop,
        ordinal: Int,_ a: inout A) throws -> [Segment] {
        var result: [Segment] = []
        func append(_ first: [Field.Value],_ last: [Field.Value],curve: Int,segment: Int) throws {
            try a.consumeWork(1)
            guard try field.compare(first[0],last[0],using:&a) != .equal || field.compare(first[1],last[1],using:&a) != .equal else {
                throw NativeExactRelationFailure.invalidDomain
            }
            if let previous = result.last {
                guard try field.compare(previous.last[0],first[0],using:&a) == .equal,
                    try field.compare(previous.last[1],first[1],using:&a) == .equal else { throw NativeExactRelationFailure.invalidDomain }
            }
            guard !result.count.addingReportingOverflow(1).overflow else { throw ExactScalarFailure.countOverflow }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Segment.self))
            result.append(.init(first:first,last:last,reference:.init(loopOrdinal:ordinal,curveOrdinal:curve,segmentOrdinal:segment)))
        }
        for (index,curve) in loop.curves.enumerated() {
            try a.consumeWork(1)
            switch curve {
            case .constantU(let u,let start,let end): try append(point(u,start,&a),point(u,end,&a),curve:index,segment:0)
            case .constantV(let v,let start,let end): try append(point(start,v,&a),point(end,v,&a),curve:index,segment:0)
            case .affine(let origin,let direction,let start,let end):
                let o = try point(origin.x,origin.y,&a),d = try point(direction.x,direction.y,&a)
                let low = try scalar(start,&a),high = try scalar(end,&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Field.Value.self))
                let first = [try field.adding(o[0],field.multiplying(d[0],low,using:&a),using:&a),
                    try field.adding(o[1],field.multiplying(d[1],low,using:&a),using:&a)]
                let last = [try field.adding(o[0],field.multiplying(d[0],high,using:&a),using:&a),
                    try field.adding(o[1],field.multiplying(d[1],high,using:&a),using:&a)]
                try append(first,last,curve:index,segment:0)
            case .polyline(let values):
                guard values.count >= 2 else { throw NativeExactRelationFailure.invalidDomain }
                for segment in 0..<(values.count-1) {
                    try append(point(values[segment].u,values[segment].v,&a),point(values[segment+1].u,values[segment+1].v,&a),curve:index,segment:segment)
                }
            default:
                // FIXME(INCOMPLETE_IMPLEMENTATION): This additive Native L5 face consumer
                // requires an original winding law for rational/implicit/nonrational pcurves.
                // It cannot report successful clipping until their whole directed cover is issued.
                throw NativeExactRelationFailure.unsupportedCoverage
            }
        }
        guard let first = result.first,let last = result.last,
            try field.compare(first.first[0],last.last[0],using:&a) == .equal,
            try field.compare(first.first[1],last.last[1],using:&a) == .equal else { throw NativeExactRelationFailure.invalidDomain }
        return result
    }
    mutating func boundary<A: ExactScalarAdmission & ~Copyable>(_ domain: OriginalExactNativeBoundaryDomain,
        part: OriginalExactBoundaryPart,selection: OriginalNativeBoundaryDomain.Selection,
        limits: OriginalDomainIdentityLimits,_ a: inout A) throws -> Int {
        let transporter = DefaultOriginalParameterTransporter<BSplineSurface3D,Field>()
        let forward = try transporter.inverse(part.surface.inverse,limits:limits,using:&a)
        let coordinates = try transporter.affineCoordinates(of:forward,limits:limits,using:&a)
        let ring = cells.polynomials
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Polynomial.self))
        var uv: [Polynomial] = [];uv.reserveCapacity(2)
        for axis in 0..<2 {
            try a.consumeWork(1)
            uv.append(try ring.adding(ring.scaled(ring.variable(part.uAxis+coordinates.permutation[axis],using:&a),
                by:coordinates.gains[axis],using:&a),ring.constant(coordinates.offsets[axis],using:&a),using:&a))
        }
        var outer = try node(.literal(false),&a),inner = try node(.literal(false),&a),anyBoundary = try node(.literal(false),&a)
        for (ordinal,loop) in domain.loops.enumerated() {
            let spans = try segments(loop,ordinal:ordinal,&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:spans.count,of:(Int,Int).self))
            var crossings: [(node:Int,delta:Int)] = []
            var loopBoundary = try node(.literal(false),&a)
            for span in spans {
                try a.consumeWork(1)
                let du = try field.subtracting(span.last[0],span.first[0],using:&a),dv = try field.subtracting(span.last[1],span.first[1],using:&a)
                let x = try ring.subtracting(uv[0],ring.constant(span.first[0],using:&a),using:&a)
                let y = try ring.subtracting(uv[1],ring.constant(span.first[1],using:&a),using:&a)
                let cross = try ring.subtracting(ring.scaled(y,by:du,using:&a),ring.scaled(x,by:dv,using:&a),using:&a)
                let vertical = try field.sign(of:du,using:&a) == .zero
                let coordinate = vertical ? uv[1]:uv[0],start = span.first[vertical ? 1:0],end = span.last[vertical ? 1:0]
                let ascending = try field.compare(start,end,using:&a) != .greater
                let lower = try ring.subtracting(coordinate,ring.constant(ascending ? start:end,using:&a),using:&a)
                let upper = try ring.subtracting(coordinate,ring.constant(ascending ? end:start,using:&a),using:&a)
                let on = try and(and(atom(cross,.equal,&a),atom(lower,.greaterOrEqual,&a),&a),atom(upper,.lessOrEqual,&a),&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Int.self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalNativeBoundaryDomain.SpanReference.self))
                boundaryNodes.append(on);references.append(span.reference)
                loopBoundary = try or(loopBoundary,on,&a)
                let direction = try field.sign(of:dv,using:&a)
                if direction != .zero {
                    let first = try ring.subtracting(uv[1],ring.constant(direction == .positive ? span.first[1]:span.last[1],using:&a),using:&a)
                    let last = try ring.subtracting(uv[1],ring.constant(direction == .positive ? span.last[1]:span.first[1],using:&a),using:&a)
                    let crossing = try and(and(atom(first,.greaterOrEqual,&a),atom(last,.less,&a),&a),
                        atom(cross,direction == .positive ? .greater:.less,&a),&a)
                    crossings.append((crossing,direction == .positive ? 1:-1))
                }
            }
            let winding = try nonzeroWinding(crossings,&a)
            anyBoundary = try or(anyBoundary,loopBoundary,&a)
            if loop.isInner { inner = try or(inner,and(winding,not(loopBoundary,&a),&a),&a) }
            else { outer = try or(outer,or(winding,loopBoundary,&a),&a) }
        }
        let closed = try and(outer,not(inner,&a),&a)
        switch selection {
        case .closed:return closed
        case .strictInterior:return try and(closed,not(anyBoundary,&a),&a)
        case .boundary:return try and(closed,anyBoundary,&a)
        }
    }
    private mutating func nonzeroWinding<A: ExactScalarAdmission & ~Copyable>(_ crossings: [(node:Int,delta:Int)],_ a: inout A) throws -> Int {
        let count = crossings.count,twice = count.multipliedReportingOverflow(by:2)
        let capacity = twice.partialValue.addingReportingOverflow(1)
        guard !twice.overflow,!capacity.overflow else { throw ExactScalarFailure.countOverflow }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:capacity.partialValue,of:Int.self))
        var next: [Int] = [];next.reserveCapacity(capacity.partialValue)
        for sum in -count...count { next.append(try node(.literal(sum != 0),&a)) }
        if count == 0 { return next[0] }
        for index in crossings.indices.reversed() {
            let size = index*2+1
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:size,of:Int.self))
            var current: [Int] = [];current.reserveCapacity(size)
            let crossing = crossings[index],inverse = try not(crossing.node,&a)
            for sum in -index...index {
                let offset = index+1
                current.append(try or(and(crossing.node,next[sum+crossing.delta+offset],&a),and(inverse,next[sum+offset],&a),&a))
            }
            next = current
        }
        return next[0]
    }
    func instructions<A: ExactScalarAdmission & ~Copyable>(_ root: Int,_ a: inout A) throws -> [ExactRealCellInstruction] {
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:(Int,Bool).self))
        var pending: [(index:Int,finished:Bool)] = [(root,false)],result: [ExactRealCellInstruction] = []
        while let item = pending.popLast() {
            try a.consumeWork(1)
            let instruction: ExactRealCellInstruction?
            switch nodes[item.index] {
            case .literal(let value):instruction = .literal(value)
            case .sign(let index,let relation):instruction = .sign(polynomial:index,relation:relation)
            case .not(let child):
                if item.finished { instruction = .not }
                else { try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:(Int,Bool).self));pending.append((item.index,true));pending.append((child,false));instruction = nil }
            case .and(let left,let right),.or(let left,let right):
                if item.finished { if case .and = nodes[item.index] { instruction = .and } else { instruction = .or } }
                else { try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:(Int,Bool).self));pending.append((item.index,true));pending.append((right,false));pending.append((left,false));instruction = nil }
            }
            if let instruction { try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactRealCellInstruction.self));result.append(instruction) }
        }
        return result
    }
    func boundaryReferences<A: ExactScalarAdmission & ~Copyable>(in refinement: NativeExactParameterRefinement,
        using a: inout A) throws -> [[OriginalNativeBoundaryDomain.SpanReference]] {
        let region = refinement.pullback.region
        var included = false
        for value in region.included { try a.consumeWork(1);if value { included = true;break } }
        if !included {
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:region.cells.count,of:[OriginalNativeBoundaryDomain.SpanReference].self))
            return Array(repeating:[],count:region.cells.count)
        }
        let domain = try ExactRealCellDomain<ExactRationalScalarDomain>(retaining:region.partition.source,using:&a)
        try a.admitDepth(value:region.depth.value,coefficient:region.depth.coefficient)
        let scalar = try domain.coefficientField(of:region.partition.source,using:&a)
        let polynomials = domain.polynomials
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:laws.count,of:Int.self))
        var ordinals: [Int] = [];ordinals.reserveCapacity(laws.count)
        for law in laws {
            try a.consumeWork(1)
            var transported = try polynomials.importing(law,using:&a)
            // L4's sealed reductions certify ordinal-preserving substitutions over
            // this complete retained singleton box, not global polynomial equality.
            for proof in region.reductions {
                try a.consumeWork(1)
                guard let box = proof.domainRestriction,!box.isEmpty,box.includesLower,box.includesUpper,
                    proof.variable >= 0,proof.variable < region.partition.source.domains.count,
                    proof.originalAtoms.count == proof.derivedAtoms.count,
                    case .finite(let lo) = box.lower,case .finite(let hi) = box.upper,
                    try scalar.compare(lo,hi,using:&a) == .equal else { throw NativeExactRelationFailure.invalidDomain }
                let scope = region.partition.source.domains[proof.variable]
                guard !scope.isEmpty,scope.includesLower,scope.includesUpper,
                    case .finite(let scopeLo) = scope.lower,case .finite(let scopeHi) = scope.upper,
                    try scalar.compare(lo,scopeLo,using:&a) == .equal,
                    try scalar.compare(hi,scopeHi,using:&a) == .equal else { throw NativeExactRelationFailure.invalidDomain }
                var derived: Polynomial? = nil
                for index in proof.originalAtoms.indices {
                    try a.consumeWork(1)
                    if try polynomials.equals(transported,polynomials.importing(proof.originalAtoms[index],using:&a),using:&a) {
                        derived = try polynomials.importing(proof.derivedAtoms[index],using:&a)
                        break
                    }
                }
                guard let derived else { throw NativeExactRelationFailure.invalidDomain }
                transported = derived
            }
            var ordinal: Int? = nil
            for index in region.partition.source.polynomials.indices {
                try a.consumeWork(1)
                if try polynomials.equals(transported,region.partition.source.polynomials[index],using:&a) { ordinal = index;break }
            }
            guard let ordinal else { throw NativeExactRelationFailure.invalidDomain }
            ordinals.append(ordinal)
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:region.cells.count,of:[OriginalNativeBoundaryDomain.SpanReference].self))
        var result: [[OriginalNativeBoundaryDomain.SpanReference]] = [];result.reserveCapacity(region.cells.count)
        for index in region.cells.indices {
            try a.consumeWork(1)
            var spans: [OriginalNativeBoundaryDomain.SpanReference] = []
            if region.included[index] {
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:ordinals.count,of:ExactSign.self))
                var signs: [ExactSign] = [];signs.reserveCapacity(ordinals.count)
                // Original input-law signs have L3's whole-cell lifting authority.
                // Auxiliary projection/derivative signs and samples are never used.
                for ordinal in ordinals {
                    try a.consumeWork(1)
                    guard region.cells[index].signs.indices.contains(ordinal) else { throw NativeExactRelationFailure.invalidDomain }
                    signs.append(region.cells[index].signs[ordinal])
                }
                let values = try values(signs,&a)
                for ordinal in references.indices where values[boundaryNodes[ordinal]] {
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalNativeBoundaryDomain.SpanReference.self))
                    spans.append(references[ordinal])
                }
            }
            result.append(spans)
        }
        return result
    }
    private func values<A: ExactScalarAdmission & ~Copyable>(_ signs: [ExactSign],_ a: inout A) throws -> [Bool] {
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:nodes.count,of:Bool.self))
        var result: [Bool] = [];result.reserveCapacity(nodes.count)
        for node in nodes {
            try a.consumeWork(1)
            let value: Bool
            switch node {
            case .literal(let constant):value = constant
            case .sign(let index,let relation):
                switch relation {
                case .equal:value = signs[index] == .zero
                case .notEqual:value = signs[index] != .zero
                case .less:value = signs[index] == .negative
                case .lessOrEqual:value = signs[index] != .positive
                case .greater:value = signs[index] == .positive
                case .greaterOrEqual:value = signs[index] != .negative
                }
            case .not(let child):value = !result[child]
            case .and(let left,let right):value = result[left] && result[right]
            case .or(let left,let right):value = result[left] || result[right]
            }
            result.append(value)
        }
        return result
    }
}
