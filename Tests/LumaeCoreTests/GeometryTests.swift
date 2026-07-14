import XCTest
@testable import LumaeCore
final class GeometryTests: XCTestCase {
    private func d(_ id:String,_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ scale:Double=1)->DisplayDescriptor { DisplayDescriptor(fingerprint:.init(stableID:id,localizedName:id),framePoints:.init(x:x,y:y,width:w,height:h),visibleFramePoints:.init(x:x,y:y,width:w,height:h),pixelSize:.init(width:w*scale,height:h*scale),backingScaleFactor:scale) }
    func testTwo1080pSideBySide() throws { let t=DisplayTopology(displays:[d("a",0,0,1920,1080),d("b",1920,0,1920,1080)]); XCTAssertEqual(t.virtualBoundsPoints,LRect(x:0,y:0,width:3840,height:1080)); let l=try SpanLayoutEngine.makeLayout(topology:t,sourceSize:.init(width:3840,height:1080),mode:.fill); XCTAssertEqual(l.slices[1].sourceCrop.origin.x,1920,accuracy:0.001) }
    func testNegativeCoordinatesAndOffsets() throws { let t=DisplayTopology(displays:[d("left",-1600,120,1600,900),d("main",0,0,2560,1440,2),d("top",400,1440,1200,1920)]); XCTAssertEqual(t.virtualBoundsPoints,LRect(x:-1600,y:0,width:4160,height:3360)); XCTAssertEqual(try SpanLayoutEngine.makeLayout(topology:t,sourceSize:.init(width:8320,height:6720),mode:.stretch).slices.count,3) }
    func testFillAndFit() { let dst=LRect(x:0,y:0,width:1920,height:1080); XCTAssertEqual(GeometryEngine.placement(source:.init(width:1000,height:1000),destination:dst,mode:.fill).frame.size.height,1920,accuracy:0.001); XCTAssertEqual(GeometryEngine.placement(source:.init(width:1000,height:1000),destination:dst,mode:.fit).frame.size.width,1080,accuracy:0.001) }
    func testPortraitLandscapeMixedScale() throws { let t=DisplayTopology(displays:[d("portrait",-1080,0,1080,1920),d("retina",0,240,1512,982,2)]); let l=try SpanLayoutEngine.makeLayout(topology:t,sourceSize:.init(width:5000,height:3000),mode:.fill); XCTAssertLessThanOrEqual(SpanLayoutEngine.maximumBoundaryErrorInPixels(l),1) }
    func testAssignmentRestoration() { let old=DisplayFingerprint(stableID:"old",vendorID:1,modelID:2,serialNumber:3,localizedName:"Panel"); let new=DisplayFingerprint(stableID:"new",vendorID:1,modelID:2,serialNumber:3,localizedName:"Panel"); let t=DisplayTopology(displays:[DisplayDescriptor(fingerprint:new,framePoints:.init(x:0,y:0,width:100,height:100),visibleFramePoints:.init(x:0,y:0,width:100,height:100),pixelSize:.init(width:100,height:100),backingScaleFactor:1)]); XCTAssertNotNil(DisplayAssignmentRestorer.restore(saved:[.init(displayFingerprint:old)],onto:t)["new"]) }
    func testAssignmentRestorationKeepsIndependentSettings() {
        let wallpaperID = UUID()
        let old = DisplayFingerprint(stableID:"old",vendorID:10,modelID:20,serialNumber:30,localizedName:"Studio")
        let new = DisplayFingerprint(stableID:"new",vendorID:10,modelID:20,serialNumber:30,localizedName:"Studio")
        let assignment = DisplayAssignment(displayFingerprint:old,wallpaperID:wallpaperID,enabled:false,scalingMode:.fit,maxFrameRate:24,videoQuality:.efficiency)
        let topology = DisplayTopology(displays:[DisplayDescriptor(fingerprint:new,framePoints:.init(x:0,y:0,width:1920,height:1080),visibleFramePoints:.init(x:0,y:0,width:1920,height:1080),pixelSize:.init(width:1920,height:1080),backingScaleFactor:1)])
        let restored = DisplayAssignmentRestorer.restore(saved:[assignment],onto:topology)["new"]
        XCTAssertEqual(restored?.wallpaperID, wallpaperID)
        XCTAssertEqual(restored?.enabled, false)
        XCTAssertEqual(restored?.scalingMode, .fit)
        XCTAssertEqual(restored?.maxFrameRate, 24)
        XCTAssertEqual(restored?.videoQuality, .efficiency)
    }
}
