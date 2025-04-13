pub const Client = @import("client.zig").Client;
pub const Command = @import("command.zig").Command;
pub const Protocol = @import("protocol.zig");
pub const CommandType = Protocol.CommandType;
pub const Error = Protocol.Error;
pub const Response = @import("response.zig").Response;

// Export PacketAnnotator and related types
pub const PacketAnnotator = @import("packet_annotator.zig").PacketAnnotator;
