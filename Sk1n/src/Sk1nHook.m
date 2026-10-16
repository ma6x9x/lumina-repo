#import "Sk1nHook.h"
#import "SPKRuntime.h"

IMP Sk1nHookInstanceMethod(Class cls, SEL sel, id (^factory)(IMP orig)) {
    if (!cls || !sel || !factory) return NULL;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NULL;
    IMP orig = method_getImplementation(m);
    id block = factory(orig);
    if (!block) return NULL;
    IMP repl = imp_implementationWithBlock(block);
    if (!repl) return NULL;
    class_replaceMethod(cls, sel, repl, method_getTypeEncoding(m));
    return orig;
}

IMP Sk1nHookNamed(NSString *className, SEL sel, id (^factory)(IMP orig)) {
    Class cls = NSClassFromString(className);
    NSString *what = [NSString stringWithFormat:@"%@.%@", className, NSStringFromSelector(sel)];
    if (!cls) {
        SPKTrace(@"hook_missing_class", @{@"target": what});
        return NULL;
    }
    SPKTrace(@"hook_begin", @{@"target": what});
    IMP orig = Sk1nHookInstanceMethod(cls, sel, factory);
    SPKTrace(orig ? @"hook_installed" : @"hook_missing_selector", @{@"target": what});
    return orig;
}
