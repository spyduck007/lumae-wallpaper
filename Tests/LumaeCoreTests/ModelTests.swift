import XCTest
@testable import LumaeCore
final class ModelTests:XCTestCase {
 func testDuplicate(){ let a=WallpaperMetadata(name:"A",originalFilePath:"/a",format:.png,fileSizeBytes:1,pixelWidth:1,pixelHeight:1,contentHash:"same"); let b=WallpaperMetadata(name:"B",originalFilePath:"/b",format:.png,fileSizeBytes:1,pixelWidth:1,pixelHeight:1,contentHash:"same"); XCTAssertEqual(DuplicateDetector.duplicate(of:b,in:[a])?.id,a.id) }
 func testPersistence() throws { let s=PersistedApplicationState(wallpapers:[WallpaperMetadata(name:"A",originalFilePath:"/a",format:.jpg,fileSizeBytes:4,pixelWidth:1920,pixelHeight:1080,contentHash:"x")]); XCTAssertEqual(try JSONDecoder().decode(PersistedApplicationState.self,from:JSONEncoder().encode(s)),s) }
 func testCache(){ let e=[CacheEntry(path:"old",sizeBytes:10,lastAccessed:.distantPast),CacheEntry(path:"new",sizeBytes:10,lastAccessed:.now),CacheEntry(path:"pin",sizeBytes:10,lastAccessed:.distantPast,isPinned:true)]; XCTAssertEqual(CachePolicy.evictionCandidates(entries:e,limitBytes:20).map(\.path),["old"]) }
 func testPlaylist(){ let a=UUID(),b=UUID(),m=UUID(); var p=PlaylistConfiguration(isEnabled:true,wallpaperIDs:[m,a,b]); XCTAssertEqual(PlaylistEngine.nextID(configuration:&p,availableIDs:[a,b]),a); XCTAssertEqual(PlaylistEngine.nextID(configuration:&p,availableIDs:[a,b]),b) }

 func testNamedPlaylistSequentialAndMissingSkip(){
  let missing=UUID(),a=UUID(),b=UUID(); var p=WallpaperPlaylist(name:"Mix",wallpaperIDs:[missing,a,b],intervalSeconds:60)
  XCTAssertEqual(WallpaperPlaylistEngine.advance(playlist:&p,direction:.next,availableIDs:[a,b]),a)
  XCTAssertEqual(WallpaperPlaylistEngine.advance(playlist:&p,direction:.next,availableIDs:[a,b]),b)
  XCTAssertEqual(WallpaperPlaylistEngine.advance(playlist:&p,direction:.previous,availableIDs:[a,b]),a)
 }
 func testNamedPlaylistShuffleAvoidsImmediateRepeat(){
  let a=UUID(),b=UUID(); var p=WallpaperPlaylist(name:"Shuffle",wallpaperIDs:[a,b],shuffle:true,currentWallpaperID:a)
  XCTAssertEqual(WallpaperPlaylistEngine.advance(playlist:&p,direction:.next,availableIDs:[a,b],randomIndex:{_ in 0}),b)
 }

 func testWidgetPositionClampsToCanvas(){
  let position=NormalizedWidgetPosition(x:-2,y:3)
  XCTAssertEqual(position.x,0)
  XCTAssertEqual(position.y,1)
 }
 func testWidgetPersistence() throws {
  let widget=DesktopWidget(kind:.digitalClock,position:NormalizedWidgetPosition(x:0.25,y:0.75),size:.large,digitalClock:DigitalClockWidgetSettings(uses24HourTime:true,showsSeconds:true))
  let state=PersistedApplicationState(widgets:[widget])
  let decoded=try JSONDecoder().decode(PersistedApplicationState.self,from:JSONEncoder().encode(state))
  XCTAssertEqual(decoded.widgets,[widget])
 }

 func testClockBackgroundDefaultsOnForOlderState() throws {
  let json=Data("{\"uses24HourTime\":false,\"showsSeconds\":true}".utf8)
  let settings=try JSONDecoder().decode(DigitalClockWidgetSettings.self,from:json)
  XCTAssertTrue(settings.showsBackground)
 }
 func testMirroredWidgetCanBeDisabledPerDisplay(){
  let fingerprint=DisplayFingerprint(stableID:"one",localizedName:"One")
  let display=DisplayDescriptor(fingerprint:fingerprint,framePoints:LRect(x:0,y:0,width:100,height:100),visibleFramePoints:LRect(x:0,y:0,width:100,height:100),pixelSize:LSize(width:100,height:100),backingScaleFactor:1)
  let clock=DesktopWidget(kind:.digitalClock)
  let config=WidgetDisplayConfiguration(displayFingerprint:fingerprint,isEnabled:false)
  XCTAssertTrue(WidgetDisplayResolver.widgets(for:display,mode:.mirrored,mirroredWidgets:[clock],configurations:[config]).isEmpty)
 }
 func testPerDisplayWidgetResolutionUsesFingerprintFallback(){
  let saved=DisplayFingerprint(stableID:"old",vendorID:1,modelID:2,serialNumber:3,localizedName:"Monitor")
  let current=DisplayFingerprint(stableID:"new",vendorID:1,modelID:2,serialNumber:3,localizedName:"Monitor")
  let display=DisplayDescriptor(fingerprint:current,framePoints:LRect(x:0,y:0,width:100,height:100),visibleFramePoints:LRect(x:0,y:0,width:100,height:100),pixelSize:LSize(width:100,height:100),backingScaleFactor:1)
  let clock=DesktopWidget(kind:.digitalClock)
  let config=WidgetDisplayConfiguration(displayFingerprint:saved,widgets:[clock])
  XCTAssertEqual(WidgetDisplayResolver.widgets(for:display,mode:.perDisplay,mirroredWidgets:[],configurations:[config]),[clock])
 }

 func testActiveIdenticalDisplaysDoNotShareWidgetConfiguration(){
  let firstFingerprint=DisplayFingerprint(stableID:"cg-1-v10-m20",vendorID:10,modelID:20,serialNumber:0,localizedName:"24G15N")
  let secondFingerprint=DisplayFingerprint(stableID:"cg-2-v10-m20",vendorID:10,modelID:20,serialNumber:0,localizedName:"24G15N")
  let first=DisplayDescriptor(fingerprint:firstFingerprint,framePoints:LRect(x:0,y:0,width:100,height:100),visibleFramePoints:LRect(x:0,y:0,width:100,height:100),pixelSize:LSize(width:100,height:100),backingScaleFactor:1)
  let second=DisplayDescriptor(fingerprint:secondFingerprint,framePoints:LRect(x:100,y:0,width:100,height:100),visibleFramePoints:LRect(x:100,y:0,width:100,height:100),pixelSize:LSize(width:100,height:100),backingScaleFactor:1)
  let firstConfig=WidgetDisplayConfiguration(displayFingerprint:firstFingerprint,isEnabled:false)
  let secondConfig=WidgetDisplayConfiguration(displayFingerprint:secondFingerprint,isEnabled:true)
  XCTAssertTrue(WidgetDisplayResolver.widgets(for:first,mode:.mirrored,mirroredWidgets:[DesktopWidget(kind:.digitalClock)],configurations:[firstConfig,secondConfig],excludingConfigurationIDs:[second.id]).isEmpty)
  XCTAssertEqual(WidgetDisplayResolver.widgets(for:second,mode:.mirrored,mirroredWidgets:[DesktopWidget(kind:.digitalClock)],configurations:[firstConfig,secondConfig],excludingConfigurationIDs:[first.id]).count,1)
 }
 func testWidgetSnappingToCanvasGuides(){
  let result=WidgetSnapEngine.snap(position:NormalizedWidgetPosition(x:0.492,y:0.126),canvasSize:LSize(width:1000,height:500))
  XCTAssertEqual(result.position.x,0.5)
  XCTAssertEqual(result.position.y,0.12)
  XCTAssertEqual(result.verticalGuide,0.5)
  XCTAssertEqual(result.horizontalGuide,0.12)
 }
 func testWidgetSnappingLeavesDistantPositionAlone(){
  let result=WidgetSnapEngine.snap(position:NormalizedWidgetPosition(x:0.37,y:0.31),canvasSize:LSize(width:1000,height:500))
  XCTAssertEqual(result.position,NormalizedWidgetPosition(x:0.37,y:0.31))
  XCTAssertNil(result.verticalGuide)
  XCTAssertNil(result.horizontalGuide)
 }

 func testNowPlayingWidgetPersistsAlongsideClock() throws {
  let clock=DesktopWidget(kind:.digitalClock)
  let nowPlaying=DesktopWidget(kind:.nowPlaying,position:NormalizedWidgetPosition(x:0.5,y:0.78),size:.large,nowPlaying:NowPlayingWidgetSettings(showsBackground:false))
  let state=PersistedApplicationState(widgets:[clock,nowPlaying])
  let decoded=try JSONDecoder().decode(PersistedApplicationState.self,from:JSONEncoder().encode(state))
  XCTAssertEqual(decoded.widgets,[clock,nowPlaying])
 }
 func testOlderDesktopWidgetDecodesNowPlayingDefaults() throws {
  let widget=DesktopWidget(kind:.digitalClock)
  let encoded=try JSONEncoder().encode(widget)
  var object=try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
  object.removeValue(forKey:"nowPlaying")
  let legacy=try JSONSerialization.data(withJSONObject:object)
  let decoded=try JSONDecoder().decode(DesktopWidget.self,from:legacy)
  XCTAssertTrue(decoded.nowPlaying.showsBackground)
 }

 func testCustomWidgetScalePersistsAndClamps() throws {
  let widget=DesktopWidget(kind:.nowPlaying,size:.custom,customScale:9)
  XCTAssertEqual(widget.renderingScale,2.5)
  let decoded=try JSONDecoder().decode(DesktopWidget.self,from:JSONEncoder().encode(widget))
  XCTAssertEqual(decoded.size,.custom)
  XCTAssertEqual(decoded.renderingScale,2.5)
 }
 func testOlderWidgetDefaultsCustomScaleSafely() throws {
  let widget=DesktopWidget(kind:.digitalClock)
  let encoded=try JSONEncoder().encode(widget)
  var object=try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
  object.removeValue(forKey:"customScale")
  object["size"]="custom"
  let legacy=try JSONSerialization.data(withJSONObject:object)
  let decoded=try JSONDecoder().decode(DesktopWidget.self,from:legacy)
  XCTAssertEqual(decoded.renderingScale,1)
 }

 func testWidgetCanvasClampsAndSnapsToOtherWidget(){
  let other=WidgetCanvasItem(id:UUID(),frame:LRect(x:100,y:100,width:120,height:60))
  let moving=WidgetCanvasItem(id:UUID(),frame:LRect(x:124,y:190,width:80,height:40))
  let result=WidgetCanvasEngine.snap(moving:moving,canvasSize:LSize(width:500,height:300),others:[other])
  XCTAssertEqual(result.frame.midX,160,accuracy:0.001)
  XCTAssertEqual(result.verticalGuides.first ?? -1,160,accuracy:0.001)
  let clamped=WidgetCanvasEngine.clamp(LRect(x:-20,y:500,width:80,height:40),to:LSize(width:500,height:300))
  XCTAssertEqual(clamped,LRect(x:0,y:260,width:80,height:40))
 }
 func testWidgetCanvasMaximumScaleRespectsBounds(){
  let scale=WidgetCanvasEngine.maximumScale(currentFrame:LRect(x:200,y:125,width:100,height:50),currentScale:1,center:LPoint(x:250,y:150),canvasSize:LSize(width:500,height:300))
  XCTAssertEqual(scale,5,accuracy:0.001)
  let edgeScale=WidgetCanvasEngine.maximumScale(currentFrame:LRect(x:25,y:25,width:100,height:50),currentScale:1,center:LPoint(x:75,y:50),canvasSize:LSize(width:500,height:300))
  XCTAssertEqual(edgeScale,1.5,accuracy:0.001)
 }

 func testWidgetCanvasEqualSpacing(){
  let left=WidgetCanvasItem(id:UUID(),frame:LRect(x:20,y:50,width:50,height:40))
  let right=WidgetCanvasItem(id:UUID(),frame:LRect(x:230,y:50,width:50,height:40))
  let moving=WidgetCanvasItem(id:UUID(),frame:LRect(x:140,y:50,width:40,height:40))
  let result=WidgetCanvasEngine.snap(moving:moving,canvasSize:LSize(width:300,height:180),others:[left,right],thresholdPoints:12)
  XCTAssertTrue(result.hasEqualHorizontalSpacing)
  XCTAssertEqual(result.frame.minX,130,accuracy:0.001)
 }
 func testWidgetCanvasDetectsEqualSpacing(){
  let left=WidgetCanvasItem(id:UUID(),frame:LRect(x:20,y:100,width:60,height:40))
  let right=WidgetCanvasItem(id:UUID(),frame:LRect(x:220,y:100,width:60,height:40))
  let moving=WidgetCanvasItem(id:UUID(),frame:LRect(x:111,y:100,width:80,height:40))
  let result=WidgetCanvasEngine.snap(moving:moving,canvasSize:LSize(width:400,height:300),others:[left,right],thresholdPoints:12)
  XCTAssertTrue(result.hasEqualHorizontalSpacing)
  XCTAssertEqual(result.frame.minX,110,accuracy:0.001)
 }

 func testNewWidgetSettingsPersist() throws {
  let date=DesktopWidget(
   kind:.dateCalendar,
   dateCalendar:DateCalendarWidgetSettings(
    mode:.monthCalendar,
    showsWeekday:false,
    showsYear:true,
    weekStart:.monday,
    showsAdjacentMonthDates:false,
    showsBackground:false
   )
  )
  let battery=DesktopWidget(
   kind:.battery,
   battery:BatteryWidgetSettings(
    showsPercentage:false,
    showsStatusText:true,
    showsProgressBar:false,
    showsBackground:false
   )
  )
  let state=PersistedApplicationState(widgets:[date,battery])
  let decoded=try JSONDecoder().decode(PersistedApplicationState.self,from:JSONEncoder().encode(state))
  XCTAssertEqual(decoded.widgets,[date,battery])
 }
 func testOlderWidgetDecodesNewSettingsDefaults() throws {
  let widget=DesktopWidget(kind:.digitalClock)
  let encoded=try JSONEncoder().encode(widget)
  var object=try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
  object.removeValue(forKey:"dateCalendar")
  object.removeValue(forKey:"battery")
  let legacy=try JSONSerialization.data(withJSONObject:object)
  let decoded=try JSONDecoder().decode(DesktopWidget.self,from:legacy)
  XCTAssertEqual(decoded.dateCalendar,DateCalendarWidgetSettings())
  XCTAssertEqual(decoded.battery,BatteryWidgetSettings())
 }
 func testWidgetKindsIncludeDateAndBattery(){
  XCTAssertTrue(DesktopWidgetKind.allCases.contains(.dateCalendar))
  XCTAssertTrue(DesktopWidgetKind.allCases.contains(.battery))
 }

 func testLegacyBackgroundMigratesToWidgetStyle() throws {
  let visible=DesktopWidget(kind:.digitalClock,digitalClock:DigitalClockWidgetSettings(showsBackground:true))
  let hidden=DesktopWidget(kind:.dateCalendar,dateCalendar:DateCalendarWidgetSettings(showsBackground:false))
  for (widget,expected) in [(visible,WidgetVisualStyle.glass),(hidden,WidgetVisualStyle.none)] {
   let encoded=try JSONEncoder().encode(widget)
   var object=try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
   object.removeValue(forKey:"style")
   let legacy=try JSONSerialization.data(withJSONObject:object)
   XCTAssertEqual(try JSONDecoder().decode(DesktopWidget.self,from:legacy).style,expected)
  }
 }
 func testWidgetStyleAndArtworkTintPersist() throws {
  let widget=DesktopWidget(
   kind:.nowPlaying,
   style:.clear,
   nowPlaying:NowPlayingWidgetSettings(showsBackground:true,usesArtworkTint:false)
  )
  let decoded=try JSONDecoder().decode(DesktopWidget.self,from:JSONEncoder().encode(widget))
  XCTAssertEqual(decoded.style,.clear)
  XCTAssertFalse(decoded.nowPlaying.usesArtworkTint)
 }
 func testDefaultWidgetStylePersists() throws {
  let state=PersistedApplicationState(defaultWidgetStyle:.highContrast)
  let decoded=try JSONDecoder().decode(PersistedApplicationState.self,from:JSONEncoder().encode(state))
  XCTAssertEqual(decoded.defaultWidgetStyle,.highContrast)
 }
 func testWidgetVisualStylesComplete(){
  XCTAssertEqual(Set(WidgetVisualStyle.allCases),Set([.glass,.clear,.highContrast,.none]))
 }

 func testSceneConfigurationPersistsCompleteDesktopState() throws {
  let wallpaperID=UUID()
  let fingerprint=DisplayFingerprint(stableID:"display",localizedName:"Display")
  let assignment=DisplayAssignment(displayFingerprint:fingerprint,wallpaperID:wallpaperID)
  let widget=DesktopWidget(kind:.digitalClock,style:.clear)
  let playlist=WallpaperPlaylist(name:"Focus",wallpaperIDs:[wallpaperID],isRunning:true)
  let configuration=SceneConfiguration(
   playback:ScenePlaybackSettings(
    presentationMode:.perDisplay,
    defaultScalingMode:.fill,
    videoQuality:.balanced,
    maximumFrameRate:60,
    audioBehavior:.muted,
    synchronizedDuplicatePlayback:true
   ),
   sharedWallpaperID:wallpaperID,
   assignments:[assignment],
   playlists:[playlist],
   activePlaylistID:playlist.id,
   widgets:[widget],
   widgetDisplayMode:.mirrored,
   widgetDisplayConfigurations:[],
   widgetPerDisplayInitialized:false,
   defaultWidgetStyle:.glass
  )
  let scene=DesktopScene(name:"Work",configuration:configuration)
  let decoded=try JSONDecoder().decode(DesktopScene.self,from:JSONEncoder().encode(scene))
  XCTAssertEqual(decoded,scene)
  XCTAssertEqual(decoded.configuration.referencedWallpaperIDs,[wallpaperID])
 }
 func testSceneStateIsBackwardCompatible() throws {
  let state=PersistedApplicationState()
  let encoded=try JSONEncoder().encode(state)
  var object=try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
  object.removeValue(forKey:"scenes")
  object.removeValue(forKey:"activeSceneID")
  object.removeValue(forKey:"defaultSceneID")
  let legacy=try JSONSerialization.data(withJSONObject:object)
  let decoded=try JSONDecoder().decode(PersistedApplicationState.self,from:legacy)
  XCTAssertNil(decoded.scenes)
  XCTAssertNil(decoded.activeSceneID)
  XCTAssertNil(decoded.defaultSceneID)
 }
 func testSceneReferencedWallpapersIncludesAssignmentsAndPlaylists(){
  let shared=UUID(), assigned=UUID(), playlistID=UUID(), current=UUID()
  let fingerprint=DisplayFingerprint(stableID:"display",localizedName:"Display")
  var playlist=WallpaperPlaylist(name:"Rotation",wallpaperIDs:[playlistID])
  playlist.currentWallpaperID=current
  let configuration=SceneConfiguration(
   playback:ScenePlaybackSettings(
    presentationMode:.duplicate,
    defaultScalingMode:.fit,
    videoQuality:.efficiency,
    maximumFrameRate:30,
    audioBehavior:.muted,
    synchronizedDuplicatePlayback:true
   ),
   sharedWallpaperID:shared,
   assignments:[DisplayAssignment(displayFingerprint:fingerprint,wallpaperID:assigned)],
   playlists:[playlist],
   activePlaylistID:playlist.id,
   widgets:[],
   widgetDisplayMode:.mirrored,
   widgetDisplayConfigurations:[],
   widgetPerDisplayInitialized:false,
   defaultWidgetStyle:.glass
  )
  XCTAssertEqual(configuration.referencedWallpaperIDs,[shared,assigned,playlistID,current])
 }
}
