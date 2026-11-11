import ServiceManagement

/// Login item for the app bundle itself. Only works from the installed, signed bundle.
enum LaunchAtLogin {
    /// Read live: the user can also change it in System Settings › Login Items.
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
