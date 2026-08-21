import XCTest

/// Tapping things that are still moving.
///
/// Extracted from `SeededLaunch` when it crossed SwiftLint's 400-line limit, following the
/// precedent `AccessibilityAudit.swift` set: a concern worth a paragraph of rationale gets its
/// own file, and there is exactly one copy of the paragraph.
extension XCUIElement {
    /// Tap this element once it has **stopped moving** — not merely once it exists.
    ///
    /// 🚨 `waitForExistence` returns the instant an element joins the accessibility tree, which
    /// on these screens is well before it has animated into place: a correction, the memory
    /// offer's dismissal and the list's re-read are three animations deep. A tap issued in that
    /// window lands where the element *was*, hits nothing, and whatever assertion follows
    /// reports something like "tapping a row did not open the transaction" — **a sentence that
    /// reads exactly like a broken row and is not**
    /// (`.scratch/020-categorize/issues/06`). It went red on `main` and green on a re-run of
    /// the identical commit; `CategorizeWorklistUITests` had already found the same thing one
    /// screen over and solved it only for itself.
    ///
    /// ⚠️ The `Thread.sleep` below is a **sampling interval, not a wait.** The loop returns the
    /// moment two consecutive samples agree and the element is hittable, so an element that is
    /// already settled costs one interval. A fixed sleep would be the thing this repository
    /// keeps refusing — a statement about the machine rather than about the app — and this
    /// ticket exists precisely because statements about the machine do not survive a different
    /// machine.
    ///
    /// It deliberately **does not fail** when it times out: being settled is a precondition,
    /// never the claim under test. The caller's own assertion reports, with its own message, at
    /// its own line — so a genuinely broken row still fails, and fails where it means something.
    func tapWhenSettled(timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        var previous = exists ? frame : .null
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            guard exists else { break }
            let current = frame
            if current == previous, isHittable { break }
            previous = current
        }
        tap()
    }
}
