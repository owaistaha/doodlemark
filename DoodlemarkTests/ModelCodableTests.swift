import XCTest
@testable import Doodlemark

/// encode → decode → equal, using the same JSON coders ProjectStore will use.
final class ModelCodableTests: XCTestCase {
    private func roundTrip<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try ProjectCoding.makeEncoder().encode(value)
        let decoded = try ProjectCoding.makeDecoder().decode(T.self, from: data)
        XCTAssertEqual(decoded, value, file: file, line: line)
    }

    func testProjectRoundTripsWithShapesAndText() throws {
        try roundTrip(Fixtures.fullProject())
    }

    func testProjectRoundTripsWithoutText() throws {
        var project = Fixtures.fullProject()
        project.text = nil
        project.shapes = []
        try roundTrip(project)
    }

    func testProjectRoundTripsWithNonRoundDates() throws {
        // A real Date() has sub-millisecond precision. It must survive exactly.
        var project = Fixtures.fullProject()
        project.createdAt = Date()
        project.updatedAt = project.createdAt.addingTimeInterval(0.123456789)
        try roundTrip(project)
    }

    func testEveryShapeKindRoundTrips() throws {
        for kind in LogoShape.Kind.allCases {
            try roundTrip(LogoShape(
                id: UUID(), kind: kind, center: CGPoint(x: 12.5, y: 1000.25),
                size: 333.3, rotation: -1.25, fill: .third))
        }
    }

    func testLogoTextRoundTrips() throws {
        try roundTrip(Fixtures.pizzaText())
    }

    func testHexColorEncodesAsHexString() throws {
        let data = try JSONEncoder().encode([Fixtures.tangerine, HexColor(red: 0, green: 10, blue: 255)])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), ##"["#FF5A1F","#000AFF"]"##)
    }

    func testHexColorParsing() {
        XCTAssertEqual(HexColor("#1c1b22"), Fixtures.ink)
        XCTAssertEqual(HexColor("1C1B22"), Fixtures.ink)
        XCTAssertNil(HexColor("#12345"))
        XCTAssertNil(HexColor("#GGGGGG"))
    }

    func testInvalidHexColorFailsToDecode() {
        let json = Data(##"["#XYZ"]"##.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode([HexColor].self, from: json))
    }
}
