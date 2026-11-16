import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  /// Native glass's window (lib/desktop/backdrop.dart): the desktop, blurred, behind the app.
  private var glass: NSVisualEffectView?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Flutter paints every pixel of the page itself, except in native glass, where the page is
    // see-through to the glass behind it.
    flutterViewController.backgroundColor = .clear
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    // Each desktop widget is a window with an engine of its own: it gets the same plugins.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
    }
    (NSApp.delegate as? AppDelegate)?.attach(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// The glass on or off, light or dark to match the app rather than the Mac. Off where the Mac
  /// has Reduce transparency on: false, and the app frosts its own.
  func setGlass(_ on: Bool, dark: Bool) -> Bool {
    let wanted = on && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    guard let content = contentView, let frame = content.superview else { return false }
    if wanted {
      let effect = glass ?? NSVisualEffectView(frame: frame.bounds)
      if glass == nil {
        effect.autoresizingMask = [.width, .height]
        effect.blendingMode = .behindWindow
        effect.material = .sidebar
        effect.state = .active
        // Under the app's own view, in the window's frame view: the title bar is the app's.
        frame.addSubview(effect, positioned: .below, relativeTo: content)
        glass = effect
      }
      effect.frame = frame.bounds
      effect.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      effect.isHidden = false
      isOpaque = false
      backgroundColor = .clear
    } else {
      glass?.isHidden = true
      isOpaque = true
      backgroundColor = .windowBackgroundColor
    }
    invalidateShadow()
    return wanted
  }
}
