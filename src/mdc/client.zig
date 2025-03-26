const std = @import("std");
const net = std.net;

const mdc = @import("mod.zig");

pub const Client = struct {
    allocator: std.mem.Allocator,
    address: net.Address,
    display_id: u8,
    socket: ?net.Stream,

    pub fn init(allocator: std.mem.Allocator, address: net.Address, display_id: u8) Client {
        return Client{
            .allocator = allocator,
            .address = address,
            .display_id = display_id,
            .socket = null,
        };
    }

    pub fn deinit(self: *Client) void {
        if (self.socket) |*s| {
            s.close();
        }
    }

    fn connect(self: *Client) !void {
        if (self.socket != null) {
            // Already connected
            return;
        }

        const socket = try net.tcpConnectToAddress(self.address);

        self.socket = socket;
    }

    fn disconnect(self: *Client) void {
        if (self.socket) |*s| {
            s.close();
            self.socket = null;
        }
    }

    fn sendCommand(
        self: *Client,
        command: mdc.Command,
    ) !mdc.Response {
        try self.connect();

        // Create command packet
        const cmd_packet = try command.serialize(self.allocator);
        defer self.allocator.free(cmd_packet);

        std.debug.print("Command: {any}\n", .{command});
        printBytes(cmd_packet);

        // Send the command
        if (self.socket) |s| {
            _ = try s.write(cmd_packet);

            // Read response
            var buffer: [1024]u8 = undefined;
            const bytes_read = try s.read(&buffer);

            if (bytes_read == 0) {
                return mdc.Error.ReceiveFailed;
            }

            // Parse the response, let caller deinit
            const response = try mdc.Response.init(buffer[0..bytes_read], self.allocator);
            std.debug.print("Response: {any}\n", .{response});
            printBytes(buffer[0..bytes_read]);

            // Check if response is NAK
            if (response.response_type == .Nak) {
                return mdc.Error.NakReceived;
            }

            return response;
        } else {
            return mdc.Error.ConnectionFailed;
        }
    }

    // Power control
    pub fn getPowerStatus(self: *Client) !bool {
        const command = mdc.Command.init(.{ .Power = .Status }, self.display_id);

        var response = try self.sendCommand(command);
        defer response.deinit();

        return response.getPowerStatus();
    }

    pub fn setPower(self: *Client, on: bool) !void {
        const command = if (on)
            mdc.Command.init(.{ .Power = .{ .Set = .On } }, self.display_id)
        else
            mdc.Command.init(.{ .Power = .{ .Set = .Off } }, self.display_id);
        var response = try self.sendCommand(command);
        defer response.deinit();
    }

    pub fn reboot(self: *Client) !void {
        const command = mdc.Command.init(.{ .Power = .{ .Set = .Reboot } }, self.display_id);

        var response = try self.sendCommand(command);
        defer response.deinit();
    }

    // Launcher URL
    pub fn setLauncherUrl(self: *Client, url: []const u8) !void {
        const command = mdc.Command.init(.{ .LauncherUrl = .{ .Set = url } }, self.display_id);

        var response = try self.sendCommand(command);
        defer response.deinit();
    }

    pub fn getLauncherUrl(self: *Client) ![]const u8 {
        const command = mdc.Command.init(.{ .LauncherUrl = .Status }, self.display_id);

        var response = try self.sendCommand(command);
        defer response.deinit();

        const url = try response.getLauncherUrl();
        return try self.allocator.dupe(u8, url);
    }

    // Volume control
    pub fn getVolume(self: *Client) !u8 {
        const command = mdc.Command.init(.{ .Volume = .Status }, self.display_id);

        var response = try self.sendCommand(command);
        defer response.deinit();

        return response.getVolume();
    }

    pub fn setVolume(self: *Client, level: u8) !void {
        if (level > 100) return mdc.Error.InvalidParameter;

        const command = mdc.Command.init(.{ .Volume = .{ .Set = level } }, self.display_id);

        var response = try self.sendCommand(command);
        defer response.deinit();
    }
};

fn printBytes(bytes: []u8) void {
    std.debug.print("[ ", .{});
    for (bytes) |byte| {
        if (std.ascii.isPrint(byte)) {
            std.debug.print("{X:0>2} ({c}) ", .{ byte, byte });
        } else {
            std.debug.print("{X:0>2} ", .{byte});
        }
    }
    std.debug.print("]\n", .{});
}
