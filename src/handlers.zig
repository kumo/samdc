const std = @import("std");
const cli = @import("cli.zig");
const mdc = @import("mdc/mod.zig");

// Handler for the 'on' action
pub fn handleOn(client: *mdc.Client, display: *cli.Display) void {
    _ = display;
    client.setPower(true);
}

// Handler for the 'off' action
pub fn handleOff(client: *mdc.Client, display: *cli.Display) void {
    _ = display;
    client.setPower(false);
}

// Handler for the 'reboot' action
pub fn handleReboot(client: *mdc.Client, display: *cli.Display) void {
    _ = display;
    client.reboot();
}

// Handler for the 'volume' action (get or set)
pub fn handleVolume(client: *mdc.Client, display: *cli.Display, config: *const cli.Config) void {
    if (config.positional_args.items.len > 0) {
        // Set volume
        const volume_value = config.getPositionalInteger(0) orelse {
            display.showError(cli.ConfigError.InvalidVolumeLevel);
            return;
        };
        if (volume_value > 100) {
            display.showError(cli.ConfigError.InvalidVolumeLevel);
            return;
        }
        client.setVolume(@intCast(volume_value));
    } else {
        // Get volume
        client.showVolume();
    }
}

// Handler for the 'url' action (get or set)
pub fn handleUrl(client: *mdc.Client, display: *cli.Display, config: *const cli.Config) void {
    if (config.positional_args.items.len > 0) {
        // Set URL
        const url = config.getPositionalString(0) orelse {
            display.showError(cli.ConfigError.InvalidUrl);
            return;
        };
        client.setLauncherUrl(url);
    } else {
        // Get URL
        client.showLauncherUrl();
    }
}

// Handler for the 'serial' action (get only)
pub fn handleSerial(client: *mdc.Client, display: *cli.Display) void {
    _ = display;
    client.showSerial();
}
