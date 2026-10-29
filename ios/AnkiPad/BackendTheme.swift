import Foundation

extension StudyTheme {
    var backendIsDark: Bool { self == .black || self == .dark }
    var backendScript: String {
        let canvas = self == .black ? "#000000" : self == .dark ? "#303030" : "#ffffff"
        let raised = self == .black ? "#1a1a1a" : self == .dark ? "#363636" : "#ffffff"
        return """
        (() => {
          const apply = () => {
            const root = document.documentElement;
            if (!root) return;
            root.classList.toggle('night-mode', \(backendIsDark));
            root.dataset.bsTheme = '\(backendIsDark ? "dark" : "light")';
            root.dataset.studyBackendTheme = '\(rawValue)';
            root.style.colorScheme = '\(backendIsDark ? "dark" : "light")';
            root.style.setProperty('--canvas', '\(canvas)');
            root.style.setProperty('--canvas-inset', '\(canvas)');
            root.style.setProperty('--canvas-elevated', '\(raised)');
            root.style.setProperty('--canvas-overlay', '\(raised)');
            root.style.backgroundColor = '\(canvas)';
            if (document.body) document.body.style.backgroundColor = '\(canvas)';
          };
          apply();
          if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', apply, {once: true});
        })();
        """
    }
    func backendURL(_ url: URL) -> URL {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        parts.fragment = backendIsDark ? "night" : nil
        return parts.url!
    }
}
