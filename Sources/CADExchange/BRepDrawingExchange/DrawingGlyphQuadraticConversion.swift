import CADCore
import CADGeometry
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("Drawing glyph conversion requires the target C math module.")
#endif

/// Original quadratic-to-cubic conversion, with exact control rounding admission.
enum DrawingGlyphQuadraticConversion {
    static func controls(start: Point2D, control: Point2D, end: Point2D, allowance: Double,
                         maximumAlgebraicDepth: Int, using execution: inout OriginalQueryExecution) throws -> (Point2D, Point2D) {
        return try execution.withProofScope(maximum: .init(value: maximumAlgebraicDepth, coefficient: maximumAlgebraicDepth)) { execution in
        func coordinate(_ endpoint: Double, _ control: Double, using execution: inout OriginalQueryExecution) throws -> (Double, Double) {
            let first = try ExactRationalCoefficient.originalDouble(endpoint, usage: &execution)
            let second = try ExactRationalCoefficient.originalDouble(control, usage: &execution)
            let two = try ExactRationalCoefficient.originalDouble(2, usage: &execution)
            let three = try ExactRationalCoefficient.originalDouble(3, usage: &execution)
            let exact = try first.adding(second.multiplied(by: two, usage: &execution), usage: &execution).divided(by: three, usage: &execution)
            let range = try exact.outwardInterval(usage: &execution)
            guard range.lower.isFinite, range.upper.isFinite else { throw ExportError.invalidMesh("Glyph cubic control cannot be represented in the target format.") }
            let candidate = range.lower * 0.5 + range.upper * 0.5
            let candidateExact = try ExactRationalCoefficient.originalDouble(candidate, usage: &execution)
            let difference = try exact.subtracting(candidateExact, usage: &execution).outwardInterval(usage: &execution)
            return (candidate, max(abs(difference.lower), abs(difference.upper)).nextUp)
        }
        let x1 = try coordinate(start.x, control.x, using: &execution), y1 = try coordinate(start.y, control.y, using: &execution)
        let x2 = try coordinate(end.x, control.x, using: &execution), y2 = try coordinate(end.y, control.y, using: &execution)
        guard max(hypot(x1.1, y1.1).nextUp, hypot(x2.1, y2.1).nextUp) <= allowance else {
            throw ExportError.invalidMesh("Original glyph cubic conversion exceeds the caller's paper-point allowance.")
        }
        return (.init(x: x1.0, y: y1.0), .init(x: x2.0, y: y2.0))

        }
    }
}
