import Testing
import Foundation
import MachOKit
import ObjCDump
import ObjCTypeDecodeKit
import Semantic
@testable import ObjCDeclarationRendering

/// C writes an array's dimensions after the name it declares — `char name[32]`
/// — and an array of arrays outermost first: `int grid[8][4]`, encoded
/// `[8[4i]]`, is eight arrays of four ints.
@Suite("Array declarators")
struct ArrayDeclaratorRenderingTests {
    private static func makeContext() throws -> ObjCRenderingContext<MachOImage> {
        ObjCRenderingContext(machO: try #require(MachOImage(name: "Foundation")))
    }

    @Test("A struct field keeps its array dimension")
    func structFieldKeepsArrayDimension() throws {
        let field = ObjCField(type: .array(type: .char, size: 56), name: "__opaque")

        #expect(field.semanticString(fallbackName: "x0", context: try Self.makeContext()).string == "char __opaque[56];")
    }

    @Test("The array field of a struct ivar keeps its dimension, and the ivar gets none")
    func structIvarArrayFieldKeepsDimension() throws {
        let ivar = ObjCIvarInfo(name: "_info", typeEncoding: #"{?="count"i"name"[32c]}"#, offset: 8)
        let rendered = ivar.semanticString(using: try Self.makeContext()).string

        #expect(rendered.contains("char name[32];"))
        #expect(rendered.hasSuffix("} _info;"))
    }

    @Test("An array of arrays keeps every dimension, outermost first")
    func multidimensionalArrayKeepsEveryDimension() throws {
        let ivar = ObjCIvarInfo(name: "_grid", typeEncoding: "[8[4i]]", offset: 8)

        #expect(ivar.semanticString(using: try Self.makeContext()).string == "int _grid[8][4];")
    }

    @Test("A struct field of a method argument keeps its array dimension")
    func methodArgumentStructFieldKeepsDimension() throws {
        let method = ObjCMethodInfo(
            name: "takeDecimal:",
            typeEncoding: #"v40@0:8{?="_length"I"_mantissa"[8S]}16"#,
            isClassMethod: false,
            imp: 0
        )

        #expect(method.semanticString(using: try Self.makeContext()).string.contains("unsigned short _mantissa[8];"))
    }
}
