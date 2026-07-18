import CADCore
import OpenUSD

struct USDStandaloneLayerValidator: Sendable {
    func validate(_ layer: SdfLayer) throws {
        if !layer.composition.isEmpty {
            throw ImportError.compositionFailure(
                kind: "unresolvedStandaloneLayerArc",
                message: "Standalone USDA and USDC imports cannot resolve sublayers, references, or payloads. Package the dependency graph as USDZ."
            )
        }

        if layer.specs.contains(where: containsVariantOpinion) {
            throw ImportError.unsupportedFeature(
                "Standalone USDA and USDC imports require variant opinions to be composed before scene materialization."
            )
        }

        if let fieldName = firstUnsupportedCompositionField(in: layer) {
            throw ImportError.unsupportedFeature(
                "Standalone USDA and USDC imports do not materialize the USD composition field \(fieldName)."
            )
        }

        if layer.specs.contains(where: isActiveFalse) {
            throw ImportError.unsupportedFeature(
                "Standalone USDA and USDC imports do not materialize inactive prim semantics."
            )
        }

        if layer.specs.contains(where: isInstanceable) {
            throw ImportError.unsupportedFeature(
                "Standalone USDA and USDC imports require instanceable prims to be composed before scene materialization."
            )
        }

        if layer.specs.contains(where: hasValueClipOpinion) {
            throw ImportError.unsupportedFeature(
                "Standalone USDA and USDC imports support authored time samples but not value clips."
            )
        }
    }

    private func containsVariantOpinion(_ spec: SdfSpec) -> Bool {
        spec.specType == .variantSet
            || spec.specType == .variant
            || spec.path.containsVariantSelection
            || spec.fields["variantSelections"] != nil
            || spec.fields["variantSetNames"] != nil
            || spec.fields["variants"] != nil
    }

    private func firstUnsupportedCompositionField(in layer: SdfLayer) -> String? {
        let fieldNames = ["inherits", "relocates", "specializes"]
        for spec in layer.specs {
            if let fieldName = fieldNames.first(where: { spec.fields[$0] != nil }) {
                return fieldName
            }
        }
        return nil
    }

    private func isActiveFalse(_ spec: SdfSpec) -> Bool {
        guard case .bool(false)? = spec.fields["active"] else {
            return false
        }
        return true
    }

    private func isInstanceable(_ spec: SdfSpec) -> Bool {
        guard case .bool(true)? = spec.fields["instanceable"] else {
            return false
        }
        return true
    }

    private func hasValueClipOpinion(_ spec: SdfSpec) -> Bool {
        spec.fields["clips"] != nil
    }
}
