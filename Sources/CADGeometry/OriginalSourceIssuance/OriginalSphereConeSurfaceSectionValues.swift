import CADCore

/// Source-issued exact unit-circle position law and its two selected slants.
public struct OriginalSphereConeSurfaceSectionValues: Sendable {
    public typealias Field = OriginalCertifiedSphereConePlaneRoot.Field
    public let halfAngle: Field.Value
    public let field: Field
    public let sine: Field.Value
    public let cosine: Field.Value
    public let plusSlant: Field.Value
    public let minusSlant: Field.Value
    public let isDoubleRoot: Bool
    public let proofDepth: ExactScalarDepth
    private let sourceSine: Field.Value
    private let sourceCosine: Field.Value
    private let apex: Point3D
    static func issue<A: ExactScalarAdmission & ~Copyable>(halfAngle t: Field.Value, chart: Int,
        sourceSine: Field.Value, sourceCosine: Field.Value, apexX: Int, constant: Int,
        isDoubleRoot: Bool, using a: inout A) throws -> Self {
        let f=try Field(retaining:t,using:&a)
        return try issue(halfAngle:t,chart:chart,sourceSine:sourceSine,sourceCosine:sourceCosine,
            apex:.init(x:Double(apexX),y:0,z:-4),dx:f.integer(apexX,using:&a),dy:f.integer(0,using:&a),
            dz:f.integer(-4,using:&a),constant:f.integer(constant,using:&a),isDoubleRoot:isDoubleRoot,using:&a)
    }
    static func issue<A:ExactScalarAdmission & ~Copyable>(halfAngle t:Field.Value,chart:Int,
        sourceSine:Field.Value,sourceCosine:Field.Value,apex:Point3D,center:Point3D,radius:Double,
        isDoubleRoot:Bool = false,discriminantRoot:Bool = false,using a:inout A) throws -> Self {
        let f=try Field(retaining:t,using:&a)
        let dx=try f.subtracting(f.binary64(exactly:apex.x,using:&a),f.binary64(exactly:center.x,using:&a),using:&a)
        let dy=try f.subtracting(f.binary64(exactly:apex.y,using:&a),f.binary64(exactly:center.y,using:&a),using:&a)
        let dz=try f.subtracting(f.binary64(exactly:apex.z,using:&a),f.binary64(exactly:center.z,using:&a),using:&a)
        let r=try f.binary64(exactly:radius,using:&a)
        let constant=try f.subtracting(f.adding(f.adding(f.multiplying(dx,dx,using:&a),f.multiplying(dy,dy,using:&a),using:&a),
            f.multiplying(dz,dz,using:&a),using:&a),f.multiplying(r,r,using:&a),using:&a)
        return try issue(halfAngle:t,chart:chart,sourceSine:sourceSine,sourceCosine:sourceCosine,
            apex:apex,dx:dx,dy:dy,dz:dz,constant:constant,isDoubleRoot:isDoubleRoot,discriminantRoot:discriminantRoot,using:&a)
    }
    private static func issue<A:ExactScalarAdmission & ~Copyable>(halfAngle t:Field.Value,chart:Int,
        sourceSine:Field.Value,sourceCosine:Field.Value,apex:Point3D,dx:Field.Value,dy:Field.Value,dz:Field.Value,
        constant:Field.Value,isDoubleRoot:Bool,discriminantRoot:Bool = false,using a:inout A) throws -> Self {
        try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
            let base = try Field(retaining: t, using: &a)
            let s = try base.importing(sourceSine, using: &a), c = try base.importing(sourceCosine, using: &a)
            let one = try base.integer(1, using: &a), two = try base.integer(2, using: &a)
            let square = try base.multiplying(t, t, using: &a), q = try base.adding(one, square, using: &a)
            var sine = try base.dividing(base.multiplying(two, t, using: &a), q, using: &a)
            var cosine = try base.dividing(base.subtracting(one, square, using: &a), q, using: &a)
            if chart == 1 { sine = try base.negated(sine, using: &a); cosine = try base.negated(cosine, using: &a) }
            let xOffset=try base.importing(dx,using:&a),yOffset=try base.importing(dy,using:&a),zOffset=try base.importing(dz,using:&a)
            let coefficient=try base.importing(constant,using:&a)
            let b = try base.subtracting(base.subtracting(base.multiplying(base.multiplying(xOffset,s,using:&a),sine,using:&a),
                base.multiplying(base.multiplying(yOffset,s,using:&a),cosine,using:&a),using:&a),base.multiplying(zOffset,c,using:&a),using:&a)
            let field: Field, plus: Field.Value, minus: Field.Value
            if isDoubleRoot { field = base; plus = b; minus = b }
            else if !discriminantRoot {
                let roots = try ExactRealRootDomain(field: base, using: &a)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: ExactPolynomialTerm<Field.Value>.self))
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Int.self))
                let polynomial = try roots.polynomials.polynomial(terms: [
                    .init(powers: [2], coefficient: one),
                    .init(powers: [1], coefficient: try base.multiplying(base.integer(-2, using: &a), b, using: &a)),
                    .init(powers: [0], coefficient: coefficient)], using: &a)
                let linear=try base.multiplying(two,b,using:&a)
                let absLinear=try base.sign(of:linear,using:&a) == .negative ? base.negated(linear,using:&a):linear
                let absConstant=try base.sign(of:coefficient,using:&a) == .negative ? base.negated(coefficient,using:&a):coefficient
                let bound=try base.adding(one,base.adding(absLinear,absConstant,using:&a),using:&a)
                // The issued discriminant proof separates the two roots strictly at b.
                let scope = try roots.domain(lower:.finite(b),upper:.finite(bound),
                    includesLower:false,includesUpper:false,using:&a)
                let isolated = try roots.isolate(roots.bind(polynomial, using: &a), in: scope, limits: .init(maximumRoots: 1), using: &a)
                guard isolated.roots.count == 1 else { throw OriginalSourceIssuanceFailure.invalidSource }
                let extended = try base.adjoin(isolated.roots[0], using: &a)
                field = extended.domain; plus = extended.generator
                minus = try field.subtracting(field.importing(base.multiplying(two, b, using: &a), using: &a), plus, using: &a)
            }
            else {
                let roots=try ExactRealRootDomain(field:base,using:&a)
                let discriminant=try base.subtracting(base.multiplying(b,b,using:&a),coefficient,using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:ExactPolynomialTerm<Field.Value>.self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Int.self))
                let polynomial=try roots.polynomials.polynomial(terms:[
                    .init(powers:[2],coefficient:one),
                    .init(powers:[0],coefficient:base.negated(discriminant,using:&a))],using:&a)
                let absB=try base.sign(of:b,using:&a) == .negative ? base.negated(b,using:&a):b
                let absConstant=try base.sign(of:coefficient,using:&a) == .negative ? base.negated(coefficient,using:&a):coefficient
                let bound=try base.adding(one,base.adding(absB,absConstant,using:&a),using:&a)
                let scope=try roots.domain(lower:.finite(base.integer(0,using:&a)),upper:.finite(bound),
                    includesLower:false,includesUpper:false,using:&a)
                let isolated=try roots.isolate(roots.bind(polynomial,using:&a),in:scope,limits:.init(maximumRoots:1),using:&a)
                guard isolated.roots.count==1 else { throw OriginalSourceIssuanceFailure.invalidSource }
                let extended=try base.adjoin(isolated.roots[0],using:&a)
                field=extended.domain
                let middle=try field.importing(b,using:&a)
                plus=try field.adding(middle,extended.generator,using:&a)
                minus=try field.subtracting(middle,extended.generator,using:&a)
            }
            let h = try field.importing(t, using: &a), ss = try field.importing(sine, using: &a), cc = try field.importing(cosine, using: &a)
            let sourceSine = try field.importing(s, using: &a), sourceCosine = try field.importing(c, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
            let value = Self(halfAngle: h, field: field, sine: ss, cosine: cc, plusSlant: plus, minusSlant: minus,
                isDoubleRoot: isDoubleRoot, proofDepth: try a.depth, sourceSine: sourceSine, sourceCosine: sourceCosine, apex: apex)
            try a.checkpoint(); return value
        }
    }
    static func endpoint<A:ExactScalarAdmission & ~Copyable>(halfAngle:Field.Value,sine:Field.Value,cosine:Field.Value,
        slant:Field.Value,sourceSine:Field.Value,sourceCosine:Field.Value,apex:Point3D,using a:inout A) throws -> Self {
        try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
            let f=try Field(retaining:halfAngle,using:&a)
            let s=try f.importing(sine,using:&a),c=try f.importing(cosine,using:&a),root=try f.importing(slant,using:&a)
            let ss=try f.importing(sourceSine,using:&a),cc=try f.importing(sourceCosine,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Self.self))
            let value=Self(halfAngle:halfAngle,field:f,sine:s,cosine:c,plusSlant:root,minusSlant:root,
                isDoubleRoot:true,proofDepth:try a.depth,sourceSine:ss,sourceCosine:cc,apex:apex)
            try a.checkpoint();return value
        }
    }
    public func position<A: ExactScalarAdmission & ~Copyable>(branch: Int, using a: inout A)
        throws -> (slant: Field.Value, x: Field.Value, y: Field.Value, z: Field.Value) {
        try a.checkpoint(); try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        guard branch == 0 || branch == 1 else { throw OriginalSourceIssuanceFailure.invalidSource }
        let f = field, slant = branch == 0 ? plusSlant : minusSlant
        let radial = try f.multiplying(sourceSine, slant, using: &a)
        let x = try f.subtracting(f.binary64(exactly:apex.x,using:&a), f.multiplying(radial, sine, using: &a), using: &a)
        let y = try f.adding(f.binary64(exactly:apex.y,using:&a),f.multiplying(radial,cosine,using:&a),using:&a)
        let z = try f.adding(f.binary64(exactly:apex.z,using:&a), f.multiplying(sourceCosine, slant, using: &a), using: &a)
        try a.checkpoint(); return (slant, x, y, z)
    }
}
