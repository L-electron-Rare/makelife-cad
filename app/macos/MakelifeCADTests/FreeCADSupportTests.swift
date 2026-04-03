import XCTest
@testable import MakelifeCAD

final class FreeCADSupportTests: XCTestCase {
    func testDiscoverFreeCADDocumentsRecursively() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("makelife-freecad-tests-\(UUID().uuidString)", isDirectory: true)
        let mechanical = tempRoot.appendingPathComponent("mechanical", isDirectory: true)
        let nested = mechanical.appendingPathComponent("enclosure/rev-a", isDirectory: true)

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let rootFile = mechanical.appendingPathComponent("assembly.FCStd")
        let nestedFile = nested.appendingPathComponent("bracket.FCStd")
        FileManager.default.createFile(atPath: rootFile.path, contents: Data())
        FileManager.default.createFile(atPath: nestedFile.path, contents: Data())

        let docs = YiacadProject.discoverFreeCADDocuments(projectRoot: tempRoot)

        XCTAssertEqual(docs.count, 2)
        XCTAssertEqual(docs.map(\.relativePath), [
            "mechanical/assembly.FCStd",
            "mechanical/enclosure/rev-a/bracket.FCStd"
        ])

        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testParseVersionAndCompatibility() {
        XCTAssertEqual(FreeCADRuntimeResolver.parseVersion(from: "FreeCAD 1.1.0"), "1.1.0")
        XCTAssertEqual(FreeCADRuntimeResolver.parseVersion(from: "1.1.3 build"), "1.1.3")
        XCTAssertTrue(FreeCADRuntimeResolver.isCompatible(version: "1.1.0"))
        XCTAssertTrue(FreeCADRuntimeResolver.isCompatible(version: "1.1.8"))
        XCTAssertFalse(FreeCADRuntimeResolver.isCompatible(version: "1.2.0"))
        XCTAssertFalse(FreeCADRuntimeResolver.isCompatible(version: nil))
    }

    func testExportPlannerPrefersGatewayWhenLocalAndHealthy() {
        let local = FreeCADRuntimeStatus(
            status: "available",
            installed: true,
            version: "1.1.0",
            compatible: true,
            path: "/Applications/FreeCAD.app/Contents/MacOS/FreeCADCmd",
            source: "app_bundle",
            preferredExportMode: "local"
        )
        let gateway = FreeCADRuntimeStatus(
            status: "available",
            installed: true,
            version: "1.1.0",
            compatible: true,
            path: "/Applications/FreeCAD.app/Contents/MacOS/FreeCADCmd",
            source: "app_bundle",
            preferredExportMode: "gateway"
        )

        XCTAssertEqual(
            FreeCADExportPlanner.chooseMode(
                localStatus: local,
                gatewayBaseURL: "http://localhost:8001",
                gatewayStatus: gateway
            ),
            .gateway
        )
        XCTAssertEqual(
            FreeCADExportPlanner.chooseMode(
                localStatus: local,
                gatewayBaseURL: "https://cad.saillant.cc",
                gatewayStatus: gateway
            ),
            .local
        )
        XCTAssertEqual(
            FreeCADExportPlanner.chooseMode(
                localStatus: FreeCADRuntimeStatus.unavailable,
                gatewayBaseURL: "http://localhost:8001",
                gatewayStatus: gateway
            ),
            .unavailable
        )
    }

    func testGatewayProbePolicySkipsBootProbeWithoutProject() {
        XCTAssertFalse(
            FreeCADExportPlanner.shouldProbeGateway(
                projectAvailable: false,
                gatewayBaseURL: "http://localhost:8001"
            )
        )
        XCTAssertTrue(
            FreeCADExportPlanner.shouldProbeGateway(
                projectAvailable: true,
                gatewayBaseURL: "http://localhost:8001"
            )
        )
        XCTAssertTrue(
            FreeCADExportPlanner.shouldProbeGateway(
                projectAvailable: false,
                gatewayBaseURL: "http://localhost:8001",
                force: true
            )
        )
        XCTAssertFalse(
            FreeCADExportPlanner.shouldProbeGateway(
                projectAvailable: true,
                gatewayBaseURL: "https://cad.saillant.cc",
                force: true
            )
        )
    }
}
