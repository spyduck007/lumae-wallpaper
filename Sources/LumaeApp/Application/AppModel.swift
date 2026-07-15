import SwiftUI
import AppKit
import LumaeCore

@MainActor
final class AppModel: ObservableObject {
    @Published var state = PersistedApplicationState()
    @Published var selectedWallpaperID: UUID?
    @Published var selectedDisplayID: String?
    @Published var searchText = ""
    @Published var sortOrder: LibrarySortOrder = .dateAddedNewest
    @Published var viewMode: LibraryViewMode = .grid
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isPaused = false
    @Published private(set) var displayTopology = DisplayTopology(displays: [])

    let store = JSONStateStore()
    let importer = WallpaperImporter()
    let displayService = DisplayDiscoveryService()
    let engine = WallpaperEngine()
    let cache = ThumbnailCache()
    let launchAtLogin = LaunchAtLoginService()

    private var configurationApplyTask: Task<Void, Never>?
    private var playlistRotationTask: Task<Void, Never>?

    var filteredWallpapers: [WallpaperMetadata] {
        let filter = LibraryFilter(query: searchText)
        return WallpaperSorter.sort(
            state.wallpapers.filter(filter.matches),
            by: sortOrder
        )
    }

    var assignableWallpapers: [WallpaperMetadata] {
        state.wallpapers
            .filter { !$0.isMissing && $0.kind != .unsupported }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    init() {
        displayService.onTopologyChange = { [weak self] topology in
            Task { @MainActor in
                await self?.handleTopology(topology)
            }
        }

        Task { [weak self] in
            guard let self else { return }
            await self.load()
            self.displayService.start()
            let topology = self.displayService.currentTopology
            self.displayTopology = topology
            self.reconcileAssignments(onto: topology)
            self.reconcileWidgetDisplays(onto: topology)
            if self.state.settings.restoreLastConfiguration {
                await self.engine.restore(
                    state: self.state,
                    topology: self.displayService.currentTopology
                )
            }
            self.schedulePlaylistRotation()
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            state = try await store.load()
            normalizePlaylistState()
            normalizeWidgetState()
            state.wallpapers = state.wallpapers.map { item in
                var copy = item
                copy.isMissing = !FileManager.default.fileExists(
                    atPath: item.effectiveFilePath
                )
                return copy
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func presentImporter() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = WallpaperImporter.allowedTypes
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                await self?.importURLs(panel.urls)
            }
        }
    }

    func importURLs(_ urls: [URL]) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let imported = try await importer.importFiles(
                urls,
                behavior: state.settings.importBehavior,
                managedLibraryPath: state.settings.managedLibraryPath,
                existing: state.wallpapers,
                thumbnailCache: cache
            )
            state.wallpapers.append(contentsOf: imported)
            try await save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ wallpaper: WallpaperMetadata) {
        state.wallpapers.removeAll { $0.id == wallpaper.id }
        if selectedWallpaperID == wallpaper.id {
            selectedWallpaperID = nil
        }
        state.assignments = state.assignments.map {
            var copy = $0
            if copy.wallpaperID == wallpaper.id {
                copy.wallpaperID = nil
            }
            return copy
        }
        if state.sharedWallpaperID == wallpaper.id {
            state.sharedWallpaperID = nil
        }
        scheduleConfigurationApply()
    }


    func revealInFinder(_ wallpaper: WallpaperMetadata) {
        let url = URL(fileURLWithPath: wallpaper.effectiveFilePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "The wallpaper file is missing. Use Locate File… to reconnect it."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPath(_ wallpaper: WallpaperMetadata) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            wallpaper.effectiveFilePath,
            forType: .string
        )
    }

    func presentRelink(for wallpaper: WallpaperMetadata) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = WallpaperImporter.allowedTypes
        panel.prompt = "Relink"
        panel.message = "Choose the file that should replace the missing wallpaper reference."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.relink(wallpaper, to: url)
            }
        }
    }

    func relink(_ wallpaper: WallpaperMetadata, to url: URL) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let updated = try await importer.relink(
                wallpaper,
                to: url,
                existing: state.wallpapers,
                thumbnailCache: cache
            )
            guard let index = state.wallpapers.firstIndex(where: { $0.id == wallpaper.id }) else {
                return
            }
            state.wallpapers[index] = updated
            selectedWallpaperID = updated.id
            try await save()
            try await engine.applyConfiguration(
                state: state,
                topology: displayTopology
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ wallpaper: WallpaperMetadata, to proposedName: String) -> Bool {
        let trimmedName = proposedName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedName.isEmpty else {
            errorMessage = "Wallpaper names cannot be empty."
            return false
        }
        guard let index = state.wallpapers.firstIndex(where: { $0.id == wallpaper.id }) else {
            return false
        }
        guard state.wallpapers[index].name != trimmedName else {
            return true
        }

        state.wallpapers[index].name = trimmedName
        persistSoon()
        return true
    }

    func toggleFavorite(_ wallpaper: WallpaperMetadata) {
        guard let index = state.wallpapers.firstIndex(where: { $0.id == wallpaper.id }) else {
            return
        }
        state.wallpapers[index].isFavorite.toggle()
        persistSoon()
    }

    func applySelected() async {
        guard let id = selectedWallpaperID,
              let wallpaper = state.wallpapers.first(where: { $0.id == id }) else {
            return
        }
        await apply(wallpaper)
    }

    /// Applies a wallpaper from the library to the current presentation.
    /// In Per Display mode this intentionally assigns it to every active display;
    /// individual assignments are then refined from Display Layout.
    func apply(_ wallpaper: WallpaperMetadata) async {
        do {
            state.sharedWallpaperID = wallpaper.id
            reconcileAssignments(onto: displayService.currentTopology)

            if state.settings.presentationMode == .perDisplay {
                let activeIDs = displayService.currentTopology.activeDisplayIDs
                for index in state.assignments.indices
                    where activeIDs.contains(state.assignments[index].id) {
                    state.assignments[index].wallpaperID = wallpaper.id
                }
            }

            try await engine.applyConfiguration(
                state: state,
                topology: displayService.currentTopology
            )

            if let index = state.wallpapers.firstIndex(where: { $0.id == wallpaper.id }) {
                state.wallpapers[index].dateLastUsed = Date()
            }
            try await save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setPresentationMode(_ mode: DisplayPresentationMode) {
        guard state.settings.presentationMode != mode else { return }
        reconcileAssignments(onto: displayTopology)

        if mode != .perDisplay, state.sharedWallpaperID == nil {
            let mainDisplayID = displayTopology.displays.first(where: { $0.isMain })?.id
            let preferredAssignment = mainDisplayID.flatMap { displayID in
                state.assignments.first { $0.id == displayID }
            } ?? state.assignments.first(where: { $0.wallpaperID != nil })
            state.sharedWallpaperID = preferredAssignment?.wallpaperID
        }

        state.settings.presentationMode = mode
        scheduleConfigurationApply()
    }

    func setSharedWallpaper(_ wallpaperID: UUID?) {
        guard state.sharedWallpaperID != wallpaperID else { return }
        state.sharedWallpaperID = wallpaperID
        markWallpaperUsed(wallpaperID)
        scheduleConfigurationApply()
    }

    func setDefaultScalingMode(_ mode: WallpaperScalingMode) {
        guard state.settings.defaultScalingMode != mode else { return }
        state.settings.defaultScalingMode = mode
        scheduleConfigurationApply()
    }

    func setDisplayWallpaper(_ wallpaperID: UUID?, for displayID: String) {
        guard let index = assignmentIndex(for: displayID) else { return }
        guard state.assignments[index].wallpaperID != wallpaperID else { return }
        state.assignments[index].wallpaperID = wallpaperID
        markWallpaperUsed(wallpaperID)
        scheduleConfigurationApply()
    }

    func setDisplayEnabled(_ enabled: Bool, for displayID: String) {
        guard let index = assignmentIndex(for: displayID) else { return }
        guard state.assignments[index].enabled != enabled else { return }
        state.assignments[index].enabled = enabled
        scheduleConfigurationApply()
    }

    func setDisplayScalingMode(_ mode: WallpaperScalingMode, for displayID: String) {
        guard let index = assignmentIndex(for: displayID) else { return }
        guard state.assignments[index].scalingMode != mode else { return }
        state.assignments[index].scalingMode = mode
        scheduleConfigurationApply()
    }

    func applySharedWallpaperToAllDisplays() {
        reconcileAssignments(onto: displayTopology)
        let activeIDs = displayTopology.activeDisplayIDs
        for index in state.assignments.indices
            where activeIDs.contains(state.assignments[index].id) {
            state.assignments[index].wallpaperID = state.sharedWallpaperID
            state.assignments[index].enabled = true
        }
        scheduleConfigurationApply()
    }

    func displayAssignment(for display: DisplayDescriptor) -> DisplayAssignment {
        let restored = DisplayAssignmentRestorer.restore(
            saved: state.assignments,
            onto: displayTopology
        )
        return restored[display.id]
            ?? DisplayAssignment(
                displayFingerprint: display.fingerprint,
                wallpaperID: state.sharedWallpaperID,
                scalingMode: state.settings.defaultScalingMode
            )
    }

    func wallpaper(id: UUID?) -> WallpaperMetadata? {
        guard let id else { return nil }
        return state.wallpapers.first { $0.id == id }
    }

    func togglePause() {
        isPaused.toggle()
        isPaused ? engine.pause() : engine.resume()
    }

    func advancePlaylist() {
        advanceActivePlaylist(.next)
    }

    func handleTopology(_ topology: DisplayTopology) async {
        displayTopology = topology
        state.lastKnownTopology = topology
        reconcileAssignments(onto: topology)
        reconcileWidgetDisplays(onto: topology)

        if selectedDisplayID == nil
            || !topology.activeDisplayIDs.contains(selectedDisplayID ?? "") {
            selectedDisplayID = topology.displays.first(where: { $0.isMain })?.id
                ?? topology.displays.first?.id
        }

        await engine.topologyDidChange(topology, state: state)
        persistSoon()
    }

    func save() async throws {
        try await store.save(state)
    }

    func persistSoon() {
        Task { try? await save() }
    }

    private func assignmentIndex(for displayID: String) -> Int? {
        reconcileAssignments(onto: displayTopology)
        return state.assignments.firstIndex { $0.id == displayID }
    }

    private func reconcileAssignments(onto topology: DisplayTopology) {
        guard !topology.displays.isEmpty else { return }

        let restored = DisplayAssignmentRestorer.restore(
            saved: state.assignments,
            onto: topology
        )

        let activeAssignments = topology.displays.map { display -> DisplayAssignment in
            var assignment = restored[display.id]
                ?? DisplayAssignment(
                    displayFingerprint: display.fingerprint,
                    wallpaperID: state.sharedWallpaperID
                        ?? state.wallpapers.first(where: { !$0.isMissing })?.id,
                    scalingMode: state.settings.defaultScalingMode
                )
            assignment.displayFingerprint = display.fingerprint
            return assignment
        }

        let disconnectedAssignments = state.assignments.filter { assignment in
            !topology.displays.contains { display in
                assignment.displayFingerprint.matchScore(
                    against: display.fingerprint
                ) >= 200
            }
        }

        state.assignments = activeAssignments + disconnectedAssignments
    }

    private func scheduleConfigurationApply() {
        configurationApplyTask?.cancel()
        configurationApplyTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            await self.applyCurrentConfiguration()
        }
    }

    private func applyCurrentConfiguration() async {
        do {
            try await save()
            try await engine.applyConfiguration(
                state: state,
                topology: displayTopology
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markWallpaperUsed(_ wallpaperID: UUID?) {
        guard let wallpaperID,
              let index = state.wallpapers.firstIndex(where: { $0.id == wallpaperID }) else {
            return
        }
        state.wallpapers[index].dateLastUsed = Date()
    }
}

enum LibraryViewMode: String, CaseIterable {
    case grid
    case list
}


extension AppModel {
    var playlists: [WallpaperPlaylist] {
        get { state.playlists ?? [] }
        set { state.playlists = newValue }
    }

    var activePlaylist: WallpaperPlaylist? {
        guard let id = state.activePlaylistID else { return nil }
        return playlists.first { $0.id == id }
    }

    var activePlaylistIsRunning: Bool {
        activePlaylist?.isRunning == true
    }

    func playlist(id: UUID) -> WallpaperPlaylist? {
        playlists.first { $0.id == id }
    }

    @discardableResult
    func createPlaylist(named proposedName: String = "New Playlist") -> UUID {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "New Playlist" : trimmed
        let existingNames = Set(playlists.map { $0.name.lowercased() })
        var name = baseName
        var suffix = 2
        while existingNames.contains(name.lowercased()) {
            name = "\(baseName) \(suffix)"
            suffix += 1
        }

        let playlist = WallpaperPlaylist(name: name)
        playlists.append(playlist)
        persistSoon()
        return playlist.id
    }

    func deletePlaylist(id: UUID) {
        playlists.removeAll { $0.id == id }
        if state.activePlaylistID == id {
            state.activePlaylistID = nil
            playlistRotationTask?.cancel()
            playlistRotationTask = nil
        }
        persistSoon()
    }

    func renamePlaylist(id: UUID, to proposedName: String) -> Bool {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Playlist names cannot be empty."
            return false
        }
        guard let index = playlists.firstIndex(where: { $0.id == id }) else {
            return false
        }
        playlists[index].name = trimmed
        persistSoon()
        return true
    }

    func addWallpaper(_ wallpaperID: UUID, toPlaylist id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        guard !playlists[index].wallpaperIDs.contains(wallpaperID) else { return }
        playlists[index].wallpaperIDs.append(wallpaperID)
        persistSoon()
        schedulePlaylistRotation()
    }

    func removeWallpaper(at offsets: IndexSet, fromPlaylist id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        let removed = offsets.compactMap { position in
            playlists[index].wallpaperIDs.indices.contains(position)
                ? playlists[index].wallpaperIDs[position]
                : nil
        }
        playlists[index].wallpaperIDs.remove(atOffsets: offsets)
        if let current = playlists[index].currentWallpaperID,
           removed.contains(current) {
            playlists[index].currentWallpaperID = nil
        }
        persistSoon()
        schedulePlaylistRotation()
    }

    func moveWallpaper(
        inPlaylist id: UUID,
        from source: IndexSet,
        to destination: Int
    ) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].wallpaperIDs.move(fromOffsets: source, toOffset: destination)
        playlists[index].cursor = min(
            playlists[index].cursor,
            max(playlists[index].wallpaperIDs.count - 1, 0)
        )
        persistSoon()
    }

    func moveWallpaperUp(_ wallpaperID: UUID, inPlaylist id: UUID) {
        guard let playlistIndex = playlists.firstIndex(where: { $0.id == id }),
              let itemIndex = playlists[playlistIndex].wallpaperIDs.firstIndex(of: wallpaperID),
              itemIndex > 0 else { return }
        playlists[playlistIndex].wallpaperIDs.swapAt(itemIndex, itemIndex - 1)
        persistSoon()
    }

    func moveWallpaperDown(_ wallpaperID: UUID, inPlaylist id: UUID) {
        guard let playlistIndex = playlists.firstIndex(where: { $0.id == id }),
              let itemIndex = playlists[playlistIndex].wallpaperIDs.firstIndex(of: wallpaperID),
              itemIndex + 1 < playlists[playlistIndex].wallpaperIDs.count else { return }
        playlists[playlistIndex].wallpaperIDs.swapAt(itemIndex, itemIndex + 1)
        persistSoon()
    }

    func setPlaylistShuffle(_ shuffle: Bool, id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].shuffle = shuffle
        playlists[index].history.removeAll()
        persistSoon()
    }

    func setPlaylistInterval(_ interval: TimeInterval, id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].intervalSeconds = max(interval, 10)
        persistSoon()
        schedulePlaylistRotation()
    }

    func setPlaylistTarget(_ target: PlaylistTarget, id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].target = target
        persistSoon()
    }

    func startPlaylist(id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        for candidate in playlists.indices {
            playlists[candidate].isRunning = candidate == index
        }
        state.activePlaylistID = id
        playlists[index].lastAdvancedAt = Date()
        persistSoon()

        if let currentID = playlists[index].currentWallpaperID,
           let wallpaper = state.wallpapers.first(where: { $0.id == currentID && !$0.isMissing }) {
            let target = playlists[index].target
            Task {
                await applyPlaylistWallpaper(wallpaper, target: target)
                schedulePlaylistRotation()
            }
        } else {
            advanceActivePlaylist(.next)
        }
    }

    func pauseActivePlaylist() {
        guard let id = state.activePlaylistID,
              let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].isRunning = false
        playlistRotationTask?.cancel()
        playlistRotationTask = nil
        persistSoon()
    }

    func resumeActivePlaylist() {
        guard let id = state.activePlaylistID,
              let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].isRunning = true
        playlists[index].lastAdvancedAt = Date()
        persistSoon()
        schedulePlaylistRotation()
    }

    func toggleActivePlaylist() {
        activePlaylistIsRunning ? pauseActivePlaylist() : resumeActivePlaylist()
    }

    func advanceActivePlaylist(_ direction: PlaylistDirection) {
        guard let activeID = state.activePlaylistID,
              let index = playlists.firstIndex(where: { $0.id == activeID }) else {
            return
        }

        let availableIDs = Set(
            state.wallpapers
                .filter { !$0.isMissing && $0.kind != .unsupported }
                .map(\.id)
        )
        guard let wallpaperID = WallpaperPlaylistEngine.advance(
            playlist: &playlists[index],
            direction: direction,
            availableIDs: availableIDs
        ), let wallpaper = state.wallpapers.first(where: { $0.id == wallpaperID }) else {
            errorMessage = "This playlist has no available wallpapers."
            schedulePlaylistRotation()
            return
        }

        selectedWallpaperID = wallpaperID
        let target = playlists[index].target
        Task {
            await applyPlaylistWallpaper(wallpaper, target: target)
            schedulePlaylistRotation()
        }
        persistSoon()
    }

    func setActivePlaylist(id: UUID?) {
        guard state.activePlaylistID != id else { return }
        for index in playlists.indices {
            playlists[index].isRunning = false
        }
        state.activePlaylistID = id
        playlistRotationTask?.cancel()
        playlistRotationTask = nil
        persistSoon()
    }

    private func normalizePlaylistState() {
        if state.playlists == nil {
            let legacy = state.settings.playlist
            if !legacy.wallpaperIDs.isEmpty {
                let migrated = WallpaperPlaylist(
                    name: "Imported Playlist",
                    wallpaperIDs: legacy.wallpaperIDs,
                    intervalSeconds: legacy.intervalSeconds,
                    shuffle: legacy.shuffle,
                    isRunning: legacy.isEnabled,
                    cursor: legacy.cursor
                )
                state.playlists = [migrated]
                state.activePlaylistID = legacy.isEnabled ? migrated.id : nil
            } else {
                state.playlists = []
            }
        }

        let ids = Set(playlists.map(\.id))
        if let activeID = state.activePlaylistID, !ids.contains(activeID) {
            state.activePlaylistID = nil
        }
        if let activeID = state.activePlaylistID {
            for index in playlists.indices {
                playlists[index].isRunning = playlists[index].id == activeID
                    && playlists[index].isRunning
            }
        }
    }

    private func schedulePlaylistRotation() {
        playlistRotationTask?.cancel()
        playlistRotationTask = nil

        guard let activeID = state.activePlaylistID,
              let playlist = playlists.first(where: { $0.id == activeID }),
              playlist.isRunning,
              !playlist.wallpaperIDs.isEmpty else {
            return
        }

        let elapsed = playlist.lastAdvancedAt.map { Date().timeIntervalSince($0) } ?? 0
        let delay = max(playlist.intervalSeconds - elapsed, 1)

        playlistRotationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.advanceActivePlaylist(.next)
            }
        }
    }

    private func applyPlaylistWallpaper(
        _ wallpaper: WallpaperMetadata,
        target: PlaylistTarget
    ) async {
        switch target {
        case .currentPresentation:
            await apply(wallpaper)

        case .display(let fingerprint):
            guard let display = displayTopology.displays.max(by: {
                $0.fingerprint.matchScore(against: fingerprint)
                    < $1.fingerprint.matchScore(against: fingerprint)
            }), display.fingerprint.matchScore(against: fingerprint) >= 200 else {
                errorMessage = "The playlist’s target display is not connected."
                return
            }

            state.settings.presentationMode = .perDisplay
            reconcileAssignments(onto: displayTopology)
            if let assignmentIndex = state.assignments.firstIndex(where: { $0.id == display.id }) {
                state.assignments[assignmentIndex].wallpaperID = wallpaper.id
                state.assignments[assignmentIndex].enabled = true
            }
            markWallpaperUsed(wallpaper.id)

            do {
                try await engine.applyConfiguration(
                    state: state,
                    topology: displayTopology
                )
                try await save()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}



extension AppModel {
    var widgets: [DesktopWidget] {
        get { state.widgets ?? [] }
        set { state.widgets = newValue }
    }

    var widgetDisplayMode: WidgetDisplayMode {
        state.widgetDisplayMode ?? .mirrored
    }

    var widgetDisplayConfigurations: [WidgetDisplayConfiguration] {
        get { state.widgetDisplayConfigurations ?? [] }
        set { state.widgetDisplayConfigurations = newValue }
    }

    var digitalClockWidget: DesktopWidget? {
        widgets.first { $0.kind == .digitalClock }
    }

    func widgetDisplayEnabled(for displayID: String) -> Bool {
        guard let display = displayTopology.display(id: displayID) else { return true }
        return WidgetDisplayResolver.bestConfiguration(
            for: display.fingerprint,
            in: widgetDisplayConfigurations,
            excludingConfigurationIDs: reservedWidgetConfigurationIDs(
                except: display.id
            )
        )?.isEnabled ?? true
    }

    func widgetsForDisplay(_ displayID: String) -> [DesktopWidget] {
        guard let display = displayTopology.display(id: displayID) else { return [] }
        return WidgetDisplayResolver.widgets(
            for: display,
            mode: widgetDisplayMode,
            mirroredWidgets: widgets,
            configurations: widgetDisplayConfigurations,
            excludingConfigurationIDs: reservedWidgetConfigurationIDs(
                except: display.id
            )
        )
    }

    func digitalClockWidget(for displayID: String?) -> DesktopWidget? {
        if widgetDisplayMode == .mirrored {
            return digitalClockWidget
        }
        guard let displayID else { return nil }
        return widgetsForDisplay(displayID).first { $0.kind == .digitalClock }
    }

    func setWidgetDisplayMode(_ mode: WidgetDisplayMode) {
        guard widgetDisplayMode != mode else { return }
        if mode == .perDisplay {
            initializePerDisplayWidgetsIfNeeded()
        }
        state.widgetDisplayMode = mode
        scheduleConfigurationApply()
    }

    func setWidgetsEnabled(_ enabled: Bool, for displayID: String) {
        guard let index = widgetConfigurationIndex(for: displayID, createIfMissing: true) else {
            return
        }
        var configurations = widgetDisplayConfigurations
        configurations[index].isEnabled = enabled
        widgetDisplayConfigurations = configurations
        scheduleConfigurationApply()
    }

    @discardableResult
    func addDigitalClockWidget(for displayID: String? = nil) -> UUID {
        if widgetDisplayMode == .mirrored {
            if let existing = digitalClockWidget { return existing.id }
            let widget = DesktopWidget(kind: .digitalClock)
            widgets.append(widget)
            scheduleConfigurationApply()
            return widget.id
        }

        let targetID = displayID
            ?? selectedDisplayID
            ?? displayTopology.displays.first(where: { $0.isMain })?.id
            ?? displayTopology.displays.first?.id
        guard let targetID,
              let index = widgetConfigurationIndex(
                for: targetID,
                createIfMissing: true
              ) else {
            let widget = DesktopWidget(kind: .digitalClock)
            widgets.append(widget)
            scheduleConfigurationApply()
            return widget.id
        }

        var configurations = widgetDisplayConfigurations
        if let existing = configurations[index].widgets.first(where: {
            $0.kind == .digitalClock
        }) {
            return existing.id
        }

        let source = digitalClockWidget ?? DesktopWidget(kind: .digitalClock)
        let widget = source.duplicated()
        configurations[index].widgets.append(widget)
        widgetDisplayConfigurations = configurations
        scheduleConfigurationApply()
        return widget.id
    }

    func removeWidget(id: UUID) {
        var mirrored = widgets
        mirrored.removeAll { $0.id == id }
        widgets = mirrored

        var configurations = widgetDisplayConfigurations
        for index in configurations.indices {
            configurations[index].widgets.removeAll { $0.id == id }
        }
        widgetDisplayConfigurations = configurations
        scheduleConfigurationApply()
    }

    func setWidgetEnabled(_ enabled: Bool, id: UUID) {
        updateWidget(id: id) { $0.isEnabled = enabled }
    }

    func setWidgetPosition(_ position: NormalizedWidgetPosition, id: UUID) {
        updateWidget(id: id) { $0.position = position }
    }

    func setWidgetSize(_ size: DesktopWidgetSize, id: UUID) {
        updateWidget(id: id) { $0.size = size }
    }

    func setClockUses24HourTime(_ enabled: Bool, id: UUID) {
        updateWidget(id: id) { $0.digitalClock.uses24HourTime = enabled }
    }

    func setClockShowsSeconds(_ enabled: Bool, id: UUID) {
        updateWidget(id: id) { $0.digitalClock.showsSeconds = enabled }
    }

    func setClockShowsBackground(_ enabled: Bool, id: UUID) {
        updateWidget(id: id) { $0.digitalClock.showsBackground = enabled }
    }

    private func updateWidget(
        id: UUID,
        change: (inout DesktopWidget) -> Void
    ) {
        var mirrored = widgets
        if let index = mirrored.firstIndex(where: { $0.id == id }) {
            change(&mirrored[index])
            widgets = mirrored
            scheduleConfigurationApply()
            return
        }

        var configurations = widgetDisplayConfigurations
        for configurationIndex in configurations.indices {
            if let widgetIndex = configurations[configurationIndex]
                .widgets.firstIndex(where: { $0.id == id }) {
                change(&configurations[configurationIndex].widgets[widgetIndex])
                widgetDisplayConfigurations = configurations
                scheduleConfigurationApply()
                return
            }
        }
    }

    private func normalizeWidgetState() {
        if state.widgets == nil { state.widgets = [] }
        if state.widgetDisplayMode == nil { state.widgetDisplayMode = .mirrored }
        if state.widgetDisplayConfigurations == nil {
            state.widgetDisplayConfigurations = []
        }
        if state.widgetPerDisplayInitialized == nil {
            state.widgetPerDisplayInitialized = false
        }
    }

    private func initializePerDisplayWidgetsIfNeeded() {
        reconcileWidgetDisplays(onto: displayTopology)
        guard state.widgetPerDisplayInitialized != true else { return }

        var configurations = widgetDisplayConfigurations
        for index in configurations.indices {
            if configurations[index].widgets.isEmpty {
                configurations[index].widgets = widgets.map { $0.duplicated() }
            }
        }
        widgetDisplayConfigurations = configurations
        state.widgetPerDisplayInitialized = true
    }

    private func reconcileWidgetDisplays(onto topology: DisplayTopology) {
        guard !topology.displays.isEmpty else { return }

        var configurations = widgetDisplayConfigurations
        let activeIDs = topology.activeDisplayIDs

        for display in topology.displays {
            if configurations.contains(where: {
                $0.displayFingerprint.stableID == display.id
            }) {
                continue
            }

            let reservedIDs = activeIDs.subtracting([display.id])
            if let matched = WidgetDisplayResolver.bestConfiguration(
                for: display.fingerprint,
                in: configurations,
                excludingConfigurationIDs: reservedIDs
            ), let index = configurations.firstIndex(of: matched) {
                configurations[index].displayFingerprint = display.fingerprint
                continue
            }

            let initialWidgets = widgetDisplayMode == .perDisplay
                ? widgets.map { $0.duplicated() }
                : []
            configurations.append(
                WidgetDisplayConfiguration(
                    displayFingerprint: display.fingerprint,
                    widgets: initialWidgets
                )
            )
        }
        widgetDisplayConfigurations = configurations
    }

    private func reservedWidgetConfigurationIDs(
        except displayID: String
    ) -> Set<String> {
        displayTopology.activeDisplayIDs.subtracting([displayID])
    }

    private func widgetConfigurationIndex(
        for displayID: String,
        createIfMissing: Bool
    ) -> Int? {
        guard let display = displayTopology.display(id: displayID) else { return nil }
        var configurations = widgetDisplayConfigurations

        if let exact = configurations.firstIndex(where: {
            $0.displayFingerprint.stableID == display.fingerprint.stableID
        }) {
            return exact
        }

        if let matched = WidgetDisplayResolver.bestConfiguration(
            for: display.fingerprint,
            in: configurations,
            excludingConfigurationIDs: reservedWidgetConfigurationIDs(
                except: display.id
            )
        ), let index = configurations.firstIndex(of: matched) {
            configurations[index].displayFingerprint = display.fingerprint
            widgetDisplayConfigurations = configurations
            return index
        }

        guard createIfMissing else { return nil }
        let initialWidgets = widgetDisplayMode == .perDisplay
            ? widgets.map { $0.duplicated() }
            : []
        configurations.append(
            WidgetDisplayConfiguration(
                displayFingerprint: display.fingerprint,
                widgets: initialWidgets
            )
        )
        widgetDisplayConfigurations = configurations
        return configurations.indices.last
    }

}
