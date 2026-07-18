import Testing
import CADGeometry

@Suite("B-spline sparse basis evaluation")
struct BSplineBasisSparseEvaluationTests {
    @Test
    func sparseValuesMatchDenseValuesAndDerivatives() {
        let degree = 3
        let count = 7
        let knots = [
            0.0, 0.0, 0.0, 0.0,
            0.25, 0.5, 0.5,
            1.0, 1.0, 1.0, 1.0,
        ]
        for parameter in [0.0, 0.125, 0.25, 0.5, 0.875, 1.0] {
            for derivativeOrder in 0...2 {
                let dense = BSplineBasis.derivativeValues(
                    parameter: parameter,
                    degree: degree,
                    derivativeOrder: derivativeOrder,
                    knots: knots,
                    count: count
                )
                let sparse = BSplineBasis.nonzeroValues(
                    parameter: parameter,
                    degree: degree,
                    derivativeOrder: derivativeOrder,
                    knots: knots,
                    count: count
                )
                var expanded = Array(repeating: 0.0, count: count)
                for (offset, value) in sparse.values.enumerated() {
                    let index = sparse.startIndex + offset
                    if expanded.indices.contains(index) {
                        expanded[index] = value
                    }
                }
                #expect(zip(dense, expanded).allSatisfy { pair in
                    abs(pair.0 - pair.1) <= 1.0e-10
                })
            }
        }
    }
}
