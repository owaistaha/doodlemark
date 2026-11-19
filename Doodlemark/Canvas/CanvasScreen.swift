import SwiftUI

/// The editor (design/Canvas.png): top bar, tool rail, the square canvas on
/// its backdrop, and the right panel with layers, palette and tool options.
///
/// Every tool works, with one undo history; the project autosaves. The
/// first canvas ever opened shows three tips (`CanvasTips`).
struct CanvasScreen: View {
    @State var model: CanvasModel
    /// Saves the project; drives "Saved" in the top bar.
    var autosaver: ProjectAutosaver?
    /// Back to the gallery (saves first).
    var onBack: (() -> Void)?
    /// The three first-canvas tips (shown once).
    @State private var tips = CanvasTipsModel()

    var body: some View {
        VStack(spacing: 0) {
            CanvasTopBar(model: model, autosaver: autosaver, onBack: onBack)
            Rectangle().fill(Theme.line).frame(height: Theme.Metrics.hairline)
            HStack(spacing: 0) {
                // The rail stays full height behind the on-screen keyboard. It's
                // an overlay so its height never makes this row taller than the
                // space above the keyboard (that pushed the top bar off screen).
                Color.clear
                    .frame(width: Theme.Metrics.toolRailWidth)
                    .overlay(alignment: .top) {
                        ToolRail(model: model)
                            .ignoresSafeArea(.keyboard)
                    }
                Rectangle().fill(Theme.line).frame(width: Theme.Metrics.hairline)
                CanvasArea(model: model)
                Rectangle().fill(Theme.line).frame(width: Theme.Metrics.hairline)
                CanvasRightPanel(model: model)
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .canvasTips(tips)
        .environment(\.colorScheme, .light)
        .focusedSceneValue(\.canvasModel, model)
        .onAppear { tips.startIfNeeded() }
    }
}

private extension CanvasTool {
    /// The first-canvas tip that points at this tool, if any.
    var tip: CanvasTip? {
        switch self {
        case .sketch: .sketch
        case .ink: .ink
        default: nil
        }
    }
}

private extension View {
    @ViewBuilder
    func canvasTipAnchor(_ tip: CanvasTip?) -> some View {
        if let tip { canvasTipAnchor(tip) } else { self }
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
    let autosaver: ProjectAutosaver?
    let onBack: (() -> Void)?
    @State private var renaming = false
    @State private var draftName = ""
    @State private var nothingToExport = false
    @State private var export: ExportModel?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 16) {
                BarIconButton(symbol: "chevron.left", label: "Back to my logos") { onBack?() }
                    .disabled(onBack == nil)
                    .accessibilityIdentifier("back")
                Button {
                    draftName = model.project.name
                    renaming = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.project.name).font(Theme.heading).lineLimit(1)
                        Text(saveStatus).font(Theme.small).foregroundStyle(Theme.inkMuted)
                            .accessibilityIdentifier("saveStatus")
                    }
                    .frame(minHeight: Theme.Metrics.minTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(model.project.name), \(saveStatus)")
                .accessibilityHint("Rename this logo")
                .accessibilityIdentifier("projectTitle")
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

            PrimaryButton(title: "Preview & export", symbol: "square.and.arrow.up") { openExport() }
                .accessibilityIdentifier("previewExport")
                .canvasTipAnchor(CanvasTip.export)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Metrics.barPadding)
        .frame(height: Theme.Metrics.topBarHeight)
        .background(Theme.surface)
        .renameAlert(isPresented: $renaming, name: $draftName) { model.rename(to: draftName) }
        .alert("Draw something first.", isPresented: $nothingToExport) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Ink a line, add a shape or type a name. Your sketch stays private, so it doesn't count.")
        }
        .fullScreenCover(item: $export) { export in
            ExportScreen(model: export) { self.export = nil }
        }
    }

    /// Ink, shapes or text: the export screen. Nothing (or only a sketch):
    /// "Draw something first." and no export.
    private func openExport() {
        model.endTyping()
        guard !ExportFiles.isEmpty(project: model.project, ink: model.ink) else {
            nothingToExport = true
            return
        }
        autosaver?.saveNow()
        export = ExportModel(project: model.project, ink: model.ink, displayScale: displayScale)
    }

    private var saveStatus: String {
        switch autosaver?.state {
        case .saved: "Saved"
        case .editing: "Saving…"
        case .failed: "Couldn't save. Trying again on the next change."
        case .notSaved, nil: "Not saved yet"
        }
    }
}

extension View {
    /// "Rename" with a text field, from the canvas title and the gallery card.
    func renameAlert(isPresented: Binding<Bool>, name: Binding<String>, onSave: @escaping () -> Void) -> some View {
        alert("Rename logo", isPresented: isPresented) {
            TextField("Logo name", text: name)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("renameField")
            Button("Cancel", role: .cancel) {}
            Button("Rename", action: onSave)
        } message: {
            Text("Up to \(ProjectNames.maxLength) letters.")
        }
    }
}

/// Square top-bar button (canvas, lesson player).
struct BarIconButton: View {
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

// MARK: - Tool rail

private struct ToolRail: View {
    let model: CanvasModel

    var body: some View {
        VStack(spacing: 12) {
            ForEach(CanvasTool.allCases) { tool in
                ToolButton(tool: tool, selected: model.tool == tool) { model.select(tool) }
                    .canvasTipAnchor(tool.tip)
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
    /// Below this height (the on-screen keyboard is up while typing the logo
    /// name) the square keeps small margins and the pills step aside, so the
    /// whole logo stays visible above the keyboard.
    private static let compactHeight: CGFloat = 560
    private static let compactInset: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < Self.compactHeight
            let v = compact ? Self.compactInset : verticalInset, h = compact ? Self.compactInset : horizontalInset
            let side = max(0, min(geo.size.width - 2 * h, geo.size.height - 2 * v))
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
                if !compact {
                    ZoomPill(factor: model.zoomFactor) { model.zoomToFit() }
                        .padding(Theme.Metrics.barPadding)
                }
            }
            .overlay(alignment: .bottom) {
                if !compact {
                    HintPill(text: hint)
                        .padding(.bottom, (verticalInset - Theme.Metrics.minTarget) / 2)
                }
            }
            #if DEBUG
            .overlay(alignment: .topLeading) {
                // Invisible; lets UI tests read the palette and Ink line colors.
                VStack(spacing: 0) {
                    Color.clear.frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(model.debugColorSummary)
                        .accessibilityIdentifier("debugColors")
                    Color.clear.frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(model.debugShapeSummary)
                        .accessibilityIdentifier("debugShapes")
                    Color.clear.frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(model.debugTextSummary)
                        .accessibilityIdentifier("debugText")
                    Color.clear.frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(model.debugDocumentFingerprint)
                        .accessibilityIdentifier("debugDocument")
                }
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
        case .shapes:
            if model.project.shapes.isEmpty { "Shapes: pick one on the right to add it" }
            else if model.selectedShape == nil { "Tap a shape to pick it" }
            else { "Drag to move. Pull a corner to resize. Two fingers turn it." }
        case .text:
            if model.pickedItem == nil { "Text: type your logo name on the right" }
            else { "Drag to move. Pull a corner to resize. Two fingers turn it." }
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

/// Floating dark pill that says what the current tool does (or, in a
/// lesson, what to do).
struct HintPill: View {
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
        ScrollViewReader { proxy in
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
            .environment(\.panelScroll, proxy)
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
                ShapeOptions(model: model)
            case .text:
                TextOptions(model: model)
            }
        }
    }
}

/// Shapes tool: add a shape (drawn by `ShapeGeometry` in the current color),
/// then Flip and Delete for the picked one.
private struct ShapeOptions: View {
    let model: CanvasModel

    var body: some View {
        // The picked shape's actions come first, so they're in view without scrolling.
        if model.selectedShape != nil {
            Text("Picked shape").sectionLabelStyle()
            VStack(spacing: 12) {
                SecondaryButton(title: "Flip sideways", symbol: "arrow.left.and.right") {
                    model.flipSelectedShape(sideways: true)
                }
                .disabled(!model.canFlipSelectedShape(sideways: true))
                .accessibilityIdentifier("flipSideways")
                SecondaryButton(title: "Flip upside down", symbol: "arrow.up.and.down") {
                    model.flipSelectedShape(sideways: false)
                }
                .disabled(!model.canFlipSelectedShape(sideways: false))
                .accessibilityIdentifier("flipUpsideDown")
                SecondaryButton(title: "Delete", symbol: "trash") { model.deleteSelectedShape() }
                    .accessibilityIdentifier("deleteShape")
            }
            Text("Tap a color to fill it. Put two fingers on it to turn it.")
                .font(Theme.small).foregroundStyle(Theme.inkMuted)
                .padding(.bottom, 12)
        }

        Text("Add a shape").sectionLabelStyle()
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(LogoShape.Kind.allCases, id: \.self) { kind in
                AddShapeButton(kind: kind, color: model.penColor) { model.addShape(kind) }
            }
        }
        Text("New shapes use the selected color.")
            .font(Theme.small).foregroundStyle(Theme.inkMuted)
    }
}

/// A shape kind as a big button: its real outline in the current color.
private struct AddShapeButton: View {
    let kind: LogoShape.Kind
    let color: HexColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Path(ShapeGeometry.path(kind: kind, center: CGPoint(x: 16, y: 16), size: 32, rotation: 0))
                    .fill(Color(cgColor: color.cgColor))
                    .frame(width: 32, height: 32)
                Text(kind.title).font(Theme.label).lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.toolButton)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.line, lineWidth: Theme.Metrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a \(kind.title.lowercased())")
        .accessibilityIdentifier("add-\(kind.rawValue)")
    }
}

/// Text tool: the logo name (a system text field, so the keyboard, dictation
/// and Scribble all work), its font, size, letter spacing and ALL CAPS.
extension EnvironmentValues {
    /// Scrolls the right panel (the Text tool brings the logo name above the keyboard).
    @Entry var panelScroll: ScrollViewProxy?
}

private struct TextOptions: View {
    let model: CanvasModel
    @Environment(\.panelScroll) private var panelScroll
    /// The "Logo name" label, field, note and counter: kept in view together.
    private static let nameBlock = "logoNameBlock"
    /// What the field shows. Kept in step with the model: anything the model
    /// refuses (a character the font can't draw, letter 25) is taken back out.
    @State private var draft = ""
    @FocusState private var typing: Bool

    private var text: LogoText? { model.project.text }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Logo name").sectionLabelStyle()
            nameField
        }
        .id(Self.nameBlock)
        .onChange(of: typing) { _, focused in
            if focused { showNameBlock() } else { model.endTyping() }
        }
        .onChange(of: model.textMessage) { _, message in
            if message != nil, typing { showNameBlock() }
        }
        .onDisappear { model.endTyping() }

        Text("Font").sectionLabelStyle()
            .padding(.top, 8)
        fontsAndControls
    }

    /// With the keyboard up, the field would sit on the keys' top edge and the
    /// note under it ("This font can't draw …") behind them. Scrolled to the
    /// top of the panel, the whole block is above the keyboard.
    private func showNameBlock() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))    // after the keyboard's own scroll
            withAnimation(.easeOut(duration: 0.25)) { panelScroll?.scrollTo(Self.nameBlock, anchor: .top) }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Your logo name", text: $draft)
                .font(Theme.body)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($typing)
                .padding(.horizontal, 14)
                .frame(minHeight: Theme.Metrics.barButton)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .strokeBorder(typing ? Theme.pencilBlue : Theme.lineStrong,
                                  lineWidth: typing ? Theme.Metrics.selectedBorder : Theme.Metrics.hairline))
                .accessibilityIdentifier("textField")
            HStack(alignment: .top) {
                if let message = model.textMessage {
                    Text(message)
                        .font(Theme.small).foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("textMessage")
                }
                Spacer(minLength: 8)
                Text("\(draft.count)/\(LogoText.maxLength)")
                    .font(Theme.small).foregroundStyle(Theme.inkMuted).monospacedDigit()
            }
        }
        .onAppear { draft = model.textString }
        .onChange(of: draft) { _, new in
            let accepted = model.typeText(new)
            if accepted != new { draft = accepted }
        }
        .onChange(of: model.textReplaced) {
            // Undo, redo, Delete text. Not typing: the field is already ahead
            // of the model there, and echoing could drop a fast keystroke.
            if model.textString != draft { draft = model.textString }
        }
        .onSubmit { typing = false }
    }

    @ViewBuilder private var fontsAndControls: some View {
        VStack(spacing: 8) {
            ForEach(LogoFonts.all) { font in
                FontRow(font: font, selected: model.textFont == font.postScriptName) { model.setTextFont(font) }
            }
        }

        Group {
            SliderRow(title: "Size", value: text?.pointSize ?? Self.sizeDefault, range: LogoText.scaleRange,
                      model: model, set: model.setTextSize)
                .accessibilityIdentifier("textSize")
            SliderRow(title: "Letter spacing", value: text?.tracking ?? 0, range: LogoText.trackingRange,
                      model: model, set: model.setTextTracking)
                .accessibilityIdentifier("textTracking")
            CheckRow(title: "ALL CAPS", subtitle: nil, isOn: Binding(get: { text?.allCaps ?? false },
                                                                       set: { model.setTextAllCaps($0) }))
                .accessibilityIdentifier("allCaps")
            SecondaryButton(title: "Delete text", symbol: "trash") { model.deleteText() }
                .accessibilityIdentifier("deleteText")
        }
        .disabled(text == nil)
        .padding(.top, 8)
    }

    private static let sizeDefault = CanvasModel.newTextSize
}

/// One logo font, its name written in that font, the style underneath.
/// Chosen = blue tint, 2 pt blue border and a check (not color alone).
private struct FontRow: View {
    let font: LogoFont
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(font.displayName)
                        .font(.custom(font.postScriptName, fixedSize: 26))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(font.style).font(Theme.small).foregroundStyle(selected ? Theme.blueText : Theme.inkMuted)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.pencilBlue)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.toolButton - 12)
            .background(selected ? Theme.blueTint : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button)
                .strokeBorder(selected ? Theme.pencilBlue : Theme.line,
                              lineWidth: selected ? Theme.Metrics.selectedBorder : Theme.Metrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(font.displayName), \(font.style)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("font-\(font.postScriptName)")
    }
}

/// A labelled slider whose whole drag is one undo step.
private struct SliderRow: View {
    let title: String
    let value: CGFloat
    let range: ClosedRange<CGFloat>
    let model: CanvasModel
    let set: (CGFloat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(Theme.bodyStrong)
                Spacer()
                Text("\(Int(value.rounded()))").font(Theme.labelStrong).foregroundStyle(Theme.inkMuted).monospacedDigit()
            }
            Slider(value: Binding(get: { value }, set: { set($0) }), in: range) { editing in
                if editing { model.beginEdit() } else { model.endEdit() }
            }
            .tint(Theme.pencilBlue)
            .accessibilityLabel(title)
            .accessibilityValue("\(Int(value.rounded()))")
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
