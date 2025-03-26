const std = @import("std");

pub const ConnectionError = error{
    ConnectionFailed,
    ReceiveFailed,
};

pub const Connection = struct {
    address: std.net.Address,
    socket: ?std.net.Stream,

    pub fn init(address: std.net.Address) Connection {
        return Connection{
            .address = address,
            .socket = null,
        };
    }

    pub fn deinit(self: *Connection) void {
        self.disconnect();
    }

    pub fn connect(self: *Connection) !void {
        if (self.socket != null) {
            // Already connected
            return;
        }

        const socket = try std.net.tcpConnectToAddress(self.address);

        self.socket = socket;
    }

    fn disconnect(self: *Connection) void {
        if (self.socket) |*s| {
            s.close();
            self.socket = null;
        }
    }

    pub fn send(self: *Connection, data: []const u8) !void {
        try self.connect();

        if (self.socket) |s| {
            _ = try s.write(data);
        } else {
            return error.ConnectionFailed;
        }
    }

    pub fn receive(self: *Connection, buffer: []u8) !usize {
        if (self.socket) |s| {
            const bytes_read = try s.read(buffer);

            if (bytes_read == 0) {
                return error.ReceiveFailed;
            }

            return bytes_read;
        } else {
            return error.ConnectionFailed;
        }
    }
};
