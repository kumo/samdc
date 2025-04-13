const std = @import("std");
const testing = std.testing;

const mdc = @import("mdc/mod.zig");

pub const CliError = error{
    InvalidArgCount,
    InvalidAddress,
    InvalidAction,
    InvalidFlag,
};

const Action = enum {
    on,
    off,
    reboot,
    volume,
    url,
    help,
    version,
    serial,
    unknown,

    pub fn fromString(s: []const u8) Action {
        const lookup = [_]struct { []const u8, Action }{
            .{ "on", .on },
            .{ "off", .off },
            .{ "reboot", .reboot },
            .{ "volume", .volume },
            .{ "url", .url },
            .{ "help", .help },
            .{ "serial", .serial },
            .{ "serial_num", .serial },
            .{ "serial_number", .serial },
        };

        for (lookup) |entry| {
            if (std.mem.eql(u8, s, entry[0])) {
                return entry[1];
            }
        }
        return .unknown;
    }
};

// Argument types for commands
pub const CommandArg = union(enum) {
    Integer: u32,
    String: []const u8,
    Boolean: bool,

    pub fn asBool(self: CommandArg) bool {
        return switch (self) {
            .Boolean => |b| b,
            .Integer => |i| i > 0,
            .String => |s| s.len > 0,
        };
    }

    pub fn asInteger(self: CommandArg) !u32 {
        return switch (self) {
            .Integer => |i| i,
            .String => |s| std.fmt.parseInt(u32, s, 10) catch return error.InvalidInteger,
            .Boolean => |b| if (b) @as(u32, 1) else @as(u32, 0),
        };
    }

    pub fn asString(self: CommandArg, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self) {
            .String => |s| s,
            .Integer => |i| {
                // Caller must free this buffer
                const buf = try allocator.alloc(u8, 20);
                errdefer allocator.free(buf);
                return std.fmt.bufPrint(buf, "{d}", .{i});
            },
            .Boolean => |b| if (b) "true" else "false",
        };
    }
};

pub const OutputMode = enum {
    Quiet,
    Normal,
    Verbose,
    Json,
};

pub const ColorMode = enum {
    Auto, // Default: Use color if TTY
    Always,
    Never,
};

pub const Config = struct {
    allocator: std.mem.Allocator,
    action: Action,
    addresses: std.ArrayList(std.net.Address),
    positional_args: std.ArrayList(CommandArg),
    timeout: u32 = 5,
    output_mode: OutputMode = .Normal, // Default to Normal
    color_mode: ColorMode = .Auto, // Default to Auto

    pub fn init(allocator: std.mem.Allocator) Config {
        return .{
            .allocator = allocator,
            .action = .unknown,
            .addresses = std.ArrayList(std.net.Address).init(allocator),
            .positional_args = std.ArrayList(CommandArg).init(allocator),
            .timeout = 5,
            .output_mode = .Normal,
            .color_mode = .Auto,
        };
    }

    pub fn deinit(self: *Config) void {
        self.addresses.deinit();
        // Free any string arguments
        for (self.positional_args.items) |arg| {
            if (arg == .String) {
                self.allocator.free(arg.String);
            }
        }
        self.positional_args.deinit();
    }

    pub fn fromArgs(allocator: std.mem.Allocator, args: []const []const u8) !Config {
        if (args.len < 2) {
            return CliError.InvalidArgCount;
        }

        var config = Config.init(allocator);
        errdefer config.deinit();

        var output_mode_set = false;

        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            const arg = args[i];

            if (std.mem.startsWith(u8, arg, "--")) {
                if (std.mem.eql(u8, arg, "--help")) {
                    config.action = .help;
                    return config; // Early return for help
                } else if (std.mem.eql(u8, arg, "--version")) {
                    config.action = .version;
                    return config; // Early return for version
                } else if (std.mem.eql(u8, arg, "--verbose")) {
                    if (output_mode_set and config.output_mode != .Verbose) return error.ConflictingOutputFlags;
                    config.output_mode = .Verbose;
                    output_mode_set = true;
                } else if (std.mem.eql(u8, arg, "--quiet")) {
                    if (output_mode_set and config.output_mode != .Quiet) return error.ConflictingOutputFlags;
                    config.output_mode = .Quiet;
                    output_mode_set = true;
                } else if (std.mem.eql(u8, arg, "--json")) {
                    if (output_mode_set and config.output_mode != .Json) return error.ConflictingOutputFlags;
                    config.output_mode = .Json;
                    output_mode_set = true;
                } else if (std.mem.eql(u8, arg, "--timeout")) {
                    // Check if a value exists after the flag
                    if (i + 1 >= args.len) {
                        std.log.warn("Missing value for --timeout flag", .{});
                        return CliError.InvalidFlag;
                    }
                    const timeout_str = args[i + 1];
                    // Try parsing, mapping errors to InvalidFlag
                    const parsed_timeout = std.fmt.parseInt(u32, timeout_str, 10) catch |err| {
                        std.log.warn("Invalid value for --timeout flag: '{s}' ({s})", .{ timeout_str, @errorName(err) });
                        return CliError.InvalidFlag;
                    };

                    // Validate the parsed value (must be > 0)
                    if (parsed_timeout == 0) {
                        std.log.warn("Timeout value must be greater than zero, got {d}", .{parsed_timeout});
                        return CliError.InvalidFlag;
                    }

                    // Validate upper bound
                    if (parsed_timeout > 120) {
                        std.log.warn("Timeout value must be less than 120 seconds, got {d}", .{parsed_timeout});
                        return CliError.InvalidFlag;
                    }

                    config.timeout = parsed_timeout;
                    i += 1; // Consume the value argument as well
                } else if (std.mem.eql(u8, arg, "--color")) {
                    if (i + 1 >= args.len) return error.InvalidFlag; // Missing value
                    const color_arg = args[i + 1];
                    if (std.mem.eql(u8, color_arg, "auto")) {
                        config.color_mode = .Auto;
                    } else if (std.mem.eql(u8, color_arg, "always")) {
                        config.color_mode = .Always;
                    } else if (std.mem.eql(u8, color_arg, "never")) {
                        config.color_mode = .Never;
                    } else {
                        std.log.warn("Invalid value for --color: '{s}'. Use 'auto', 'always', or 'never'.", .{color_arg});
                        return error.InvalidFlag;
                    }
                    i += 1;
                } else {
                    std.log.warn("Unknown flag: {s}", .{arg});
                    return CliError.InvalidFlag;
                }
                continue;
            }

            if (std.mem.startsWith(u8, arg, "-")) {
                if (std.mem.eql(u8, arg, "-h")) {
                    config.action = .help;
                    return config;
                } else if (std.mem.eql(u8, arg, "-v")) { // Treat -v as --verbose
                    if (output_mode_set and config.output_mode != .Verbose) return error.ConflictingOutputFlags;
                    config.output_mode = .Verbose;
                    output_mode_set = true;
                } else if (std.mem.eql(u8, arg, "-q")) { // Treat -q as --quiet
                    if (output_mode_set and config.output_mode != .Quiet) return error.ConflictingOutputFlags;
                    config.output_mode = .Quiet;
                    output_mode_set = true;
                } else {
                    std.log.warn("Unknown short flag: {s}", .{arg});
                    return CliError.InvalidFlag;
                }
                continue;
            }

            // First non-flag argument is the action - use 'arg' directly
            if (config.action == .unknown) {
                config.action = Action.fromString(arg);
                if (config.action == .unknown) {
                    return CliError.InvalidAction;
                }
                continue;
            }

            // Try to parse as IP address - use 'arg' directly
            if (std.net.Address.parseIp4(arg, 1515)) |address| {
                try config.addresses.append(address);
                continue;
            } else |_| {}

            // Handle positional arguments
            // Try to parse as integer first - use 'arg' directly
            if (std.fmt.parseInt(u32, arg, 10)) |int_val| {
                try config.positional_args.append(.{ .Integer = int_val });
            } else |_| {
                // Make a copy of the string - use 'arg' directly
                const str_copy = try allocator.dupe(u8, arg);
                // errdefer allocator.free(str_copy); // Keep errdefer for the dupe call itself
                // Important: The 'errdefer' for freeing str_copy should remain here
                // in case the *subsequent* append call fails.
                // If fromArgs itself fails later, config.deinit() handles freeing.
                errdefer allocator.free(str_copy);
                try config.positional_args.append(.{ .String = str_copy });
            }
        }

        if (config.action == .unknown) {
            return CliError.InvalidAction;
        }

        // Ensure we have at least one address for non-special actions
        if (config.action != .help and config.action != .version and config.addresses.items.len == 0) {
            return CliError.InvalidAddress;
        }

        return config;
    }

    // Helper methods to get arguments
    pub fn getPositionalInteger(self: Config, index: usize) ?u32 {
        if (index < self.positional_args.items.len) {
            const arg = self.positional_args.items[index];
            return arg.asInteger() catch |err| {
                std.log.err("Integer conversion error: {}", .{err});
                return null;
            };
        }
        return null;
    }

    pub fn getPositionalString(self: Config, index: usize) ?[]const u8 {
        if (index < self.positional_args.items.len) {
            const arg = self.positional_args.items[index];
            if (arg == .String) {
                return arg.String;
            }
        }
        return null;
    }
};

pub const Display = struct {
    writer: std.fs.File.Writer,
    err_writer: std.fs.File.Writer, // Add stderr writer
    allocator: std.mem.Allocator, // Add allocator
    output_mode: OutputMode,
    color_mode: ColorMode,
    use_color: bool, // Determined by color_mode and TTY checks

    const VERSION = "0.1.2";

    pub fn init(
        allocator: std.mem.Allocator,
        output_mode: OutputMode,
        color_mode: ColorMode,
    ) Display {
        const stdout = std.io.getStdOut();
        const stderr = std.io.getStdErr();

        // Determine if color should be used based on mode and TTY status
        var use_color = switch (color_mode) {
            .Always => true,
            .Never => false,
            .Auto => stdout.supportsAnsiEscapeCodes(),
        };

        // Quiet mode should generally not use color by default, even if TTY
        if (output_mode == .Quiet and color_mode == .Auto) {
            use_color = false;
        }

        return Display{
            .writer = stdout.writer(),
            .err_writer = stderr.writer(),
            .allocator = allocator,
            .output_mode = output_mode,
            .color_mode = color_mode,
            .use_color = use_color,
        };
    }

    // New: Simple initializer for early errors before config is parsed
    pub fn init_simple(allocator: std.mem.Allocator) Display {
        // Defaults to Normal output, Auto color (which likely becomes Never due to checks)
        // Only purpose is to get err_writer working for showError
        return Display.init(allocator, .Normal, .Auto);
    }

    // --- Placeholder Methods ---
    // (Actual implementation to follow)

    pub fn startCommand(self: *Display, ip: std.net.Address, action_name: []const u8) !void {
        _ = self;
        _ = ip;
        _ = action_name;
        // TODO: Print start message based on output_mode (Normal/Verbose)
    }

    pub fn logCommand(self: *Display, command: *const mdc.Command, raw_tx_bytes: []const u8) !void {
        switch (self.output_mode) {
            .Quiet => return, // Do nothing in quiet mode
            .Json => {
                // For JSON, only log packets to stderr if verbose is also enabled
                // TODO: Need to check if verbose is actually enabled when mode is Json.
                // We need to adjust how modes are stored/checked. For now, assume Json mode means non-verbose stderr.
                // Let's refine this when implementing full `--json --verbose`.
                // For now, JSON means no packet logging to stdout/stderr.
                return;
            },
            .Normal, .Verbose => {
                // Determine the writer (currently always stdout for Normal/Verbose)
                const writer = self.writer;

                // Get the placeholder annotated packet string
                const annotated_string = self.formatAnnotatedPacket(.Tx, command, null) catch |err| {
                    // Log formatting errors to stderr
                    self.err_writer.print("Error formatting TX packet: {s}\n", .{@errorName(err)}) catch {};
                    return; // Don't proceed if formatting failed
                };
                defer self.allocator.free(annotated_string);

                // Print the annotated packet
                // TODO: Add tree/box formatting prefixes later
                try writer.print("{s}\n", .{annotated_string});

                // If verbose, also print the hex dump
                if (self.output_mode == .Verbose) {
                    const hex_dump = self.formatHexDump(raw_tx_bytes) catch |err| {
                        self.err_writer.print("Error formatting TX hex dump: {s}\n", .{@errorName(err)}) catch {};
                        return;
                    };
                    defer self.allocator.free(hex_dump);
                    // TODO: Add indentation later
                    try writer.print("  {s}\n", .{hex_dump});
                }
            },
        }
    }

    pub fn logResponse(self: *Display, response: *const mdc.Response) !void {
        switch (self.output_mode) {
            .Quiet => return,
            .Json => {
                // As with logCommand, JSON currently means no packet logging to stdout/stderr.
                // TODO: Refine for --json --verbose later.
                return;
            },
            .Normal, .Verbose => {
                const writer = self.writer;

                // Format annotated packet using the Response struct
                const annotated_string = self.formatAnnotatedPacket(.Rx, null, response) catch |err| {
                    self.err_writer.print("Error formatting RX packet: {s}\n", .{@errorName(err)}) catch {};
                    return;
                };
                defer self.allocator.free(annotated_string);

                // Print annotated packet
                try writer.print("{s}\n", .{annotated_string});

                // If verbose, print hex dump using raw bytes stored in Response
                if (self.output_mode == .Verbose) {
                    const hex_dump = self.formatHexDump(response.raw_packet_alloc) catch |err| {
                        self.err_writer.print("Error formatting RX hex dump: {s}\n", .{@errorName(err)}) catch {};
                        return;
                    };
                    defer self.allocator.free(hex_dump);
                    try writer.print("  {s}\n", .{hex_dump});
                }
            },
        }
    }

    // Need a structure to pass result data, similar to ActionResult
    pub const ResultData = struct {
        // TODO: Define fields: status (success/error), value (union?), error_type, error_message?
        // This might become similar to handlers.ActionResult later
        placeholder: void = {},
    };

    pub fn finalizeResult(self: *Display, ip: std.net.Address, result: ResultData) !void {
        _ = self;
        _ = ip;
        _ = result;
        // TODO: Print final status line based on output_mode (Quiet/Normal/Verbose/Json)
        // If JSON, call jsonStringify on result data.
    }

    // --- Existing Methods (May need slight adjustment) ---

    pub fn printUsage(self: *Display) void {
        // Print to stdout
        self.writer.print(
            \\Usage: samdc [options] <action> [IP addresses...] [action args...]
            \\
            \\Actions:
            \\  on                Turn device on
            \\  off               Turn device off
            \\  reboot            Reboot device 
            \\  volume [level]    Get or set volume (0-100)
            \\  url [new_url]     Get or set launcher URL
            \\  serial            Get serial number
            \\  help              Show this help message
            \\  version           Show version information
            \\
            \\Options:
            \\  --help, -h       Show this help message
            \\  --version         Show version information
            \\  --verbose, -v     Enable verbose output
            \\  --quiet, -q       Enable quiet output (minimal info)
            \\  --json            Output results as newline-delimited JSON
            \\  --timeout <secs>  Set connection timeout in seconds (default: 5)
            \\  --color <mode>    Set color output mode: auto, always, never (default: auto)
            \\  IP addresses      One or more IP addresses of the target devices
            \\
            \\Examples:
            \\  samdc reboot 192.168.1.1                  # Reboot single device
            \\  samdc on 192.168.1.1 192.168.1.2          # Turn on multiple device
            \\  samdc volume 50 192.168.1.1 192.168.1.2   # Set volume on multiple devices
            \\  samdc url http://example.com 192.168.1.1  # Set URL on a device
        , .{}) catch |e| {
            std.debug.print("Error printing usage: {s}\n", .{@errorName(e)});
        };
    }

    pub fn showVersion(self: *Display) void {
        // Print to stdout
        self.writer.print("samdc version {s}\n", .{VERSION}) catch |e| {
            std.debug.print("Error printing version: {s}\n", .{@errorName(e)});
        };
    }

    pub fn showError(self: *Display, err: anyerror) void {
        // Always print errors to stderr
        // TODO: Add color support if self.use_color is true
        self.err_writer.print("Error: {s}\n", .{@errorName(err)}) catch |e| {
            // If we can't even print to stderr, print to debug log
            std.debug.print("Critical error writing to stderr: {s}\n", .{@errorName(e)});
            std.debug.print("Original error was: {s}\n", .{@errorName(err)});
        };
    }

    // --- Internal Helpers (To be implemented) ---
    fn formatAnnotatedPacket(self: *Display, direction: enum { Tx, Rx }, maybe_command: ?*const mdc.Command, maybe_response: ?*const mdc.Response) ![]u8 {
        // _ = self; // Removed pointless discard
        _ = direction;
        _ = maybe_command;
        _ = maybe_response;
        // TODO: Implement actual annotation logic using allocator
        return self.allocator.dupe(u8, "TODO: Annotated Packet");
    }

    fn formatHexDump(self: *Display, bytes: []const u8) ![]u8 {
        // _ = self; // Removed pointless discard
        _ = bytes;
        // TODO: Implement actual hex dump logic using allocator
        return self.allocator.dupe(u8, "TODO: Hex Dump");
    }
};

test "Parse simple command" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "on", "192.168.1.10" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    try testing.expectEqual(Action.on, config.action);
    try testing.expectEqual(@as(usize, 1), config.addresses.items.len);
    const expected_addr = try std.net.Address.parseIp4("192.168.1.10", 1515);
    try testing.expect(expected_addr.eql(config.addresses.items[0]));
    try testing.expectEqual(@as(usize, 0), config.positional_args.items.len);
}

test "Parse command with numeric arg" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "volume", "75", "10.0.0.1" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    try testing.expectEqual(Action.volume, config.action);
    try testing.expectEqual(@as(usize, 1), config.addresses.items.len);
    const expected_addr = try std.net.Address.parseIp4("10.0.0.1", 1515);
    try testing.expect(expected_addr.eql(config.addresses.items[0]));
    try testing.expectEqual(@as(usize, 1), config.positional_args.items.len);
    const vol_arg = config.positional_args.items[0];
    try testing.expectEqualStrings("Integer", @tagName(vol_arg));
    try testing.expectEqual(@as(u32, 75), try vol_arg.asInteger());
}

test "Parse command with text arg" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "url", "http://example.com", "10.0.0.1" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit(); // deinit will free the duped string

    try testing.expectEqual(Action.url, config.action);
    try testing.expectEqual(@as(usize, 1), config.addresses.items.len);
    const expected_addr = try std.net.Address.parseIp4("10.0.0.1", 1515);
    try testing.expect(expected_addr.eql(config.addresses.items[0]));
    try testing.expectEqual(@as(usize, 1), config.positional_args.items.len);
    const url_arg = config.positional_args.items[0];
    try testing.expectEqualStrings("String", @tagName(url_arg));
    try testing.expectEqualStrings("http://example.com", url_arg.String);
}

test "Parse simple command with multiple IPs" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "off", "192.168.1.10", "192.168.1.11" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    try testing.expectEqual(Action.off, config.action);
    try testing.expectEqual(@as(usize, 2), config.addresses.items.len);
    const expected_addr1 = try std.net.Address.parseIp4("192.168.1.10", 1515);
    const expected_addr2 = try std.net.Address.parseIp4("192.168.1.11", 1515);
    try testing.expect(expected_addr1.eql(config.addresses.items[0]));
    try testing.expect(expected_addr2.eql(config.addresses.items[1]));
    try testing.expectEqual(@as(usize, 0), config.positional_args.items.len);
}

test "Parse command with verbose flag" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--verbose", "on", "192.168.1.10" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();
    try testing.expectEqual(Action.on, config.action);
}

test "Parse command with short verbose flag" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "-v", "on", "192.168.1.10" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();
    try testing.expectEqual(Action.on, config.action);
}

test "Parse help flag" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--help" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();
    try testing.expectEqual(Action.help, config.action);
}

test "Parse short help flag" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "-h" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();
    try testing.expectEqual(Action.help, config.action);
}

test "Help flag should take precendence" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "on", "192.168.1.1", "--help" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();
    try testing.expectEqual(Action.help, config.action);
}

test "Parse version flag" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--version" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();
    try testing.expectEqual(Action.version, config.action);
}

test "Parse invalid action" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "invalidaction", "192.168.1.1" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidAction, result);
}

test "Parse invalid flag" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--invalidflag", "on", "192.168.1.1" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidFlag, result);
}

test "Parse invalid short flag" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "-x", "on", "192.168.1.1" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidFlag, result);
}

test "Parse missing ip address (for non-help/version)" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "on" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidAddress, result);
}

test "Parse missing action" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "192.168.1.1" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidAction, result);
}

test "Parse flag without action" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--verbose" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidAction, result);
}

test "Parse no arguments" {
    const allocator = testing.allocator;

    const args1 = [_][]const u8{"samdc"};
    const result1 = Config.fromArgs(allocator, &args1);
    try testing.expectError(CliError.InvalidArgCount, result1);
}

test "Parse mixed positional args and addresses" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "url", "http://a.com", "10.0.0.1", "some_string", "50", "10.0.0.2" };
    // Parses as: action=url, pos="http://a.com", addr=10.0.0.1, pos="some_string", pos=50, addr=10.0.0.2
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    try testing.expectEqual(Action.url, config.action);
    try testing.expectEqual(@as(usize, 2), config.addresses.items.len);
    const expected_addr1 = try std.net.Address.parseIp4("10.0.0.1", 1515);
    const expected_addr2 = try std.net.Address.parseIp4("10.0.0.2", 1515);
    try testing.expect(expected_addr1.eql(config.addresses.items[0]));
    try testing.expect(expected_addr2.eql(config.addresses.items[1]));

    try testing.expectEqual(@as(usize, 3), config.positional_args.items.len);
    // arg 0: "http://a.com" (String)
    const arg0 = config.positional_args.items[0];
    try testing.expectEqualStrings("String", @tagName(arg0));
    try testing.expectEqualStrings("http://a.com", arg0.String);
    // arg 1: "some_string" (String)
    const arg1 = config.positional_args.items[1];
    try testing.expectEqualStrings("String", @tagName(arg1));
    try testing.expectEqualStrings("some_string", arg1.String);
    // arg 2: 50 (Integer)
    const arg2 = config.positional_args.items[2];
    try testing.expectEqualStrings("Integer", @tagName(arg2));
    try testing.expectEqual(@as(u32, 50), try arg2.asInteger());
}

test "Parse timeout flag" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--timeout", "10", "on", "192.168.1.1" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    try testing.expectEqual(10, config.timeout);
}

test "Parse timeout flag with non-integer value" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--timeout", "not_an_integer", "on", "192.168.1.1" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidFlag, result);
}

test "Parse timeout flag with negative value" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--timeout", "-1", "on", "192.168.1.1" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidFlag, result);
}

test "Parse timeout flag with zero value" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--timeout", "0", "on", "192.168.1.1" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidFlag, result);
}

test "Parse timeout flag with large value" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--timeout", "1000000", "on", "192.168.1.1" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidFlag, result);
}

test "Parse timeout flag without a value" {
    const allocator = testing.allocator;

    const args = [_][]const u8{ "samdc", "--timeout", "on", "192.168.1.1" };
    const result = Config.fromArgs(allocator, &args);
    try testing.expectError(CliError.InvalidFlag, result);
}
