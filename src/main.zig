const std = @import("std");
const net = std.net;
const testing = std.testing;

const cli = @import("cli.zig");
const mdc = @import("mdc/mod.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var display = cli.Display.init();

    // Parse command line arguments
    var config = cli.Config.fromArgs(allocator) catch |err| {
        display.showError(err);
        return;
    };
    defer config.deinit();

    // Handle special actions first
    switch (config.action) {
        .help => {
            display.printUsage();
            return;
        },
        .version => {
            display.showVersion();
            return;
        },
        else => {},
    }

    // Execute command for each address
    for (config.addresses.items) |address| {
        var client = mdc.Client.init(allocator, address, 0, config.verbose); // Default Display ID
        defer client.deinit();

        // Show address if multiple targets or verbose mode
        if (config.addresses.items.len > 1 or config.verbose) {
            std.log.debug("Executing command on {}", .{address});
        }

        switch (config.action) {
            .on => {
                client.setPower(true) catch |err| {
                    display.showError(err);
                    continue;
                };
                display.writer.writeAll("Turn on command sent\n") catch {};
            },
            .off => {
                client.setPower(false) catch |err| {
                    display.showError(err);
                    continue;
                };
                display.writer.writeAll("Turn off command sent\n") catch {};
            },
            .reboot => {
                client.reboot() catch |err| {
                    display.showError(err);
                    continue;
                };
                display.writer.writeAll("Reboot command sent\n") catch {};
            },
            .volume => {
                // Volume can be set or queried
                if (config.positional_args.items.len > 0) {
                    // Set volume
                    const volume_value = config.getPositionalInteger(0) orelse {
                        std.log.err("Invalid volume level", .{});
                        continue;
                    };

                    if (volume_value > 100) {
                        std.log.err("Volume must be between 0-100", .{});
                        continue;
                    }

                    client.setVolume(@intCast(volume_value)) catch |err| {
                        display.showError(err);
                        continue;
                    };
                    display.writer.print("Volume set to {d}\n", .{volume_value}) catch {};
                } else {
                    // Get volume
                    const volume = client.getVolume() catch |err| {
                        display.showError(err);
                        continue;
                    };
                    display.writer.print("Current volume: {d}\n", .{volume}) catch {};
                }
            },
            .url => {
                // URL can be set or queried
                if (config.positional_args.items.len > 0) {
                    // Set URL
                    const url = config.getPositionalString(0) orelse {
                        std.log.err("Invalid URL", .{});
                        continue;
                    };

                    client.setLauncherUrl(url) catch |err| {
                        display.showError(err);
                        continue;
                    };
                    display.writer.print("URL set to {s}\n", .{url}) catch {};
                } else {
                    // Get URL
                    const url = client.getLauncherUrl() catch |err| {
                        display.showError(err);
                        continue;
                    };
                    defer allocator.free(url);
                    display.writer.print("Current URL: {s}\n", .{url}) catch {};
                }
            },
            else => {
                display.writer.writeAll("Command not implemented\n") catch {};
            },
        }
    }
}
