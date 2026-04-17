import AppKit

/// Small modal dialog with a centred app-icon tile at the top, title, body,
/// optional text field, and one or two buttons. Used instead of NSAlert in
/// SpaceMan because NSAlert forces the icon to the top-left corner.
enum SpaceManDialog {

    /// Prompt the user for a line of text. Returns the trimmed input on
    /// confirm, or nil on cancel / empty input.
    @MainActor
    static func promptText(
        title: String,
        body: String,
        placeholder: String = "",
        confirmTitle: String = "OK",
        cancelTitle: String = "Cancel"
    ) -> String? {
        let field = NSTextField(frame: .zero)
        field.placeholderString = placeholder
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        let confirmed = runModal(
            title: title,
            body: body,
            accessory: field,
            confirmTitle: confirmTitle,
            cancelTitle: cancelTitle,
            initialFirstResponder: field
        )
        guard confirmed else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Show a simple message. If `cancelTitle` is nil, only the confirm
    /// button is shown. Returns true on confirm.
    @discardableResult
    @MainActor
    static func showMessage(
        title: String,
        body: String,
        confirmTitle: String = "OK",
        cancelTitle: String? = nil
    ) -> Bool {
        runModal(
            title: title,
            body: body,
            accessory: nil,
            confirmTitle: confirmTitle,
            cancelTitle: cancelTitle,
            initialFirstResponder: nil
        )
    }

    // MARK: - Private

    @MainActor
    private static func runModal(
        title: String,
        body: String,
        accessory: NSView?,
        confirmTitle: String,
        cancelTitle: String?,
        initialFirstResponder: NSView?
    ) -> Bool {
        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 64).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 0

        let bodyLabel = NSTextField(wrappingLabelWithString: body)
        bodyLabel.alignment = .center
        bodyLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.preferredMaxLayoutWidth = 280

        // Buttons
        let confirmButton = NSButton(title: confirmTitle, target: ModalResponder.shared, action: #selector(ModalResponder.confirm))
        confirmButton.keyEquivalent = "\r"
        confirmButton.bezelStyle = .rounded

        let buttonRow: NSStackView
        if let cancelTitle {
            let cancel = NSButton(title: cancelTitle, target: ModalResponder.shared, action: #selector(ModalResponder.cancel))
            cancel.keyEquivalent = "\u{1b}" // Esc
            cancel.bezelStyle = .rounded
            buttonRow = NSStackView(views: [cancel, confirmButton])
        } else {
            buttonRow = NSStackView(views: [confirmButton])
        }
        buttonRow.orientation = .horizontal
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 8
        buttonRow.alignment = .centerY

        // Vertical stack
        var stackViews: [NSView] = [iconView, titleLabel, bodyLabel]
        if let accessory { stackViews.append(accessory) }
        stackViews.append(buttonRow)

        let stack = NSStackView(views: stackViews)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = container
        window.center()
        if let initialFirstResponder {
            window.initialFirstResponder = initialFirstResponder
        }

        ModalResponder.shared.reset()
        let response = NSApp.runModal(for: window)
        window.orderOut(nil)

        return response == .alertFirstButtonReturn
    }
}

/// Shared target/action responder used by dialog buttons to end the modal
/// session. Maps confirm → `.alertFirstButtonReturn`, cancel → `.cancel`.
private final class ModalResponder: NSObject {
    static let shared = ModalResponder()

    func reset() {}

    @objc func confirm() { NSApp.stopModal(withCode: .alertFirstButtonReturn) }
    @objc func cancel()  { NSApp.stopModal(withCode: .cancel) }
}
