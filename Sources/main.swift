import AppKit

AppLaunch.runLaunchCommandIfRequested()

let application = NSApplication.shared
let controller = AppController()
application.setActivationPolicy(.accessory)
application.delegate = controller
application.run()
