/*
    Copyright (C) 2022-2026 Andrea Scarpino <andrea@scarpino.dev>
    All rights reserved.

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    // Passed in from the device list. Matching is done by IP, not by name,
    // because the list's name column can differ from the JSON HostName
    // (especially for Android nodes).
    property string hostname: ""
    property string nodeIp: ""
    property bool isSelf: false

    // Node data (populated by loadNode()). Plain string/bool properties:
    // every row below is a fixed item bound to them. Deliberately NO
    // Repeater/JS-array model: on SFOS 5.2 (Qt 5.6) a Repeater with a JS
    // array model reports the right count but never instantiates delegate
    // items, which left the rows blank on the phone.
    property bool hasData: false
    property string dnsName: ""
    property string ip4: ""
    property string ip6: ""
    property string osName: ""
    property string keyExpiry: ""
    property bool online: false

    // Ping state
    readonly property int pingCount: 10
    property bool pinging: false
    property var graphData: []      // [ms, ms, ...] appended per sample
    property var relayedData: []    // [bool, bool, ...] parallel to graphData
    property int sampleCount: 0
    property double latestMs: 0
    property bool lastRelayed: false
    property bool hasResult: false
    // Set when a ping run finished without a single sample (offline peer:
    // `tailscale ping` prints "timed out / no reply" and exits 1).
    property bool pingNoResponse: false
    // 0=dns 1=ipv4 2=ipv6, -1=none. Drives the "Copied" caption flash.
    property int copiedRow: -1

    // Single source of truth for the content's top offset. The 140px
    // floor GUARANTEES the first rows clear the header + camera notch
    // even if the header item's height ever evaluates small/zero; the
    // header term keeps the content below a taller header. Do NOT use
    // Theme.pageHeaderHeight (does not exist in Silica 5.2 → NaN → the
    // whole binding silently fails → content renders at y=0; that is
    // the -6..-10 cutoff bug).
    readonly property real contentTop: Math.max(pageHeader.height + Theme.paddingLarge, 140)

    Timer {
        id: copyTimer
        interval: 1200
        onTriggered: page.copiedRow = -1
    }

    // No back button: SFOS edge-swipe (from the left edge) pops the page,
    // which fires Component.onDestruction below and cancels any running
    // ping. (The old IconButton back arrow was removed in 0.0.14-14 as
    // unneeded.)
    PageHeader {
        id: pageHeader
        title: page.hostname
    }

    Connections {
        target: client

        onPingSample: {
            page.graphData = page.graphData.concat([latencyMs]);
            page.relayedData = page.relayedData.concat([relayed]);
            page.sampleCount += 1;
            page.latestMs = latencyMs;
            page.lastRelayed = relayed;
            page.hasResult = true;
            page.pingNoResponse = false;
        }

        onPingFinished: {
            page.pinging = false;
            if (page.sampleCount === 0)
                page.pingNoResponse = true;
        }
    }

    function loadNode() {
        try {
            var status = JSON.parse(client.getStatusJson());
            var node = null;
            var peers = status.Peer || {};

            for (var id in peers) {
                var ips = peers[id].TailscaleIPs || [];
                if (ips.indexOf(page.nodeIp) !== -1) {
                    node = peers[id];
                    break;
                }
            }

            if (!node && status.Self) {
                var selfIps = status.Self.TailscaleIPs || [];
                if (selfIps.indexOf(page.nodeIp) !== -1 || page.isSelf)
                    node = status.Self;
            }

            if (!node) {
                console.log("DevicePage: no node found for " + page.nodeIp);
                return;
            }

            page.dnsName = node.DNSName ? node.DNSName.replace(/\.$/, "") : "";

            var ips2 = node.TailscaleIPs || [];
            page.ip4 = "";
            page.ip6 = "";
            for (var i = 0; i < ips2.length; i++) {
                if (ips2[i].indexOf(":") !== -1)
                    page.ip6 = ips2[i];
                else if (page.ip4 === "")
                    page.ip4 = ips2[i];
            }
            page.osName = node.OS || "";

            page.keyExpiry = node.KeyExpiry
                ? Qt.formatDateTime(new Date(node.KeyExpiry), Qt.TextDate)
                : qsTr("No expiry");

            page.online = node.Online === true;
            page.hasData = true;
        } catch (error) {
            console.log("DevicePage: loadNode failed: " + error);
        }
    }

    function startPing() {
        if (page.pinging)
            return;
        page.graphData = [];
        page.relayedData = [];
        page.sampleCount = 0;
        page.latestMs = 0;
        page.hasResult = false;
        page.pingNoResponse = false;
        page.copiedRow = -1;
        page.pinging = true;
        client.startPing(page.nodeIp, page.pingCount);
    }

    ViewPlaceholder {
        anchors.centerIn: parent
        visible: !page.hasData
        text: qsTr("No data available")
    }

    SilicaFlickable {
        anchors.fill: parent
        visible: page.hasData
        // contentTop carries the guaranteed floor (see page.contentTop):
        // the content can never end up at y=0 under the header/notch.
        contentHeight: page.contentTop
                        + contentColumn.implicitHeight
                        + Theme.paddingLarge

        Column {
            id: contentColumn
            anchors {
                left: parent.left
                right: parent.right
                // top: parent.top + a CONSTANT-guaranteed margin (page.contentTop).
                // No cross-item anchor, no Theme constant that might not exist:
                // a failed binding here silently leaves the margin at 0 and
                // the content renders at the very top of the screen (the bug
                // that survived builds -6..-10).
                top: parent.top
                topMargin: page.contentTop
                leftMargin: Theme.horizontalPageMargin
                rightMargin: Theme.horizontalPageMargin
            }
            spacing: Theme.paddingLarge

            Label {
                text: qsTr("Tailscale addresses")
                font.pixelSize: Theme.fontSizeSmall
                font.letterSpacing: 0.5
                color: Theme.secondaryColor
            }

            // MagicDNS ----------------------------------------------------
            Column {
                width: contentColumn.width
                spacing: Theme.paddingSmall / 2
                visible: page.dnsName !== ""

                Label {
                    width: contentColumn.width
                    text: page.dnsName
                    font.pixelSize: Theme.fontSizeMedium
                    elide: Text.ElideRight
                    color: Theme.primaryColor
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            client.copyToClipboard(page.dnsName);
                            page.copiedRow = 0;
                            copyTimer.restart();
                        }
                    }
                }
                Label {
                    text: page.copiedRow === 0 ? qsTr("Copied") : qsTr("MagicDNS")
                    font.pixelSize: Theme.fontSizeSmall
                    color: page.copiedRow === 0 ? Theme.highlightColor : Theme.secondaryColor
                }
            }

            // IPv4 ---------------------------------------------------------
            Column {
                width: contentColumn.width
                spacing: Theme.paddingSmall / 2
                visible: page.ip4 !== ""

                Label {
                    width: contentColumn.width
                    text: page.ip4
                    font.pixelSize: Theme.fontSizeMedium
                    elide: Text.ElideRight
                    color: Theme.primaryColor
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            client.copyToClipboard(page.ip4);
                            page.copiedRow = 1;
                            copyTimer.restart();
                        }
                    }
                }
                Label {
                    text: page.copiedRow === 1 ? qsTr("Copied") : qsTr("IPv4")
                    font.pixelSize: Theme.fontSizeSmall
                    color: page.copiedRow === 1 ? Theme.highlightColor : Theme.secondaryColor
                }
            }

            // IPv6 ---------------------------------------------------------
            Column {
                width: contentColumn.width
                spacing: Theme.paddingSmall / 2
                visible: page.ip6 !== ""

                Label {
                    width: contentColumn.width
                    text: page.ip6
                    font.pixelSize: Theme.fontSizeMedium
                    elide: Text.ElideRight
                    color: Theme.primaryColor
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            client.copyToClipboard(page.ip6);
                            page.copiedRow = 2;
                            copyTimer.restart();
                        }
                    }
                }
                Label {
                    text: page.copiedRow === 2 ? qsTr("Copied") : qsTr("IPv6")
                    font.pixelSize: Theme.fontSizeSmall
                    color: page.copiedRow === 2 ? Theme.highlightColor : Theme.secondaryColor
                }
            }

            // OS -----------------------------------------------------------
            Column {
                width: contentColumn.width
                spacing: Theme.paddingSmall / 2
                visible: page.osName !== ""

                Label {
                    width: contentColumn.width
                    text: page.osName
                    font.pixelSize: Theme.fontSizeMedium
                    elide: Text.ElideRight
                    color: Theme.primaryColor
                }
                Label {
                    text: qsTr("OS")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                }
            }

            // Key expiry ---------------------------------------------------
            Column {
                width: contentColumn.width
                spacing: Theme.paddingSmall / 2
                visible: page.hasData

                Label {
                    width: contentColumn.width
                    text: page.keyExpiry
                    font.pixelSize: Theme.fontSizeMedium
                    elide: Text.ElideRight
                    color: page.keyExpiry !== qsTr("No expiry")
                        ? Theme.primaryColor : Theme.secondaryColor
                }
                Label {
                    text: qsTr("Key expiry")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                }
            }

            // Status -------------------------------------------------------
            Column {
                width: contentColumn.width
                spacing: Theme.paddingSmall / 2
                visible: page.hasData

                Label {
                    width: contentColumn.width
                    text: page.online ? qsTr("Online") : qsTr("Offline")
                    font.pixelSize: Theme.fontSizeMedium
                    color: page.online ? Theme.highlightColor : Theme.errorColor
                }
                Label {
                    text: qsTr("Status")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                }
            }

            // Ping section ------------------------------------------------
            Rectangle {
                width: contentColumn.width
                height: 1
                color: Theme.rgba(Theme.primaryColor, 0.12)
            }

            Label {
                text: qsTr("Ping")
                font.pixelSize: Theme.fontSizeSmall
                font.letterSpacing: 0.5
                color: Theme.secondaryColor
            }

            Label {
                width: contentColumn.width
                visible: page.isSelf
                text: qsTr("This is your own device — Tailscale can't ping itself.")
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.secondaryColor
            }

            Row {
                id: pingRow
                visible: !page.isSelf
                width: contentColumn.width
                spacing: Theme.paddingMedium

                Button {
                    id: pingButton
                    width: parent.width * 0.5
                    text: page.pinging ? qsTr("Stop") : qsTr("Ping")
                    onClicked: {
                        if (page.pinging)
                            client.cancelPing("stop-button");
                        else
                            page.startPing();
                    }
                }

                Label {
                    id: pingLatest
                    anchors.verticalCenter: pingButton.verticalCenter
                    visible: page.hasResult
                    width: parent.width - pingButton.width - parent.spacing
                    text: page.latestMs + " ms"
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignRight
                    color: Theme.primaryColor
                }
            }

            // Immediate feedback: an offline peer produces ZERO samples
            // (`tailscale ping` prints "timed out / no reply", exit 1),
            // so without this the Ping button looked dead for ~40 s.
            Label {
                id: noResponseLabel
                width: contentColumn.width
                visible: !page.isSelf && page.sampleCount === 0
                          && (page.pinging || page.pingNoResponse)
                text: page.pinging
                    ? qsTr("Pinging… no reply yet (offline devices take a few seconds)")
                    : qsTr("No response — device offline or unreachable")
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: page.pinging ? Theme.secondaryColor : Theme.errorColor
            }

            Label {
                id: connLabel
                width: contentColumn.width
                visible: page.hasResult
                text: page.lastRelayed ? qsTr("Relayed connection (via DERP)")
                                      : qsTr("Direct connection")
                font.pixelSize: Theme.fontSizeSmall
                color: page.lastRelayed ? Theme.secondaryHighlightColor : Theme.highlightColor
            }

            // Latency graph: 10 fixed bars (one per ping slot). Pure
            // Rectangles with explicit x + bottom anchor — NO Row (its
            // baseline alignment silently bottom-aligned the bars and broke
            // the intended layout), NO Repeater (JS-array model is broken on
            // this Qt), NO Canvas.
            // Orientation per user request: the duration grows toward the
            // TOP — 0 ms baseline at the bottom, max ms at the top (the same
            // chart as the Android Tailscale app).
            Item {
                id: graphBox
                width: contentColumn.width
                height: 190
                visible: page.sampleCount > 0

                function barMax() {
                    var m = 0;
                    for (var i = 0; i < page.graphData.length; i++)
                        if (page.graphData[i] > m)
                            m = page.graphData[i];
                    return Math.max(10, Math.ceil(m));
                }

                function slotWidth() {
                    return (plotArea.width - 9 * 8) / 10;
                }

                function barHeight(v) {
                    return Math.max(4, (v / graphBox.barMax()) * (plotArea.height - 8));
                }

                // Connection type is shown ONCE, by connLabel above the
                // graph ("Direct connection" / "Relayed connection (via
                // DERP)") — the old legend listed both types under the
                // graph at the same time and contradicted connLabel, so it
                // was removed. The per-bar ms labels (below) live in the
                // bottom strip; the old "max ms" label above the bars was
                // removed per user request (redundant with the per-bar
                // labels).
                Rectangle {
                    id: plotArea
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                        bottomMargin: 44   // per-bar ms label strip (clear of the bars)
                    }
                    color: "transparent"

                    Rectangle {
                        anchors { top: parent.top; left: parent.left; right: parent.right }
                        height: 1
                        color: Theme.rgba(Theme.primaryColor, 0.12)
                    }
                    Rectangle {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; right: parent.right }
                        height: 1
                        color: Theme.rgba(Theme.primaryColor, 0.12)
                    }
                    // Baseline at the BOTTOM (0 ms): bars grow UP from here.
                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        height: 1
                        color: Theme.rgba(Theme.primaryColor, 0.25)
                    }

                    // 10 fixed bars, each individually positioned: explicit
                    // x, bottom-anchored, growing UP. No Row: Row baseline
                    // alignment made "anchored" bars render bottom-aligned
                    // and broke the intended layout in 0.0.14-9.
                    // slot 0
                    Rectangle {
                        anchors.bottom: parent.bottom
                        x: 0 * (graphBox.slotWidth() + 8)
                        width: graphBox.slotWidth()
                        height: 0 < page.sampleCount ? graphBox.barHeight(page.graphData[0]) : 2
                        visible: 0 < page.sampleCount
                        radius: 3
                        color: Theme.highlightColor
                    }
                    // slot 1
                    Rectangle {
                        anchors.bottom: parent.bottom
                        x: 1 * (graphBox.slotWidth() + 8)
                        width: graphBox.slotWidth()
                        height: 1 < page.sampleCount ? graphBox.barHeight(page.graphData[1]) : 2
                        visible: 1 < page.sampleCount
                        radius: 3
                        color: Theme.highlightColor
                    }
                    // slot 2
                    Rectangle {
                        anchors.bottom: parent.bottom
                        x: 2 * (graphBox.slotWidth() + 8)
                        width: graphBox.slotWidth()
                        height: 2 < page.sampleCount ? graphBox.barHeight(page.graphData[2]) : 2
                        visible: 2 < page.sampleCount
                        radius: 3
                        color: Theme.highlightColor
                    }
                    // slot 3
                    Rectangle {
                        anchors.bottom: parent.bottom
                        x: 3 * (graphBox.slotWidth() + 8)
                        width: graphBox.slotWidth()
                        height: 3 < page.sampleCount ? graphBox.barHeight(page.graphData[3]) : 2
                        visible: 3 < page.sampleCount
                        radius: 3
                        color: Theme.highlightColor
                    }
                    // slot 4
                    Rectangle {
                        anchors.bottom: parent.bottom
                        x: 4 * (graphBox.slotWidth() + 8)
                        width: graphBox.slotWidth()
                        height: 4 < page.sampleCount ? graphBox.barHeight(page.graphData[4]) : 2
                        visible: 4 < page.sampleCount
                        radius: 3
                        color: Theme.highlightColor
                    }
                    // slot 5
                    Rectangle {
                        anchors.bottom: parent.bottom
                        x: 5 * (graphBox.slotWidth() + 8)
                        width: graphBox.slotWidth()
                        height: 5 < page.sampleCount ? graphBox.barHeight(page.graphData[5]) : 2
                        visible: 5 < page.sampleCount
                        radius: 3
                        color: Theme.highlightColor
                    }
                    // slot 6
                    Rectangle {
                        anchors.bottom: parent.bottom
                        x: 6 * (graphBox.slotWidth() + 8)
                        width: graphBox.slotWidth()
                        height: 6 < page.sampleCount ? graphBox.barHeight(page.graphData[6]) : 2
                        visible: 6 < page.sampleCount
                        radius: 3
                        color: Theme.highlightColor
                    }
                    // slot 7
                    Rectangle {
                        anchors.bottom: parent.bottom
                        x: 7 * (graphBox.slotWidth() + 8)
                        width: graphBox.slotWidth()
                        height: 7 < page.sampleCount ? graphBox.barHeight(page.graphData[7]) : 2
                        visible: 7 < page.sampleCount
                        radius: 3
                        color: Theme.highlightColor
                    }
                    // slot 8
                    Rectangle {
                        anchors.bottom: parent.bottom
                        x: 8 * (graphBox.slotWidth() + 8)
                        width: graphBox.slotWidth()
                        height: 8 < page.sampleCount ? graphBox.barHeight(page.graphData[8]) : 2
                        visible: 8 < page.sampleCount
                        radius: 3
                        color: Theme.highlightColor
                    }
                    // slot 9
                    Rectangle {
                        anchors.bottom: parent.bottom
                        x: 9 * (graphBox.slotWidth() + 8)
                        width: graphBox.slotWidth()
                        height: 9 < page.sampleCount ? graphBox.barHeight(page.graphData[9]) : 2
                        visible: 9 < page.sampleCount
                        radius: 3
                        color: Theme.highlightColor
                    }
                }

                // Per-bar ms labels, in the 44px strip BELOW the baseline
                // (children of graphBox, not plotArea — anchoring them to
                // plotArea's bottom would overlap the bars). One per slot,
                // same x/width as the bar, shown once that ping arrived.
                // Each label reads e.g. "4 ms".
                // slot 0
                Label {
                    anchors.bottom: parent.bottom
                    x: 0 * (graphBox.slotWidth() + 8)
                    width: graphBox.slotWidth()
                    text: page.sampleCount > 0 ? Math.round(page.graphData[0]) + " ms" : ""
                    horizontalAlignment: Text.AlignHCenter
                    visible: page.sampleCount > 0
                    font.pixelSize: 16
                    color: Theme.secondaryColor
                }
                // slot 1
                Label {
                    anchors.bottom: parent.bottom
                    x: 1 * (graphBox.slotWidth() + 8)
                    width: graphBox.slotWidth()
                    text: page.sampleCount > 1 ? Math.round(page.graphData[1]) + " ms" : ""
                    horizontalAlignment: Text.AlignHCenter
                    visible: page.sampleCount > 1
                    font.pixelSize: 16
                    color: Theme.secondaryColor
                }
                // slot 2
                Label {
                    anchors.bottom: parent.bottom
                    x: 2 * (graphBox.slotWidth() + 8)
                    width: graphBox.slotWidth()
                    text: page.sampleCount > 2 ? Math.round(page.graphData[2]) + " ms" : ""
                    horizontalAlignment: Text.AlignHCenter
                    visible: page.sampleCount > 2
                    font.pixelSize: 16
                    color: Theme.secondaryColor
                }
                // slot 3
                Label {
                    anchors.bottom: parent.bottom
                    x: 3 * (graphBox.slotWidth() + 8)
                    width: graphBox.slotWidth()
                    text: page.sampleCount > 3 ? Math.round(page.graphData[3]) + " ms" : ""
                    horizontalAlignment: Text.AlignHCenter
                    visible: page.sampleCount > 3
                    font.pixelSize: 16
                    color: Theme.secondaryColor
                }
                // slot 4
                Label {
                    anchors.bottom: parent.bottom
                    x: 4 * (graphBox.slotWidth() + 8)
                    width: graphBox.slotWidth()
                    text: page.sampleCount > 4 ? Math.round(page.graphData[4]) + " ms" : ""
                    horizontalAlignment: Text.AlignHCenter
                    visible: page.sampleCount > 4
                    font.pixelSize: 16
                    color: Theme.secondaryColor
                }
                // slot 5
                Label {
                    anchors.bottom: parent.bottom
                    x: 5 * (graphBox.slotWidth() + 8)
                    width: graphBox.slotWidth()
                    text: page.sampleCount > 5 ? Math.round(page.graphData[5]) + " ms" : ""
                    horizontalAlignment: Text.AlignHCenter
                    visible: page.sampleCount > 5
                    font.pixelSize: 16
                    color: Theme.secondaryColor
                }
                // slot 6
                Label {
                    anchors.bottom: parent.bottom
                    x: 6 * (graphBox.slotWidth() + 8)
                    width: graphBox.slotWidth()
                    text: page.sampleCount > 6 ? Math.round(page.graphData[6]) + " ms" : ""
                    horizontalAlignment: Text.AlignHCenter
                    visible: page.sampleCount > 6
                    font.pixelSize: 16
                    color: Theme.secondaryColor
                }
                // slot 7
                Label {
                    anchors.bottom: parent.bottom
                    x: 7 * (graphBox.slotWidth() + 8)
                    width: graphBox.slotWidth()
                    text: page.sampleCount > 7 ? Math.round(page.graphData[7]) + " ms" : ""
                    horizontalAlignment: Text.AlignHCenter
                    visible: page.sampleCount > 7
                    font.pixelSize: 16
                    color: Theme.secondaryColor
                }
                // slot 8
                Label {
                    anchors.bottom: parent.bottom
                    x: 8 * (graphBox.slotWidth() + 8)
                    width: graphBox.slotWidth()
                    text: page.sampleCount > 8 ? Math.round(page.graphData[8]) + " ms" : ""
                    horizontalAlignment: Text.AlignHCenter
                    visible: page.sampleCount > 8
                    font.pixelSize: 16
                    color: Theme.secondaryColor
                }
                // slot 9
                Label {
                    anchors.bottom: parent.bottom
                    x: 9 * (graphBox.slotWidth() + 8)
                    width: graphBox.slotWidth()
                    text: page.sampleCount > 9 ? Math.round(page.graphData[9]) + " ms" : ""
                    horizontalAlignment: Text.AlignHCenter
                    visible: page.sampleCount > 9
                    font.pixelSize: 16
                    color: Theme.secondaryColor
                }
            }

            Label {
                width: contentColumn.width
                visible: page.hasResult
                text: page.sampleCount + "/" + page.pingCount + " " + qsTr("pings")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
            }
        }

        VerticalScrollDecorator {}
    }

    Component.onCompleted: loadNode()

    // Catch-ALL cancel hook: whichever way this page goes away (back
    // button, or any future navigation), a running `tailscale ping` must
    // die with it. Component.onDestruction is a valid QML property in
    // this Qt 5.6 (MainPage already uses it and it works on the phone);
    // only the `onDestroyed` signal handler is invalid. This is the
    // hook that was missing in 0.0.14-12, where ONLY the back button
    // cancelled — any other way of leaving the page leaked the ping.
    Component.onDestruction: client.cancelPing("page-destruction")
}
