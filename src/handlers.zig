const std = @import("std");
const cli = @import("cli.zig");
const mdc = @import("mdc/mod.zig");

// Handler for the 'on' action
pub fn handleOn(client: *mdc.Client, display: *cli.Display) void {
    _ = display;
    client.setPower(true) catch return;
}

// Handler for the 'off' action
pub fn handleOff(client: *mdc.Client, display: *cli.Display) void {
    _ = display;
    client.setPower(false) catch return;
}

// Handler for the 'reboot' action
pub fn handleReboot(client: *mdc.Client, display: *cli.Display) void {
    _ = display;
    client.reboot() catch return;
}

// Handler for the 'volume' action (get or set)
pub fn handleVolume(client: *mdc.Client, display: *cli.Display, config: *const cli.Config) void {
    if (config.positional_args.items.len > 0) {
        // Set volume
        const volume_value = config.getPositionalInteger(0) orelse {
            display.showError(cli.ConfigError.InvalidVolumeLevel); // Use specific error
            return; // Return void on validation error, don't propagate
        };
        if (volume_value > 100) {
            display.showError(cli.ConfigError.InvalidVolumeLevel); // Use specific error
            return;
        }
        client.setVolume(@intCast(volume_value)) catch return;
    } else {
        // Get volume
        const volume = client.getVolume() catch return;
        _ = volume; // Result is handled by finalizeResult called within client.getVolume
    }
}

// Handler for the 'url' action (get or set)
pub fn handleUrl(client: *mdc.Client, display: *cli.Display, config: *const cli.Config, allocator: std.mem.Allocator) void {
    if (config.positional_args.items.len > 0) {
        // Set URL
        const url = config.getPositionalString(0) orelse {
            display.showError(cli.ConfigError.InvalidUrl); // Assuming this error exists
            return;
        };
        client.setLauncherUrl(url) catch return;
    } else {
        // Get URL
        const url = client.getLauncherUrl() catch return;
        defer allocator.free(url);
        // Result is handled by finalizeResult called within client.getLauncherUrl
    }
}

// Handler for the 'serial' action (get only)
pub fn handleSerial(client: *mdc.Client, allocator: std.mem.Allocator) void {
    const serial = client.getSerial() catch return;
    defer allocator.free(serial);
    // Result is handled by finalizeResult called within client.getSerial
}
