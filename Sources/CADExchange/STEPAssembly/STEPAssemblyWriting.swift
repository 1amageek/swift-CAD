import CADCore
import CADKernel

public protocol STEPAssemblyWriting: Sendable {
    func write(_ evaluated: EvaluatedDocument, units: UnitSystem, to sink: any ByteSink) throws
}
