const std = @import("std");
const net = std.net;

const mdc = @import("mod.zig");
const cli = @import("../cli.zig");
const Connection = @import("../net/connection.zig").Connection;
const command_def = @import("command.zig");

pub const Client = struct {
    allocator: std.mem.Allocator,
    conn: Connection,
    display_id: u8,
    display: *cli.Display,

    pub fn init(allocator: std.mem.Allocator, address: net.Address, display_id: u8, display: *cli.Display, timeout: u32) Client {
        return Client{
            .allocator = allocator,
            .conn = Connection.init(address, timeout),
            .display_id = display_id,
            .display = display,
        };
    }

    pub fn deinit(self: *Client) void {
        self.conn.deinit();
    }

    fn sendCommandAndLog(
        self: *Client,
        command: mdc.Command,
    ) !mdc.Response {
        try self.conn.connect();

        const raw_tx_bytes = try command.serialize(self.allocator);
        defer self.allocator.free(raw_tx_bytes);

        try self.display.logCommand(&command, raw_tx_bytes);

        _ = try self.conn.send(raw_tx_bytes);

        var buffer: [1024]u8 = undefined;
        const bytes_read = try self.conn.receive(&buffer);
        const raw_rx_bytes_slice = buffer[0..bytes_read];

        var response = try mdc.Response.init(raw_rx_bytes_slice, self.allocator);
        errdefer response.deinit();

        try self.display.logResponse(&response);

        if (response.response_type == .Nak) {
            // Clean up allocated memory before returning error
            response.deinit();
            return mdc.Error.NakReceived;
        }

        return response;
    }

    pub fn getPowerStatus(self: *Client) !bool {
        const command = mdc.Command.init(.{ .Power = .Status }, self.display_id);
        var response = try self.sendCommandAndLog(command);
        defer response.deinit();
        const status = try response.getPowerStatus();
        return status;
    }

    pub fn setPower(self: *Client, on: bool) !void {
        const cmd_data: command_def.CommandData = if (on)
            .{ .Power = .{ .Set = .On } }
        else
            .{ .Power = .{ .Set = .Off } };

        const command = mdc.Command.init(cmd_data, self.display_id);
        var response = try self.sendCommandAndLog(command);
        defer response.deinit();
    }

    pub fn reboot(self: *Client) !void {
        const command = mdc.Command.init(.{ .Power = .{ .Set = .Reboot } }, self.display_id);
        var response = try self.sendCommandAndLog(command);
        defer response.deinit();
    }

    pub fn setLauncherUrl(self: *Client, url: []const u8) !void {
        const command = mdc.Command.init(.{ .LauncherUrl = .{ .Set = url } }, self.display_id);
        var response = try self.sendCommandAndLog(command);
        defer response.deinit();
    }

    pub fn getLauncherUrl(self: *Client) ![]const u8 {
        const command = mdc.Command.init(.{ .LauncherUrl = .Status }, self.display_id);
        var response = try self.sendCommandAndLog(command);
        defer response.deinit();
        const url = try response.getLauncherUrl();
        const owned_url = try self.allocator.dupe(u8, url);
        return owned_url;
    }

    pub fn getVolume(self: *Client) !u8 {
        const command = mdc.Command.init(.{ .Volume = .Status }, self.display_id);
        var response = try self.sendCommandAndLog(command);
        defer response.deinit();
        const volume = try response.getVolume();
        return volume;
    }

    pub fn setVolume(self: *Client, level: u8) !void {
        if (level > 100) return mdc.Error.InvalidParameter;
        const command = mdc.Command.init(.{ .Volume = .{ .Set = level } }, self.display_id);
        var response = try self.sendCommandAndLog(command);
        defer response.deinit();
    }

    pub fn getSerial(self: *Client) ![]const u8 {
        const command = mdc.Command.init(.{ .Serial = .Status }, self.display_id);
        var response = try self.sendCommandAndLog(command);
        defer response.deinit();
        const serial = try response.getSerial();
        const owned_serial = try self.allocator.dupe(u8, serial);
        return owned_serial;
    }
};
