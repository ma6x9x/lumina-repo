#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Plain ObjC-runtime method replacement. No Substrate/Logos dependency in the
// hook layer, and every hook FAILS CLOSED: a missing class or selector installs
// nothing and is traced, so an iOS release that renames a private method costs
// a feature, not SpringBoard.

/// Replaces -[cls sel]. `factory` receives the original IMP and returns the
/// block that becomes the new implementation (block signature: (id self, ...)).
/// Returns the original IMP, or NULL if class/method was not found.
IMP Sk1nHookInstanceMethod(Class cls, SEL sel, id (^factory)(IMP orig));

/// Convenience: NSClassFromString + Sk1nHookInstanceMethod.
IMP Sk1nHookNamed(NSString *className, SEL sel, id (^factory)(IMP orig));
