import CoreGraphics

/// Every number Learn scoring uses (TECH_SPEC "Stroke scoring"). All
/// distances are in the 1024 canvas space: strokes are read in canvas
/// space, which doesn't change with zoom, so these are never scaled.
///
/// Starting values. TECH_SPEC: tune them with a finger on a real iPad
/// (DEVICE_CHECKLIST), and `LessonLoaderTests.testThresholdsAreFairToWobblyFingers`
/// reports how simulated finger strokes land with them.
struct ScoringConfig: Equatable, Sendable {
    /// Both strokes are resampled to this many points, evenly spaced along their length.
    var sampleCount = 64

    /// Discrete Fréchet distance (canvas points) for each star level.
    var threeStarDistance: Double = 18
    var twoStarDistance: Double = 36
    var oneStarDistance: Double = 60

    /// User length / target length outside this range is a miss ("Try
    /// drawing the whole line").
    var lengthRatio: ClosedRange<Double> = 0.6...1.5

    /// Lengths for that check are measured on lines resampled with points at
    /// least this far apart (and at most `sampleCount` points), so a shaky
    /// finger on a short stroke isn't told it went "too long".
    var lengthSampleSpacing: Double = 8

    /// Wobble = how much more the user's line turns, on average, between
    /// resampled segments than the target does (radians). Above this, one
    /// star comes off and the tip says to go slower. 0.25: a steady finger
    /// (the gate's wobble at half strength) stays under it (max 0.22); the
    /// gate's shaky-finger wobble mostly goes over (median 0.32).
    var wobbleLimit: Double = 0.25

    static let standard = ScoringConfig()
}
