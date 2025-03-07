const std = @import("std");
const net = std.net;

const MdcCommand = @import("command.zig").MdcCommand;
const MdcError = @import("protocol.zig").MdcError;
const MdcResponse = @import("response.zig").MdcResponse;

pub const MdcClient = struct {
    allocator: std.mem.Allocator,
    address: net.Address,
    display_id: u8,
    socket: ?net.Stream,

    pub fn init(allocator: std.mem.Allocator, address: net.Address, display_id: u8) !MdcClient {
        return MdcClient{
            .allocator = allocator,
            .address = address,
            .display_id = display_id,
            .socket = null,
        };
    }

    pub fn deinit(self: *MdcClient) void {
        if (self.socket) |*s| {
            s.close();
        }
    }

    fn connect(self: *MdcClient) !void {
        if (self.socket != null) {
            // Already connected
            return;
        }

        const socket = try net.tcpConnectToAddress(self.address);

        self.socket = socket;
    }

    fn disconnect(self: *MdcClient) void {
        if (self.socket) |*s| {
            s.close();
            self.socket = null;
        }
    }

    fn sendCommand(
        self: *MdcClient,
        command: MdcCommand,
    ) !MdcResponse {
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
                return MdcError.ReceiveFailed;
            }

            // Parse the response, let caller deinit
            const response = try MdcResponse.init(buffer[0..bytes_read], self.allocator);
            std.debug.print("Response: {any}\n", .{response});
            printBytes(buffer[0..bytes_read]);

            // Check if response is NAK
            if (response.response_type == .Nak) {
                return MdcError.NakReceived;
            }

            return response;
        } else {
            return MdcError.ConnectionFailed;
        }
    }

    // Power control
    pub fn getPowerStatus(self: *MdcClient) !bool {
        const command = MdcCommand.init(.{ .Power = .Status }, self.display_id);

        var response = try self.sendCommand(command);
        defer response.deinit();

        return response.getPowerStatus();
    }

    pub fn setPower(self: *MdcClient, on: bool) !void {
        const command = MdcCommand.init(.{ .Power = .{ .Set = on } }, self.display_id);

        var response = try self.sendCommand(command);
        defer response.deinit();
    }

    // Launcher URL
    pub fn setLauncherUrl(self: *MdcClient, url: []const u8) !void {
        const command = MdcCommand.init(.{ .LauncherUrl = .{ .Set = url } }, self.display_id);

        var response = try self.sendCommand(command);
        defer response.deinit();
    }

    pub fn getLauncherUrl(self: *MdcClient) ![]const u8 {
        const command = MdcCommand.init(.{ .LauncherUrl = .Status }, self.display_id);

        var response = try self.sendCommand(command);
        defer response.deinit();

        const url = try response.getLauncherUrl();
        return try self.allocator.dupe(u8, url);
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
