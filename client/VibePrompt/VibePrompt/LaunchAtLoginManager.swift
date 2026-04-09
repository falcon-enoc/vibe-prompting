import ServiceManagement

/// Gestiona el inicio automático de la app con macOS usando SMAppService
enum LaunchAtLoginManager {
    static func update(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Log pero no crashear — puede fallar en sandbox o sin permisos
            #if DEBUG
            print("[LaunchAtLoginManager] Error: \(error.localizedDescription)")
            #endif
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
