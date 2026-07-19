import SwiftUI
import AppKit
import AVFoundation
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
    @State private var confirmRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                WallpaperThumbnail(item: item, animate: hovering)
                    .frame(maxWidth: .infinity)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Button("Open Inspector") {
                model.selectedWallpaperID = item.id
            }

            Button("Apply Wallpaper") {
                Task { await model.apply(item) }
            }
            .disabled(item.isMissing)

            Button(item.isFavorite ? "Unfavorite" : "Favorite") {
                model.toggleFavorite(item)
            }

            Divider()

            if item.isMissing {
                Button("Locate File…") {
                    model.presentRelink(for: item)
                }
            } else {
                Button("Reveal in Finder") {
                    model.revealInFinder(item)
                }
            }

            Button("Copy File Path") {
                model.copyPath(item)
            }

            Divider()

            Button("Remove from Lumae", role: .destructive) {
                confirmRemoval = true
            }
        }
        .confirmationDialog(
            "Remove “\(item.name)” from Lumae?",
            isPresented: $confirmRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove from Lumae", role: .destructive) {
                model.remove(item)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The original media file will not be deleted.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.kind.rawValue) wallpaper")
    }
}

struct WallpaperThumbnail: View {
    let item: WallpaperMetadata
    let animate: Bool

    var body: some View {
        Color.black
            .overlay {
                poster
            }
            .overlay {
                if animate, item.kind == .video, !item.isMissing {
                    HoverVideoPreview(
                        url: URL(fileURLWithPath: item.effectiveFilePath)
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
                }
            }
            .clipped()
    }

    @ViewBuilder
    private var poster: some View {
        if let path = item.thumbnailPath,
           let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        .purple.opacity(0.8),
                        .blue.opacity(0.6),
                        .pink.opacity(0.5)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(
                    systemName: item.isMissing
                        ? "exclamationmark.triangle"
                        : "photo"
                )
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

/// A lightweight AppKit/Core Animation video preview.
///
/// SwiftUI's `VideoPlayer` routes through the private `_AVKit_SwiftUI`
/// framework. On macOS 26.5 Release builds that view can abort while Swift is
/// initializing its `AVPlayerView` superclass metadata. This preview uses the
/// public `AVPlayerLayer` API directly and therefore avoids that code path.
private struct HoverVideoPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> HoverVideoPreviewView {
        HoverVideoPreviewView(url: url)
    }

    func updateNSView(_ nsView: HoverVideoPreviewView, context: Context) {
        nsView.updateURLIfNeeded(url)
        nsView.play()
    }

    static func dismantleNSView(
        _ nsView: HoverVideoPreviewView,
        coordinator: Void
    ) {
        nsView.stop()
    }
}

private final class HoverVideoPreviewView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    init(url: URL) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true

        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull()
        ]
        layer?.addSublayer(playerLayer)

        configure(url: url)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func updateURLIfNeeded(_ url: URL) {
        guard currentURL != url else { return }
        configure(url: url)
    }

    func play() {
        player?.play()
    }

    func stop() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        playerLayer.player = nil
        player?.removeAllItems()
        player = nil
        currentURL = nil
    }

    private func configure(url: URL) {
        stop()

        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 1

        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.actionAtItemEnd = .advance
        queue.automaticallyWaitsToMinimizeStalling = true

        let looper = AVPlayerLooper(player: queue, templateItem: item)

        currentURL = url
        player = queue
        self.looper = looper
        playerLayer.player = queue
        queue.play()
    }

    deinit {
        stop()
    }
}
