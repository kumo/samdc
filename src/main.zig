const std = @import("std");
const net = std.net;
const testing = std.testing;

const cli = @import("cli.zig");
const mdc = @import("mdc/mod.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments first to get output mode
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    var config = cli.Config.fromArgs(allocator, args) catch |err| {
        // Need a temporary, simple display for pre-config errors
        var error_display = cli.Display.init_simple(allocator);
        error_display.showError(err);
        return;
    };
    defer config.deinit();

    // Now initialize the main Display using the parsed config
    var display = cli.Display.init(allocator, config.output_mode, config.color_mode);

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
        // Pass the display instance to the Client
        var client = mdc.Client.init(allocator, address, 0, &display, config.timeout);
        defer client.deinit();

        // Call startCommand here
        display.startCommand(address, @tagName(config.action)) catch |e| {
            // Log error but continue if possible
            std.debug.print("ERROR writing start command message: {}\\n", .{e});
        };

        // Logging the target address can be handled by display.startCommand later
        // if (config.addresses.items.len > 1 or config.verbose) {
        //     std.log.debug("Executing command on {}", .{address});
        // }

        switch (config.action) {
            .on => {
                client.setPower(true) catch continue;
            },
            .off => {
                client.setPower(false) catch continue;
            },
            .reboot => {
                client.reboot() catch continue;
            },
            .volume => {
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
                    client.setVolume(@intCast(volume_value)) catch continue;
                } else {
                    // Get volume
                    const volume = client.getVolume() catch continue;
                    _ = volume;
                }
            },
            .url => {
                if (config.positional_args.items.len > 0) {
                    // Set URL
                    const url = config.getPositionalString(0) orelse {
                        std.log.err("Invalid URL", .{});
                        continue;
                    };
                    client.setLauncherUrl(url) catch continue;
                } else {
                    // Get URL
                    const url = client.getLauncherUrl() catch continue;
                    defer allocator.free(url);
                }
            },
            .serial => {
                const serial = client.getSerial() catch continue;
                defer allocator.free(serial);
            },
            else => {
                // This case should ideally not be reachable if actions are validated
                display.writer.writeAll("Command not implemented\n") catch {};
            },
        }
    }
}
