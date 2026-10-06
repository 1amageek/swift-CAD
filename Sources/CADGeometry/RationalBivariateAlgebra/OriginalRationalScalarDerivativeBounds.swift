/// Whole-chart original rational polynomial derivative enclosures through order three.
package struct OriginalRationalScalarDerivativeBounds: Sendable {
    package let value: OutwardScalarInterval
    package let u: OutwardScalarInterval
    package let v: OutwardScalarInterval
    package let uu: OutwardScalarInterval
    package let uv: OutwardScalarInterval
    package let vv: OutwardScalarInterval
    package let uuu: OutwardScalarInterval
    package let uuv: OutwardScalarInterval
    package let uvv: OutwardScalarInterval
    package let vvv: OutwardScalarInterval
}
