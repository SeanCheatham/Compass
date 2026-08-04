import AppKit
import Foundation
import SwiftUI
import Virtualization

/// SwiftUI wrapper around `VZVirtualMachineView`.
///
/// Threading: all VZ APIs (including assignment to `VZVirtualMachineView.virtualMachine`)
/// are main-thread-only. `NSViewRepresentable.updateNSView` runs on main, so this is
/// fine — just don't try to push the assignment off-main via `Task.detached`.
struct SharedCompassVMView: NSViewRepresentable {
  /// Live VZ machine to render. Nil means "show a blank view" (used during
  /// pre-provisioning and warmup).
  var virtualMachine: VZVirtualMachine?

  /// Whether the embedded view should automatically capture system shortcuts.
  /// Default false to keep host shortcuts (cmd-Q, cmd-W, etc.) working.
  var capturesSystemKeys: Bool = false

  /// Whether to start with the embedded view as first responder so keystrokes
  /// route to the guest. Default true while the Runtime section is active.
  var becomesFirstResponderOnAppear: Bool = true

  func makeNSView(context: Context) -> CompassVZContainer {
    let container = CompassVZContainer()
    container.vmView.virtualMachine = virtualMachine
    container.vmView.capturesSystemKeys = capturesSystemKeys
    container.becomesFirstResponderOnAppear = becomesFirstResponderOnAppear
    return container
  }

  func updateNSView(_ nsView: CompassVZContainer, context: Context) {
    // Only reassign if the identity changed — assigning the same machine
    // repeatedly is harmless but generates extra layer churn.
    if nsView.vmView.virtualMachine !== virtualMachine {
      nsView.vmView.virtualMachine = virtualMachine
    }
    nsView.vmView.capturesSystemKeys = capturesSystemKeys
    nsView.becomesFirstResponderOnAppear = becomesFirstResponderOnAppear
    if becomesFirstResponderOnAppear, virtualMachine != nil {
      nsView.window?.makeFirstResponder(nsView.vmView)
    }
  }

  /// Container view that wraps `VZVirtualMachineView` and is responsible for
  /// first-responder wiring. We use a container (rather than exposing the
  /// VZ view directly) so we can manage layout + future overlays without
  /// fighting the VZ view's autoresizing semantics.
  final class CompassVZContainer: NSView {
    let vmView = VZVirtualMachineView()
    var becomesFirstResponderOnAppear: Bool = true

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      commonInit()
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      commonInit()
    }

    private func commonInit() {
      wantsLayer = true
      vmView.translatesAutoresizingMaskIntoConstraints = false
      addSubview(vmView)
      NSLayoutConstraint.activate([
        vmView.leadingAnchor.constraint(equalTo: leadingAnchor),
        vmView.trailingAnchor.constraint(equalTo: trailingAnchor),
        vmView.topAnchor.constraint(equalTo: topAnchor),
        vmView.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if becomesFirstResponderOnAppear, vmView.virtualMachine != nil {
        window?.makeFirstResponder(vmView)
      }
    }

    override func mouseDown(with event: NSEvent) {
      // Forward focus to the VZ view on click so keyboard input is captured.
      window?.makeFirstResponder(vmView)
      super.mouseDown(with: event)
    }
  }
}
