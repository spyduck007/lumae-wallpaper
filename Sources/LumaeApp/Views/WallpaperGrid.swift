import SwiftUI
import AVKit
import LumaeCore

struct WallpaperGrid: View {
    @EnvironmentObject var model: AppModel
    let items: [WallpaperMetadata]
    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 330), spacing: 18)]
    var body: some View {
        ScrollView { LazyVGrid(columns: columns, spacing: 18) { ForEach(items) { item in WallpaperCard(item: item).onTapGesture { model.selectedWallpaperID = item.id }.accessibilityAddTraits(model.selectedWallpaperID == item.id ? .isSelected : []) } }.padding(20) }
    }
}

struct WallpaperCard: View {
    @EnvironmentObject var model: AppModel
    let item: WallpaperMetadata
    @State private var hovering = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                WallpaperThumbnail(item: item, animate: hovering)
                    .aspectRatio(16/10, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
                if item.kind == .video { Label("Video", systemImage: "play.fill").font(.caption.bold()).padding(7).background(.ultraThinMaterial, in: Capsule()).padding(8) }
                if item.isMissing { Label("Missing", systemImage: "exclamationmark.triangle.fill").font(.caption.bold()).padding(7).background(.red.opacity(0.85), in: Capsule()).padding(8) }
            }
            HStack { VStack(alignment: .leading) { Text(item.name).font(.headline).lineLimit(1); Text("\(item.pixelWidth) × \(item.pixelHeight)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button { model.toggleFavorite(item) } label: { Image(systemName: item.isFavorite ? "star.fill" : "star") }.buttonStyle(.plain).accessibilityLabel(item.isFavorite ? "Remove from favorites" : "Add to favorites") }
        }
        .padding(10).background(model.selectedWallpaperID == item.id ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(model.selectedWallpaperID == item.id ? Color.accentColor : .clear, lineWidth: 2) }
        .onHover { hovering = $0 }
        .contextMenu { Button("Apply") { Task { await model.apply(item) } }; Button(item.isFavorite ? "Unfavorite" : "Favorite") { model.toggleFavorite(item) }; Divider(); Button("Remove from Lumae", role: .destructive) { model.remove(item) } }
        .accessibilityElement(children: .combine).accessibilityLabel("\(item.name), \(item.kind.rawValue) wallpaper")
    }
}

struct WallpaperThumbnail: View {
    let item: WallpaperMetadata; let animate: Bool
    var body: some View {
        Group {
            if animate, item.kind == .video, !item.isMissing { VideoPlayer(player: AVPlayer(url: URL(fileURLWithPath: item.effectiveFilePath))).allowsHitTesting(false) }
            else if let path = item.thumbnailPath, let image = NSImage(contentsOfFile: path) { Image(nsImage: image).resizable().scaledToFill() }
            else { ZStack { LinearGradient(colors: [.purple.opacity(0.8), .blue.opacity(0.6), .pink.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing); Image(systemName: item.isMissing ? "exclamationmark.triangle" : "photo").font(.largeTitle).foregroundStyle(.white.opacity(0.85)) } }
        }.background(.black)
    }
}
