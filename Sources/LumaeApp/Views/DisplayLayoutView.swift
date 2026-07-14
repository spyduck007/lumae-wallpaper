import SwiftUI
import LumaeCore

struct DisplayLayoutView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { VStack(alignment: .leading) { Text("Display Layout").font(.largeTitle.bold()); Text("Assignments use stable hardware fingerprints and are restored conservatively.").foregroundStyle(.secondary) }; Spacer(); Picker("Mode", selection: $model.state.settings.presentationMode) { Text("Per Display").tag(DisplayPresentationMode.perDisplay); Text("Duplicate").tag(DisplayPresentationMode.duplicate); Text("Span").tag(DisplayPresentationMode.span) }.frame(width: 300) }
            GeometryReader { proxy in
                let topology = model.displayService.currentTopology
                let bounds = topology.virtualBoundsPoints ?? LRect(x: 0, y: 0, width: 1, height: 1)
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(.quaternary.opacity(0.4))
                    ForEach(topology.displays) { display in
                        let scale = min((proxy.size.width - 60) / bounds.size.width, (proxy.size.height - 60) / bounds.size.height)
                        let x = (display.framePoints.minX - bounds.minX) * scale + 30
                        let y = (bounds.maxY - display.framePoints.maxY) * scale + 30
                        RoundedRectangle(cornerRadius: 12).fill(.blue.opacity(0.2)).stroke(.blue, lineWidth: display.isMain ? 3 : 1)
                            .frame(width: display.framePoints.size.width * scale, height: display.framePoints.size.height * scale)
                            .overlay { VStack { Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display"); Text(display.fingerprint.localizedName).font(.caption.bold()); Text("\(Int(display.pixelSize.width))×\(Int(display.pixelSize.height)) · \(display.backingScaleFactor, specifier: "%.1f")×").font(.caption2).foregroundStyle(.secondary) } }
                            .position(x: x + display.framePoints.size.width * scale / 2, y: y + display.framePoints.size.height * scale / 2)
                            .accessibilityLabel("Display \(display.fingerprint.localizedName)")
                    }
                }
            }
            Text("Span mode maps one source into the complete virtual desktop, then crops the correct synchronized region for each display.").font(.callout).foregroundStyle(.secondary)
        }.padding(24)
    }
}
