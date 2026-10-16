import CADCore
import CADTopology

public extension MassPropertyEvaluator {
    init(tolerance: ModelingTolerance) {
        self.init(tolerance: tolerance, momentMeasurer: DefaultBRepVolumeMomentMeasurer(),
            attributes: ProductAttributeResolver())
    }
    init(tolerance: ModelingTolerance, momentMeasurer: any BRepVolumeMomentMeasuring) {
        self.init(tolerance: tolerance, momentMeasurer: momentMeasurer,
            attributes: ProductAttributeResolver())
    }
    init(tolerance: ModelingTolerance, attributes: any ProductAttributeResolving) {
        self.init(tolerance: tolerance, momentMeasurer: DefaultBRepVolumeMomentMeasurer(),
            attributes: attributes)
    }
}
