import UIKit

/// Tap and hold on a swatch: the system color picker (`UIColorPickerViewController`)
/// in a popover next to the swatch. Every color it shows goes straight to the
/// canvas (`CanvasModel.previewColor`), and closing it makes the whole change
/// one undo step (`endColorEdit`).
///
/// Presented from UIKit rather than with SwiftUI's `ColorPicker`, because that
/// one only opens from its own color well, not from a long press.
@MainActor
final class SlotColorPicker: NSObject, UIColorPickerViewControllerDelegate, UIPopoverPresentationControllerDelegate {
    /// Keeps the delegate alive while the picker is on screen.
    private static var current: SlotColorPicker?

    private let model: CanvasModel

    private init(model: CanvasModel) {
        self.model = model
    }

    /// `frame` is the swatch in window coordinates (SwiftUI's global space).
    static func present(slot: PaletteSlot, model: CanvasModel, from frame: CGRect) {
        guard let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first,
              var top = window.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        guard !(top is UIColorPickerViewController) else { return }

        let session = SlotColorPicker(model: model)
        model.beginColorEdit(slot)

        let picker = UIColorPickerViewController()
        picker.title = "Color \(slot.number)"
        picker.supportsAlpha = false            // logo colors are opaque
        picker.selectedColor = UIColor(cgColor: model.project.color(for: slot).cgColor)
        picker.delegate = session
        picker.modalPresentationStyle = .popover
        if let popover = picker.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = frame
            popover.permittedArrowDirections = [.right, .left]
            popover.delegate = session
        }
        current = session
        top.present(picker, animated: true)
    }

    func colorPickerViewController(_ picker: UIColorPickerViewController, didSelect color: UIColor,
                                   continuously: Bool) {
        guard let hex = HexColor.sRGB(from: color.cgColor)?.color else { return }
        model.previewColor(hex)
    }

    /// The picker's own close button.
    func colorPickerViewControllerDidFinish(_ picker: UIColorPickerViewController) {
        finish()
    }

    /// A tap outside the popover.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish()
    }

    /// Stay a popover on iPad, whatever the size class.
    func adaptivePresentationStyle(for controller: UIPresentationController,
                                   traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }

    private func finish() {
        model.endColorEdit()
        Self.current = nil
    }
}
