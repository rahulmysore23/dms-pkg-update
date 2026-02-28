import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root

    pluginId: "pkgUpdate"

    StyledText {
        width: parent.width
        text: "Package Updates"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Configure how system package, Flatpak, and Snap updates are checked and applied."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "terminalApp"
        label: "Terminal Application"
        description: "Command used to open the terminal for running updates. Most terminals accept '-e' to run a command (e.g. 'alacritty', 'kitty', 'foot', 'ghostty')."
        defaultValue: "alacritty"
        placeholder: "alacritty"
    }

    SliderSetting {
        settingKey: "refreshMins"
        label: "Refresh Interval"
        description: "How often to check for available updates, in minutes."
        defaultValue: 60
        minimum: 5
        maximum: 240
        unit: "min"
        leftIcon: "schedule"
    }

    StringSetting {
        settingKey: "backendMode"
        label: "Package Backend"
        description: "Backend for system updates: 'auto' (prefer apt, fallback to dnf), 'apt', or 'dnf'."
        defaultValue: "auto"
        placeholder: "auto"
    }

    ToggleSetting {
        settingKey: "showFlatpak"
        label: "Show Flatpak Updates"
        description: "Check and display Flatpak application updates alongside system packages."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showSnap"
        label: "Show Snap Updates"
        description: "Check and display Snap application updates alongside system packages."
        defaultValue: true
    }
}