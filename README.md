# SaMDC

A lightweight CLI tool for interacting with Samsung displays using the MDC (Multiple Display Control) protocol.

## Overview

SaMDC is designed as a more user-friendly alternative to existing Samsung MDC tools, focusing on simplicity and common use cases like rebooting, replacing the app, and auditing one or more displays.

## Features

- Basic display control commands:
  - `reboot`: Restart the display
  - `wake`: Power on the display
  - `sleep`: Put the display to sleep
  - `volume`: Get or set the volume
  - `url`: Get or set the launcher url

## Installation

```bash
# Installation instructions will go here
```

## Usage

### Basic Commands

```bash
# Reboot a display
samdc reboot 10.10.10.10

# Wake up multiple displays
samdc wake 10.10.10.10 11.11.11.11

# Change the volume of a display
samdc volume 50 10.10.10.10
```

## Development

This project is in very early development. Currently implementing core commands with plans to add more functionality over time.

## Roadmap

- [x] Basic device control (reboot, wake, sleep)
- [x] Multi-device management
- [ ] Advanced display settings
- [ ] Export data in JSON
- [ ] Configuration profiles
- [ ] Audit capabilities

## Contributing

Contributions welcome! Feel free to submit issues or pull requests.

## License

[MIT License](LICENSE)
