//
//  SwiftInjection.swift
//  InjectionBundle
//
//  Created by John Holdsworth on 05/11/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//
//  $Id: //depot/ResidentEval/InjectionBundle/SwiftInjection.swift#40 $
//
//  Cut-down version of code injection in Swift. Uses code
//  from SwiftEval.swift to recompile and reload class.
//

#if arch(x86_64) || arch(i386) // simulator/macOS only
import Foundation
import XCTest

@objc public protocol SwiftInjected {
    @objc optional func injected()
}

#if os(iOS) || os(tvOS)
import UIKit

extension UIViewController {

    /// inject a UIView controller and redraw
    public func injectVC() {
        inject()
        for subview in self.view.subviews {
            subview.removeFromSuperview()
        }
        if let sublayers = self.view.layer.sublayers {
            for sublayer in sublayers {
                sublayer.removeFromSuperlayer()
            }
        }
        viewDidLoad()
    }
}
#else
import Cocoa
#endif

extension NSObject {

    public func inject() {
        if let oldClass: AnyClass = object_getClass(self) {
            SwiftInjection.inject(oldClass: oldClass, classNameOrFile: "\(oldClass)")
        }
    }

    @objc
    public class func inject(file: String) {
        SwiftInjection.inject(oldClass: nil, classNameOrFile: file)
    }
}

@objc
public class SwiftInjection: NSObject {

    static let testQueue = DispatchQueue(label: "INTestQueue")

    @objc
    public class func inject(oldClass: AnyClass?, classNameOrFile: String) {
        do {
            let tmpfile = try SwiftEval.instance.rebuildClass(oldClass: oldClass,
                                                              classNameOrFile: classNameOrFile, extra: nil)
            try inject(tmpfile: tmpfile)
        }
        catch {
        }
    }

    @objc
    public class func replayInjections() -> Int {
        var injectionNumber = 0
        do {
            func mtime(_ path: String) -> time_t {
                return SwiftEval.instance.mtime(URL(fileURLWithPath: path))
            }
            let execBuild = mtime(Bundle.main.executablePath!)

            while true {
                let tmpfile = "/tmp/eval\(injectionNumber + 1)"
                if mtime("\(tmpfile).dylib") < execBuild {
                    break
                }
                try self.inject(tmpfile: tmpfile)
                injectionNumber += 1
            }
        }
        catch {
        }
        return injectionNumber
    }

    @objc
    public class func inject(tmpfile: String) throws {
        let newClasses = try SwiftEval.instance.loadAndInject(tmpfile: tmpfile)
        let oldClasses = // oldClass != nil ? [oldClass!] :
            newClasses.map { objc_getClass(class_getName($0)) as! AnyClass }
        var testClasses = [AnyClass]()
        for i in 0 ..< oldClasses.count {
            let oldClass: AnyClass = oldClasses[i], newClass: AnyClass = newClasses[i]

            // old-school swizzle Objective-C class & instance methods
            injection(swizzle: object_getClass(newClass), onto: object_getClass(oldClass))
            injection(swizzle: newClass, onto: oldClass)

            // overwrite Swift vtable of existing class with implementations from new class
            let existingClass = unsafeBitCast(oldClass, to: UnsafeMutablePointer<ClassMetadataSwift>.self)
            let classMetadata = unsafeBitCast(newClass, to: UnsafeMutablePointer<ClassMetadataSwift>.self)

            // Swift equivalent of Swizzling
            if (classMetadata.pointee.Data & 0x1) == 1 {
                if classMetadata.pointee.ClassSize != existingClass.pointee.ClassSize {
                    NSLog("\(oldClass) metadata size changed. Did you add a method?")
                }

                func byteAddr<T>(_ location: UnsafeMutablePointer<T>) -> UnsafeMutablePointer<UInt8> {
                    return location.withMemoryRebound(to: UInt8.self, capacity: 1) { $0 }
                }

                let vtableOffset = byteAddr(&existingClass.pointee.IVarDestroyer) - byteAddr(existingClass)
                let vtableLength = Int(existingClass.pointee.ClassSize -
                    existingClass.pointee.ClassAddressPoint) - vtableOffset

                print("Injected '\(NSStringFromClass(oldClass))', vtable length: \(vtableLength)")
                memcpy(byteAddr(existingClass) + vtableOffset,
                       byteAddr(classMetadata) + vtableOffset, vtableLength)
            }

            if newClass.isSubclass(of: XCTestCase.self) {
                testClasses.append(newClass)
//                if ( [newClass isSubclassOfClass:objc_getClass("QuickSpec")] )
//                [[objc_getClass("_TtC5Quick5World") sharedWorld]
//                setCurrentExampleMetadata:nil];
            }
        }

        // Thanks https://github.com/johnno1962/injectionforxcode/pull/234
        if !testClasses.isEmpty {
            self.testQueue.async {
                testQueue.suspend()
                let timer = Timer(timeInterval: 0, repeats: false, block: { _ in
                    for newClass in testClasses {
                        let suite0 = XCTestSuite(name: "Injected")
                        let suite = XCTestSuite(forTestCaseClass: newClass)
                        let tr = XCTestSuiteRun(test: suite)
                        suite0.addTest(suite)
                        suite0.perform(tr)
                    }
                    testQueue.resume()
                })
                RunLoop.main.add(timer, forMode: RunLoopMode.commonModes)
            }
        }
        else {
            #if os(iOS) || os(tvOS)
            let app = UIApplication.shared
            #else
            let app = NSApplication.shared
            #endif
            let seeds: [Any] = [app.delegate as Any] + app.windows
            SwiftSweeper(instanceTask: {
                (instance: AnyObject) in
                #if os(iOS) || os(tvOS)
                
                if let vc = instance as? UIViewController {
                    if instance is UITabBarController || instance is UINavigationController {
                        print("ignore vc: \(instance)")
                    }else if vc.isViewLoaded && vc.view.window != nil {
                        print("start reload vc: \(vc)")
                        for subview in vc.view.subviews {
                            subview.removeFromSuperview()
                        }
                        if let sublayers = vc.view.layer.sublayers {
                            for sublayer in sublayers {
                                sublayer.removeFromSuperlayer()
                            }
                        }

                        vc.viewDidLoad()
                        vc.viewWillAppear(false)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            vc.viewDidAppear(false)
                        }
                    }
                    else {
                        print("ignore vc: \(vc)")
                    }
                }
                #endif
            }).sweepValue(seeds)
//            let injectedClasses = oldClasses.filter {
//                class_getInstanceMethod($0, #selector(SwiftInjected.injected)) != nil }
            //
//            // implement -injected() method using sweep of objects in application
//            if !injectedClasses.isEmpty {
//                #if os(iOS) || os(tvOS)
//                let app = UIApplication.shared
//                #else
//                let app = NSApplication.shared
//                #endif
//                let seeds: [Any] =  [app.delegate as Any] + app.windows
//                SwiftSweeper(instanceTask: {
//                    (instance: AnyObject) in
//                    if injectedClasses.contains(where: { $0 == object_getClass(instance) }) {
//                        let proto = unsafeBitCast(instance, to: SwiftInjected.self)
//                        proto.injected?()
//                    }
//                }).sweepValue(seeds)
//            }
            //
//            let notification = Notification.Name("INJECTION_BUNDLE_NOTIFICATION")
//            NotificationCenter.default.post(name: notification, object: oldClasses)
        }
    }

    static func injection(swizzle newClass: AnyClass?, onto oldClass: AnyClass?) {
        var methodCount: UInt32 = 0
        if let methods = class_copyMethodList(newClass, &methodCount) {
            for i in 0 ..< Int(methodCount) {
                class_replaceMethod(oldClass, method_getName(methods[i]),
                                    method_getImplementation(methods[i]),
                                    method_getTypeEncoding(methods[i]))
            }
            free(methods)
        }
    }
}

class SwiftSweeper {

    static var current: SwiftSweeper?

    let instanceTask: (AnyObject) -> Void
    var seen = [UnsafeRawPointer: Bool]()

    init(instanceTask: @escaping (AnyObject) -> Void) {
        self.instanceTask = instanceTask
        SwiftSweeper.current = self
    }

    func sweepValue(_ value: Any) {
        let mirror = Mirror(reflecting: value)
        if var style = mirror.displayStyle {
            if _typeName(mirror.subjectType).hasPrefix("Swift.ImplicitlyUnwrappedOptional<") {
                style = .optional
            }
            switch style {
            case .set:
                fallthrough
            case .collection:
                for (_, child) in mirror.children {
                    self.sweepValue(child)
                }
                return
            case .dictionary:
                for (_, child) in mirror.children {
                    for (_, element) in Mirror(reflecting: child).children {
                        self.sweepValue(element)
                    }
                }
                return
            case .class:
                self.sweepInstance(value as AnyObject)
                return
            case .optional:
                if let some = mirror.children.first?.value {
                    self.sweepValue(some)
                }
                return
            case .enum:
                if let evals = mirror.children.first?.value {
                    self.sweepValue(evals)
                }
            case .tuple:
                fallthrough
            case .struct:
                self.sweepMembers(value)
            }
        }
    }

    func sweepInstance(_ instance: AnyObject) {
        let reference = unsafeBitCast(instance, to: UnsafeRawPointer.self)
        if self.seen[reference] == nil {
            self.seen[reference] = true

            self.instanceTask(instance)

            self.sweepMembers(instance)
            instance.legacySwiftSweep?()
        }
    }

    func sweepMembers(_ instance: Any) {
        var mirror: Mirror? = Mirror(reflecting: instance)
        while mirror != nil {
            for (_, value) in mirror!.children {
                self.sweepValue(value)
            }
            mirror = mirror!.superclassMirror
        }
    }
}

extension NSObject {
    @objc func legacySwiftSweep() {
        var icnt: UInt32 = 0, cls: AnyClass? = object_getClass(self)!
        let object = "@".utf16.first!
        while cls != nil && cls != NSObject.self && cls != NSURL.self {
            let className = NSStringFromClass(cls!)
            if className.hasPrefix("_") {
                return
            }
            #if os(OSX)
            if className.starts(with: "NS") && cls != NSWindow.self {
                return
            }
            #endif
            if let ivars = class_copyIvarList(cls, &icnt) {
                for i in 0 ..< Int(icnt) {
                    if let type = ivar_getTypeEncoding(ivars[i]), type[0] == object {
                        (unsafeBitCast(self, to: UnsafePointer<Int8>.self) + ivar_getOffset(ivars[i]))
                            .withMemoryRebound(to: AnyObject?.self, capacity: 1) {
//                                print("\(self) \(String(cString: ivar_getName(ivars[i])!))")
                                if let obj = $0.pointee {
                                    SwiftSweeper.current?.sweepInstance(obj)
                                }
                            }
                    }
                }
                free(ivars)
            }
            cls = class_getSuperclass(cls)
        }
    }
}

extension NSSet {
    @objc override func legacySwiftSweep() {
        self.forEach { SwiftSweeper.current?.sweepInstance($0 as AnyObject) }
    }
}

extension NSArray {
    @objc override func legacySwiftSweep() {
        self.forEach { SwiftSweeper.current?.sweepInstance($0 as AnyObject) }
    }
}

extension NSDictionary {
    @objc override func legacySwiftSweep() {
        self.allValues.forEach { SwiftSweeper.current?.sweepInstance($0 as AnyObject) }
    }
}

/**
 Layout of a class instance. Needs to be kept in sync with ~swift/include/swift/Runtime/Metadata.h
 */
public struct ClassMetadataSwift {

    public let MetaClass: uintptr_t = 0, SuperClass: uintptr_t = 0
    public let CacheData1: uintptr_t = 0, CacheData2: uintptr_t = 0

    public let Data: uintptr_t = 0

    /// Swift-specific class flags.
    public let Flags: UInt32 = 0

    /// The address point of instances of this type.
    public let InstanceAddressPoint: UInt32 = 0

    /// The required size of instances of this type.
    /// 'InstanceAddressPoint' bytes go before the address point;
    /// 'InstanceSize - InstanceAddressPoint' bytes go after it.
    public let InstanceSize: UInt32 = 0

    /// The alignment mask of the address point of instances of this type.
    public let InstanceAlignMask: UInt16 = 0

    /// Reserved for runtime use.
    public let Reserved: UInt16 = 0

    /// The total size of the class object, including prefix and suffix
    /// extents.
    public let ClassSize: UInt32 = 0

    /// The offset of the address point within the class object.
    public let ClassAddressPoint: UInt32 = 0

    /// An out-of-line Swift-specific description of the type, or null
    /// if this is an artificial subclass.  We currently provide no
    /// supported mechanism for making a non-artificial subclass
    /// dynamically.
    public let Description: uintptr_t = 0

    /// A function for destroying instance variables, used to clean up
    /// after an early return from a constructor.
    public var IVarDestroyer: SIMP?

    // After this come the class members, laid out as follows:
    //   - class members for the superclass (recursively)
    //   - metadata reference for the parent, if applicable
    //   - generic parameters for this class
    //   - class variables (if we choose to support these)
    //   - "tabulated" virtual methods

}

/** pointer to a function implementing a Swift method */
public typealias SIMP = @convention(c) (_: AnyObject) -> Void

#if swift(>=3.0)
// not public in Swift3
@_silgen_name("swift_demangle")
private
func _stdlib_demangleImpl(
    mangledName: UnsafePointer<CChar>?,
    mangledNameLength: UInt,
    outputBuffer: UnsafeMutablePointer<UInt8>?,
    outputBufferSize: UnsafeMutablePointer<UInt>?,
    flags: UInt32
) -> UnsafeMutablePointer<CChar>?

public func _stdlib_demangleName(_ mangledName: String) -> String {
    return mangledName.utf8CString.withUnsafeBufferPointer {
        mangledNameUTF8 in

        let demangledNamePtr = _stdlib_demangleImpl(
            mangledName: mangledNameUTF8.baseAddress,
            mangledNameLength: UInt(mangledNameUTF8.count - 1),
            outputBuffer: nil,
            outputBufferSize: nil,
            flags: 0)

        if let demangledNamePtr = demangledNamePtr {
            let demangledName = String(cString: demangledNamePtr)
            free(demangledNamePtr)
            return demangledName
        }
        return mangledName
    }
}
#endif
#endif
