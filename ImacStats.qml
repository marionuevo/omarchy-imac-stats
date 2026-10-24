import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Always-visible sensor readout: fan RPM, CPU/GPU temp and usage, memory
// temp (SMC TM1a) and RAM usage, disk usage — icon+value pairs polled from
// stats.py every 2s. The last two minutes of CPU, GPU and memory temps are
// kept here, not in the panel, so its chart is already full when it opens.
//
// Clicking opens the fan mode picker (Panel.qml). The fan itself is driven
// by the imac-fand system daemon, not by this widget, so the readout keeps
// being a readout and the fan keeps being regulated if the shell dies.
BarWidget {
    id: root
    moduleName: "marionuevo.imac-stats"

    property var stats: ({})
    property var history: []

    readonly property int historySeconds: 120

    // Padded to `width` characters: the bar font is monospaced, so every
    // reading keeps its width and the widgets to the right don't shift as
    // numbers change.
    // `after` pads behind the unit, so a usage stays next to its "/".
    function fmt(value, unit, width, after) {
        var v = (value === undefined || value === null) ? "--" : String(value)
        var pad = ""
        while (v.length + pad.length < (width || 0)) pad += " "
        return after ? v + unit + pad : pad + v + unit
    }

    // The reading imac-fand follows ("cpu", "gpu" or an SMC key such as
    // TM1a); empty without the daemon, when nothing here drives the fan. An
    // SMC CPU or GPU probe (TC1c, TG0D...) counts as the CPU or GPU reading.
    readonly property string driverKey: stats.daemon !== true || !stats.sensor ? "" :
        (stats.source === "cpu" || stats.source === "gpu") ? String(stats.source) : String(stats.sensor)

    // The label as [text, drives the fan, separator] pieces. Another SMC probe
    // in charge (TM2d, a board sensor...) is shown next to the rpm, already
    // marked. Separators are three spaces with a hairline drawn across the
    // middle one, so the plain text WidgetButton sizes itself by still has
    // the label's exact width.
    readonly property var pieces: {
        var other = driverKey !== "" && ["cpu", "gpu", "TM1a"].indexOf(driverKey) < 0
        var hottest = stats.hottest != null ? Math.round(stats.hottest) : null
        // rpm 1200-2900; temperatures stay under 100°C (full fan from 90);
        // usage reaches 100%; the disk is far from full.
        var sep = ["   ", false, true]
        return [
            ["󰈐 " + fmt(stats.fan, "", 4) + (stats.daemon === false ? "!" : ""), false],
            [other ? " " + driverKey + " " + fmt(hottest, "°C", 2) : "", other],
            sep,
            [" " + fmt(stats.cpuTemp, "°C", 2), driverKey === "cpu"],
            ["/" + fmt(stats.cpu, "%", 3, true), false],
            sep,
            ["󰢮 " + fmt(stats.gpuTemp, "°C", 2), driverKey === "gpu"],
            ["/" + fmt(stats.gpu, "%", 3, true), false],
            sep,
            [" " + fmt(stats.memTemp, "°C", 2) + (stats.ramCap != null ? "!" : ""), driverKey === "TM1a"],
            ["/" + fmt(stats.ram, "%", 3, true), false],
            sep,
            ["󰋊 " + fmt(stats.disk, "%", 2), false]
        ]
    }

    readonly property string displayText: {
        var out = ""
        for (var i = 0; i < pieces.length; i++) out += pieces[i][0]
        return out
    }

    function parseStats(raw) {
        try {
            var parsed = JSON.parse(String(raw || "").trim())
            if (parsed) {
                root.stats = parsed
                root.record(parsed)
                if (panelLoader.item) {
                    panelLoader.item.stats = parsed
                    panelLoader.item.history = root.history
                }
            }
        } catch (e) {
            // keep last good values on parse failure
        }
    }

    // A new array each time, so bindings on `history` see the change.
    function record(s) {
        var now = Date.now()
        var cutoff = now - historySeconds * 1000
        var kept = []
        for (var i = 0; i < history.length; i++)
            if (history[i].t >= cutoff) kept.push(history[i])
        kept.push({ t: now, cpu: s.cpuTemp, gpu: s.gpuTemp, mem: s.memTemp })
        history = kept
    }

    // ---- Fan mode popup. Shape contract for shell.summon/hide/toggle
    //      routing: Bar.findPanelWidget requires open/close/opened on the
    //      bar-widget root.
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

    function open() { if (panelLoader.item) panelLoader.item.open() }
    function close() { if (panelLoader.item) panelLoader.item.close() }
    function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

    readonly property real openPanelIndicatorWidth: styledLabel.implicitWidth
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
        if ("history" in target) target.history = root.history
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
        labelVisible: false
        horizontalMargin: 8.5

        // WidgetButton's own label is one plain text; this one colors the
        // reading that drives the fan. One plain Text per piece rather than
        // StyledText, which collapses runs of spaces and so would undo the
        // padding. Same glyphs and font, so the same width.
        Row {
            id: styledLabel
            anchors.centerIn: parent

            Repeater {
                model: root.pieces

                Text {
                    required property var modelData
                    text: modelData[0]
                    color: modelData[1] ? Color.accent : button.foreground
                    font.family: button.fontFamily
                    font.pixelSize: button.fontSize
                    renderType: Text.NativeRendering
                    verticalAlignment: Text.AlignVCenter

                    // The hairline between readings; marionuevo.separator
                    // draws a stronger one between widgets.
                    Rectangle {
                        visible: modelData[2] === true
                        anchors.centerIn: parent
                        width: 1
                        height: Math.round((root.bar ? root.bar.barSize : Style.bar.sizeHorizontal) * 0.45)
                        color: button.foreground
                        opacity: 0.3
                    }
                }
            }
        }

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
