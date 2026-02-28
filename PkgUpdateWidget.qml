import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // ── State ────────────────────────────────────────────────────────────────
    property var packageUpdates: []
    property var flatpakUpdates: []
    property var snapUpdates: []
    property bool packageChecking: true
    property bool flatpakChecking: true
    property bool snapChecking: true
    property string packageError: ""
    property string flatpakError: ""
    property string snapError: ""
    property string effectiveBackend: "none"

    // ── Settings (from plugin data) ───────────────────────────────────────────
    property string terminalApp: normalizeTerminalApp(pluginData.terminalApp)
    property int refreshMins: normalizeRefreshMins(pluginData.refreshMins)
    property string backendMode: normalizeBackendMode(pluginData.backendMode)
    property bool showFlatpak: pluginData.showFlatpak !== undefined ? pluginData.showFlatpak : true
    property bool showSnap: pluginData.showSnap !== undefined ? pluginData.showSnap : true

    property int totalUpdates: packageUpdates.length + (showFlatpak ? flatpakUpdates.length : 0) + (showSnap ? snapUpdates.length : 0)

    popoutWidth: 480

    // ── Periodic refresh ──────────────────────────────────────────────────────
    Timer {
        interval: root.refreshMins * 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.checkUpdates()
    }

    // ── Update check functions ────────────────────────────────────────────────
    function normalizeTerminalApp(command) {
        if (!command)
            return "alacritty"
        const trimmed = String(command).trim()
        return trimmed.length > 0 ? trimmed : "alacritty"
    }

    function splitCommandLine(command) {
        const input = String(command || "").trim()
        if (input.length === 0)
            return []

        const parts = []
        let current = ""
        let quote = ""

        for (let i = 0; i < input.length; i++) {
            const ch = input[i]

            if (quote.length > 0) {
                if (ch === quote) {
                    quote = ""
                } else if (ch === "\\" && i + 1 < input.length) {
                    i += 1
                    current += input[i]
                } else {
                    current += ch
                }
                continue
            }

            if (ch === '"' || ch === "'") {
                quote = ch
                continue
            }

            if (/\s/.test(ch)) {
                if (current.length > 0) {
                    parts.push(current)
                    current = ""
                }
                continue
            }

            if (ch === "\\" && i + 1 < input.length) {
                i += 1
                current += input[i]
                continue
            }

            current += ch
        }

        if (quote.length > 0)
            return []
        if (current.length > 0)
            parts.push(current)
        return parts
    }

    function hasUnsafeToken(token) {
        return /[;&|`$<>\n\r]/.test(token || "")
    }

    function buildTerminalCommand(updateCmd) {
        const parsed = splitCommandLine(root.terminalApp)
        const fallback = ["alacritty"]
        const terminalParts = parsed.length > 0 ? parsed : fallback

        for (let i = 0; i < terminalParts.length; i++) {
            if (hasUnsafeToken(terminalParts[i]))
                return fallback.concat(["-e", "sh", "-lc", updateCmd])
        }

        return terminalParts.concat(["-e", "sh", "-lc", updateCmd])
    }

    function normalizeRefreshMins(value) {
        const parsed = Number(value)
        if (!Number.isFinite(parsed))
            return 60
        return Math.max(5, Math.min(240, Math.floor(parsed)))
    }

    function normalizeBackendMode(mode) {
        const value = String(mode || "").trim().toLowerCase()
        if (value === "apt" || value === "dnf" || value === "auto")
            return value
        return "auto"
    }

    function parseBackendMarker(stdout) {
        const markerPrefix = "__PKG_BACKEND__:"
        const errorPrefix = "__PKG_ERROR__:"
        const lines = (stdout || "").split('\n')
        let backend = "none"
        let errorCode = ""
        const cleaned = []

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim()
            if (line.startsWith(markerPrefix)) {
                backend = line.slice(markerPrefix.length).trim()
                continue
            }
            if (line.startsWith(errorPrefix)) {
                errorCode = line.slice(errorPrefix.length).trim()
                continue
            }
            cleaned.push(lines[i])
        }

        return {
            backend,
            errorCode,
            output: cleaned.join('\n')
        }
    }

    function parseFlatpakMarker(stdout) {
        const errorPrefix = "__FLATPAK_ERROR__:"
        const lines = (stdout || "").split('\n')
        let errorCode = ""
        const cleaned = []

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim()
            if (line.startsWith(errorPrefix)) {
                errorCode = line.slice(errorPrefix.length).trim()
                continue
            }
            cleaned.push(lines[i])
        }

        return {
            errorCode,
            output: cleaned.join('\n')
        }
    }

    function parseSnapMarker(stdout) {
        const errorPrefix = "__SNAP_ERROR__:"
        const lines = (stdout || "").split('\n')
        let errorCode = ""
        const cleaned = []

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim()
            if (line.startsWith(errorPrefix)) {
                errorCode = line.slice(errorPrefix.length).trim()
                continue
            }
            cleaned.push(lines[i])
        }

        return {
            errorCode,
            output: cleaned.join('\n')
        }
    }

    function humanizePackageError(code, backend) {
        if (code === "apt_missing")
            return "APT is not installed on this system"
        if (code === "aptdcon_missing")
            return "aptdcon is not installed (required for APT metadata refresh without sudo)"
        if (code === "apt_update_failed")
            return "APT metadata refresh failed (check network, lock, or permissions)"
        if (code === "dnf_missing")
            return "DNF is not installed on this system"
        if (code === "dnf_check_failed")
            return "DNF update check failed"
        if (code === "no_backend")
            return "No supported package manager found (apt/dnf)"
        return backend === "dnf" ? "Failed to check DNF updates" : "Failed to check APT updates"
    }

    function humanizeFlatpakError(code) {
        if (code === "flatpak_missing")
            return "Flatpak is not installed on this system"
        if (code === "flatpak_check_failed")
            return "Flatpak update check failed"
        return "Failed to check Flatpak updates"
    }

    function humanizeSnapError(code) {
        if (code === "snap_missing")
            return "Snap is not installed on this system"
        if (code === "snap_check_failed")
            return "Snap update check failed"
        return "Failed to check Snap updates"
    }

    function parseAptPackages(stdout) {
        if (!stdout || stdout.trim().length === 0)
            return []
        return stdout.trim().split('\n').filter(line => {
            const t = line.trim()
            return t.length > 0 && !t.startsWith("Listing...") && t.indexOf("/") > -1
        }).map(line => {
            const parts = line.trim().split(/\s+/)
            const packagePart = parts[0] || ""
            const slashIndex = packagePart.indexOf("/")
            return {
                name: slashIndex > -1 ? packagePart.slice(0, slashIndex) : packagePart,
                version: parts[1] || "",
                repo: parts[2] || ""
            }
        }).filter(p => p.name.length > 0)
    }

    function parseDnfPackages(stdout) {
        if (!stdout || stdout.trim().length === 0)
            return []
        return stdout.trim().split('\n').filter(line => {
            const t = line.trim()
            return t.length > 0 && !t.startsWith('Last') && !t.startsWith('Upgradable') && !t.startsWith('Available') && !t.startsWith('Extra') && !t.startsWith('Obsoleting')
        }).map(line => {
            const parts = line.trim().split(/\s+/)
            return {
                name: parts[0] || '',
                version: parts[1] || '',
                repo: parts[2] || ''
            }
        }).filter(p => p.name.length > 0 && p.name.indexOf('.') > -1)
    }

    function parsePackageResult(stdout, mode) {
        let backend = mode
        let errorCode = ""
        let output = stdout || ""

        const marker = parseBackendMarker(output)
        output = marker.output
        errorCode = marker.errorCode

        if (mode === "auto") {
            backend = marker.backend
        } else if (marker.backend.length > 0 && marker.backend !== "none") {
            backend = marker.backend
        }

        if (backend === "apt")
            return {
                backend,
                errorCode,
                updates: parseAptPackages(output)
            }
        if (backend === "dnf")
            return {
                backend,
                errorCode,
                updates: parseDnfPackages(output)
            }

        return {
            backend: "none",
            errorCode: errorCode.length > 0 ? errorCode : "no_backend",
            updates: []
        }
    }

    function parseFlatpakResult(stdout) {
        const marker = parseFlatpakMarker(stdout)
        return {
            errorCode: marker.errorCode,
            updates: parseFlatpakApps(marker.output)
        }
    }

    function parseSnapResult(stdout) {
        const marker = parseSnapMarker(stdout)
        return {
            errorCode: marker.errorCode,
            updates: parseSnapApps(marker.output)
        }
    }

    function checkUpdates() {
        root.packageChecking = true
        root.packageError = ""
        const mode = normalizeBackendMode(root.backendMode)
        let checkCmd = ""

        if (mode === "apt") {
            root.effectiveBackend = "apt"
            checkCmd = "if ! command -v apt >/dev/null 2>&1; then echo __PKG_ERROR__:apt_missing; exit 127; fi; if ! command -v aptdcon >/dev/null 2>&1; then echo __PKG_ERROR__:aptdcon_missing; exit 127; fi; if ! aptdcon --refresh >/dev/null 2>&1; then echo __PKG_ERROR__:apt_update_failed; exit 20; fi; LC_ALL=C apt list --upgradable 2>/dev/null"
        } else if (mode === "dnf") {
            root.effectiveBackend = "dnf"
            checkCmd = "if ! command -v dnf >/dev/null 2>&1; then echo __PKG_ERROR__:dnf_missing; exit 127; fi; LC_ALL=C dnf list --upgrades --color=never 2>/dev/null || { echo __PKG_ERROR__:dnf_check_failed; exit 21; }"
        } else {
            checkCmd = "if command -v apt >/dev/null 2>&1; then echo __PKG_BACKEND__:apt; if ! command -v aptdcon >/dev/null 2>&1; then echo __PKG_ERROR__:aptdcon_missing; exit 127; fi; if ! aptdcon --refresh >/dev/null 2>&1; then echo __PKG_ERROR__:apt_update_failed; exit 20; fi; LC_ALL=C apt list --upgradable 2>/dev/null; elif command -v dnf >/dev/null 2>&1; then echo __PKG_BACKEND__:dnf; LC_ALL=C dnf list --upgrades --color=never 2>/dev/null || { echo __PKG_ERROR__:dnf_check_failed; exit 21; }; else echo __PKG_BACKEND__:none; echo __PKG_ERROR__:no_backend; exit 127; fi"
        }

        Proc.runCommand("pkgUpdate.system", ["sh", "-c", checkCmd], (stdout, exitCode) => {
            const result = parsePackageResult(stdout, mode)
            root.effectiveBackend = result.backend
            if (result.errorCode.length > 0) {
                root.packageUpdates = []
                root.packageError = humanizePackageError(result.errorCode, result.backend)
            } else if (exitCode !== 0) {
                root.packageUpdates = []
                root.packageError = humanizePackageError("", result.backend)
            } else {
                root.packageUpdates = result.updates
                root.packageError = ""
            }
            root.packageChecking = false
        }, 100)

        if (root.showFlatpak) {
            root.flatpakChecking = true
            root.flatpakError = ""
            Proc.runCommand("pkgUpdate.flatpak", ["sh", "-c", "if ! command -v flatpak >/dev/null 2>&1; then echo __FLATPAK_ERROR__:flatpak_missing; exit 127; fi; flatpak remote-ls --updates 2>/dev/null || { echo __FLATPAK_ERROR__:flatpak_check_failed; exit 22; }"], (stdout, exitCode) => {
                const result = parseFlatpakResult(stdout)
                if (result.errorCode.length > 0) {
                    root.flatpakUpdates = []
                    root.flatpakError = humanizeFlatpakError(result.errorCode)
                } else if (exitCode !== 0) {
                    root.flatpakUpdates = []
                    root.flatpakError = humanizeFlatpakError("")
                } else {
                    root.flatpakUpdates = result.updates
                    root.flatpakError = ""
                }
                root.flatpakChecking = false
            }, 100)
        } else {
            root.flatpakChecking = false
            root.flatpakError = ""
        }

        if (root.showSnap) {
            root.snapChecking = true
            root.snapError = ""
            Proc.runCommand("pkgUpdate.snap", ["sh", "-c", "if ! command -v snap >/dev/null 2>&1; then echo __SNAP_ERROR__:snap_missing; exit 127; fi; LC_ALL=C snap refresh --list 2>/dev/null || { echo __SNAP_ERROR__:snap_check_failed; exit 23; }"], (stdout, exitCode) => {
                const result = parseSnapResult(stdout)
                if (result.errorCode.length > 0) {
                    root.snapUpdates = []
                    root.snapError = humanizeSnapError(result.errorCode)
                } else if (exitCode !== 0) {
                    root.snapUpdates = []
                    root.snapError = humanizeSnapError("")
                } else {
                    root.snapUpdates = result.updates
                    root.snapError = ""
                }
                root.snapChecking = false
            }, 100)
        } else {
            root.snapChecking = false
            root.snapError = ""
        }
    }

    function parseFlatpakApps(stdout) {
        if (!stdout || stdout.trim().length === 0)
            return []
        return stdout.trim().split('\n').filter(line => {
            const t = line.trim()
            return t.length > 0 && !t.startsWith("Name") && !t.startsWith("Application")
        }).map(line => {
            const parts = line.trim().split(/\t|\s{2,}/)
            return {
                name: parts[0] || '',
                branch: parts[1] || '',
                origin: parts[2] || ''
            }
        }).filter(a => a.name.length > 0)
    }

    function parseSnapApps(stdout) {
        if (!stdout || stdout.trim().length === 0)
            return []
        return stdout.trim().split('\n').filter(line => {
            const t = line.trim()
            return t.length > 0 && !t.startsWith("Name") && !t.startsWith("All snaps")
        }).map(line => {
            const parts = line.trim().split(/\s+/)
            return {
                name: parts[0] || "",
                version: parts[1] || "",
                channel: parts[3] || ""
            }
        }).filter(app => app.name.length > 0)
    }

    // ── Terminal launch ───────────────────────────────────────────────────────
    function runPackageUpdate() {
        root.closePopout()
        const mode = normalizeBackendMode(root.backendMode)
        const backend = mode === "auto" ? root.effectiveBackend : mode
        const cmd = backend === "dnf"
            ? "sudo dnf upgrade -y; echo; echo '=== Done. Press Enter to close. ==='; read"
            : "aptdcon --refresh && sudo apt -o APT::Get::Always-Include-Phased-Updates=true upgrade -y; echo; echo '=== Done. Press Enter to close. ==='; read"
        Quickshell.execDetached(buildTerminalCommand(cmd))
    }

    function runFlatpakUpdate() {
        root.closePopout()
        const cmd = "flatpak update -y; echo; echo '=== Done. Press Enter to close. ==='; read"
        Quickshell.execDetached(buildTerminalCommand(cmd))
    }

    function runSnapUpdate() {
        root.closePopout()
        const cmd = "sudo snap refresh; echo; echo '=== Done. Press Enter to close. ==='; read"
        Quickshell.execDetached(buildTerminalCommand(cmd))
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
                text: (root.packageChecking || (root.showFlatpak && root.flatpakChecking) || (root.showSnap && root.snapChecking)) ? "…" : root.totalUpdates.toString()
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
                text: (root.packageChecking || (root.showFlatpak && root.flatpakChecking) || (root.showSnap && root.snapChecking)) ? "…" : root.totalUpdates.toString()
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

            // ── System packages section header ───────────────────────────────
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
                        text: "System Packages"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: packageCountLabel.width + 14
                        height: 20
                        radius: 10
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            id: packageCountLabel
                            text: root.packageChecking ? "…" : root.packageUpdates.length.toString()
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.primary
                            anchors.centerIn: parent
                        }
                    }
                }

                // Update packages button
                Item {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: packageBtnRow.width + Theme.spacingM * 2
                    height: 30
                    visible: !root.packageChecking && root.packageUpdates.length > 0

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadius
                        color: packageBtnArea.containsMouse ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }

                    Row {
                        id: packageBtnRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: "download"
                            size: 14
                            color: packageBtnArea.containsMouse ? "white" : Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Update Packages"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: packageBtnArea.containsMouse ? "white" : Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: packageBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runPackageUpdate()
                    }
                }
            }

            // ── System package update list ───────────────────────────────────
            StyledRect {
                width: parent.width
                height: root.packageChecking ? 52 : (root.packageUpdates.length === 0 ? 46 : Math.min(root.packageUpdates.length * 38 + 8, 180))
                radius: Theme.cornerRadius * 1.5
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: root.packageChecking

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
                    visible: !root.packageChecking && root.packageError.length > 0

                    DankIcon {
                        name: "error"
                        size: 16
                        color: Theme.error
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: root.packageError
                        color: Theme.error
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: !root.packageChecking && root.packageError.length === 0 && root.packageUpdates.length === 0

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
                    model: root.packageUpdates
                    spacing: 2
                    visible: !root.packageChecking && root.packageError.length === 0 && root.packageUpdates.length > 0

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
                width: parent.width
                height: root.flatpakChecking ? 52 : (root.flatpakUpdates.length === 0 ? 46 : Math.min(root.flatpakUpdates.length * 38 + 8, 180))
                radius: Theme.cornerRadius * 1.5
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                border.width: 1
                border.color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.1)
                clip: true
                visible: root.showFlatpak

                Behavior on height {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: root.flatpakChecking

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
                    visible: !root.flatpakChecking && root.flatpakError.length > 0

                    DankIcon {
                        name: "error"
                        size: 16
                        color: Theme.error
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: root.flatpakError
                        color: Theme.error
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: !root.flatpakChecking && root.flatpakError.length === 0 && root.flatpakUpdates.length === 0

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
                    visible: !root.flatpakChecking && root.flatpakError.length === 0 && root.flatpakUpdates.length > 0

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

            // ── Snap section header ───────────────────────────────────────────
            Item {
                width: parent.width
                height: 36
                visible: root.showSnap

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
                        name: "extension"
                        size: 20
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Snap"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: snapCountLabel.width + 14
                        height: 20
                        radius: 10
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            id: snapCountLabel
                            text: root.snapChecking ? "…" : root.snapUpdates.length.toString()
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.primary
                            anchors.centerIn: parent
                        }
                    }
                }

                // Update Snap button
                Item {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: snapBtnRow.width + Theme.spacingM * 2
                    height: 30
                    visible: !root.snapChecking && root.snapUpdates.length > 0

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadius
                        color: snapBtnArea.containsMouse ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }

                    Row {
                        id: snapBtnRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: "download"
                            size: 14
                            color: snapBtnArea.containsMouse ? "white" : Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Update Snap"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: snapBtnArea.containsMouse ? "white" : Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: snapBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runSnapUpdate()
                    }
                }
            }

            // ── Snap update list ─────────────────────────────────────────────
            StyledRect {
                width: parent.width
                height: root.snapChecking ? 52 : (root.snapUpdates.length === 0 ? 46 : Math.min(root.snapUpdates.length * 38 + 8, 180))
                radius: Theme.cornerRadius * 1.5
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                clip: true
                visible: root.showSnap

                Behavior on height {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: root.snapChecking

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
                    visible: !root.snapChecking && root.snapError.length > 0

                    DankIcon {
                        name: "error"
                        size: 16
                        color: Theme.error
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: root.snapError
                        color: Theme.error
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: !root.snapChecking && root.snapError.length === 0 && root.snapUpdates.length === 0

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
                    model: root.snapUpdates
                    spacing: 2
                    visible: !root.snapChecking && root.snapError.length === 0 && root.snapUpdates.length > 0

                    delegate: Item {
                        width: ListView.view.width
                        height: 36

                        property string snapName: modelData.name
                        property string snapVersion: modelData.version

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
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: snapName
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: parent.width - snapVersionText.implicitWidth - 14 - Theme.spacingS * 2
                            }

                            StyledText {
                                id: snapVersionText
                                text: snapVersion
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