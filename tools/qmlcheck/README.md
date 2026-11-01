# QML compile-check tool for SailfishOS 5.2

Compiles a QML file against the REAL SFOS 5.2 aarch64 QML engine (via the SDK target
rootfs + qemu-aarch64), catching exactly the errors the phone would hit — without
shipping a test RPM. This is what caught the "Could not load page" bugs
(`header:` on Silica Page, SilicaButton/BackButton).

## Build (once, inside any mb2 build tree)
    BT=/tmp/tailscale-<n>-aarch64        # any existing build tree from the build pipeline
    mkdir -p $BT/qmltest2 && cp test2.cpp test2.pro $BT/qmltest2/
    chmod -R a+rwX $BT
    docker run --rm -v $BT:/home/mersdk/proj coderus/sailfishos-platform-sdk-aarch64:5.2.0.15 \
      bash -lc 'cd /home/mersdk/proj && mb2 build-shell sh -c "cd qmltest2 && qmake test2.pro >/dev/null 2>&1 && make"'

## Run (needs /tmp/sfos-target extracted from the SDK image — see HANDOFF.md for the recipe)
    T=/tmp/sfos-target
    cp -r ../../qml $BT/qml
    LD_LIBRARY_PATH=$T/usr/lib64:$T/lib64 \
      timeout 60 qemu-aarch64 -L $T $BT/qmltest2/testload2 $BT/qml/pages/DevicePage.qml

Output: `COMPILE OK` or the exact QML error + line number.
Rule: run on every QML file you touch before building the RPM.
