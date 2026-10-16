import UIKit

/// Which app the keyboard is typing into, so Yapper can send the user back
/// to it once recording has started. Private API (see HostArbiter.m); every
/// read is by name and guarded, so when Apple changes it the answer is nil
/// and the user gets the swipe-back screen instead. Adapted from Dictus
/// (MIT, github.com/getdictus/dictus-ios).
///
/// The arbiter's `sourceBundleIdentifier` can name an app the user has
/// already left, so it is never used directly. Each read records the pair
/// (pid, bundle ID); the host is our own controller's `_hostProcessIdentifier`,
/// which is always current; the answer is the bundle ID recorded for that pid
/// since the keyboard last appeared. A stale reading becomes no answer, never
/// the wrong app. The table lives only in this process: pids get reused.
enum HostApp {
    private static var bundleByPid: [Int: String] = [:]

    /// Forget the last appearance, register with the arbiter, and read it.
    static func keyboardWillAppear() {
        bundleByPid.removeAll()
        connect()
        harvest()
    }

    /// The host's bundle ID, or nil when it isn't known for sure.
    static func current(for controller: UIInputViewController) -> String? {
        // Again at the tap: on a fresh extension the arbiter fills in about
        // 200 ms after the keyboard appears.
        harvest()
        guard let pid = (read("_hostProcessIdentifier", from: controller) as? NSNumber)?.intValue, pid > 0 else {
            return nil
        }
        return bundleByPid[pid]
    }

    private static func harvest() {
        guard let client = arbiterClient(),
              let state = read("currentClientState", from: client) as? NSObject,
              let bundle = read("sourceBundleIdentifier", from: state) as? String, !bundle.isEmpty,
              let pid = (read("processIdentifier", from: state) as? NSNumber)?.intValue, pid > 0
        else { return }
        bundleByPid[pid] = bundle
    }

    /// The arbiter only tells keyboards that have registered with it, and
    /// drops a keyboard whenever it leaves the screen. Register again as the
    /// keyboard appears, so the host's record arrives before the mic tap.
    private static func connect() {
        guard let client = arbiterClient(), read("connection", from: client) == nil else { return }
        let start = NSSelectorFromString("startConnection")
        guard client.responds(to: start) else { return }
        _ = client.perform(start)
    }

    private static func arbiterClient() -> NSObject? {
        guard let cls = NSClassFromString("_UIKeyboardArbiterClient") as? NSObject.Type else { return nil }
        let shared = NSSelectorFromString("automaticSharedArbiterClient")
        let object = cls as AnyObject
        guard object.responds(to: shared) else { return nil }
        return object.perform(shared)?.takeUnretainedValue() as? NSObject
    }

    /// KVC that can't crash: a missing key would raise an Objective-C
    /// exception Swift can't catch.
    private static func read(_ key: String, from object: NSObject) -> Any? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        return object.value(forKey: key)
    }
}
