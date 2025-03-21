const std = @import("std");
const net = std.net;
const testing = std.testing;

const cli = @import("cli.zig");
const MdcClient = @import("client.zig").MdcClient;
const MdcCommand = @import("command.zig").MdcCommand;
const MdcResponse = @import("response.zig").MdcResponse;

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

    // Execute command for each address
    for (config.addresses.items) |address| {
        var client = MdcClient.init(allocator, address, 0); // Default Display ID
        defer client.deinit();

        // Show address if multiple targets
        if (config.addresses.items.len > 1) {
            display.writer.print("Executing on {}\n", .{address}) catch {};
        }

        switch (config.action) {
            .demo => {
                display.showExamples(&client, allocator) catch |err| {
                    display.showError(err);
                };
            },
            .wake => {
                client.setPower(true) catch |err| {
                    display.showError(err);
                };
            },
            .sleep => {
                client.setPower(false) catch |err| {
                    display.showError(err);
                };
            },
            .reboot => {
                client.reboot() catch |err| {
                    display.showError(err);
                };
            },
            else => {},
        }
    }
}
