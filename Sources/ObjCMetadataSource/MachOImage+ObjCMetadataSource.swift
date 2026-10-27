import Foundation
import MachOKit
import MachOKitExtensions
import MachOObjCSection
import ObjCDump

extension MachOImage: ObjCMetadataSource {
    public typealias ResolvedSource = MachOImage

    public func objcClassInfo<Class: ObjCClassProtocol>(
        of objcClass: Class,
        options: ObjCInfoOptions = .recursive
    ) -> ObjCClassInfo? {
        objcClass.info(in: self, options: options)
    }

    public func objcClassName<Class: ObjCClassProtocol>(of objcClass: Class) -> String? {
        objcClass.name(in: self)
    }

    /// The superclass of `objcClass`, paired with the image it was found in.
    ///
    /// Unlike the file-mode counterpart this resolves across every image mapped
    /// into the process, so the chain runs all the way to the root class.
    public func objcSuperClass<Class: ObjCClassProtocol>(of objcClass: Class) -> (MachOImage, Class)? {
        // Explicitly typed: `superClass(in:)` also has a deprecated overload
        // returning a bare `Self?`, and the two are otherwise ambiguous here.
        let resolved: (MachOImage, Class)? = objcClass.superClass(in: self)
        return resolved
    }

    public func objcProtocolInfo<ObjCProtocol: ObjCProtocolProtocol>(
        of objcProtocol: ObjCProtocol,
        options: ObjCProtocolInfoOptions = .recursive
    ) -> ObjCProtocolInfo? {
        objcProtocol.info(in: self, options: options)
    }

    public func objcCategoryInfo<Category: ObjCCategoryProtocol>(
        of objcCategory: Category,
        options: ObjCInfoOptions = .recursive
    ) -> ObjCCategoryInfo? {
        objcCategory.info(in: self, options: options)
    }

    public func objcCategoryTargetClass<Category: ObjCCategoryProtocol>(
        of objcCategory: Category
    ) -> (MachOImage, Category.ObjCClass)? {
        // Explicitly typed for the same reason as `objcSuperClass(of:)`.
        let resolved: (MachOImage, Category.ObjCClass)? = objcCategory.class(in: self)
        return resolved
    }

    public func objcClassInfo(
        readOnlyDataOffset: Int,
        metaclassReadOnlyDataOffset: Int?,
        name: String,
        superClassName: String?,
        options: ObjCInfoOptions = .recursive
    ) -> (info: ObjCClassInfo, ivarNamesWithUnknownOffset: Set<String>)? {
        func classInfo<ReadOnlyData: ObjCClassRODataProtocol>(
            _: ReadOnlyData.Type
        ) -> (info: ObjCClassInfo, ivarNamesWithUnknownOffset: Set<String>)? {
            guard let readOnlyData = ReadOnlyData(offset: readOnlyDataOffset, in: self) else { return nil }
            let metaclassReadOnlyData = metaclassReadOnlyDataOffset.flatMap { ReadOnlyData(offset: $0, in: self) }
            return readOnlyData.classInfo(
                name: name,
                superClassName: superClassName,
                metaclassData: metaclassReadOnlyData,
                in: self,
                options: options
            )
        }
        return is64Bit ? classInfo(ObjCClassROData64.self) : classInfo(ObjCClassROData32.self)
    }

    public func objcCategoryInfo<Category: ObjCCategoryProtocol>(
        of objcCategory: Category,
        className: String,
        options: ObjCInfoOptions = .recursive
    ) -> ObjCCategoryInfo? {
        objcCategory.info(in: self, className: className, options: options)
    }

    /// A stub in another image is left out: its offset counts from that
    /// image's header, and could equal one of this image's.
    public func objcCategoryTargetClassStubOffset<Category: ObjCCategoryProtocol>(
        of objcCategory: Category
    ) -> Int? {
        guard let (stubImage, stubClass) = objcCategory.stubClass(in: self),
              stubImage.ptr == ptr else {
            return nil
        }
        return stubClass.offset
    }

    /// In image mode the raw `imp` is the live function pointer: an absolute
    /// runtime address that includes the slide. Rebasing it onto the image's
    /// own start turns it into an offset, which `address(forOffset:)` then
    /// reports as an unslid virtual address — the spelling a disassembler
    /// shows. A value below the image start is not an implementation pointer
    /// at all and is rejected.
    ///
    /// On arm64e a method list in the pointer format holds each IMP signed,
    /// its authentication code in the bits above the address, so those bits
    /// come off first: left on, the difference overflowed `Int` and trapped,
    /// or came out as an address nowhere in the image.
    public func objcResolvedIMPAddress(forRawValue rawValue: UInt64) -> UInt64? {
        let value = UInt(stripPointerTags(of: rawValue))
        let baseAddress = UInt(bitPattern: ptr)
        guard value != 0, value >= baseAddress,
              let offset = Int(exactly: value - baseAddress) else {
            return nil
        }
        return address(forOffset: offset)
    }
}
