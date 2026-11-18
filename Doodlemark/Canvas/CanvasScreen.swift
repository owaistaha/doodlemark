import SwiftUI

/// The editor (design/Canvas.png): top bar, tool rail, the square canvas on
/// its backdrop, and the right panel with layers, palette and tool options.
///
/// Sketch and Ink draw for real, with undo/redo, Mirror and Grid. Shapes and
/// Text are placeholders (step 5), Preview & export is step 7, saving step 6.
struct CanvasScreen: View {
    @State var model: CanvasModel
    /// Back to the gallery. `nil` until the gallery exists (step 6).
    var onBack: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            CanvasTopBar(model: model, onBack: onBack)
            Rectangle().fill(Theme.line).frame(height: Theme.Metrics.hairline)
            HStack(spacing: 0) {
                ToolRail(model: model)
                Rectangle().fill(Theme.line).frame(width: Theme.Metrics.hairline)
                CanvasArea(model: model)
                Rectangle().fill(Theme.line).frame(width: Theme.Metrics.hairline)
                CanvasRightPanel(model: model)
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .environment(\.colorScheme, .light)
        .focusedSceneValue(\.canvasModel, model)
    }
}

// MARK: - Keyboard: ⌘Z / ⇧⌘Z

extension FocusedValues {
    /// The canvas in the focused scene, for the Edit-menu commands.
    @Entry var canvasModel: CanvasModel?
}

/// Replaces the system Undo/Redo menu items, which own ⌘Z / ⇧⌘Z on iPadOS,
/// so the keyboard steps our one history whoever is first responder.
struct CanvasCommands: Commands {
    @FocusedValue(\.canvasModel) private var model

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { model?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!(model?.canUndo ?? false))
            Button("Redo") { model?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(model?.canRedo ?? false))
        }
    }
}

// MARK: - Top bar

private struct CanvasTopBar: View {
    let model: CanvasModel
    let onBack: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 16) {
                BarIconButton(symbol: "chevron.left", label: "Back to my logos") { onBack?() }
                    .disabled(onBack == nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.project.name).font(Theme.heading).lineLimit(1)
                    Text("Not saved yet").font(Theme.small).foregroundStyle(Theme.inkMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                // ⌘Z / ⇧⌘Z are the scene's Edit-menu commands (CanvasCommands);
                // the system undo gestures go through HistoryUndoManager.
                BarIconButton(symbol: "arrow.uturn.backward", label: "Undo") { model.undo() }
                    .disabled(!model.canUndo)
                    .accessibilityIdentifier("undo")
                BarIconButton(symbol: "arrow.uturn.forward", label: "Redo") { model.redo() }
                    .disabled(!model.canRedo)
                    .accessibilityIdentifier("redo")
                Rectangle().fill(Theme.line).frame(width: Theme.Metrics.hairline, height: Theme.Metrics.barButton - 16)
                    .padding(.horizontal, 4)
                ToggleButton(title: "Mirror", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                             isOn: model.mirrorOn) { model.mirrorOn.toggle() }
                    .accessibilityIdentifier("mirror")
                ToggleButton(title: "Grid", symbol: "squareshape.split.2x2", isOn: model.gridOn) { model.gridOn.toggle() }
                    .accessibilityIdentifier("grid")
            }

            // Preview & export is step 7.
            PrimaryButton(title: "Preview & export", symbol: "square.and.arrow.up") {}
                .disabled(true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Metrics.barPadding)
        .frame(height: Theme.Metrics.topBarHeight)
        .background(Theme.surface)
    }
}

private struct BarIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .regular))
                .frame(width: Theme.Metrics.barButton, height: Theme.Metrics.barButton)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button)
                    .stroke(Theme.line, lineWidth: Theme.Metrics.hairline))
                .foregroundStyle(isEnabled ? Theme.ink : Theme.lineStrong)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// "Toggle on" from the style guide: pencil blue with white text when on,
/// white with a border when off (fill and border change, not color alone).
private struct ToggleButton: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Theme.bodyStrong)
                .foregroundStyle(isOn ? Theme.surface : Theme.ink)
                .padding(.horizontal, 16)
                .frame(height: Theme.Metrics.barButton)
                .background(isOn ? Theme.pencilBlue : Theme.surface,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.button))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button)
                    .strokeBorder(isOn ? Theme.pencilBlue : Theme.line, lineWidth: Theme.Metrics.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Tangerine main action. Text on tangerine is always ink (DESIGN.md).
private struct PrimaryButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Theme.bodyStrong)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 20)
                .frame(height: Theme.Metrics.barButton)
                .background(Theme.tangerine, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tool rail

private struct ToolRail: View {
    let model: CanvasModel

    var body: some View {
        VStack(spacing: 12) {
            ForEach(CanvasTool.allCases) { tool in
                ToolButton(tool: tool, selected: model.tool == tool) { model.select(tool) }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Metrics.barPadding)
        .frame(width: Theme.Metrics.toolRailWidth)
        .background(Theme.surface)
    }
}

/// 76×76 tool button, icon + label, never icon only. Selected = pencil blue
/// fill with white content (a fill change plus a weight change, not color alone).
private struct ToolButton: View {
    let tool: CanvasTool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 26, weight: selected ? .semibold : .regular))
                Text(tool.title).font(selected ? Theme.labelStrong : Theme.label)
            }
            .frame(width: Theme.Metrics.toolButton, height: Theme.Metrics.toolButton)
            .foregroundStyle(selected ? Theme.surface : Theme.ink)
            .background(selected ? Theme.pencilBlue : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tool-\(tool.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Canvas area

private struct CanvasArea: View {
    let model: CanvasModel
    /// Space above/below the square, from design/Canvas.png.
    private let verticalInset: CGFloat = 80
    private let horizontalInset: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            let side = max(0, min(geo.size.width - 2 * horizontalInset, geo.size.height - 2 * verticalInset))
            ZStack {
                Theme.canvasBackdrop
                PencilCanvas(model: model, config: model.stackConfig)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.canvas))
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.canvas)
                            .fill(Theme.surface)
                            .shadow(color: Theme.CanvasShadow.color, radius: Theme.CanvasShadow.radius,
                                    y: Theme.CanvasShadow.y))
            }
            .overlay(alignment: .topTrailing) {
                ZoomPill(factor: model.zoomFactor) { model.zoomToFit() }
                    .padding(Theme.Metrics.barPadding)
            }
            .overlay(alignment: .bottom) {
                HintPill(text: hint)
                    .padding(.bottom, (verticalInset - Theme.Metrics.minTarget) / 2)
            }
            #if DEBUG
            .overlay(alignment: .topLeading) {
                // Invisible; lets UI tests read the palette and Ink line colors.
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel(model.debugColorSummary)
                    .accessibilityIdentifier("debugColors")
            }
            #endif
        }
    }

    private var hint: String {
        if model.mirrorOn, model.tool == .ink { return "Mirror is on: draw one side, the other side copies you" }
        return switch model.tool {
        case .sketch: "Sketch freely. This layer is never exported."
        case .ink: "Ink: trace clean lines over your sketch"
        case .eraser: "Eraser: touch a line on the \(model.eraserLayer.title) layer to remove it"
        case .shapes: "Shapes are coming soon"
        case .text: "Text is coming soon"
        }
    }
}

/// "100%": zoom relative to the whole canvas fitting. Tap to fit again.
private struct ZoomPill: View {
    let factor: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(Int((factor * 100).rounded()))%")
                .font(Theme.labelStrong)
                .monospacedDigit()
                .padding(.horizontal, 14)
                .frame(minWidth: 60, minHeight: Theme.Metrics.minTarget)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zoom \(Int((factor * 100).rounded())) percent. Tap to fit the canvas.")
        .accessibilityIdentifier("zoomPill")
    }
}

/// Floating dark pill that says what the current tool does.
private struct HintPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Theme.butter).frame(width: 10, height: 10)
            Text(text).font(Theme.bodyStrong).foregroundStyle(Theme.surface)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: Theme.Metrics.minTarget)
        .background(Theme.ink, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("hintPill")
    }
}

// MARK: - Right panel

private struct CanvasRightPanel: View {
    @Bindable var model: CanvasModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Layers").sectionLabelStyle()
                    ForEach(CanvasLayer.allCases) { layer in
                        LayerRow(model: model, layer: layer)
                    }
                }
                PaletteSection(model: model)
                ToolOptions(model: model)
                #if DEBUG
                DebugLinks()
                #endif
            }
            .padding(Theme.Metrics.barPadding)
        }
        .frame(width: Theme.Metrics.rightPanelWidth)
        .background(Theme.surface)
    }
}

/// One of the four fixed layers. Active = blue tint + 2pt blue border + a
/// "drawing here" note, so it never relies on color alone.
private struct LayerRow: View {
    let model: CanvasModel
    let layer: CanvasLayer

    private var active: Bool { model.activeLayer == layer }
    private var hidden: Bool { model.hiddenLayers.contains(layer) }

    var body: some View {
        HStack(spacing: 0) {
            Button { model.activate(layer) } label: {
                HStack(spacing: 12) {
                    icon
                    (Text(layer.title).font(Theme.bodyStrong).foregroundStyle(Theme.ink)
                     + Text(note).font(Theme.label).foregroundStyle(active ? Theme.blueText : Theme.inkMuted))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .opacity(hidden ? 0.4 : 1)
                .padding(.leading, 12)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("layer-\(layer.rawValue)")
            .accessibilityAddTraits(active ? .isSelected : [])

            Button { model.toggleVisibility(layer) } label: {
                Image(systemName: hidden ? "eye.slash" : "eye")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.ink)
                    .frame(width: Theme.Metrics.minTarget, height: Theme.Metrics.minTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hidden ? "Show \(layer.title)" : "Hide \(layer.title)")
            .padding(.trailing, 6)
        }
        .frame(height: Theme.Metrics.layerRowHeight)
        .background(active ? Theme.blueTint : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button)
            .strokeBorder(active ? Theme.pencilBlue : Theme.line,
                          lineWidth: active ? Theme.Metrics.selectedBorder : Theme.Metrics.hairline))
    }

    private var note: String {
        if active { return model.tool == .eraser ? " · erasing here" : " · drawing here" }
        if layer == .sketch { return " · not exported" }
        return ""
    }

    @ViewBuilder private var icon: some View {
        let tile = RoundedRectangle(cornerRadius: Theme.Radius.tile)
        switch layer {
        case .text:
            Text("T").font(Theme.bodyStrong)
                .frame(width: Theme.Metrics.iconTile, height: Theme.Metrics.iconTile)
                .background(Theme.thumbBackdrop, in: tile)
        case .ink:
            Image(systemName: "line.diagonal").font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.surface)
                .frame(width: Theme.Metrics.iconTile, height: Theme.Metrics.iconTile)
                .background(Theme.pencilBlue, in: tile)
        case .shapes:
            tile.fill(Color(cgColor: model.project.palette[0].cgColor))
                .frame(width: Theme.Metrics.iconTile, height: Theme.Metrics.iconTile)
        case .sketch:
            Image(systemName: "scribble").font(.system(size: 16))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: Theme.Metrics.iconTile, height: Theme.Metrics.iconTile)
                .background(Theme.thumbBackdrop, in: tile)
        }
    }
}

// MARK: Palette

/// Three swatches and "Try another" (design/Canvas.png). Tap a swatch to make
/// it the current color; tap and hold to change that color everywhere.
private struct PaletteSection: View {
    let model: CanvasModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Palette").sectionLabelStyle()
                Spacer(minLength: 0)
                SecondaryButton(title: "Try another", compact: true) { model.tryAnotherPalette() }
                    .accessibilityIdentifier("tryAnother")
            }
            HStack(spacing: 16) {
                ForEach(PaletteSlot.allCases) { slot in
                    Swatch(color: model.project.color(for: slot), slot: slot,
                           selected: model.currentSlot == slot,
                           onTap: { model.chooseSlot(slot) },
                           onHold: { frame in SlotColorPicker.present(slot: slot, model: model, from: frame) })
                }
            }
            Text("Tap and hold a color to change it everywhere.")
                .font(Theme.small).foregroundStyle(Theme.inkMuted)
        }
    }
}

/// Palette swatch. Selected gets a blue ring, not just a color change.
private struct Swatch: View {
    let color: HexColor
    let slot: PaletteSlot
    let selected: Bool
    let onTap: () -> Void
    let onHold: (CGRect) -> Void
    @State private var frame = CGRect.zero

    var body: some View {
        Circle()
            .fill(Color(cgColor: color.cgColor))
            .overlay(Circle().strokeBorder(Theme.line, lineWidth: Theme.Metrics.hairline))
            .padding(6)
            .overlay(Circle().strokeBorder(selected ? Theme.pencilBlue : .clear, lineWidth: 3))
            .frame(width: Theme.Metrics.swatch + 12, height: Theme.Metrics.swatch + 12)
            .contentShape(Circle())
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.4) { onHold(frame) }
            .accessibilityElement()
            .accessibilityLabel("Color \(slot.number) of \(PaletteSlot.allCases.count)")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { onTap() }
            .accessibilityAction(named: "Change this color everywhere") { onHold(frame) }
            .accessibilityIdentifier("swatch-\(slot.number)")
    }
}

/// "Secondary" from the style guide: white with a border, ink text.
private struct SecondaryButton: View {
    let title: String
    var symbol: String?
    var compact = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
            }
            .font(compact ? Theme.labelStrong : Theme.bodyStrong)
            .foregroundStyle(isEnabled ? Theme.ink : Theme.lineStrong)
            .padding(.horizontal, compact ? 12 : 16)
            .frame(minHeight: compact ? 36 : Theme.Metrics.barButton)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small)
                .strokeBorder(Theme.line, lineWidth: Theme.Metrics.hairline))
            .frame(minHeight: Theme.Metrics.minTarget)   // 44 pt target even when it looks compact
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Options for the current tool.
private struct ToolOptions: View {
    @Bindable var model: CanvasModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model.tool {
            case .ink:
                Text("Ink pen").sectionLabelStyle()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Line size").font(Theme.bodyStrong)
                        Spacer()
                        Text("\(Int(model.lineSize))").font(Theme.labelStrong).foregroundStyle(Theme.inkMuted)
                            .monospacedDigit()
                    }
                    Slider(value: $model.lineSize, in: LineSize.range, step: LineSize.step)
                        .tint(Theme.pencilBlue)
                        .accessibilityLabel("Line size")
                        .accessibilityValue("\(Int(model.lineSize))")
                        .accessibilityIdentifier("lineSize")
                }
                CheckRow(title: "Smooth my lines", subtitle: nil, isOn: $model.smoothLines)
                    .accessibilityIdentifier("smoothLines")
                PencilOnlyRow(isOn: $model.pencilOnly)
            case .sketch:
                Text("Sketch pencil").sectionLabelStyle()
                Text("Your sketch layer stays private. It's never exported.")
                    .font(Theme.body).foregroundStyle(Theme.inkMuted)
                PencilOnlyRow(isOn: $model.pencilOnly)
            case .eraser:
                Text("Eraser").sectionLabelStyle()
                Text("Erases whole lines on the \(model.eraserLayer.title) layer. Tap the Sketch or Ink layer to switch.")
                    .font(Theme.body).foregroundStyle(Theme.inkMuted)
                PencilOnlyRow(isOn: $model.pencilOnly)
            case .shapes:
                Text("Shapes").sectionLabelStyle()
                Text("Circles, squares, triangles and stars are coming soon.")
                    .font(Theme.body).foregroundStyle(Theme.inkMuted)
            case .text:
                Text("Text").sectionLabelStyle()
                Text("Adding your logo name is coming soon.")
                    .font(Theme.body).foregroundStyle(Theme.inkMuted)
            }
        }
    }
}

private struct PencilOnlyRow: View {
    @Binding var isOn: Bool

    var body: some View {
        CheckRow(title: "Pencil only", subtitle: "Off = fingers and any stylus draw", isOn: $isOn)
            .accessibilityIdentifier("pencilOnly")
    }
}

/// A label with a checkbox; the whole row is the tap target.
private struct CheckRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.bodyStrong)
                    if let subtitle {
                        Text(subtitle).font(Theme.small).foregroundStyle(Theme.inkMuted)
                    }
                }
                Spacer(minLength: 0)
                CheckBox(isOn: isOn)
            }
            .frame(minHeight: Theme.Metrics.minTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct CheckBox: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.tile)
            .fill(isOn ? Theme.pencilBlue : Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile)
                .strokeBorder(isOn ? Theme.pencilBlue : Theme.lineStrong, lineWidth: Theme.Metrics.selectedBorder))
            .overlay {
                if isOn {
                    Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.surface)
                }
            }
            .frame(width: Theme.Metrics.iconTile, height: Theme.Metrics.iconTile)
    }
}
