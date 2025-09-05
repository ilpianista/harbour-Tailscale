TARGET = harbour-tailscale

CONFIG += sailfishapp

SOURCES += \
    src/client.cpp \
    src/main.cpp

OTHER_FILES += \
    qml/cover/CoverPage.qml \
    qml/pages/About.qml \
    qml/pages/MainPage.qml \
    qml/Tailscale.qml \
    harbour-tailscale.desktop \
    rpm/harbour-tailscale.changes \
    rpm/harbour-tailscale.spec \
    rpm/tailscaled.defaults \
    rpm/tailscaled.service \
    translations/*.ts

CONFIG += sailfishapp_i18n
TRANSLATIONS += \
    translations/harbour-tailscale-et.ts \
    translations/harbour-tailscale-it.ts \
    translations/harbour-tailscale-nb_NO.ts \
    translations/harbour-tailscale-ru.ts \
    translations/harbour-tailscale-ta.ts

HEADERS += \
    src/client.h
