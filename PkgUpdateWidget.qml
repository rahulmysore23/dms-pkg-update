import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // ── State ────────────────────────────────────────────────────────────────
    property var dnfUpdates: []
    property var flatpakUpdates: []
    property bool dnfChecking: true
    property bool flatpakChecking: true

    // ── Settings (from plugin data) ───────────────────────────────────────────
    property string terminalApp: pluginData.terminalApp || "alacritty"
    property int refreshMins: pluginData.refreshMins || 60
    property bool showFlatpak: pluginData.showFlatpak !== undefined ? pluginData.showFlatpak : true

    property int totalUpdates: dnfUpdates.length + (showFlatpak ? flatpakUpdates.length : 0)

    popoutWidth: 480

    // ── Periodic refresh ──────────────────────────────────────────────────────
    Timer {
        interval: root.refreshMins * 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.checkUpdates()
    }

    // ── Update check functions ───────────────────────────────────────────────
    function checkUpdates() {
        root.dnfChecking = true
        Proc.runCommand("pkgUpdate.dnf", ["sh", "-c", "dnf list --upgrades --color=never --assumeyes 2>/dev/null"], (stdout, exitCode) => {
            root.dnfUpdates = parseDnfPackages(stdout)
            root.dnfChecking = false
        }, 100)

        if (root.showFlatpak) {
            root.flatpakChecking = true
            Proc.runCommand("pkgUpdate.flatpakInstalled", ["sh", "-c", "flatpak list --app --columns=application,version 2>/dev/null"], (installedOut, installedCode) => {
                const installed = {}
                if (installedOut && installedOut.trim()) {
                    installedOut.trim().split('\n').forEach(line => {
                        const parts = line.trim().split('\t')
                        if (parts.length >= 2 && parts[1] && parts[1] !== '-') {
                            installed[parts[0]] = parts[1]
                        }
                    })
                }
                Proc.runCommand("pkgUpdate.flatpakUpdates", ["sh", "-c", "flatpak remote-ls --updates --app --columns=application,version,origin 2>/dev/null"], (updatesOut, updatesCode) => {
                    const rawUpdates = parseFlatpakApps(updatesOut)
                    root.flatpakUpdates = rawUpdates.filter(app => {
                        if (!app.name || app.name.length === 0)
                            return false
                        // Must be an installed application (excludes runtimes/extensions)
                        return installed.hasOwnProperty(app.name)
                    })
                    root.flatpakChecking = false
                }, 100)
            }, 100)
        } else {
            root.flatpakChecking = false
        }
    }

    function parseDnfPackages(stdout) {
        if (!stdout || stdout.trim().length === 0)
            return []
        return stdout.trim().split('\n').filter(line => {
            const t = line.trim()
            return t.length > 0 && !t.startsWith('Last') && !t.startsWith('Upgradable') && !t.startsWith('Available') && !t.startsWith('Extra')
        }).map(line => {
            const parts = line.trim().split(/\s+/)
            return {
                name: parts[0] || '',
                version: parts[1] || '',
                repo: parts[2] || ''
            }
        }).filter(p => p.name.length > 0 && p.name.indexOf('.') > -1)
    }

    function parseFlatpakApps(stdout) {
        if (!stdout || stdout.trim().length === 0)
            return []
        return stdout.trim().split('\n').filter(line => line.trim().length > 0).map(line => {
            const parts = line.trim().split('\t')
            return {
                name: parts[0] || '',
                version: parts[1] || '',
                origin: parts[2] || ''
            }
        }).filter(a => a.name.length > 0)
    }

    // ── Terminal launch ───────────────────────────────────────────────────────
    function runDnfUpdate() {
        root.closePopout()
        const cmd = "sudo dnf upgrade -y; echo; echo '=== Done. Press Enter to close. ==='; read"
        Quickshell.execDetached(["sh", "-c", root.terminalApp + " -e sh -c '" + cmd + "'"])
    }

    function runFlatpakUpdate() {
        root.closePopout()
        const cmd = "flatpak update -y; echo; echo '=== Done. Press Enter to close. ==='; read"
        Quickshell.execDetached(["sh", "-c", root.terminalApp + " -e sh -c '" + cmd + "'"])
    }

    // ── Bar pills ─────────────────────────────────────────────────────────────
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.totalUpdates > 0 ? "system_update" : "check_circle"
                color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                size: root.iconSize
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: (root.dnfChecking || (root.showFlatpak && root.flatpakChecking)) ? "…" : root.totalUpdates.toString()
                color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                font.pixelSize: Theme.fontSizeMedium
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 2
            anchors.horizontalCenter: parent.horizontalCenter

            DankIcon {
                name: root.totalUpdates > 0 ? "system_update" : "check_circle"
                color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                size: root.iconSize
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (root.dnfChecking || (root.showFlatpak && root.flatpakChecking)) ? "…" : root.totalUpdates.toString()
                color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    // ── Popout ────────────────────────────────────────────────────────────────
    popoutContent: Component {
        Column {
            width: parent.width
            spacing: Theme.spacingM
            topPadding: Theme.spacingM
            bottomPadding: Theme.spacingM

            // Header card
            Item {
                width: parent.width
                height: 68

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.cornerRadius * 1.5
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        }
                        GradientStop {
                            position: 1.0
                            color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.08)
                        }
                    }
                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingM

                    Item {
                        width: 40
                        height: 40
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.fill: parent
                            radius: 20
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                        }

                        DankIcon {
                            name: "system_update"
                            size: 22
                            color: Theme.primary
                            anchors.centerIn: parent
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        StyledText {
                            text: "Package Updates"
                            font.bold: true
                            font.pixelSize: Theme.fontSizeLarge
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: root.totalUpdates > 0 ? root.totalUpdates + " update" + (root.totalUpdates !== 1 ? "s" : "") + " available" : "System is up to date"
                            font.pixelSize: Theme.fontSizeSmall
                            color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                        }
                    }
                }

                // Refresh button
                Item {
                    width: 32
                    height: 32
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: refreshArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2) : "transparent"
                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }

                    DankIcon {
                        name: "refresh"
                        size: 20
                        color: Theme.primary
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        id: refreshArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.checkUpdates()
                    }
                }
            }

            // ── DNF section header ───────────────────────────────────────────
            Item {
                width: parent.width
                height: 36

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    Rectangle {
                        width: 4
                        height: 22
                        radius: 2
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DankIcon {
                        name: "archive"
                        size: 20
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "DNF"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: dnfCountLabel.width + 14
                        height: 20
                        radius: 10
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            id: dnfCountLabel
                            text: root.dnfChecking ? "…" : root.dnfUpdates.length.toString()
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.primary
                            anchors.centerIn: parent
                        }
                    }
                }

                // Update DNF button
                Item {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: dnfBtnRow.width + Theme.spacingM * 2
                    height: 30
                    visible: !root.dnfChecking && root.dnfUpdates.length > 0

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadius
                        color: dnfBtnArea.containsMouse ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }

                    Row {
                        id: dnfBtnRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: "download"
                            size: 14
                            color: dnfBtnArea.containsMouse ? "white" : Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Update DNF"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: dnfBtnArea.containsMouse ? "white" : Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: dnfBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runDnfUpdate()
                    }
                }
            }

            // ── DNF update list ──────────────────────────────────────────────
            StyledRect {
                id: dnfContainer
                width: parent.width
                height: (root.dnfChecking && root.dnfUpdates.length === 0) ? 52 : (root.dnfUpdates.length === 0 ? 46 : Math.min(root.dnfUpdates.length * 38 + 8, 180))
                radius: Theme.cornerRadius * 1.5
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: root.dnfChecking && root.dnfUpdates.length === 0

                    DankIcon {
                        name: "sync"
                        size: 16
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Checking for updates…"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: !root.dnfChecking && root.dnfUpdates.length === 0

                    DankIcon {
                        name: "check_circle"
                        size: 16
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "No updates available"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ListView {
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    model: root.dnfUpdates
                    spacing: 2
                    visible: root.dnfUpdates.length > 0

                    delegate: Item {
                        width: ListView.view.width
                        height: 36

                        property string pkgName: modelData.name
                        property string pkgVersion: modelData.version

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "upgrade"
                                size: 14
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: pkgName
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: parent.width - pkgVersionText.implicitWidth - 14 - Theme.spacingS * 2
                            }

                            StyledText {
                                id: pkgVersionText
                                text: pkgVersion
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }

            // ── Flatpak section header ────────────────────────────────────────
            Item {
                width: parent.width
                height: 36
                visible: root.showFlatpak

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    Rectangle {
                        width: 4
                        height: 22
                        radius: 2
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DankIcon {
                        name: "apps"
                        size: 20
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Flatpak"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: flatpakCountLabel.width + 14
                        height: 20
                        radius: 10
                        color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            id: flatpakCountLabel
                            text: root.flatpakChecking ? "…" : root.flatpakUpdates.length.toString()
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.secondary
                            anchors.centerIn: parent
                        }
                    }
                }

                // Update Flatpak button
                Item {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: flatpakBtnRow.width + Theme.spacingM * 2
                    height: 30
                    visible: !root.flatpakChecking && root.flatpakUpdates.length > 0

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadius
                        color: flatpakBtnArea.containsMouse ? Theme.secondary : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)
                        border.width: 1
                        border.color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.4)
                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }

                    Row {
                        id: flatpakBtnRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: "download"
                            size: 14
                            color: flatpakBtnArea.containsMouse ? "white" : Theme.secondary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Update Flatpak"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: flatpakBtnArea.containsMouse ? "white" : Theme.secondary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: flatpakBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runFlatpakUpdate()
                    }
                }
            }

            // ── Flatpak update list ──────────────────────────────────────────
            StyledRect {
                id: flatpakContainer
                width: parent.width
                height: (root.flatpakChecking && root.flatpakUpdates.length === 0) ? 52 : (root.flatpakUpdates.length === 0 ? 46 : Math.min(root.flatpakUpdates.length * 38 + 8, 180))
                radius: Theme.cornerRadius * 1.5
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                border.width: 1
                border.color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.1)
                clip: true
                visible: root.showFlatpak

                Behavior on height {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: root.flatpakChecking && root.flatpakUpdates.length === 0

                    DankIcon {
                        name: "sync"
                        size: 16
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Checking for updates…"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: !root.flatpakChecking && root.flatpakUpdates.length === 0

                    DankIcon {
                        name: "check_circle"
                        size: 16
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "No updates available"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ListView {
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    model: root.flatpakUpdates
                    spacing: 2
                    visible: root.flatpakUpdates.length > 0

                    delegate: Item {
                        width: ListView.view.width
                        height: 36

                        property string appId: modelData.name
                        property string appOrigin: modelData.origin

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "extension"
                                size: 14
                                color: Theme.secondary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: appId
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: parent.width - appOriginText.implicitWidth - 14 - Theme.spacingS * 2
                            }

                            StyledText {
                                id: appOriginText
                                text: appOrigin
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }
}