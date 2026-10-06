import CADCore
import CADGeometry

/// Shared outward physical magnitude of nonnegative original coordinate gaps.
package enum OriginalDistanceMagnitude {
    package static func bounds(_ x: Double, _ y: Double, _ z: Double)
        -> (lower: Double, upper: Double) {
        let scale = max(x,y,z)
        guard x >= 0, y >= 0, z >= 0, scale.isFinite else { return (0,.infinity) }
        if scale == 0 { return (0,0) }
        let divisor = OutwardScalarInterval.exact(scale)
        guard let a = OutwardScalarInterval.exact(x).divided(by: divisor),
            let b = OutwardScalarInterval.exact(y).divided(by: divisor),
            let c = OutwardScalarInterval.exact(z).divided(by: divisor) else { return (0,.infinity) }
        let square = a*a+b*b+c*c
        let root = OutwardScalarInterval(lower: max(0,max(0,square.lower).squareRoot().nextDown),
            upper: max(0,square.upper).squareRoot().nextUp)
        let norm = root * divisor
        return (max(0,norm.lower),norm.upper)
    }
}
