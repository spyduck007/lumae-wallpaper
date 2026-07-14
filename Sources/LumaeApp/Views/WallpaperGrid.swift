import SwiftUI
import AVKit
import LumaeCore

struct WallpaperGrid: View {
    @EnvironmentObject var model: AppModel
    let items: [WallpaperMetadata]

    private let columns = [
        GridItem(.adaptive(minimum: 230, maximum: 330), spacing: 18)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(items) { item in
                    WallpaperCard(item: item)
                        .onTapGesture { model.selectedWallpaperID = item.id }
                        .accessibilityAddTraits(
                            model.selectedWallpaperID == item.id ? .isSelected : []
                        )
                }
            }
            .padding(18)
        }
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
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                if item.kind == .video {
                    Label("Video", systemImage: "play.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                }

                if item.isMissing {
                    Label("Missing", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.red.opacity(0.85), in: Capsule())
                        .padding(8)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.name)

                    Text("\(item.pixelWidth) × \(item.pixelHeight)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    model.toggleFavorite(item)
                } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .padding(.top, 1)
                .accessibilityLabel(
                    item.isFavorite ? "Remove from favorites" : "Add to favorites"
                )
            }
        }
        .padding(10)
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .background(
            model.selectedWallpaperID == item.id
                ? Color.accentColor.opacity(0.16)
                : Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(
                    model.selectedWallpaperID == item.id
                        ? Color.accentColor
                        : Color.primary.opacity(hovering ? 0.12 : 0.06),
                    lineWidth: model.selectedWallpaperID == item.id ? 2 : 1
                )
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contextMenu {
            Button("Apply") { Task { await model.apply(item) } }
            Button(item.isFavorite ? "Unfavorite" : "Favorite") {
                model.toggleFavorite(item)
            }
            Divider()
            Button("Remove from Lumae", role: .destructive) { model.remove(item) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.kind.rawValue) wallpaper")
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
