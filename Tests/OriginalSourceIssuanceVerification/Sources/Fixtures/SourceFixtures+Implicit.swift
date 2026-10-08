import L0
import L1
import SourceIssuer

struct PrimitiveInput: OriginalPrimitiveImageReading {
    let imageKind: OriginalPrimitiveImageKind
    let majorRadius: Double
    let minorRadius: Double
    var origin: [Double]
    var matrix: [Double]
    func center(in axis: Int) -> Double { origin[axis] }
    func frame(row: Int, column: Int) -> Double { matrix[row*3+column] }
}
struct PrimitiveProvider: OriginalSourceSnapshotting {
    func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing PrimitiveInput,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<PrimitiveInput> {
        do {
            try admission.consumeWork(1)
            guard input.origin.count == 3, input.matrix.count == 9 else {
                throw OriginalSourceIssuanceFailure.invalidSource
            }
            for value in input.origin {
                try admission.consumeWork(1)
                guard value.isFinite else { throw OriginalSourceIssuanceFailure.invalidSource }
            }
            for value in input.matrix {
                try admission.consumeWork(1)
                guard value.isFinite else { throw OriginalSourceIssuanceFailure.invalidSource }
            }
            return .init(original:copy input,sourceDepth:0)
        } catch let failure as OriginalSourceIssuanceFailure { throw failure }
        catch let failure as ExactScalarFailure { throw .scalar(failure) }
        catch { throw .sourceRejected(error) }
    }
}
extension SourceFixtures {
    typealias Image = OriginalImplicitImageReceipt<PrimitiveInput, OriginalPrimitiveImageSelection, Field>
    static func image<A: ExactScalarAdmission & ~Copyable>(_ input: PrimitiveInput, using a: inout A) throws -> Image {
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:0)
        let binding = try DefaultOriginalSourceBindingIssuer(provider:PrimitiveProvider()).bind(input,limits:limits,using:&a)
        let chart = try binding.chart(OriginalPrimitiveImageSelection(),limits:limits,using:&a)
        return try DefaultOriginalPrimitiveImageIssuer<PrimitiveInput,Field>().issue(
            source:binding,chart:chart,field:Field(),limits:limits,using:&a)
    }
    public static func implicitImages() throws {
        var a = try TraceAdmission()
        var sphere = PrimitiveInput(imageKind:.sphere,majorRadius:3,minorRadius:0,
            origin:[1,-2,3],matrix:[1,0,0,0,1,0,0,0,1])
        let issued = try image(sphere,using:&a), f = issued.field, r = issued.polynomials
        var terms: [ExactPolynomialTerm<Field.Value>] = []
        for (powers, value) in [([2,0,0],1),([0,2,0],1),([0,0,2],1),
            ([1,0,0],-2),([0,1,0],4),([0,0,1],-6),([0,0,0],5)] {
            terms.append(.init(powers:powers,coefficient:try f.integer(value,using:&a)))
        }
        try require(try r.equals(issued.equation,r.polynomial(terms:terms,using:&a),using:&a))
        try require(issued.nonzeroGuards.count == 1)
        try require(try !r.isZero(issued.nonzeroGuards[0],using:&a))
        sphere.origin[0] = 99
        try require(issued.source.original.origin[0] == 1)
        let cylinder = PrimitiveInput(imageKind:.cylinder,majorRadius:3,minorRadius:0,
            origin:[1,-2,3],matrix:[1,1,0,0,1,0,0,0,2])
        let c = try image(cylinder,using:&a), cr = c.polynomials, cf = c.field
        terms.removeAll(keepingCapacity:true)
        for (powers,value) in [([2,0,0],1),([1,1,0],-2),([0,2,0],2),
            ([1,0,0],-6),([0,1,0],10),([0,0,0],4)] {
            terms.append(.init(powers:powers,coefficient:try cf.integer(value,using:&a)))
        }
        try require(try cr.equals(c.equation,cr.polynomial(terms:terms,using:&a),using:&a))
        let torus = PrimitiveInput(imageKind:.torus,majorRadius:3,minorRadius:1,
            origin:[1,-2,3],matrix:cylinder.matrix)
        let t = try image(torus,using:&a), tr = t.polynomials, tf = t.field
        let x = try tr.variable(0,using:&a), y = try tr.variable(1,using:&a), z = try tr.variable(2,using:&a)
        let qx = try tr.subtracting(tr.subtracting(x,y,using:&a),tr.constant(tf.integer(3,using:&a),using:&a),using:&a)
        let qy = try tr.adding(y,tr.constant(tf.integer(2,using:&a),using:&a),using:&a)
        let qz = try tr.scaled(tr.subtracting(z,tr.constant(tf.integer(3,using:&a),using:&a),using:&a),
            by:tf.dividing(tf.integer(1,using:&a),tf.integer(2,using:&a),using:&a),using:&a)
        let rho = try tr.adding(tr.multiplying(qx,qx,using:&a),tr.multiplying(qy,qy,using:&a),using:&a)
        let total = try tr.adding(tr.adding(rho,tr.multiplying(qz,qz,using:&a),using:&a),
            tr.constant(tf.integer(8,using:&a),using:&a),using:&a)
        let expected = try tr.subtracting(tr.multiplying(total,total,using:&a),
            tr.scaled(rho,by:tf.integer(36,using:&a),using:&a),using:&a)
        try require(try tr.equals(t.equation,expected,using:&a))
        for bad in [PrimitiveInput(imageKind:.torus,majorRadius:1,minorRadius:2,origin:torus.origin,matrix:torus.matrix),
            PrimitiveInput(imageKind:.cylinder,majorRadius:3,minorRadius:0,origin:cylinder.origin,matrix:[1,0,0,0,1,0,0,0,0]),
            PrimitiveInput(imageKind:.sphere,majorRadius:3,minorRadius:0,origin:torus.origin,matrix:torus.matrix)] {
            do { _ = try image(bad,using:&a); throw Failure.incorrectEvidence }
            catch OriginalSourceIssuanceFailure.invalidSource {}
        }
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:0)
        let foreign = try DefaultOriginalSourceBindingIssuer(provider:PrimitiveProvider()).bind(
            torus,limits:limits,using:&a)
        do {
            _ = try DefaultOriginalPrimitiveImageIssuer<PrimitiveInput,Field>().issue(
                source:foreign,chart:t.chart,field:tf,limits:limits,using:&a)
            throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.foreignBinding {}
        var measured = try TraceAdmission()
        _ = try image(torus,using:&measured)
        var exhausted = try TraceAdmission(work:measured.work-1)
        do { _ = try image(torus,using:&exhausted); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.work))) {}
        var storage = try TraceAdmission(storage:measured.storageBytes-1)
        do { _ = try image(torus,using:&storage); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.storage))) {}
        var cancel = try TraceAdmission(cancelAtStorage:measured.storageCalls)
        do { _ = try image(torus,using:&cancel); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.cancelled)) {}
        print("PASS complete sphere/cylinder/torus image equations, original sheared frames, source lifetime and failures")
    }
}
