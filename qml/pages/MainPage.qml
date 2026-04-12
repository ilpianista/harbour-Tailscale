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
import Nemo.DBus 2.0

Page {
    id: page
    allowedOrientations: Orientation.All

    function parseStatus(statusText) {
        var result = [];
        var lines = statusText.trim().split('\n');
        var isFirst = true;

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (line === '')
                continue;

            // Collapse runs of 2+ spaces into a single tab so we can split cleanly
            var parts = line.replace(/\s{2,}/g, '\t').split('\t');
            if (parts.length < 4)
                continue;
            var ip = parts[0].trim();
            // Skip lines that don't start with a dotted-quad IP (e.g. error messages)
            if (!/^\d+\.\d+\.\d+\.\d+$/.test(ip))
                continue;
            var hostname = parts[1].trim();
            var user = parts[2].trim().replace(/@$/, '');
            var os = parts[3].trim();
            var rawStatus = parts.slice(4).join(' ').trim();
            var isOnline = (rawStatus === '-' || rawStatus === '');
            var statusLabel = '';

            if (isOnline) {
                statusLabel = isFirst ? qsTr("This device") : qsTr("Online");
            } else {
                // "offline, last seen 3d ago"  →  "Seen 3d ago"
                statusLabel = rawStatus.replace(/^offline,\s*/i, '').replace(/^last seen\s*/i, qsTr("Seen "));
            }

            result.push({
                "ip": ip,
                "hostname": hostname,
                "user": user,
                "os": os,
                "statusLabel": statusLabel,
                "isOnline": isOnline,
                "isSelf": isFirst
            });

            isFirst = false;
        }

        return result;
    }

    function refreshStatus() {
        var raw = client.getStatus();
        var parsed = parseStatus(raw);
        deviceModel.clear();
        for (var i = 0; i < parsed.length; i++) {
            deviceModel.append(parsed[i]);
        }
    }

    DBusInterface {
        id: systemd
        bus: DBus.SystemBus
        service: 'org.freedesktop.systemd1'
        path: '/org/freedesktop/systemd1'
        iface: 'org.freedesktop.systemd1.Manager'
    }

    Connections {
        target: client

        onLoginRequest: {
            console.log("Opening browser at", url);
            Qt.openUrlExternally(url);
        }

        onStatusUpdate: {
            refreshStatus();
            up.enabled = !isUp;
            down.enabled = isUp;
        }
    }

    ListModel {
        id: deviceModel
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: deviceModel

        PullDownMenu {
            MenuItem {
                text: qsTr("About")
                onClicked: pageStack.push(Qt.resolvedUrl("About.qml"))
            }

            MenuItem {
                id: down
                text: qsTr("Down")
                enabled: client.isUp()

                onClicked: {
                    client.down();
                    up.enabled = true;
                    down.enabled = false;
                    appWindow.restartBrowser();
                    refreshStatus();
                }
            }

            MenuItem {
                id: up
                text: qsTr("Up")
                enabled: !client.isUp()

                onClicked: {
                    client.up();
                    appWindow.restartBrowser();
                }
            }
        }

        header: PageHeader {
            title: qsTr("Tailscale")
        }

        ViewPlaceholder {
            enabled: deviceModel.count === 0
            text: qsTr("No devices found")
            hintText: qsTr("Pull down to bring Tailscale up")
        }

        delegate: ListItem {
            id: listItem
            width: listView.width
            contentHeight: innerColumn.implicitHeight + Theme.paddingLarge * 2

            Rectangle {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                width: Theme.paddingSmall / 2
                height: parent.contentHeight * 0.55
                radius: width / 2
                color: model.isOnline ? (model.isSelf ? Theme.highlightColor : Theme.rgba(Theme.highlightColor, 0.75)) : "transparent"
            }

            Column {
                id: innerColumn

                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                spacing: Theme.paddingSmall / 2

                Row {
                    width: parent.width
                    spacing: Theme.paddingSmall

                    Label {
                        id: hostnameLabel
                        text: model.hostname
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: model.isSelf
                        color: model.isOnline ? Theme.primaryColor : Theme.secondaryColor
                        truncationMode: TruncationMode.Fade
                        width: parent.width - osTag.width - parent.spacing
                    }

                    Rectangle {
                        id: osTag
                        anchors.verticalCenter: hostnameLabel.verticalCenter
                        width: osLabel.implicitWidth + Theme.paddingSmall * 2
                        height: osLabel.implicitHeight + Theme.paddingSmall * 0.75
                        radius: height / 2
                        color: model.isOnline ? Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity * 0.6) : Theme.rgba(Theme.primaryColor, 0.07)

                        Label {
                            id: osLabel
                            anchors.centerIn: parent
                            text: model.os
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: model.isOnline ? Theme.secondaryHighlightColor : Theme.rgba(Theme.primaryColor, 0.45)
                        }
                    }
                }

                Label {
                    text: model.ip
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.rgba(Theme.primaryColor, model.isOnline ? 0.75 : 0.4)
                }

                Label {
                    text: model.statusLabel
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: model.isOnline ? Theme.highlightColor : Theme.secondaryColor
                }
            }
        }

        VerticalScrollDecorator {}
    }

    Component.onCompleted: {
        systemd.typedCall('StartUnit', [
            {
                "type": 's',
                "value": 'tailscaled.service'
            },
            {
                "type": 's',
                "value": 'fail'
            }
        ], function (result) {
            refreshStatus();
        }, function (error, message) {
            console.log("StartUnit failed (" + error + "):", message);
        });
    }

    Component.onDestruction: {
        systemd.typedCall('StopUnit', [
            {
                "type": 's',
                "value": 'tailscaled.service'
            },
            {
                "type": 's',
                "value": 'fail'
            }
        ], function (result) {}, function (error, message) {
            console.log("StopUnit failed (" + error + "):", message);
        });
    }
}
