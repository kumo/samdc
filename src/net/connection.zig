const std = @import("std");

pub const ConnectionError = error{
    ConnectionFailed,
    ConnectionTimeout,
    WriteTimeout,
    ReadTimeout,
    ReceiveFailed,
};

pub const Connection = struct {
    address: std.net.Address,
    socket: ?std.net.Stream,
    timeout_seconds: u32,

    pub fn init(address: std.net.Address, timeout_seconds: u32) Connection {
        return .{
            .address = address,
            .socket = null,
            .timeout_seconds = timeout_seconds,
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

        const sock = try std.posix.socket(
            std.posix.AF.INET,
            std.posix.SOCK.STREAM | std.posix.SOCK.NONBLOCK,
            std.posix.IPPROTO.TCP,
        );
        errdefer std.posix.close(sock);

        // Non-blocking connect with timeout
        std.posix.connect(sock, &self.address.any, self.address.getOsSockLen()) catch |err| {
            if (err == error.WouldBlock) {
                try self.waitForConnection(sock);
            } else {
                return err;
            }
        };

        self.socket = std.net.Stream{ .handle = sock };
    }

    pub fn disconnect(self: *Connection) void {
        if (self.socket) |*s| {
            s.close();
            self.socket = null;
        }
    }

    pub fn send(self: *Connection, data: []const u8) !void {
        try self.connect();

        if (self.socket) |s| {
            // Wait for write ready with timeout
            if (!try self.waitForIO(s.handle, std.posix.POLL.OUT)) {
                return error.WriteTimeout;
            }
            _ = try s.write(data);
        } else {
            return error.ConnectionFailed;
        }
    }

    pub fn receive(self: *Connection, buffer: []u8) !usize {
        if (self.socket) |s| {
            // Wait for read ready with timeout
            if (!try self.waitForIO(s.handle, std.posix.POLL.IN)) {
                return error.ReadTimeout;
            }
            const bytes_read = try s.read(buffer);
            if (bytes_read == 0) {
                return error.ReceiveFailed;
            }
            return bytes_read;
        } else {
            return error.ConnectionFailed;
        }
    }

    fn waitForConnection(self: *Connection, sock: std.posix.socket_t) !void {
        if (!try self.waitForIO(sock, std.posix.POLL.OUT)) {
            return error.ConnectionTimeout;
        }

        // Check if connection was successful
        var err_val: i32 = 0;
        try std.posix.getsockopt(
            sock,
            std.posix.SOL.SOCKET,
            std.posix.SO.ERROR,
            std.mem.asBytes(&err_val),
        );

        if (err_val != 0) {
            return error.ConnectionFailed;
        }
    }

    fn waitForIO(self: *Connection, sock: std.posix.socket_t, events: i16) !bool {
        var pfd = std.posix.pollfd{
            .fd = sock,
            .events = events,
            .revents = 0,
        };

        const ready = try std.posix.poll(@as([*]std.posix.pollfd, @ptrCast(&pfd))[0..1], @as(i32, @intCast(self.timeout_seconds * 1000)));
        return ready != 0;
    }
};
