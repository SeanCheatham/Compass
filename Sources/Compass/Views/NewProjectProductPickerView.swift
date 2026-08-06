import AppKit
import CompassCore

/// Accessory view for the New Project save panel: pick `cli` / `macos` / `server`.
final class NewProjectProductPickerView: NSView {
  private let cliButton = NSButton(checkboxWithTitle: "CLI", target: nil, action: nil)
  private let macosButton = NSButton(checkboxWithTitle: "macOS", target: nil, action: nil)
  private let serverButton = NSButton(checkboxWithTitle: "Server", target: nil, action: nil)

  override init(frame frameRect: NSRect) {
    super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 52))
    cliButton.state = .on
    macosButton.state = .on
    serverButton.state = .off

    let label = NSTextField(labelWithString: "Products:")
    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    label.textColor = .secondaryLabelColor

    let stack = NSStackView(views: [label, cliButton, macosButton, serverButton])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func selectedProducts() -> [GeneratedProduct] {
    var products: [GeneratedProduct] = []
    if cliButton.state == .on { products.append(.cli) }
    if macosButton.state == .on { products.append(.macos) }
    if serverButton.state == .on { products.append(.server) }
    return GeneratedProducts.normalize(products)
  }
}
