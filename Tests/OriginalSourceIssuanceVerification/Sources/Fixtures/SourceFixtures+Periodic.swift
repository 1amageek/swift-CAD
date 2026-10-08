import L0
import L1
import SourceIssuer

extension SourceFixtures {
    public static func periodicLaws() throws {
        var a = try TraceAdmission()
        let periodic = NativeInput(degrees: [1], knots: [[-1,0,1,2,3]], counts: [3],
            controls: [[0,0,0],[1,0,0],[0,0,0]], weights: [1,2,1], periodic: [true])
        let translated = try issue(periodic, spans: [1], cycles: [2], using: &a)
        try equal(translated, axis: 0, terms: [([1],2),([0],-8)], using: &a)
        try equal(translated, axis: 3, terms: [([1],1),([0],-3)], using: &a)
        try require(try translated.field.compare(translated.support[0].lower,
            translated.field.integer(4, using: &a), using: &a) == .equal)
        try require(try translated.field.compare(translated.support[0].upper,
            translated.field.integer(5, using: &a), using: &a) == .equal)
        try require(try translated.polynomials.equals(translated.parameterTransport.numerators[0],
            translated.polynomials.variable(0, using: &a), using: &a))
        let right = try issue(periodic, spans: [2], cycles: [0], using: &a)
        let left = try issue(periodic, spans: [1], cycles: [1], using: &a)
        let seam = try left.field.integer(2, using: &a)
        for axis in 0..<4 {
            let l = try left.polynomials.evaluated(left.homogeneous[axis], at: [seam], using: &a).value
            let r = try right.polynomials.evaluated(right.homogeneous[axis], at: [seam], using: &a).value
            try require(try left.field.compare(l,r,using:&a) == .equal)
        }
        let negative = try issue(periodic, spans: [2], cycles: [-1], using: &a)
        try equal(negative, axis: 0, terms: [([1],-2)], using: &a)
        try equal(negative, axis: 3, terms: [([0],1),([1],-1)], using: &a)
        let tensor = NativeInput(degrees: [1,1], knots: [periodic.knots[0],periodic.knots[0]], counts: [3,3],
            controls: [[0,0,0],[1,0,0],[0,0,0], [0,1,0],[1,1,1],[0,1,0],
                [0,0,0],[1,0,0],[0,0,0]], weights: [1,2,1, 3,6,3, 1,2,1], periodic: [true,true])
        let surface = try issue(tensor, spans: [1,1], cycles: [2,-1], using: &a)
        let ring = surface.polynomials, f = surface.field
        let u = try ring.subtracting(ring.variable(0,using:&a),ring.constant(f.integer(4,using:&a),using:&a),using:&a)
        let v = try ring.adding(ring.variable(1,using:&a),ring.constant(f.integer(2,using:&a),using:&a),using:&a)
        let one = try ring.constant(f.integer(1,using:&a),using:&a)
        let ux = try ring.scaled(u,by:f.integer(2,using:&a),using:&a)
        let vy = try ring.scaled(v,by:f.integer(3,using:&a),using:&a)
        let wu = try ring.adding(one,u,using:&a)
        let wv = try ring.adding(one,ring.scaled(v,by:f.integer(2,using:&a),using:&a),using:&a)
        for (axis,l,r) in [(0,ux,wv),(1,wu,vy),(2,ux,vy),(3,wu,wv)] {
            try require(try ring.equals(surface.homogeneous[axis],ring.multiplying(l,r,using:&a),using:&a))
        }
        do { _ = try issue(input(), cycles: [1], using: &a); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.invalidChart {}
        do { _ = try issue(periodic, cycles: [0,0], using: &a); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.invalidChart {}
        var broken = periodic; broken.controls[2][0] = 9
        do { _ = try issue(broken, using: &a); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.invalidSource {}
        var rounded = periodic; rounded.knots = [[-0.9,0.1,1.1,2.1,3.1]]
        do { _ = try issue(rounded, using: &a); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        var measured = try TraceAdmission()
        _ = try issue(periodic, cycles: [2], using: &measured)
        var limited = try TraceAdmission(work: measured.work - 1)
        do { _ = try issue(periodic, cycles: [2], using: &limited); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.work))) {}
        print("PASS periodic exact knot/control law, two axes, negative cycles, seam owners, transport and failures")
    }
}
