import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Fan mode picker. Three curve presets for the iMac's single fan, plus a
// read-out of which sensor is driving it right now (its row is highlighted)
// and a chart of the last two minutes of CPU, GPU and memory (TM1a) temps.
//
// The modes only pick a curve; the imac-fand system daemon does the actual
// regulating against max(CPU, GPU), so a crashed shell can't strand the
// fan. See fanmode.py and daemon/imac-fand.
//
// ImacStats.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "marionuevo.imac-stats"
  ipcTarget: "marionuevo.imac-stats"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var stats: ({})
  // [{t, cpu, gpu, mem}], oldest first; kept by ImacStats.qml.
  property var history: []

  property string mode: "normal"
  property bool writable: false
  property bool running: false
  property bool busy: false

  readonly property var modes: [
    { value: "silent", label: "Silent", icon: "󰕿" },
    { value: "normal", label: "Normal", icon: "󰖀" },
    { value: "full",   label: "Full",   icon: "󰕾" }
  ]

  property int cursorIndex: -1
  property bool cursorActive: false

  function scriptPath(name) {
    return String(Qt.resolvedUrl(name)).replace(/^file:\/\//, "")
  }

  function refreshStatus() {
    statusProc.running = true
  }

  function setMode(value) {
    if (busy || !writable || value === "") return
    busy = true
    applyProc.command = ["python3", root.scriptPath("fanmode.py"), String(value)]
    applyProc.running = true
  }

  function selectByDelta(delta) {
    if (modes.length === 0) return
    var start = cursorIndex < 0 ? modeIndex(mode) : cursorIndex
    var next = start + delta
    if (next < 0) next = modes.length - 1
    if (next >= modes.length) next = 0
    cursorIndex = next
  }

  function modeIndex(value) {
    for (var i = 0; i < modes.length; i++)
      if (modes[i].value === value) return i
    return 0
  }

  function activateSelected() {
    if (cursorIndex >= 0 && cursorIndex < modes.length)
      setMode(modes[cursorIndex].value)
  }

  function fmt(value, unit) {
    return (value === undefined || value === null) ? ("--" + unit) : (value + unit)
  }

  // The sensor the daemon follows: CPU, GPU, or one of the SMC's memory or
  // board probes. Without the daemon, the hotter of CPU and GPU.
  readonly property bool gpuHotter: stats.source === "gpu" ||
    (stats.source == null && stats.gpuTemp != null && (stats.cpuTemp == null || stats.gpuTemp > stats.cpuTemp))
  readonly property bool smcDriven: stats.source === "memory" || stats.source === "board"
  readonly property var hottest: smcDriven ? stats.hottest : (gpuHotter ? stats.gpuTemp : stats.cpuTemp)
  readonly property string driverIcon: stats.source === "memory" ? "" :
    stats.source === "board" ? "󰘚" : (gpuHotter ? "󰢮" : "\uf2db")
  readonly property string driverName: stats.source === "memory" ? "Memory " + stats.sensor :
    stats.source === "board" ? "Board " + stats.sensor : (gpuHotter ? "GPU" : "CPU")

  // The key of the reading imac-fand follows ("cpu", "gpu" or an SMC key such
  // as TM1a); empty without the daemon, when nothing in here drives the fan.
  readonly property string driverKey: stats.daemon === true && stats.sensor ? String(stats.sensor) : ""
  readonly property bool driverListed: ["cpu", "gpu", "TM1a"].indexOf(driverKey) >= 0

  // ---- Chart: one shared °C scale, one line per sensor. Line colors come
  //      from the theme's own palette, so they follow theme switches.
  property var themeColors: ({})

  function parseColors(raw) {
    var out = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([A-Za-z0-9_]+)\s*=\s*["'](#[0-9A-Fa-f]{6})["']/)
      if (m) out[m[1]] = m[2]
    }
    return out
  }

  function themeColor(names, fallback) {
    for (var i = 0; i < names.length; i++)
      if (themeColors[names[i]]) return themeColors[names[i]]
    return fallback
  }

  readonly property var series: [
    { key: "cpu", driver: "cpu",  label: "CPU",  color: themeColor(["blue", "color4"], "#7aa2f7") },
    { key: "gpu", driver: "gpu",  label: "GPU",  color: themeColor(["yellow", "color3"], "#e0af68") },
    { key: "mem", driver: "TM1a", label: "TM1a", color: themeColor(["magenta", "color5"], "#ad8ee6") }
  ]

  readonly property int windowMs: 120000
  // Where the pointer is over the plot, 0 (two minutes ago) to 1 (now); -1 off it.
  property real hoverFrac: -1
  readonly property int hoverIndex: hoverFrac < 0 ? -1 : nearestSample(hoverFrac)
  readonly property var shownSample: history.length === 0 ? null
    : history[hoverIndex >= 0 ? hoverIndex : history.length - 1]
  readonly property var chartRange: tempRange(history)

  function windowEnd() {
    return history.length > 0 ? history[history.length - 1].t : Date.now()
  }

  function nearestSample(frac) {
    var t = windowEnd() - windowMs * (1 - frac)
    var best = -1
    for (var i = 0; i < history.length; i++)
      if (best < 0 || Math.abs(history[i].t - t) < Math.abs(history[best].t - t)) best = i
    return best
  }

  // A 10° grid around the data, at least 20° tall.
  function tempRange(samples) {
    var lo = Infinity, hi = -Infinity
    for (var i = 0; i < samples.length; i++)
      for (var j = 0; j < series.length; j++) {
        var v = samples[i][series[j].key]
        if (v === null || v === undefined) continue
        lo = Math.min(lo, v)
        hi = Math.max(hi, v)
      }
    if (lo === Infinity) { lo = 40; hi = 80 }
    lo = Math.floor((lo - 2) / 10) * 10
    hi = Math.max(Math.ceil((hi + 2) / 10) * 10, lo + 20)
    var ticks = []
    for (var t = lo; t <= hi; t += 10) ticks.push(t)
    return { min: lo, max: hi, ticks: ticks }
  }

  readonly property real plotPad: Style.space(4)

  function chartY(v, h) {
    var r = chartRange
    return h - plotPad - (v - r.min) / (r.max - r.min) * (h - 2 * plotPad)
  }

  function chartX(t, w) {
    return w - (windowEnd() - t) / windowMs * w
  }

  function paintChart(ctx, w, h) {
    ctx.reset()
    var fg = root.bar ? root.bar.foreground : Color.foreground
    ctx.lineWidth = 1
    ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.1)
    for (var g = 0; g < chartRange.ticks.length; g++) {
      var gy = Math.round(chartY(chartRange.ticks[g], h)) + 0.5
      ctx.beginPath()
      ctx.moveTo(0, gy)
      ctx.lineTo(w, gy)
      ctx.stroke()
    }

    ctx.lineWidth = 2
    ctx.lineJoin = "round"
    ctx.lineCap = "round"
    for (var s = 0; s < series.length; s++) {
      ctx.strokeStyle = series[s].color
      ctx.beginPath()
      var drawing = false
      for (var i = 0; i < history.length; i++) {
        var v = history[i][series[s].key]
        if (v === null || v === undefined) { drawing = false; continue }
        var x = chartX(history[i].t, w), y = chartY(v, h)
        if (drawing) ctx.lineTo(x, y)
        else ctx.moveTo(x, y)
        drawing = true
      }
      ctx.stroke()
    }

    if (hoverIndex < 0) return
    var sample = history[hoverIndex]
    var hx = Math.round(chartX(sample.t, w)) + 0.5
    ctx.lineWidth = 1
    ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.35)
    ctx.beginPath()
    ctx.moveTo(hx, 0)
    ctx.lineTo(hx, h)
    ctx.stroke()
    ctx.lineWidth = 2
    ctx.strokeStyle = Color.popups.background
    for (var d = 0; d < series.length; d++) {
      var dv = sample[series[d].key]
      if (dv === null || dv === undefined) continue
      ctx.fillStyle = series[d].color
      ctx.beginPath()
      ctx.arc(hx, chartY(dv, h), 4, 0, 2 * Math.PI)
      ctx.fill()
      ctx.stroke()
    }
  }

  onOpenedChanged: {
    if (opened) {
      cursorIndex = modeIndex(mode)
      cursorActive = false
      refreshStatus()
      themeColorsFile.reload()
    } else {
      hoverFrac = -1
    }
  }

  FileView {
    id: themeColorsFile
    path: Color.currentThemePath + "/colors.toml"
    printErrors: false
    onLoaded: root.themeColors = root.parseColors(text())
  }

  Process {
    id: statusProc
    command: ["python3", root.scriptPath("fanmode.py"), "--status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "").trim())
          if (parsed) {
            if (parsed.mode) root.mode = String(parsed.mode)
            root.writable = parsed.writable === true
            root.running = parsed.running === true
          }
        } catch (e) {
          // leave the last known state alone
        }
      }
    }
  }

  Process {
    id: applyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.busy = false
        root.refreshStatus()
      }
    }
    onExited: {
      root.busy = false
      root.refreshStatus()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.selectByDelta(dx !== 0 ? dx : dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateSelected()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: the hotter sensor, the one the fan follows ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            text: root.driverIcon
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: root.fmt(root.hottest, "°C")
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
            }

            Text {
              text: root.driverName + " · drives the fan"
              color: root.bar ? root.bar.foreground : Color.foreground
              opacity: 0.6
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        PanelSeparator {
          foreground: root.bar ? root.bar.foreground : Color.foreground
        }

        // ---------- Live RPM and the temps behind it ----------
        Column {
          width: parent.width

          InfoPair { label: "Fan";    value: root.fmt(root.stats.fan, " rpm") }
          InfoPair { label: "Target"; value: root.fmt(root.stats.fanTarget, " rpm") }
          InfoPair { label: "Range";  value: root.stats.fanMin != null ? (root.stats.fanMin + "–" + root.stats.fanMax + " rpm") : "--" }
          InfoPair { label: "CPU";    value: root.fmt(root.stats.cpuTemp, "°C"); driving: root.driverKey === "cpu" }
          InfoPair { label: "GPU";    value: root.fmt(root.stats.gpuTemp, "°C"); driving: root.driverKey === "gpu" }
          InfoPair { label: "Memory (TM1a)"; value: root.fmt(root.stats.memTemp, "°C"); driving: root.driverKey === "TM1a" }
          // Another SMC probe (TM2d, a board sensor...) has taken over.
          InfoPair {
            visible: root.driverKey !== "" && !root.driverListed
            label: root.driverName
            value: root.fmt(root.stats.hottest != null ? Math.round(root.stats.hottest) : null, "°C")
            driving: true
          }
        }

        PanelSeparator {
          foreground: root.bar ? root.bar.foreground : Color.foreground
        }

        // ---------- Mode picker ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "FAN MODE"
            foreground: root.bar ? root.bar.foreground : Color.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }

          Row {
            id: modeRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.modes.length > 0
              ? (width - spacing * (root.modes.length - 1)) / root.modes.length
              : 0

            Repeater {
              model: root.modes

              Button {
                required property var modelData
                required property int index
                width: modeRow.cellWidth
                iconText: String(modelData.icon)
                iconSize: Style.font.title
                text: String(modelData.label)
                fontSize: Style.font.bodySmall
                foreground: root.bar ? root.bar.foreground : Color.foreground
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                enabled: root.writable && root.running && !root.busy
                opacity: enabled ? 1.0 : 0.45
                active: root.mode === String(modelData.value)
                hasCursor: root.cursorActive && root.cursorIndex === index
                onClicked: root.setMode(String(modelData.value))
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.cursorIndex = index
                  }
                }
              }
            }
          }

          // Only ever shown when the daemon is missing or stopped — without
          // it nothing reads the mode file, so the buttons cannot do anything.
          Text {
            visible: !root.running || !root.writable
            width: parent.width
            wrapMode: Text.WordWrap
            text: !root.running
              ? "imac-fand is not running, the fan is on its own. Install it with sudo ./daemon/install.sh."
              : "The mode file is read-only. Re-run sudo ./daemon/install.sh."
            color: root.bar ? root.bar.foreground : Color.foreground
            opacity: 0.6
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Full speed above 90°C in every mode. The mode survives reboots."
            color: root.bar ? root.bar.foreground : Color.foreground
            opacity: 0.45
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        PanelSeparator {
          foreground: root.bar ? root.bar.foreground : Color.foreground
        }

        // ---------- Last two minutes ----------
        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "LAST 2 MINUTES"
            foreground: root.bar ? root.bar.foreground : Color.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }

          // The legend carries the numbers: the hovered sample's, or the latest.
          Item {
            width: parent.width
            implicitHeight: legendRow.implicitHeight

            Row {
              id: legendRow
              spacing: Style.space(12)

              Repeater {
                model: root.series

                Row {
                  required property var modelData
                  spacing: Style.space(5)

                  Rectangle {
                    width: Style.space(12)
                    height: 2
                    radius: 1
                    color: modelData.color
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: (root.driverKey === modelData.driver ? "󰈐 " : "") + modelData.label + " " +
                      root.fmt(root.shownSample ? root.shownSample[modelData.key] : null, "°C")
                    color: root.bar ? root.bar.foreground : Color.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: legendRow.verticalCenter
              text: root.hoverIndex < 0 || root.hoverIndex === root.history.length - 1 ? "now"
                : Math.round((root.windowEnd() - root.history[root.hoverIndex].t) / 1000) + " s ago"
              color: root.bar ? root.bar.foreground : Color.foreground
              opacity: 0.45
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Item {
            id: chart
            width: parent.width
            height: Style.space(110)

            readonly property real axisWidth: Style.space(28)

            Repeater {
              model: root.chartRange.ticks

              Text {
                required property var modelData
                x: 0
                width: chart.axisWidth - Style.space(6)
                y: root.chartY(modelData, chart.height) - height / 2
                horizontalAlignment: Text.AlignRight
                text: modelData + "°"
                color: root.bar ? root.bar.foreground : Color.foreground
                opacity: 0.45
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Canvas {
              id: plot
              x: chart.axisWidth
              width: chart.width - chart.axisWidth
              height: chart.height

              // Anything the picture depends on; a change repaints it.
              readonly property var inputs: [root.history, root.hoverIndex, root.series, root.opened]
              onInputsChanged: requestPaint()
              onWidthChanged: requestPaint()
              onHeightChanged: requestPaint()
              onPaint: root.paintChart(getContext("2d"), width, height)
            }

            MouseArea {
              anchors.fill: plot
              hoverEnabled: true
              onPositionChanged: function(mouse) {
                root.hoverFrac = Math.max(0, Math.min(1, mouse.x / plot.width))
              }
              onExited: root.hoverFrac = -1
            }
          }

          Item {
            width: parent.width
            implicitHeight: minus2.implicitHeight

            Text {
              id: minus2
              x: chart.axisWidth
              text: "2 min ago"
              color: root.bar ? root.bar.foreground : Color.foreground
              opacity: 0.45
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            Text {
              x: chart.axisWidth + (parent.width - chart.axisWidth - width) / 2
              text: "1 min"
              color: root.bar ? root.bar.foreground : Color.foreground
              opacity: 0.45
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.right: parent.right
              text: "now"
              color: root.bar ? root.bar.foreground : Color.foreground
              opacity: 0.45
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }

  // A label and its value. The temperature imac-fand is following gets the
  // accent, a fan glyph and a tinted row: the reading behind the rpm above.
  component InfoPair: Item {
    id: pair
    property string label: ""
    property string value: ""
    property bool driving: false
    readonly property real pad: Style.space(3)
    readonly property color ink: driving ? Color.accent : (root.bar ? root.bar.foreground : Color.foreground)
    width: parent ? parent.width : 0
    implicitHeight: pairValue.implicitHeight + 2 * pad

    Rectangle {
      anchors.fill: parent
      visible: pair.driving
      radius: Style.cornerRadius
      color: Style.selectedAccentFill
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: (pair.driving ? "󰈐 " : "") + pair.label
      color: pair.ink
      opacity: pair.driving ? 1.0 : 0.6
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: pairValue
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: pair.value
      color: pair.ink
      font.bold: pair.driving
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }
}
