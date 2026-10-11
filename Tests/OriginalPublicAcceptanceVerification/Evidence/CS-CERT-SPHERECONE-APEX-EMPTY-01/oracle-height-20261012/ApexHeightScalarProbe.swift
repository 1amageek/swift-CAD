import Foundation

@main struct ApexHeightScalarProbe {
    static func main() throws {
        let alpha = atan(0.5)
        let slope = tan(alpha)
        let cosine = cos(alpha)
        let sine = sin(alpha)
        let quadraticA = 1.0 + slope * slope
        // Exact fixture axis and basis give zero axial and cosine coefficients.
        let axialCenter = 0.0
        let radialCosine = 0.0
        // Preserve the actual analytic cone coefficient-generation rounding.
        // Its canonical quarter-label radial vector is exactly -unitX.
        let quarterPointX = 1.0 + (-1.0) * (1.0 * sine)
        let quarterRadialX = (quarterPointX - 1.0 - 0.0) / sine
        let radialSine = (-1.0) * quarterRadialX
        let inverseQuadraticCosine = 1.0 / (quadraticA * cosine)
        let scale = 2.0 * inverseQuadraticCosine
        typealias I = OutwardScalarInterval
        let trigonometricRange = I(lower: -1.0, upper: 1.0)
        let halfLinear = I.exact(axialCenter) + I.exact(slope) *
            (I.exact(radialCosine) * trigonometricRange + I.exact(radialSine) * trigonometricRange)
        guard let inverse = I.exact(1.0).divided(by: I.exact(quadraticA) * I.exact(cosine)) else {
            throw NSError(domain: "InvalidDenominator", code: 1)
        }
        let slant = halfLinear * (I.exact(2.0) * inverse)
        let height = I.exact(0.0) + I.exact(cosine) * slant
        let boxHalfLinear = I.exact(0.0) + I(lower: 31.0/64.0, upper: 33.0/64.0) *
            (I(lower: -1.0/64.0, upper: 1.0/64.0) * trigonometricRange +
             I(lower: 63.0/64.0, upper: 65.0/64.0) * trigonometricRange)
        guard let boxInverse = I.exact(1.0).divided(by:
            I(lower: 79.0/64.0, upper: 81.0/64.0) * I(lower: 7.0/8.0, upper: 29.0/32.0)) else {
            throw NSError(domain: "InvalidBoxDenominator", code: 1)
        }
        let boxHeight = I.exact(0.0) + I(lower: 7.0/8.0, upper: 29.0/32.0) *
            (boxHalfLinear * (I.exact(2.0) * boxInverse))
        let coefficients = ["alpha":alpha,"slope":slope,"cosine":cosine,"sine":sine,
            "quadraticA":quadraticA,"axialCenter":axialCenter,"radialCosine":radialCosine,
            "radialSine":radialSine,"inverseQuadraticCosine":inverseQuadraticCosine,"scale":scale]
        var values: [String:Any] = [:]
        for (key,value) in coefficients {
            values[key] = ["decimal":value,"bits":String(format:"%016llx",value.bitPattern)]
        }
        for (key,value) in ["halfLinear":halfLinear,"slant":slant,"height":height,"boxHeight":boxHeight] {
            values[key] = ["lower":value.lower,"upper":value.upper,
                "lowerBits":String(format:"%016llx",value.lower.bitPattern),
                "upperBits":String(format:"%016llx",value.upper.bitPattern)]
        }
        precondition(height.upper < 1.0 && boxHeight.upper < 1.0)
        let data = try JSONSerialization.data(withJSONObject:values, options:[.prettyPrinted,.sortedKeys])
        FileHandle.standardOutput.write(data)
        print()
    }
}
