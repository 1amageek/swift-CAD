import L0
import L1
import SourceIssuer

struct ConeInput: OriginalConeImageReading {
    let physicalHalfAngle: Double
    var origin: [Double]
    var matrix: [Double]
    func center(in axis: Int) -> Double { origin[axis] }
    func frame(row: Int, column: Int) -> Double { matrix[row*3+column] }
}
struct ConeProvider: OriginalSourceSnapshotting {
    func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing ConeInput,
        limits:OriginalSourceIssuanceLimits,using a:inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<ConeInput> {
        do {
            try a.consumeWork(1)
            guard input.origin.count == 3, input.matrix.count == 9,
                input.physicalHalfAngle > 0, input.physicalHalfAngle < 1.5 else {
                throw OriginalSourceIssuanceFailure.invalidSource
            }
            for value in input.origin + input.matrix {
                try a.consumeWork(1)
                guard value.isFinite else { throw OriginalSourceIssuanceFailure.invalidSource }
            }
            return .init(original:copy input,sourceDepth:0)
        } catch { throw .sourceRejected(error) }
    }
}
extension SourceFixtures {
    typealias ConeField = OriginalPhysicalAngleScalarDomain
    typealias ConeLaw = OriginalImplicitImageReceipt<ConeInput,OriginalPrimitiveImageSelection,ConeField>
    static func cone<A:ExactScalarAdmission & ~Copyable>(_ input:ConeInput,using a:inout A) throws -> ConeLaw {
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:0)
        let binding = try DefaultOriginalSourceBindingIssuer(provider:ConeProvider()).bind(input,limits:limits,using:&a)
        let chart = try binding.chart(OriginalPrimitiveImageSelection(),limits:limits,using:&a)
        let field = try ConeField(originalRadians:input.physicalHalfAngle,using:&a)
        return try DefaultOriginalConeImageIssuer<ConeInput,ConeField>().issue(
            source:binding,chart:chart,field:field,limits:limits,using:&a)
    }
    public static func coneImages() throws {
        var a = try TraceAdmission()
        var input = ConeInput(physicalHalfAngle:0.5,origin:[1,-2,3],matrix:[1,1,0,0,1,0,0,0,2])
        let law = try cone(input,using:&a), r = law.polynomials, f = law.field
        let x = try r.variable(0,using:&a), y = try r.variable(1,using:&a), z = try r.variable(2,using:&a)
        let qx = try r.subtracting(r.subtracting(x,y,using:&a),r.constant(f.integer(3,using:&a),using:&a),using:&a)
        let qy = try r.adding(y,r.constant(f.integer(2,using:&a),using:&a),using:&a)
        let qz = try r.scaled(r.subtracting(z,r.constant(f.integer(3,using:&a),using:&a),using:&a),
            by:f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a),using:&a)
        let s = try f.sine(using:&a), c = try f.cosine(using:&a)
        let expected = try r.subtracting(r.scaled(r.adding(r.multiplying(qx,qx,using:&a),
            r.multiplying(qy,qy,using:&a),using:&a),by:f.multiplying(c,c,using:&a),using:&a),
            r.scaled(r.multiplying(qz,qz,using:&a),by:f.multiplying(s,s,using:&a),using:&a),using:&a)
        try require(try r.equals(law.equation,expected,using:&a))
        // Algebraic identity verifies every v in both nappes, not a residual test.
        // For u=0 the original point is apex + B*(v*sin(a),0,v*cos(a)).
        for sign in [-1,0,1] {
            let v = try f.integer(sign,using:&a)
            let vs = try f.multiplying(v,s,using:&a), vc = try f.multiplying(v,c,using:&a)
            let point = [try f.adding(f.integer(1,using:&a),vs,using:&a),
                try f.integer(-2,using:&a),try f.adding(f.integer(3,using:&a),
                    f.multiplying(f.integer(2,using:&a),vc,using:&a),using:&a)]
            try require(try f.sign(of:r.evaluated(law.equation,at:point,using:&a).value,using:&a) == .zero)
        }
        let off = try r.evaluated(law.equation,at:[f.integer(2,using:&a),f.integer(-2,using:&a),f.integer(3,using:&a)],using:&a)
        try require(try f.sign(of:off.value,using:&a) == .positive)
        input.origin[0] = 999
        try require(law.source.original.origin[0] == 1 && law.source.original.physicalHalfAngle == 0.5)
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:0)
        let binding = law.source
        let wrong = try ConeField(originalRadians:1,using:&a)
        do {
            _ = try DefaultOriginalConeImageIssuer<ConeInput,ConeField>().issue(source:binding,
                chart:law.chart,field:wrong,limits:limits,using:&a)
            throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.scalar(.incompatibleDomain) {}
        let foreign = try DefaultOriginalSourceBindingIssuer(provider:ConeProvider()).bind(binding.original,limits:limits,using:&a)
        do {
            _ = try DefaultOriginalConeImageIssuer<ConeInput,ConeField>().issue(source:foreign,
                chart:law.chart,field:f,limits:limits,using:&a)
            throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.foreignBinding {}
        var singular = binding.original; singular.matrix[8] = 0
        do { _ = try cone(singular,using:&a); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.invalidSource {}
        var measured = try TraceAdmission()
        _ = try cone(binding.original,using:&measured)
        var lowWork = try TraceAdmission(work:measured.work-1)
        do { _ = try cone(binding.original,using:&lowWork); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.work))) {}
        var lowStorage = try TraceAdmission(storage:measured.storageBytes-1)
        do { _ = try cone(binding.original,using:&lowStorage); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.storage))) {}
        var cancel = try TraceAdmission(cancelAtStorage:measured.storageCalls)
        do { _ = try cone(binding.original,using:&cancel); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.cancelled)) {}
        print("PASS exact physical-angle cone image, sheared original frame, both nappes/apex, excluded point, ownership and atomic failures")
        print("MEASURE cone work=\(measured.work) generatedBytes=\(measured.storageBytes)")
    }
}
