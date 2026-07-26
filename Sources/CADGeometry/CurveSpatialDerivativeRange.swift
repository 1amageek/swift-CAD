import CADCore

struct CurveSpatialDerivativeRange: Sendable {
    let x: ScalarInterval
    let y: ScalarInterval
    let z: ScalarInterval
}
