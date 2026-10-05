import CADCore
import CADGeometry

/// Original quadratic-to-cubic conversion, with exact control rounding admission.
enum DrawingGlyphQuadraticConversion {
    static func controls(start: Point2D, control: Point2D, end: Point2D, allowance: Double,
                         usage: inout DrawingExchangeUsage) throws -> (Point2D, Point2D) {
        func coordinate(_ endpoint: Double, _ control: Double, usage: inout DrawingExchangeUsage) throws -> (Double, Double) {
            let first = try ExactRationalCoefficient.originalDouble(endpoint, usage: &usage)
            let second = try ExactRationalCoefficient.originalDouble(control, usage: &usage)
            let two = try ExactRationalCoefficient.originalDouble(2, usage: &usage)
            let three = try ExactRationalCoefficient.originalDouble(3, usage: &usage)
            let exact = try first.adding(second.multiplied(by: two, usage: &usage), usage: &usage).divided(by: three, usage: &usage)
            let range = try exact.outwardInterval(usage: &usage)
            guard range.lower.isFinite, range.upper.isFinite else { throw ExportError.invalidMesh("Glyph cubic control cannot be represented in the target format.") }
            let candidate = range.lower * 0.5 + range.upper * 0.5
            let candidateExact = try ExactRationalCoefficient.originalDouble(candidate, usage: &usage)
            let difference = try exact.subtracting(candidateExact, usage: &usage).outwardInterval(usage: &usage)
            return (candidate, max(abs(difference.lower), abs(difference.upper)).nextUp)
        }
        let x1 = try coordinate(start.x, control.x, usage: &usage), y1 = try coordinate(start.y, control.y, usage: &usage)
        let x2 = try coordinate(end.x, control.x, usage: &usage), y2 = try coordinate(end.y, control.y, usage: &usage)
        guard max(hypot(x1.1, y1.1).nextUp, hypot(x2.1, y2.1).nextUp) <= allowance else {
            throw ExportError.invalidMesh("Original glyph cubic conversion exceeds the caller's paper-point allowance.")
        }
        return (.init(x: x1.0, y: y1.0), .init(x: x2.0, y: y2.0))
    }
}
