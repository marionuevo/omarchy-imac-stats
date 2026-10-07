import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Always-visible sensor readout: fan RPM, CPU/GPU temp and usage, RAM and
// disk usage — icon+value pairs polled from stats.py every 2s.
//
// Clicking opens the fan mode picker (Panel.qml). The fan itself is driven
// by the imac-fand system daemon, not by this widget, so the readout keeps
// being a readout and the fan keeps being regulated if the shell dies.
BarWidget {
    id: root
    moduleName: "marionuevo.imac-stats"

    property var stats: ({})

    function fmt(value, unit) {
        return (value === undefined || value === null) ? ("--" + unit) : (value + unit)
    }

    readonly property string displayText:
        "󰈐 " + fmt(stats.fan, "") + (stats.daemon === false ? "!" : "") + "  " +
        " " + fmt(stats.cpuTemp, "°C") + "/" + fmt(stats.cpu, "%") + "  " +
        "󰢮 " + fmt(stats.gpuTemp, "°C") + "/" + fmt(stats.gpu, "%") + "  " +
        "󰍛 " + fmt(stats.ram, "%") + "  " +
        "󰋊 " + fmt(stats.disk, "%")

    function parseStats(raw) {
        try {
            var parsed = JSON.parse(String(raw || "").trim())
            if (parsed) {
                root.stats = parsed
                if (panelLoader.item) panelLoader.item.stats = parsed
            }
        } catch (e) {
            // keep last good values on parse failure
        }
    }

    // ---- Fan mode popup. Shape contract for shell.summon/hide/toggle
    //      routing: Bar.findPanelWidget requires open/close/opened on the
    //      bar-widget root.
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

    function open() { if (panelLoader.item) panelLoader.item.open() }
    function close() { if (panelLoader.item) panelLoader.item.close() }
    function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

    readonly property real openPanelIndicatorWidth: button.labelWidth
    readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

    // Forwarded so this widget can stand in for the panel as the bar's popout
    // identity: Bar.requestPopout prefers closeForPopoutSwitch over close.
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

    function closeForPopoutSwitch() {
        if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
    }

    function injectPanel() {
        var target = panelLoader.item
        if (!target) return
        if ("bar" in target) target.bar = root.bar
        if ("settings" in target) target.settings = root.settings
        if ("anchorItem" in target) target.anchorItem = button
        if ("hostWidget" in target) target.hostWidget = root
        if ("stats" in target) target.stats = root.stats
    }

    implicitWidth: spacer.width + button.implicitWidth
    implicitHeight: button.implicitHeight

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    Item {
        id: spacer
        width: Style.space(12)
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
    }

    WidgetButton {
        id: button
        anchors.left: spacer.right
        anchors.verticalCenter: parent.verticalCenter
        bar: root.bar
        text: root.displayText
        horizontalMargin: 8.5

        onPressed: function(b) {
            root.togglePanel()
        }
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
        }
    }

    IpcHandler {
        target: "marionuevo.imac-stats"

        function open(): void { root.open() }
        function close(): void { root.close() }
        function show(): void { root.open() }
        function hide(): void { root.close() }
        function toggle(): void { root.togglePanel() }
    }

    Process {
        id: statsProc
        command: ["python3", String(Qt.resolvedUrl("stats.py")).replace(/^file:\/\//, "")]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parseStats(text)
        }
    }

    Timer {
        id: statsTimer
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: statsProc.running = true
    }
}
