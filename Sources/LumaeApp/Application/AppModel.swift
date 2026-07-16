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
    private var widgetRefreshTask: Task<Void, Never>?
    private var playlistRotationTask: Task<Void, Never>?
    private var widgetUndoStack: [WidgetHistoryEntry] = []
    private var widgetRedoStack: [WidgetHistoryEntry] = []

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
            if let defaultSceneID = self.state.defaultSceneID {
                await self.activateScene(id: defaultSceneID, persist: false)
            } else if self.state.settings.restoreLastConfiguration {
                await self.engine.restore(
                    state: self.state,
                    topology: self.displayService.currentTopology
                )
                self.schedulePlaylistRotation()
            }
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            state = try await store.load()
            normalizePlaylistState()
            normalizeWidgetState()
            normalizeSceneState()
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

    func setPauseDuringFullScreenApps(_ enabled: Bool) {
        guard state.settings.pauseDuringFullScreenApps != enabled else { return }
        state.settings.pauseDuringFullScreenApps = enabled
        engine.updateFullScreenSuspension(
            enabled: enabled,
            topology: displayTopology
        )
        persistSoon()
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

    private func scheduleWidgetRefresh() {
        widgetRefreshTask?.cancel()
        widgetRefreshTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            do {
                try await self.save()
                self.engine.updateWidgets(
                    state: self.state,
                    topology: self.displayTopology
                )
            } catch {
                self.errorMessage = error.localizedDescription
            }
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



private struct WidgetSubsystemSnapshot: Equatable {
    var widgets: [DesktopWidget]
    var mode: WidgetDisplayMode
    var configurations: [WidgetDisplayConfiguration]
    var perDisplayInitialized: Bool
    var defaultStyle: WidgetVisualStyle
}

private struct WidgetHistoryEntry {
    var snapshot: WidgetSubsystemSnapshot
    var actionName: String
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

    var defaultWidgetStyle: WidgetVisualStyle {
        state.defaultWidgetStyle ?? .glass
    }

    var canUndoWidgetEdit: Bool { !widgetUndoStack.isEmpty }
    var canRedoWidgetEdit: Bool { !widgetRedoStack.isEmpty }

    func widget(id: UUID, for displayID: String?) -> DesktopWidget? {
        widgetCollection(for: displayID).first { $0.id == id }
    }

    func widgetDisplayEnabled(for displayID: String) -> Bool {
        guard let display = displayTopology.display(id: displayID) else { return true }
        return WidgetDisplayResolver.bestConfiguration(
            for: display.fingerprint,
            in: widgetDisplayConfigurations,
            excludingConfigurationIDs: reservedWidgetConfigurationIDs(except: display.id)
        )?.isEnabled ?? true
    }

    func widgetsForDisplay(_ displayID: String) -> [DesktopWidget] {
        guard let display = displayTopology.display(id: displayID) else { return [] }
        return WidgetDisplayResolver.widgets(
            for: display,
            mode: widgetDisplayMode,
            mirroredWidgets: widgets,
            configurations: widgetDisplayConfigurations,
            excludingConfigurationIDs: reservedWidgetConfigurationIDs(except: display.id)
        )
    }

    func widgetLayoutForEditing(_ displayID: String) -> [DesktopWidget] {
        guard widgetDisplayMode == .perDisplay,
              let index = widgetConfigurationIndex(
                for: displayID,
                createIfMissing: true
              ) else {
            return widgets
        }
        return widgetDisplayConfigurations[index].widgets
    }

    func setWidgetDisplayMode(_ mode: WidgetDisplayMode) {
        guard widgetDisplayMode != mode else { return }
        performWidgetMutation(named: "Change Widget Display Mode") {
            if mode == .perDisplay { initializePerDisplayWidgetsIfNeeded() }
            state.widgetDisplayMode = mode
        }
    }

    func setWidgetsEnabled(_ enabled: Bool, for displayID: String) {
        performWidgetMutation(named: enabled ? "Show Widgets" : "Hide Widgets") {
            guard let index = widgetConfigurationIndex(for: displayID, createIfMissing: true) else { return }
            var configurations = widgetDisplayConfigurations
            configurations[index].isEnabled = enabled
            widgetDisplayConfigurations = configurations
        }
    }

    func setDefaultWidgetStyle(_ style: WidgetVisualStyle) {
        performWidgetMutation(named: "Change Default Widget Style") {
            state.defaultWidgetStyle = style
        }
    }

    func applyDefaultStyleToAllWidgets() {
        performWidgetMutation(named: "Apply Style to All Widgets") {
            let style = defaultWidgetStyle
            state.widgets = (state.widgets ?? []).map { widget in
                var copy = widget
                setStyleWithoutHistory(style, on: &copy)
                return copy
            }
            state.widgetDisplayConfigurations = (state.widgetDisplayConfigurations ?? []).map { configuration in
                var copy = configuration
                copy.widgets = configuration.widgets.map { widget in
                    var item = widget
                    setStyleWithoutHistory(style, on: &item)
                    return item
                }
                return copy
            }
        }
    }

    @discardableResult
    func addWidget(kind: DesktopWidgetKind, for displayID: String? = nil) -> UUID {
        let id = UUID()
        performWidgetMutation(named: "Add Widget") {
            var collection = widgetCollection(for: displayID)
            var widget = makeDefaultWidget(kind: kind, id: id)
            let sameKindCount = collection.filter { $0.kind == kind }.count
            let offset = min(Double(sameKindCount) * 0.035, 0.21)
            widget.position = NormalizedWidgetPosition(
                x: min(widget.position.x + offset, 0.86),
                y: min(widget.position.y + offset, 0.86)
            )
            collection.append(widget)
            setWidgetCollection(collection, for: displayID)
        }
        return id
    }

    @discardableResult
    func duplicateWidget(id: UUID, for displayID: String?) -> UUID? {
        guard let source = widget(id: id, for: displayID) else { return nil }
        let duplicateID = UUID()
        performWidgetMutation(named: "Duplicate Widget") {
            var collection = widgetCollection(for: displayID)
            guard let index = collection.firstIndex(where: { $0.id == id }) else { return }
            var copy = source
            copy.id = duplicateID
            let xOffset = source.position.x <= 0.5 ? 0.035 : -0.035
            let yOffset = source.position.y <= 0.5 ? 0.035 : -0.035
            copy.position = NormalizedWidgetPosition(
                x: source.position.x + xOffset,
                y: source.position.y + yOffset
            )
            collection.insert(copy, at: index + 1)
            setWidgetCollection(collection, for: displayID)
        }
        return duplicateID
    }

    func removeWidget(id: UUID, for displayID: String? = nil) {
        performWidgetMutation(named: "Remove Widget") {
            var collection = widgetCollection(for: displayID)
            collection.removeAll { $0.id == id }
            setWidgetCollection(collection, for: displayID)
        }
    }

    func setWidgetEnabled(_ enabled: Bool, id: UUID) {
        performWidgetMutation(named: enabled ? "Show Widget" : "Hide Widget") {
            updateWidgetWithoutHistory(id: id) { $0.isEnabled = enabled }
        }
    }

    func setWidgetPosition(_ position: NormalizedWidgetPosition, id: UUID) {
        performWidgetMutation(named: "Move Widget") {
            updateWidgetWithoutHistory(id: id) { $0.position = position }
        }
    }

    func normalizeWidgetPosition(
        _ position: NormalizedWidgetPosition,
        id: UUID
    ) {
        guard let current = widget(id: id, for: selectedDisplayID),
              current.position != position else {
            return
        }
        updateWidgetWithoutHistory(id: id) { $0.position = position }
        scheduleWidgetRefresh()
    }

    func setWidgetSize(_ size: DesktopWidgetSize, id: UUID) {
        performWidgetMutation(named: "Resize Widget") {
            updateWidgetWithoutHistory(id: id) { widget in
                if size == .custom, widget.customScale == nil {
                    widget.customScale = initialCustomScale(for: widget)
                }
                widget.size = size
            }
        }
    }

    func setWidgetCustomScale(_ scale: Double, id: UUID) {
        performWidgetMutation(named: "Resize Widget") {
            updateWidgetWithoutHistory(id: id) { widget in
                widget.size = .custom
                widget.customScale = DesktopWidget.clampedCustomScale(scale)
            }
        }
    }

    func setClockUses24HourTime(_ enabled: Bool, id: UUID) {
        performWidgetMutation(named: "Change Clock Format") {
            updateWidgetWithoutHistory(id: id) { $0.digitalClock.uses24HourTime = enabled }
        }
    }

    func setClockShowsSeconds(_ enabled: Bool, id: UUID) {
        performWidgetMutation(named: enabled ? "Show Seconds" : "Hide Seconds") {
            updateWidgetWithoutHistory(id: id) { $0.digitalClock.showsSeconds = enabled }
        }
    }

    func setClockShowsBackground(_ enabled: Bool, id: UUID) {
        performWidgetMutation(named: "Change Clock Background") {
            updateWidgetWithoutHistory(id: id) { $0.digitalClock.showsBackground = enabled }
        }
    }

    func setNowPlayingShowsBackground(_ enabled: Bool, id: UUID) {
        performWidgetMutation(named: "Change Now Playing Background") {
            updateWidgetWithoutHistory(id: id) { $0.nowPlaying.showsBackground = enabled }
        }
    }

    func setWidgetStyle(_ style: WidgetVisualStyle, id: UUID) {
        performWidgetMutation(named: "Change Widget Style") {
            updateWidgetWithoutHistory(id: id) { widget in
                setStyleWithoutHistory(style, on: &widget)
            }
        }
    }

    func setNowPlayingUsesArtworkTint(_ enabled: Bool, id: UUID) {
        performWidgetMutation(named: "Change Artwork Tint") {
            updateWidgetWithoutHistory(id: id) { $0.nowPlaying.usesArtworkTint = enabled }
        }
    }

    func setDateCalendarMode(_ mode: DateCalendarWidgetMode, id: UUID) {
        performWidgetMutation(named: "Change Date Layout") {
            updateWidgetWithoutHistory(id: id) { $0.dateCalendar.mode = mode }
        }
    }

    func setDateShowsWeekday(_ enabled: Bool, id: UUID) {
        performWidgetMutation(named: enabled ? "Show Weekday" : "Hide Weekday") {
            updateWidgetWithoutHistory(id: id) { $0.dateCalendar.showsWeekday = enabled }
        }
    }

    func setDateShowsYear(_ enabled: Bool, id: UUID) {
        performWidgetMutation(named: enabled ? "Show Year" : "Hide Year") {
            updateWidgetWithoutHistory(id: id) { $0.dateCalendar.showsYear = enabled }
        }
    }

    func setCalendarWeekStart(_ start: CalendarWeekStart, id: UUID) {
        performWidgetMutation(named: "Change Week Start") {
            updateWidgetWithoutHistory(id: id) { $0.dateCalendar.weekStart = start }
        }
    }

    func setCalendarShowsAdjacentDates(_ enabled: Bool, id: UUID) {
        performWidgetMutation(named: "Change Adjacent Dates") {
            updateWidgetWithoutHistory(id: id) {
                $0.dateCalendar.showsAdjacentMonthDates = enabled
            }
        }
    }

    func setDateCalendarShowsBackground(_ enabled: Bool, id: UUID) {
        performWidgetMutation(named: "Change Date Background") {
            updateWidgetWithoutHistory(id: id) { $0.dateCalendar.showsBackground = enabled }
        }
    }

    func setBatteryShowsPercentage(_ enabled: Bool, id: UUID) {
        performWidgetMutation(named: "Change Battery Percentage") {
            updateWidgetWithoutHistory(id: id) { $0.battery.showsPercentage = enabled }
        }
    }

    func setBatteryShowsStatusText(_ enabled: Bool, id: UUID) {
        performWidgetMutation(named: "Change Battery Status") {
            updateWidgetWithoutHistory(id: id) { $0.battery.showsStatusText = enabled }
        }
    }

    func setBatteryShowsProgressBar(_ enabled: Bool, id: UUID) {
        performWidgetMutation(named: "Change Battery Progress") {
            updateWidgetWithoutHistory(id: id) { $0.battery.showsProgressBar = enabled }
        }
    }

    func setBatteryShowsBackground(_ enabled: Bool, id: UUID) {
        performWidgetMutation(named: "Change Battery Background") {
            updateWidgetWithoutHistory(id: id) { $0.battery.showsBackground = enabled }
        }
    }

    func bringWidgetForward(id: UUID, for displayID: String?) {
        reorderWidget(id: id, for: displayID, actionName: "Bring Widget Forward") { index, collection in
            guard index + 1 < collection.count else { return }
            collection.swapAt(index, index + 1)
        }
    }

    func sendWidgetBackward(id: UUID, for displayID: String?) {
        reorderWidget(id: id, for: displayID, actionName: "Send Widget Backward") { index, collection in
            guard index > 0 else { return }
            collection.swapAt(index, index - 1)
        }
    }

    func bringWidgetToFront(id: UUID, for displayID: String?) {
        reorderWidget(id: id, for: displayID, actionName: "Bring Widget to Front") { index, collection in
            let item = collection.remove(at: index)
            collection.append(item)
        }
    }

    func sendWidgetToBack(id: UUID, for displayID: String?) {
        reorderWidget(id: id, for: displayID, actionName: "Send Widget to Back") { index, collection in
            let item = collection.remove(at: index)
            collection.insert(item, at: 0)
        }
    }

    func undoWidgetEdit() {
        guard let entry = widgetUndoStack.popLast() else { return }
        widgetRedoStack.append(WidgetHistoryEntry(snapshot: captureWidgetSnapshot(), actionName: entry.actionName))
        restoreWidgetSnapshot(entry.snapshot)
        scheduleWidgetRefresh()
    }

    func redoWidgetEdit() {
        guard let entry = widgetRedoStack.popLast() else { return }
        widgetUndoStack.append(WidgetHistoryEntry(snapshot: captureWidgetSnapshot(), actionName: entry.actionName))
        restoreWidgetSnapshot(entry.snapshot)
        scheduleWidgetRefresh()
    }

    private func performWidgetMutation(named actionName: String, _ mutation: () -> Void) {
        let before = captureWidgetSnapshot()
        mutation()
        guard before != captureWidgetSnapshot() else { return }
        widgetUndoStack.append(WidgetHistoryEntry(snapshot: before, actionName: actionName))
        if widgetUndoStack.count > 100 { widgetUndoStack.removeFirst(widgetUndoStack.count - 100) }
        widgetRedoStack.removeAll()
        scheduleWidgetRefresh()
    }

    private func captureWidgetSnapshot() -> WidgetSubsystemSnapshot {
        WidgetSubsystemSnapshot(
            widgets: widgets,
            mode: widgetDisplayMode,
            configurations: widgetDisplayConfigurations,
            perDisplayInitialized: state.widgetPerDisplayInitialized ?? false,
            defaultStyle: defaultWidgetStyle
        )
    }

    private func restoreWidgetSnapshot(_ snapshot: WidgetSubsystemSnapshot) {
        state.widgets = snapshot.widgets
        state.widgetDisplayMode = snapshot.mode
        state.widgetDisplayConfigurations = snapshot.configurations
        state.widgetPerDisplayInitialized = snapshot.perDisplayInitialized
        state.defaultWidgetStyle = snapshot.defaultStyle
    }

    private func widgetCollection(for displayID: String?) -> [DesktopWidget] {
        if widgetDisplayMode == .mirrored { return widgets }
        guard let displayID,
              let index = widgetConfigurationIndex(
                for: displayID,
                createIfMissing: true
              ) else {
            return []
        }
        return widgetDisplayConfigurations[index].widgets
    }

    private func setWidgetCollection(_ collection: [DesktopWidget], for displayID: String?) {
        if widgetDisplayMode == .mirrored {
            widgets = collection
            return
        }
        guard let displayID,
              let index = widgetConfigurationIndex(for: displayID, createIfMissing: true) else { return }
        var configurations = widgetDisplayConfigurations
        configurations[index].widgets = collection
        widgetDisplayConfigurations = configurations
    }

    private func makeDefaultWidget(kind: DesktopWidgetKind, id: UUID) -> DesktopWidget {
        switch kind {
        case .digitalClock:
            return DesktopWidget(
                id: id,
                kind: .digitalClock,
                position: NormalizedWidgetPosition(x: 0.5, y: 0.18),
                size: .medium,
                style: defaultWidgetStyle
            )
        case .nowPlaying:
            return DesktopWidget(
                id: id,
                kind: .nowPlaying,
                position: NormalizedWidgetPosition(x: 0.5, y: 0.78),
                size: .medium,
                style: defaultWidgetStyle
            )
        case .dateCalendar:
            return DesktopWidget(
                id: id,
                kind: .dateCalendar,
                position: NormalizedWidgetPosition(x: 0.18, y: 0.20),
                size: .medium,
                style: defaultWidgetStyle
            )
        case .battery:
            return DesktopWidget(
                id: id,
                kind: .battery,
                position: NormalizedWidgetPosition(x: 0.82, y: 0.20),
                size: .medium,
                style: defaultWidgetStyle
            )
        }
    }

    private func initialCustomScale(for widget: DesktopWidget) -> Double {
        switch (widget.kind, widget.size) {
        case (.digitalClock, .small): return 0.68
        case (.digitalClock, .medium): return 1
        case (.digitalClock, .large): return 1.44
        case (.nowPlaying, .small): return 0.74
        case (.nowPlaying, .medium): return 1
        case (.nowPlaying, .large): return 1.33
        case (.dateCalendar, .small), (.battery, .small): return 0.78
        case (.dateCalendar, .medium), (.battery, .medium): return 1
        case (.dateCalendar, .large), (.battery, .large): return 1.30
        case (_, .custom): return widget.customScale ?? 1
        }
    }

    private func setStyleWithoutHistory(
        _ style: WidgetVisualStyle,
        on widget: inout DesktopWidget
    ) {
        widget.style = style
        let showsBackground = style != .none
        switch widget.kind {
        case .digitalClock:
            widget.digitalClock.showsBackground = showsBackground
        case .nowPlaying:
            widget.nowPlaying.showsBackground = showsBackground
        case .dateCalendar:
            widget.dateCalendar.showsBackground = showsBackground
        case .battery:
            widget.battery.showsBackground = showsBackground
        }
    }

    private func updateWidgetWithoutHistory(id: UUID, change: (inout DesktopWidget) -> Void) {
        var mirrored = widgets
        if let index = mirrored.firstIndex(where: { $0.id == id }) {
            change(&mirrored[index])
            widgets = mirrored
            return
        }
        var configurations = widgetDisplayConfigurations
        for configurationIndex in configurations.indices {
            if let widgetIndex = configurations[configurationIndex].widgets.firstIndex(where: { $0.id == id }) {
                change(&configurations[configurationIndex].widgets[widgetIndex])
                widgetDisplayConfigurations = configurations
                return
            }
        }
    }

    private func reorderWidget(
        id: UUID,
        for displayID: String?,
        actionName: String,
        change: (Int, inout [DesktopWidget]) -> Void
    ) {
        performWidgetMutation(named: actionName) {
            var collection = widgetCollection(for: displayID)
            guard let index = collection.firstIndex(where: { $0.id == id }) else { return }
            change(index, &collection)
            setWidgetCollection(collection, for: displayID)
        }
    }

    private func normalizeWidgetState() {
        if state.widgets == nil { state.widgets = [] }
        if state.widgetDisplayMode == nil { state.widgetDisplayMode = .mirrored }
        if state.widgetDisplayConfigurations == nil { state.widgetDisplayConfigurations = [] }
        if state.widgetPerDisplayInitialized == nil { state.widgetPerDisplayInitialized = false }
        if state.defaultWidgetStyle == nil { state.defaultWidgetStyle = .glass }
    }

    private func initializePerDisplayWidgetsIfNeeded() {
        reconcileWidgetDisplays(onto: displayTopology)
        guard state.widgetPerDisplayInitialized != true else { return }
        var configurations = widgetDisplayConfigurations
        for index in configurations.indices where configurations[index].widgets.isEmpty {
            configurations[index].widgets = widgets.map { $0.duplicated() }
        }
        widgetDisplayConfigurations = configurations
        state.widgetPerDisplayInitialized = true
    }

    private func reconcileWidgetDisplays(onto topology: DisplayTopology) {
        guard !topology.displays.isEmpty else { return }
        var configurations = widgetDisplayConfigurations
        let activeIDs = topology.activeDisplayIDs
        for display in topology.displays {
            if configurations.contains(where: { $0.displayFingerprint.stableID == display.id }) { continue }
            let reservedIDs = activeIDs.subtracting([display.id])
            if let matched = WidgetDisplayResolver.bestConfiguration(
                for: display.fingerprint,
                in: configurations,
                excludingConfigurationIDs: reservedIDs
            ), let index = configurations.firstIndex(of: matched) {
                configurations[index].displayFingerprint = display.fingerprint
                continue
            }
            configurations.append(WidgetDisplayConfiguration(
                displayFingerprint: display.fingerprint,
                widgets: widgetDisplayMode == .perDisplay ? widgets.map { $0.duplicated() } : []
            ))
        }
        widgetDisplayConfigurations = configurations
    }

    private func reservedWidgetConfigurationIDs(except displayID: String) -> Set<String> {
        displayTopology.activeDisplayIDs.subtracting([displayID])
    }

    private func widgetConfigurationIndex(for displayID: String, createIfMissing: Bool) -> Int? {
        guard let display = displayTopology.display(id: displayID) else { return nil }
        var configurations = widgetDisplayConfigurations
        if let exact = configurations.firstIndex(where: { $0.displayFingerprint.stableID == display.fingerprint.stableID }) {
            return exact
        }
        if let matched = WidgetDisplayResolver.bestConfiguration(
            for: display.fingerprint,
            in: configurations,
            excludingConfigurationIDs: reservedWidgetConfigurationIDs(except: display.id)
        ), let index = configurations.firstIndex(of: matched) {
            configurations[index].displayFingerprint = display.fingerprint
            widgetDisplayConfigurations = configurations
            return index
        }
        guard createIfMissing else { return nil }
        configurations.append(WidgetDisplayConfiguration(
            displayFingerprint: display.fingerprint,
            widgets: widgetDisplayMode == .perDisplay ? widgets.map { $0.duplicated() } : []
        ))
        widgetDisplayConfigurations = configurations
        return configurations.indices.last
    }
}

extension AppModel {
    var scenes: [DesktopScene] {
        get { state.scenes ?? [] }
        set { state.scenes = newValue }
    }

    var activeScene: DesktopScene? {
        guard let id = state.activeSceneID else { return nil }
        return scenes.first { $0.id == id }
    }

    var defaultScene: DesktopScene? {
        guard let id = state.defaultSceneID else { return nil }
        return scenes.first { $0.id == id }
    }

    var activeSceneHasChanges: Bool {
        guard let activeScene else { return false }
        return activeScene.configuration != currentSceneConfiguration()
    }

    func scene(id: UUID) -> DesktopScene? {
        scenes.first { $0.id == id }
    }

    @discardableResult
    func createScene(named proposedName: String = "New Scene") -> UUID {
        let now = Date()
        let scene = DesktopScene(
            name: uniqueSceneName(proposedName),
            configuration: currentSceneConfiguration(),
            createdAt: now,
            modifiedAt: now,
            lastActivatedAt: now
        )
        scenes.append(scene)
        state.activeSceneID = scene.id
        persistSoon()
        return scene.id
    }

    @discardableResult
    func duplicateScene(id: UUID) -> UUID? {
        guard let source = scene(id: id) else { return nil }
        let now = Date()
        let duplicate = DesktopScene(
            name: uniqueSceneName("\(source.name) Copy"),
            configuration: source.configuration,
            createdAt: now,
            modifiedAt: now
        )
        scenes.append(duplicate)
        persistSoon()
        return duplicate.id
    }

    func renameScene(id: UUID, to proposedName: String) -> Bool {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Scene names cannot be empty."
            return false
        }
        guard let index = scenes.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let duplicateExists = scenes.contains {
            $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !duplicateExists else {
            errorMessage = "A scene named “\(trimmed)” already exists."
            return false
        }
        scenes[index].name = trimmed
        scenes[index].modifiedAt = Date()
        persistSoon()
        return true
    }

    func saveCurrentSetup(toScene id: UUID) {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()
        scenes[index].configuration = currentSceneConfiguration()
        scenes[index].modifiedAt = now
        scenes[index].lastActivatedAt = now
        state.activeSceneID = id
        persistSoon()
    }

    func deleteScene(id: UUID) {
        scenes.removeAll { $0.id == id }
        if state.activeSceneID == id {
            state.activeSceneID = nil
        }
        if state.defaultSceneID == id {
            state.defaultSceneID = nil
        }
        persistSoon()
    }

    func setDefaultScene(id: UUID?) {
        guard id == nil || scenes.contains(where: { $0.id == id }) else { return }
        state.defaultSceneID = id
        persistSoon()
    }

    func activateScene(id: UUID) async {
        await activateScene(id: id, persist: true)
    }

    func sceneMissingWallpaperCount(_ scene: DesktopScene) -> Int {
        let unavailableIDs = Set(
            state.wallpapers
                .filter { $0.isMissing || $0.kind == .unsupported }
                .map(\.id)
        )
        let unknownIDs = scene.configuration.referencedWallpaperIDs.subtracting(
            Set(state.wallpapers.map(\.id))
        )
        return scene.configuration.referencedWallpaperIDs
            .intersection(unavailableIDs)
            .count + unknownIDs.count
    }

    func currentSceneConfiguration() -> SceneConfiguration {
        SceneConfiguration(
            playback: ScenePlaybackSettings(
                presentationMode: state.settings.presentationMode,
                defaultScalingMode: state.settings.defaultScalingMode,
                videoQuality: state.settings.videoQuality,
                maximumFrameRate: state.settings.maximumFrameRate,
                audioBehavior: state.settings.audioBehavior,
                synchronizedDuplicatePlayback: state.settings.synchronizedDuplicatePlayback
            ),
            sharedWallpaperID: state.sharedWallpaperID,
            assignments: state.assignments,
            playlists: sceneSnapshotPlaylists(),
            activePlaylistID: state.activePlaylistID,
            widgets: widgets,
            widgetDisplayMode: widgetDisplayMode,
            widgetDisplayConfigurations: widgetDisplayConfigurations,
            widgetPerDisplayInitialized: state.widgetPerDisplayInitialized ?? false,
            defaultWidgetStyle: defaultWidgetStyle
        )
    }

    private func activateScene(id: UUID, persist: Bool) async {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return }
        let previousState = state
        let previousConfiguration = currentSceneConfiguration()
        let configuration = scenes[index].configuration
        let requiresWallpaperRebuild = previousConfiguration.playback != configuration.playback
            || previousConfiguration.sharedWallpaperID != configuration.sharedWallpaperID
            || previousConfiguration.assignments != configuration.assignments

        configurationApplyTask?.cancel()
        widgetRefreshTask?.cancel()
        playlistRotationTask?.cancel()
        playlistRotationTask = nil

        state.settings.presentationMode = configuration.playback.presentationMode
        state.settings.defaultScalingMode = configuration.playback.defaultScalingMode
        state.settings.videoQuality = configuration.playback.videoQuality
        state.settings.maximumFrameRate = configuration.playback.maximumFrameRate
        state.settings.audioBehavior = configuration.playback.audioBehavior
        state.settings.synchronizedDuplicatePlayback = configuration.playback.synchronizedDuplicatePlayback
        state.sharedWallpaperID = configuration.sharedWallpaperID
        state.assignments = configuration.assignments
        state.playlists = configuration.playlists
        state.activePlaylistID = configuration.activePlaylistID
        state.widgets = configuration.widgets
        state.widgetDisplayMode = configuration.widgetDisplayMode
        state.widgetDisplayConfigurations = configuration.widgetDisplayConfigurations
        state.widgetPerDisplayInitialized = configuration.widgetPerDisplayInitialized
        state.defaultWidgetStyle = configuration.defaultWidgetStyle
        state.activeSceneID = id

        normalizePlaylistState()
        normalizeWidgetState()
        reconcileAssignments(onto: displayTopology)
        reconcileWidgetDisplays(onto: displayTopology)

        if let activeID = state.activePlaylistID,
           let playlistIndex = playlists.firstIndex(where: { $0.id == activeID }),
           playlists[playlistIndex].isRunning {
            playlists[playlistIndex].lastAdvancedAt = Date()
        }

        do {
            if requiresWallpaperRebuild {
                try await engine.applyConfiguration(
                    state: state,
                    topology: displayTopology
                )
            } else {
                engine.updateWidgets(
                    state: state,
                    topology: displayTopology
                )
            }
            scenes[index].lastActivatedAt = Date()
            if persist {
                try await save()
            }
            schedulePlaylistRotation()
        } catch {
            state = previousState
            normalizePlaylistState()
            normalizeWidgetState()
            normalizeSceneState()
            reconcileAssignments(onto: displayTopology)
            reconcileWidgetDisplays(onto: displayTopology)
            try? await engine.applyConfiguration(
                state: state,
                topology: displayTopology
            )
            schedulePlaylistRotation()
            errorMessage = error.localizedDescription
        }
    }

    private func sceneSnapshotPlaylists() -> [WallpaperPlaylist] {
        playlists.map { playlist in
            var copy = playlist
            copy.cursor = 0
            copy.currentWallpaperID = nil
            copy.history = []
            copy.lastAdvancedAt = nil
            return copy
        }
    }

    private func normalizeSceneState() {
        if state.scenes == nil { state.scenes = [] }
        let ids = Set(scenes.map(\.id))
        if let activeID = state.activeSceneID, !ids.contains(activeID) {
            state.activeSceneID = nil
        }
        if let defaultID = state.defaultSceneID, !ids.contains(defaultID) {
            state.defaultSceneID = nil
        }
    }

    private func uniqueSceneName(_ proposedName: String) -> String {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "New Scene" : trimmed
        let names = Set(scenes.map { $0.name.lowercased() })
        guard names.contains(base.lowercased()) else { return base }
        var suffix = 2
        while names.contains("\(base) \(suffix)".lowercased()) {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }
}
