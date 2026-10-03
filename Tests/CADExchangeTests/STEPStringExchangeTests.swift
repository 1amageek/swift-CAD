import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
@testable import CADExchange

@Suite("Standard STEP string and description interchange")
struct STEPStringExchangeTests {
    @Test(.timeLimit(.minutes(1)))
    func independentStandardLiteralsDecodeEveryDirectiveAndPage() throws {
        let codec: any STEPStringCoding = STEPStringCodec()
        let cases: [(String, String)] = [
            (#"'Don''t \\ lose \X\A7 \X2\03B103B203B3\X0\ \X4\0001F600\X0\'"#,
             "Don't \\ lose § αβγ 😀"),
            (#"'\S\Drger h\S\ttel'"#, "Ärger hôtel"),
            (#"'\PA\\S\D\PB\\S\!\PC\\S\!\PD\\S\!\PE\\S\!\PF\\S\,\PG\\S\!\PH\\S\`\PI\\S\P'"#,
             "ÄĄĦĄЁ،‘אĞ"),
            (#"'\PE\\S\*\S\U\S\b'"#, "Њет"),
            (#"'line\X\0Anext\X\7F'"#, "line\nnext\u{7F}"),
            ("'\u{301}decomposed e\u{301}'", "\u{301}decomposed e\u{301}"),
            (#"'\\X literal'"#, #"\X literal"#)
        ]
        for (token, expected) in cases {
            #expect(try codec.decode(token, limits: .standard).value.unicodeScalars.elementsEqual(expected.unicodeScalars))
        }
        #expect(try codec.decode(#"'\S\D'"#, limits: .standard).value == "Ä")
        let lexical: any STEPFieldReading = STEPAssemblySyntax(entities: [1: "PRODUCT('id','\u{301}part','description',(#2))"])
        let arguments = try lexical.arguments(1, component: nil)
        #expect(arguments.count == 4)
        #expect(try lexical.decodedString(arguments[1], limits: .standard).value == "\u{301}part")
        let value = "'\\\n\u{7F}éπ😀e\u{301}"
        let encoded = try codec.encode(value, limits: .standard)
        #expect(encoded.value.utf8.allSatisfy { $0 < 128 })
        #expect(try codec.decode(encoded.value, limits: .standard).value.unicodeScalars.elementsEqual(value.unicodeScalars))
    }
    @Test(.timeLimit(.minutes(1)))
    func malformedScalarsAndDirectivesRefuseWithoutRepair() throws {
        let codec = STEPStringCodec()
        for token in ["not quoted", "'unterminated", #"'bad\Q\'"#, #"'\X\A'"#,
                      #"'\X\gg'"#, #"'\X2\123\X0\'"#, #"'\X2\D800\X0\'"#,
                      #"'\X2\0041'"#, #"'\X2\\X0\'"#, #"'\X4\00110000\X0\'"#,
                      #"'\X4\0001F600'"#, #"'\PJ\\S\D'"#, #"'\PF\\S\!'"#,
                      "'raw\ncontrol'", "'unescaped'quote'"] {
            do { _ = try codec.decode(token); Issue.record("Malformed token succeeded: \(token)") }
            catch let error as STEPStringError {
                if case .malformed = error {} else { Issue.record("Wrong failure classification: \(error)") }
            }
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func exactByteAndWorkCeilingsAreRetained() throws {
        let codec: any STEPStringCoding = STEPStringCodec()
        let token = #"'\X2\03C0\X0\'"#
        let decoded = try codec.decode(token, limits: .standard)
        let exact = STEPStringLimits(maximumInputBytes: token.utf8.count, maximumOutputBytes: 2,
                                     maximumWork: decoded.consumedWork)
        #expect(try codec.decode(token, limits: exact).value == "π")
        for limits in [STEPStringLimits(maximumInputBytes: token.utf8.count - 1),
                       STEPStringLimits(maximumOutputBytes: 1),
                       STEPStringLimits(maximumWork: decoded.consumedWork - 1)] {
            #expect(throws: STEPStringError.resourceLimitExceeded) { _ = try codec.decode(token, limits: limits) }
        }
        let encoded = try codec.encode("π", limits: .standard)
        #expect(try codec.encode("π", limits: STEPStringLimits(maximumInputBytes: 2,
            maximumOutputBytes: encoded.outputBytes, maximumWork: encoded.consumedWork)) == encoded)
        #expect(throws: STEPStringError.resourceLimitExceeded) {
            _ = try codec.encode("π", limits: STEPStringLimits(maximumOutputBytes: encoded.outputBytes - 1))
        }
        #expect(throws: STEPStringError.resourceLimitExceeded) {
            _ = try codec.encode("π", limits: STEPStringLimits(maximumWork: encoded.consumedWork - 1))
        }
        let maximum = "'" + String(repeating: "a", count: 32767) + "'"
        #expect(try codec.decode(maximum, limits: .standard).outputBytes == 32767)
        #expect(throws: STEPStringError.resourceLimitExceeded) {
            _ = try codec.decode("'" + String(repeating: "a", count: 32768) + "'",
                limits: STEPStringLimits(maximumInputBytes: 100000, maximumOutputBytes: 100000, maximumWork: 200000))
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func unicodeDescriptionsAndAttributesSurvivePublicSTEPAndNative() throws {
        // Geometry, carrier and override records are independently authored in the sibling fixture.
        // These literal field replacements use no production string or geometry writer.
        let literal = STEPAttributesExchangeTests.independentFixture
            .replacingOccurrences(of: "PRODUCT('part','two-body real part','',",
                                  with: #"PRODUCT('part','\X2\90E854C1\X0\','\X\A7 \X2\03C0\X0\ \X4\0001F600\X0\',"#)
            .replacingOccurrences(of: "PRODUCT_DEFINITION('design','',", with: #"PRODUCT_DEFINITION('design','Don''t \\ lose \S\D',"#)
            .replacingOccurrences(of: "'body alpha'", with: #"'\X2\672C4F53\X0\'"#)
            .replacingOccurrences(of: "'face alpha'", with: #"'\X2\9762\X0\'"#)
            .replacingOccurrences(of: "'whole part'", with: #"'\X2\5C64\X0\'"#)
            .replacingOccurrences(of: "'steel'", with: #"'\X2\92FC\X0\'"#)
            .replacingOccurrences(of: "'independent physical material'", with: #"'caf\S\i'"#)
        let exchange = STEPExchange(tolerance: .standard)
        let imported = try exchange.import(Data(literal.utf8))
        let document = try #require(imported.document), part = try #require(document.assembly?.definitions.first)
        #expect(part.name == "部品" && part.productDescription == "§ π 😀")
        #expect(part.definitionDescription == "Don't \\ lose Ä")
        #expect(document.productAttributes.materials.first?.name == "鋼")
        #expect(document.productAttributes.materials.first?.description == "café")
        #expect(document.productAttributes.layers.contains { $0.name == "層" })
        #expect(document.productAttributes.assignments.contains { $0.value == .name("本体") })
        #expect(document.productAttributes.assignments.contains { $0.value == .name("面") })
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let sink = DataByteSink()
        try OfficialFormatExchange(tolerance: .standard).write(evaluated, as: .step, to: sink)
        let roundTrip = try #require(exchange.import(sink.bytes).document)
        let retained = try #require(roundTrip.assembly?.definitions.first)
        #expect(retained.name == part.name && retained.productDescription == part.productDescription)
        #expect(retained.definitionDescription == part.definitionDescription)
        #expect(roundTrip.productAttributes.materials.map(\.name) == document.productAttributes.materials.map(\.name))
        #expect(roundTrip.productAttributes.materials.map(\.description) == document.productAttributes.materials.map(\.description))
        #expect(Set(roundTrip.productAttributes.layers.map(\.name)) == Set(document.productAttributes.layers.map(\.name)))
        let store = NativePackageStore(tolerance: .standard), native = DataByteSink()
        try store.writePackage(for: document, to: native)
        #expect(try store.loadDocument(from: native.bytes) == document)
        let direct = literal.replacingOccurrences(of: #"'\X2\90E854C1\X0\'"#, with: "'\u{301}部品;#999=e\u{301}'")
            .replacingOccurrences(of: #"'\X2\672C4F53\X0\'"#, with: "'\u{301}本体,(e\u{301})'")
        let directSource = try #require(exchange.import(Data(direct.utf8)).document)
        #expect(directSource.assembly?.definitions.first?.name == "\u{301}部品;#999=e\u{301}")
        #expect(directSource.productAttributes.assignments.contains { $0.value == .name("\u{301}本体,(e\u{301})") })
        let directSink = DataByteSink()
        try exchange.write(DocumentEvaluator(tolerance: .standard).evaluateExact(directSource), to: directSink)
        let directRestored = try #require(exchange.import(directSink.bytes).document)
        #expect(directRestored.assembly?.definitions.first?.name.unicodeScalars.elementsEqual("\u{301}部品;#999=e\u{301}".unicodeScalars) == true)
        let competing = literal.replacingOccurrences(of: "ENDSEC;\nEND-ISO", with:
            "#500=PRODUCT_DEFINITION('another view','different definition description',#51,#3);\n#501=PRODUCT_DEFINITION_SHAPE('','',#500);\n#502=SHAPE_DEFINITION_REPRESENTATION(#501,#56);\nENDSEC;\nEND-ISO")
        #expect(throws: ProductAttributeError.unsupportedSemantics("Several definitions share one product description owner.")) {
            _ = try exchange.import(Data(competing.utf8))
        }
        let bad = literal.replacingOccurrences(of: #"\X4\0001F600\X0\"#, with: #"\X4\00110000\X0\"#)
        #expect(throws: STEPStringError.self) { _ = try exchange.import(Data(bad.utf8)) }
        var nilDescription = document; nilDescription.assembly?.definitions[0].productDescription = nil
        nilDescription.assembly?.definitions[0].definitionDescription = ""
        let optionalSink = DataByteSink()
        try exchange.write(DocumentEvaluator(tolerance: .standard).evaluateExact(nilDescription), to: optionalSink)
        let optional = try #require(exchange.import(optionalSink.bytes).document?.assembly?.definitions.first)
        #expect(optional.productDescription == nil && optional.definitionDescription == "")
    }
    @Test(.timeLimit(.minutes(1)))
    func cancellationAndPublicOutputFailureDoNotPublish() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try STEPStringCodec().decode(#"'\X2\03C0\X0\'"#)
        }
        do { _ = try await task.value; Issue.record("Cancelled decoding succeeded.") }
        catch is CancellationError {}
        let document = try #require(STEPExchange(tolerance: .standard).import(Data(STEPAttributesExchangeTests.independentFixture.utf8)).document)
        var oversized = document
        oversized.assembly?.definitions[0].productDescription = String(repeating: "π", count: 3000)
        let sink = DataByteSink(), evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(oversized)
        #expect(throws: STEPStringError.resourceLimitExceeded) { try STEPExchange(tolerance: .standard).write(evaluated, to: sink) }
        #expect(sink.bytes.isEmpty)
    }
}
