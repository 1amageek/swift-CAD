import CADCore

/// Original native-span coefficient authority, issued only inside CADGeometry.
package struct SurfaceAreaOriginalCoefficientReceipt: Sendable {
    package let source: BSplineSurface3D
    package let tolerance: ModelingTolerance
    package let query: SurfaceParameterBox
    package let baseQuery: SurfaceParameterBox
    package let baseDomain: SurfaceParameterBox
    package let uSpanIndex: Int
    package let vSpanIndex: Int
    package let origin: Point3D
    package let commonWeight: Double?
    private let net: [[IntervalHomogeneousSurfaceControl]]

    init(source: BSplineSurface3D, tolerance: ModelingTolerance, query: SurfaceParameterBox,
         baseQuery: SurfaceParameterBox, baseDomain: SurfaceParameterBox,
         uSpanIndex: Int, vSpanIndex: Int, origin: Point3D, commonWeight: Double?,
         net: [[IntervalHomogeneousSurfaceControl]]) {
        self.source = source; self.tolerance = tolerance; self.query = query
        self.baseQuery = baseQuery; self.baseDomain = baseDomain
        self.uSpanIndex = uSpanIndex; self.vSpanIndex = vSpanIndex
        self.origin = origin; self.commonWeight = commonWeight; self.net = net
    }

    package var rowCount: Int { net.count }
    package var columnCount: Int { net.first?.count ?? 0 }

    package func coefficient(row: Int, column: Int) throws
        -> (x: OutwardScalarInterval,y: OutwardScalarInterval,z: OutwardScalarInterval,weight: OutwardScalarInterval) {
        guard net.indices.contains(row), net[row].indices.contains(column) else {
            throw KernelError(phase:.geometry,code:.invalidInput,tolerance:tolerance,
                message:"Original surface coefficient access lies outside its retained native net.")
        }
        let value = net[row][column]
        return (value.x,value.y,value.z,value.weight)
    }
}
