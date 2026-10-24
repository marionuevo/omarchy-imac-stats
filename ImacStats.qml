import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Always-visible sensor readout polled from stats.py every 2s: fan RPM, CPU
// and GPU temp and usage, memory temp (SMC TM1a) and RAM usage, disk usage.
// Each reading is an icon and two stacked rows, like marionuevo.netgraph: the
// number on top and, below, a meter (outline = the whole range, fill = the
// current value) for the usage or, for the fan, the rpm within its range.
// The disk has only its meter. The last two minutes of CPU, GPU and memory
// temps are kept here, not in the panel, so its chart is already full when
// it opens.
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

    readonly property color fg: button.foreground
    readonly property string fontFamily: button.fontFamily

    function fmt(value, unit) {
        return ((value === undefined || value === null) ? "--" : String(value)) + unit
    }

    // 0-1 for a meter; null (no reading) leaves it empty.
    function fraction(value, lo, hi) {
        if (value === undefined || value === null || !(hi > lo)) return null
        return Math.max(0, Math.min(1, (value - lo) / (hi - lo)))
    }

    // The fan's range comes from imac-fand (fan1_min/fan1_max); without the
    // daemon, the range applesmc reported on the original board.
    readonly property real fanLo: stats.fanMin != null ? stats.fanMin : 1200
    readonly property real fanHi: stats.fanMax != null ? stats.fanMax : 2700

    // The reading imac-fand follows ("cpu", "gpu" or an SMC key such as
    // TM1a); empty without the daemon, when nothing here drives the fan. An
    // SMC CPU or GPU probe (TC1c, TG0D...) counts as the CPU or GPU reading.
    readonly property string driverKey: stats.daemon !== true || !stats.sensor ? "" :
        (stats.source === "cpu" || stats.source === "gpu") ? String(stats.source) : String(stats.sensor)

    // Another SMC probe in charge (TM2d, a board sensor...) is shown next to
    // the rpm, already marked; the CPU, GPU and memory readings are marked
    // in place.
    readonly property bool otherDriver: driverKey !== "" && ["cpu", "gpu", "TM1a"].indexOf(driverKey) < 0

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

    readonly property real openPanelIndicatorWidth: readings.implicitWidth
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

    implicitWidth: button.anchors.leftMargin + button.implicitWidth
    implicitHeight: button.implicitHeight

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    // Widest top row, a temperature or a fan rpm; every number and meter
    // takes this width, so the widget keeps its width as readings change and
    // the widgets to the right don't shift.
    TextMetrics {
        id: widest
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        text: "99°C"
    }

    // One reading: its icon and a two-row column, the number on top (empty
    // for a meter alone) and the meter below. `flag` hangs a "!" after the
    // number, out of the column, into the gap before the next hairline.
    component Reading: Row {
        id: reading
        property string icon
        property string value: ""
        property bool drives: false
        property bool flag: false
        property var fill: null
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        spacing: Style.space(4)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: reading.icon
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: button.fontSize
            renderType: Text.NativeRendering
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            Text {
                id: number
                visible: reading.value !== ""
                width: widest.width
                horizontalAlignment: Text.AlignRight
                text: reading.value
                color: reading.drives ? Color.accent : root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                renderType: Text.NativeRendering

                Text {
                    visible: reading.flag
                    anchors.left: parent.right
                    text: "!"
                    color: Color.accent
                    font: number.font
                    renderType: Text.NativeRendering
                }
            }

            Meter {
                fill: reading.fill
            }
        }
    }

    // A text row tall, so the meter sits where a second line of text would.
    // The outline is the whole range; the fill, inset from it, the value.
    component Meter: Item {
        id: meter
        property var fill: null
        width: widest.width
        height: widest.height

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 7
            radius: 2
            color: "transparent"
            border.width: 1
            border.color: root.fg
            opacity: 0.55
        }

        Rectangle {
            x: track.x + 2
            anchors.verticalCenter: track.verticalCenter
            width: meter.fill === null ? 0 : (track.width - 4) * meter.fill
            height: track.height - 4
            radius: 1
            color: root.fg
        }
    }

    // The hairline between readings; marionuevo.separator draws a stronger
    // one between widgets.
    component Gap: Item {
        width: Style.space(15)
        height: 1
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined

        Rectangle {
            anchors.centerIn: parent
            width: 1
            height: Math.round((root.bar ? root.bar.barSize : Style.bar.sizeHorizontal) * 0.45)
            color: root.fg
            opacity: 0.3
        }
    }

    WidgetButton {
        id: button
        anchors.left: parent.left
        // No gap of its own before the readings: marionuevo.separator sets
        // the space between widgets. The margins are tuned so the separator
        // lines on either side sit centered.
        anchors.leftMargin: 2.5
        anchors.verticalCenter: parent.verticalCenter
        bar: root.bar
        // WidgetButton sizes itself by its plain-text label; here the label
        // is hidden and the width comes from the readings instead.
        text: " "
        labelVisible: false
        horizontalMargin: 6
        fixedWidth: readings.implicitWidth + button.scaledHorizontalMargin * 2

        Row {
            id: readings
            anchors.centerIn: parent

            Reading {
                icon: "󰈐"
                value: root.fmt(root.stats.fan, "")
                flag: root.stats.daemon === false
                fill: root.fraction(root.stats.fan, root.fanLo, root.fanHi)
            }

            // Two rows as well: which probe and how hot.
            Column {
                visible: root.otherDriver
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: Style.space(6)

                Repeater {
                    model: [root.driverKey,
                            root.fmt(root.stats.hottest != null ? Math.round(root.stats.hottest) : null, "°C")]

                    Text {
                        required property var modelData
                        text: modelData
                        color: Color.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        renderType: Text.NativeRendering
                    }
                }
            }

            Gap {}

            Reading {
                icon: ""
                value: root.fmt(root.stats.cpuTemp, "°C")
                drives: root.driverKey === "cpu"
                fill: root.fraction(root.stats.cpu, 0, 100)
            }

            Gap {}

            Reading {
                icon: "󰢮"
                value: root.fmt(root.stats.gpuTemp, "°C")
                drives: root.driverKey === "gpu"
                fill: root.fraction(root.stats.gpu, 0, 100)
            }

            Gap {}

            Reading {
                icon: ""
                value: root.fmt(root.stats.memTemp, "°C")
                drives: root.driverKey === "TM1a"
                flag: root.stats.ramCap != null
                fill: root.fraction(root.stats.ram, 0, 100)
            }

            Gap {}

            Reading {
                icon: "󰋊"
                fill: root.fraction(root.stats.disk, 0, 100)
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
