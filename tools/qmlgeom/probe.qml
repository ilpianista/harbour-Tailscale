import QtQuick 2.0
import Sailfish.Silica 1.0
// console.log is NOT visible in this harness (no window), so results are
// written to a root property and read back from C++.
Item {
    id: probeRoot
    property string marker: "PROBE123"
    property string result: "NOT-RUN"
    property bool completed: false

    Component.onCompleted: {
        var r = [];
        try { r.push("pageHeaderHeight=[" + Theme.pageHeaderHeight + "]"); }
        catch (e) { r.push("pageHeaderHeight THROWS: " + e); }
        try { r.push("itemSizeLarge=[" + Theme.itemSizeLarge + "]"); }
        catch (e) { r.push("itemSizeLarge THROWS: " + e); }
        try { r.push("itemSizeSmall=[" + Theme.itemSizeSmall + "]"); }
        catch (e) { r.push("itemSizeSmall THROWS: " + e); }
        try { r.push("paddingLarge=[" + Theme.paddingLarge + "]"); }
        catch (e) { r.push("paddingLarge THROWS: " + e); }
        try { r.push("hasPageHeaderHeight=" + Theme.hasOwnProperty("pageHeaderHeight")); }
        catch (e) { r.push("hasOwn THROWS: " + e); }
        try { r.push("topCutout.height=[" + Screen.topCutout.height + "]"); }
        catch (e) { r.push("topCutout THROWS: " + e); }
        try { r.push("topCutoutInScreen=" + ("topCutout" in Screen)); }
        catch (e) { r.push("inScreen THROWS: " + e); }
        probeRoot.result = r.join(" | ");
        probeRoot.completed = true;
    }
}
