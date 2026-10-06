import CADCore
import CADIR
import CADTopology

/// Measures common source values without retaining a serialized output buffer.
struct AssemblyGeometryCounter {
    static func count(_ model: BRepModel, maximum: Int, maximumDepth: Int) throws -> Int {
        var consumed = 0
        func count<Value: PortableSourceEncodable>(_ value: Value) throws {
            let remaining = maximum - consumed
            guard remaining > 0 else { throw AssemblyError.resourceLimitExceeded("geometry values") }
            let measurement = try PortableSourceEncoder.measure(value, limits: PortableSourceEncodingLimits(
                maximumBytes: remaining, maximumWork: remaining, maximumDepth: maximumDepth))
            // Both original traversal and admitted retained/scratch storage belong to
            // the existing cumulative assembly work/storage allowance.
            let sum = measurement.consumedWork.addingReportingOverflow(measurement.consumedBytes)
            guard !sum.overflow, sum.partialValue <= remaining else {
                throw AssemblyError.resourceLimitExceeded("geometry traversal/storage")
            }
            consumed += sum.partialValue
        }
        for curve in model.geometry.curves.values { try count(curve) }
        for surface in model.geometry.surfaces.values { try count(surface) }
        for loop in model.loops.values { try count(loop) }
        return consumed
    }
}
