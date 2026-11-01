import QtQuick 2.0
import Sailfish.Silica 1.0
import "." as Pages
Item {
    width: 360
    height: 720

    Pages.DevicePage {
        id: dp
        width: 360
        height: 720
        hostname: "truenas-scale"
        nodeIp: "100.92.130.114"
        isSelf: false
    }

    // Drive the graph the same way the pingSample handler does
    // (plain JS arrays on `property var`), mixed relay/direct flags.
    Timer {
        id: fillTimer
        interval: 50
        onTriggered: {
            var a = [];
            for (var i = 0; i < 10; i++)
                a.push(2 + Math.round(Math.random() * 40));
            dp.graphData = a;
            dp.relayedData = [true, false, false, true, false, true, false, false, true, false];
            dp.sampleCount = 10;
            dp.latestMs = a[9];
            dp.lastRelayed = true;
            dp.hasResult = true;
        }
    }

    Component.onCompleted: fillTimer.start()
}
