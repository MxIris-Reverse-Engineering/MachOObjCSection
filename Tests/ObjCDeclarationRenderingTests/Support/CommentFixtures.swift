import Testing
import MachOKit
import ObjCDeclarationRendering

/// What the comment tests render with: Foundation, already loaded in this
/// process, every comment switched on, and IMP values that do and do not
/// resolve in it.
enum CommentFixtures {
    static func foundationImage() throws -> MachOImage {
        try #require(MachOImage(name: "Foundation"))
    }

    static let everyComment = ObjCGenerationOptions(
        addIvarOffsetComments: true,
        addPropertyAttributesComments: true,
        addMethodIMPAddressComments: true,
        addPropertyAccessorAddressComments: true
    )

    /// A raw IMP value that resolves to an address in `machO`: one past its
    /// header.
    static func resolvableIMP(in machO: MachOImage) -> UInt64 {
        UInt64(UInt(bitPattern: machO.ptr)) + 0x1000
    }
}
