import Foundation

/// SwiftTerm's `LocalProcess.terminate()` sends SIGTERM but cancels its
/// exit monitor without calling `waitpid`, which would leave one zombie
/// shell per closed Terminal Block for the app's lifetime. Every explicit
/// terminate is therefore paired with a reap here. (Natural exits are
/// unaffected — SwiftTerm's own monitor reaps those.)
enum PTYReaper {
    /// Reaps `pid`, escalating to SIGKILL if it hasn't exited within
    /// `escalateAfter` seconds of the SIGTERM the caller already sent.
    /// Blocks the calling thread; use `reapAfterTerminate` from UI code.
    @discardableResult
    static func reapNow(_ pid: pid_t, escalateAfter seconds: Double = 2.0) -> Bool {
        guard pid > 0 else { return false }
        var status: Int32 = 0
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if waitpid(pid, &status, WNOHANG) == pid { return true }
            usleep(50_000)
        }
        kill(pid, SIGKILL)
        return waitpid(pid, &status, 0) == pid
    }

    /// Fire-and-forget variant for the Block-close path — never blocks the
    /// main thread.
    static func reapAfterTerminate(_ pid: pid_t) {
        guard pid > 0 else { return }
        DispatchQueue.global(qos: .utility).async {
            reapNow(pid)
        }
    }
}
