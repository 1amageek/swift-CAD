import CADCore
import Foundation

/// A univariate Taylor expansion through order four.
///
/// Coefficients are factorial-scaled so algebraic composition preserves all
/// derivatives through fourth order without finite differencing.
struct CurveTaylorScalarJet: Sendable {
    private let c0: Double
    private let c1: Double
    private let c2: Double
    private let c3: Double
    private let c4: Double

    var value: Double { c0 }
    var firstDerivative: Double { c1 }
    var secondDerivative: Double { 2.0 * c2 }
    var thirdDerivative: Double { 6.0 * c3 }
    var fourthDerivative: Double { 24.0 * c4 }

    init(
        value: Double,
        firstDerivative: Double = 0.0,
        secondDerivative: Double = 0.0,
        thirdDerivative: Double = 0.0,
        fourthDerivative: Double = 0.0
    ) {
        c0 = value
        c1 = firstDerivative
        c2 = secondDerivative * 0.5
        c3 = thirdDerivative / 6.0
        c4 = fourthDerivative / 24.0
    }

    private init(
        coefficients: (Double, Double, Double, Double, Double)
    ) {
        c0 = coefficients.0
        c1 = coefficients.1
        c2 = coefficients.2
        c3 = coefficients.3
        c4 = coefficients.4
    }

    static func variable(_ value: Double) -> CurveTaylorScalarJet {
        CurveTaylorScalarJet(value: value, firstDerivative: 1.0)
    }

    static func + (
        lhs: CurveTaylorScalarJet,
        rhs: CurveTaylorScalarJet
    ) -> CurveTaylorScalarJet {
        CurveTaylorScalarJet(coefficients: (
            lhs.c0 + rhs.c0,
            lhs.c1 + rhs.c1,
            lhs.c2 + rhs.c2,
            lhs.c3 + rhs.c3,
            lhs.c4 + rhs.c4
        ))
    }

    static func - (
        lhs: CurveTaylorScalarJet,
        rhs: CurveTaylorScalarJet
    ) -> CurveTaylorScalarJet {
        lhs + (-rhs)
    }

    static prefix func - (value: CurveTaylorScalarJet) -> CurveTaylorScalarJet {
        value.scaled(by: -1.0)
    }

    static func * (
        lhs: CurveTaylorScalarJet,
        rhs: CurveTaylorScalarJet
    ) -> CurveTaylorScalarJet {
        CurveTaylorScalarJet(coefficients: (
            lhs.c0 * rhs.c0,
            lhs.c0 * rhs.c1 + lhs.c1 * rhs.c0,
            lhs.c0 * rhs.c2 + lhs.c1 * rhs.c1 + lhs.c2 * rhs.c0,
            lhs.c0 * rhs.c3 + lhs.c1 * rhs.c2
                + lhs.c2 * rhs.c1 + lhs.c3 * rhs.c0,
            lhs.c0 * rhs.c4 + lhs.c1 * rhs.c3
                + lhs.c2 * rhs.c2 + lhs.c3 * rhs.c1
                + lhs.c4 * rhs.c0
        ))
    }

    func scaled(by scale: Double) -> CurveTaylorScalarJet {
        CurveTaylorScalarJet(coefficients: (
            c0 * scale,
            c1 * scale,
            c2 * scale,
            c3 * scale,
            c4 * scale
        ))
    }

    func reciprocal(
        tolerance: ModelingTolerance,
        diagnosticContext: String
    ) throws -> CurveTaylorScalarJet {
        guard c0.isFinite, abs(c0) > Double.leastNonzeroMagnitude else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: c0,
                tolerance: tolerance,
                message: "\(diagnosticContext) Taylor quotient has a singular denominator."
            )
        }
        let r0 = 1.0 / c0
        let r1 = -(c1 * r0) / c0
        let r2 = -(c1 * r1 + c2 * r0) / c0
        let r3 = -(c1 * r2 + c2 * r1 + c3 * r0) / c0
        let r4 = -(c1 * r3 + c2 * r2 + c3 * r1 + c4 * r0) / c0
        return try CurveTaylorScalarJet(
            coefficients: (r0, r1, r2, r3, r4)
        )
            .validated(tolerance: tolerance, diagnosticContext: diagnosticContext)
    }

    func divided(
        by denominator: CurveTaylorScalarJet,
        tolerance: ModelingTolerance,
        diagnosticContext: String
    ) throws -> CurveTaylorScalarJet {
        self * (try denominator.reciprocal(
            tolerance: tolerance,
            diagnosticContext: diagnosticContext
        ))
    }

    func squareRoot(
        tolerance: ModelingTolerance,
        diagnosticContext: String
    ) throws -> CurveTaylorScalarJet {
        guard c0.isFinite, c0 > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: c0,
                tolerance: tolerance,
                message: "\(diagnosticContext) Taylor square root requires a positive radicand."
            )
        }
        let r0 = sqrt(c0)
        let r1 = c1 / (2.0 * r0)
        let r2 = (c2 - r1 * r1) / (2.0 * r0)
        let r3 = (c3 - 2.0 * r1 * r2) / (2.0 * r0)
        let r4 = (c4 - 2.0 * r1 * r3 - r2 * r2) / (2.0 * r0)
        return try CurveTaylorScalarJet(
            coefficients: (r0, r1, r2, r3, r4)
        )
            .validated(tolerance: tolerance, diagnosticContext: diagnosticContext)
    }

    func sine() -> CurveTaylorScalarJet {
        let sine0 = sin(c0)
        let cosine0 = cos(c0)
        let sine1 = cosine0 * c1
        let cosine1 = -sine0 * c1
        let sine2 = (cosine0 * 2.0 * c2 + cosine1 * c1) * 0.5
        let cosine2 = (-sine0 * 2.0 * c2 - sine1 * c1) * 0.5
        let sine3 = (
            cosine0 * 3.0 * c3
                + cosine1 * 2.0 * c2
                + cosine2 * c1
        ) / 3.0
        let cosine3 = (
            -sine0 * 3.0 * c3
                - sine1 * 2.0 * c2
                - sine2 * c1
        ) / 3.0
        let sine4 = (
            cosine0 * 4.0 * c4
                + cosine1 * 3.0 * c3
                + cosine2 * 2.0 * c2
                + cosine3 * c1
        ) / 4.0
        return CurveTaylorScalarJet(coefficients: (
            sine0,
            sine1,
            sine2,
            sine3,
            sine4
        ))
    }

    func cosine() -> CurveTaylorScalarJet {
        let sine0 = sin(c0)
        let cosine0 = cos(c0)
        let sine1 = cosine0 * c1
        let cosine1 = -sine0 * c1
        let sine2 = (cosine0 * 2.0 * c2 + cosine1 * c1) * 0.5
        let cosine2 = (-sine0 * 2.0 * c2 - sine1 * c1) * 0.5
        let cosine3 = (
            -sine0 * 3.0 * c3
                - sine1 * 2.0 * c2
                - sine2 * c1
        ) / 3.0
        let sine3 = (
            cosine0 * 3.0 * c3
                + cosine1 * 2.0 * c2
                + cosine2 * c1
        ) / 3.0
        let cosine4 = (
            -sine0 * 4.0 * c4
                - sine1 * 3.0 * c3
                - sine2 * 2.0 * c2
                - sine3 * c1
        ) / 4.0
        return CurveTaylorScalarJet(coefficients: (
            cosine0,
            cosine1,
            cosine2,
            cosine3,
            cosine4
        ))
    }

    func sinc(
        tolerance: ModelingTolerance,
        diagnosticContext: String
    ) throws -> CurveTaylorScalarJet {
        if abs(value) > 0.25 {
            return try sine().divided(
                by: self,
                tolerance: tolerance,
                diagnosticContext: diagnosticContext
            )
        }
        let squared = self * self
        var power = CurveTaylorScalarJet(value: 1.0)
        var result = CurveTaylorScalarJet(value: 1.0)
        var coefficient = 1.0
        for index in 1...12 {
            power = power * squared
            coefficient /= -Double((2 * index) * (2 * index + 1))
            result = result + power.scaled(by: coefficient)
        }
        return try result.validated(
            tolerance: tolerance,
            diagnosticContext: diagnosticContext
        )
    }

    func validated(
        tolerance: ModelingTolerance,
        diagnosticContext: String
    ) throws -> CurveTaylorScalarJet {
        guard c0.isFinite, c1.isFinite, c2.isFinite, c3.isFinite,
              c4.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "\(diagnosticContext) Taylor evaluation exceeded finite arithmetic."
            )
        }
        return self
    }
}
