import Foundation

struct SecondOrderTrigonometricPolynomial: Sendable {
    let constant: Double
    let cosine: Double
    let sine: Double
    let cosineDouble: Double
    let sineDouble: Double

    init(
        constant: Double,
        cosine: Double = 0.0,
        sine: Double = 0.0,
        cosineDouble: Double = 0.0,
        sineDouble: Double = 0.0
    ) {
        self.constant = constant
        self.cosine = cosine
        self.sine = sine
        self.cosineDouble = cosineDouble
        self.sineDouble = sineDouble
    }

    func value(at angle: Double) -> Double {
        constant
            + cosine * cos(angle)
            + sine * sin(angle)
            + cosineDouble * cos(2.0 * angle)
            + sineDouble * sin(2.0 * angle)
    }
}
