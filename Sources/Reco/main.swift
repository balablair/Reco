import AppKit

// 纯 AppKit 入口，不使用 SwiftUI App lifecycle
// 避免 SwiftUI Settings scene 在 setActivationPolicy(.accessory) 时自动 terminate
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
