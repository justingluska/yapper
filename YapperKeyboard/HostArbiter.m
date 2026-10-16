// Switches on UIKit's keyboard arbiter, which knows which app the keyboard
// is typing into, so the app can send the user back there after it starts
// recording (HostApp.swift reads it).
//
// Private API, by Justin's decision (2026-10-16): there is no public way.
// It runs when the extension loads, before main: the arbiter's client is set
// up early, and switching it on later (viewWillAppear) leaves it silent.
// Adapted from Dictus (MIT, github.com/getdictus/dictus-ios).
//
// Everything is looked up by name and every step is nil-checked: a missing
// class or method is a clean no-op, and the feature falls back to the
// swipe-back screen. No logging here; nothing is set up yet.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

__attribute__((constructor))
static void YapperEnableKeyboardArbiter(void) {
    Class cls = NSClassFromString(@"_UIKeyboardArbiterClient");
    if (cls == Nil) {
        return;
    }
    Method method = class_getClassMethod(cls, NSSelectorFromString(@"enabled"));
    if (method == NULL) {
        return;
    }
    // A class method's block gets the class and no _cmd.
    IMP replacement = imp_implementationWithBlock(^BOOL(id _self) {
        return YES;
    });
    method_setImplementation(method, replacement);
}
