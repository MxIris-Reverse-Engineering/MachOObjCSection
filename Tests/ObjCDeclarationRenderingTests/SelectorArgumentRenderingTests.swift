import Testing
import Foundation
import MachOKit
import ObjCDump
import Semantic
@testable import ObjCDeclarationRendering

/// A selector has one argument per colon, and a colon need not follow a label:
/// Swift's `@objc func add(_ a: Int, _ b: Int)` is `add::`, and `- (void)foo:(id)a :(id)b`
/// is `foo::` in Objective-C.
@Suite("Selector arguments")
struct SelectorArgumentRenderingTests {
    private static func render(selector: String, typeEncoding: String) throws -> String {
        let context = ObjCRenderingContext(machO: try #require(MachOImage(name: "Foundation")))
        let method = ObjCMethodInfo(name: selector, typeEncoding: typeEncoding, isClassMethod: false, imp: 0)
        return method.semanticString(using: context).string
    }

    @Test("An unlabeled argument after a labeled one is rendered")
    func unlabeledSecondArgument() throws {
        let rendered = try Self.render(selector: "add::", typeEncoding: "v32@0:8q16q24")

        #expect(rendered.hasPrefix("- (void)add:(long long)"))
        #expect(rendered.components(separatedBy: ":(long long)").count - 1 == 2)
    }

    @Test("A selector of a lone colon renders its one argument")
    func loneColonSelector() throws {
        let rendered = try Self.render(selector: ":", typeEncoding: "v24@0:8@16")

        #expect(rendered.hasPrefix("- (void):(id)"))
    }
}
