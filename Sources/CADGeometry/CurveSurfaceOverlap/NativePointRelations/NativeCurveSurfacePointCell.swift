/// A point cell index is meaningful only within its retained chart.
package struct NativeCurveSurfacePointCell: Sendable {
    package let chartIndex: Int
    package let cellIndex: Int
}
