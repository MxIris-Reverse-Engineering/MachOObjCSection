import Foundation
import Testing
import Semantic
import OutputTransformer
@testable import ObjCOutputTransformer

@Suite("ObjC output transformer")
struct ObjCOutputTransformerTests {
    private func semanticKeywords(_ keywords: [String]) -> SemanticString {
        var components: [AtomicComponent] = []
        for (keywordIndex, keyword) in keywords.enumerated() {
            if keywordIndex > 0 {
                components.append(AtomicComponent(string: " ", type: .standard))
            }
            components.append(AtomicComponent(string: keyword, type: .keyword))
        }
        return SemanticString(components: components)
    }

    @Test("CType replaces the longest pattern first")
    func cTypeReplacesLongestPatternFirst() {
        var module = Transformer.CType(isEnabled: true)
        module.replacements = Transformer.CType.Presets.stdint
        // "unsigned long long" must map to uint64_t, not "unsigned" + int64_t.
        #expect(module.transform(semanticKeywords(["unsigned", "long", "long"])).string == "uint64_t")
        #expect(module.transform(semanticKeywords(["long"])).string == "int64_t")
    }

    @Test("CType leaves non-keyword components untouched")
    func cTypeLeavesNonKeywordComponentsUntouched() {
        var module = Transformer.CType(isEnabled: true)
        module.replacements = [.double: "CGFloat"]
        let input = SemanticString(components: [
            AtomicComponent(string: "double", type: .keyword),
            AtomicComponent(string: " ", type: .standard),
            AtomicComponent(string: "value", type: .variable),
        ])
        #expect(module.transform(input).string == "CGFloat value")
    }

    /// A replacement stands in for a whole C type: the keywords spelling one
    /// type, nothing before or around them.
    struct WholeTypeCase: Sendable, CustomTestStringConvertible {
        let keywords: [String]
        let replacements: [Transformer.CType.Pattern: String]
        let expected: String

        var testDescription: String { keywords.joined(separator: " ") }
    }

    @Test(
        "CType replaces whole types only",
        arguments: [
            // A qualifier before the type keeps its space.
            WholeTypeCase(keywords: ["const", "double"], replacements: [.double: "CGFloat"], expected: "const CGFloat"),
            // `unsigned long` is a type of its own, not `long` with a prefix.
            WholeTypeCase(keywords: ["unsigned", "long"], replacements: [.long: "NSInteger"], expected: "unsigned long"),
            // Nor is `long double` a `long` followed by a `double`.
            WholeTypeCase(keywords: ["long", "double"], replacements: Transformer.CType.Presets.foundation, expected: "long double"),
        ]
    )
    func cTypeReplacesWholeTypesOnly(wholeTypeCase: WholeTypeCase) {
        var module = Transformer.CType(isEnabled: true)
        module.replacements = wholeTypeCase.replacements
        #expect(module.transform(semanticKeywords(wholeTypeCase.keywords)).string == wholeTypeCase.expected)
    }

    @Test("ObjCIvarOffset renders its template")
    func objcIvarOffsetRendersTemplate() {
        let module = Transformer.ObjCIvarOffset(isEnabled: true)
        #expect(module.transform(.init(offset: 8)) == "offset: 0x8")
    }

    @Test("ObjCConfiguration tolerates missing keys and reports enablement")
    func objcConfigurationDecodingAndEnablement() throws {
        let decoded = try JSONDecoder().decode(
            Transformer.ObjCConfiguration.self,
            from: Data("{}".utf8)
        )
        #expect(decoded == .init())
        #expect(!decoded.hasEnabledModules)

        var configuration = Transformer.ObjCConfiguration()
        configuration.ivarOffset.isEnabled = true
        #expect(configuration.hasEnabledModules)
    }
}
