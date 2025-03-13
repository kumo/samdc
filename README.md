# SamDC

A lightweight CLI tool for interacting with Samsung displays using the MDC (Multiple Display Control) protocol.

## Overview

SamDC is designed as a more user-friendly alternative to existing Samsung MDC tools, focusing on simplicity and common use cases like rebooting, replacing the app, and auditing one or more displays.

## Features

- Basic display control commands:
  - `reboot`: Restart the display
  - `wake`: Power on the display
  - `sleep`: Put the display to sleep

## Installation

```bash
# Installation instructions will go here
```

## Usage

### Basic Commands

```bash
# Reboot a display
samdc reboot 10.10.10.10

# Wake up a display
samdc wake 10.10.10.10

# Put a display to sleep
samdc sleep 10.10.10.10
```

## Development

This project is in very early development. Currently implementing core commands with plans to add more functionality over time.

## Roadmap

- [x] Basic device control (reboot, wake, sleep)
- [ ] Advanced display settings
- [ ] Multi-device management
- [ ] Export data in JSON
- [ ] Configuration profiles
- [ ] Audit capabilities

## Contributing

Contributions welcome! Feel free to submit issues or pull requests.

## License

[MIT License](LICENSE)
