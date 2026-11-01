# Tailscale

[Sailfish OS](https://sailfishos.org) UI for [Tailscale](https://tailscale.com/). A Sailfish OS application.

## Origin

Original application by [Andrea Scarpino](https://scarpino.dev):
<https://github.com/ilpianista/harbour-Tailscale>, MIT license.

This application uses **root** privileges, as this is needed to run `tailscale` with root privileges. This is a security risk!

This project **IS NOT** endorsed by Tailscale Inc.

## Why this fork exists

A fork of the original app with additional features:

- **Device detail page** — tap a device in the list to see its
  MagicDNS name, IPv4, IPv6, OS, key expiry and status. Tap any
  address to copy it to the clipboard.
- **Ping with latency graph** — 10 pings with a live per-bar ms
  latency graph, the connection type (direct vs relayed via DERP),
  and a Stop button.
- **Start at boot** — a Settings switch that enables the `tailscaled`
  service: it starts at boot and keeps running after the app is
  closed (daemon mode).

## Translations

[![Translation status](https://hosted.weblate.org/widgets/harbour-tailscale/-/svg-badge.svg)](https://hosted.weblate.org/engage/harbour-tailscale/?utm_source=widget)

Translations via [Weblate](https://hosted.weblate.org/projects/harbour-tailscale/), thank you!

## License

MIT
