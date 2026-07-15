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
}
