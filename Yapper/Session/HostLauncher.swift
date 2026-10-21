import Foundation

/// Brings an app to the front by bundle ID, the way tapping its icon does:
/// no link is delivered, so the app comes back exactly where the user left
/// it. Private API (LaunchServices' `LSApplicationWorkspace`), by Justin's
/// decision (2026-10-21), for auto-return only. Everything is looked up by
/// name and checked; any miss returns false and the caller falls back to a
/// checked link (`ReturnLinks`) or the swipe-back screen.
enum HostLauncher {
    /// Blocks on a call to LaunchServices, so call it off the main thread.
    static func open(_ bundleID: String) -> Bool {
        guard !bundleID.isEmpty,
              let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type
        else { return false }
        let shared = NSSelectorFromString("defaultWorkspace")
        guard (workspaceClass as AnyObject).responds(to: shared),
              let workspace = (workspaceClass as AnyObject).perform(shared)?.takeUnretainedValue() as? NSObject
        else { return false }
        // Returns a BOOL, which perform(_:with:) can't read: call the
        // implementation with its real signature.
        let open = NSSelectorFromString("openApplicationWithBundleID:")
        guard workspace.responds(to: open) else { return false }
        typealias Open = @convention(c) (NSObject, Selector, NSString) -> Bool
        let call = unsafeBitCast(workspace.method(for: open), to: Open.self)
        return call(workspace, open, bundleID as NSString)
    }
}
