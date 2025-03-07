pub const MdcError = error{
    PacketTooShort,
    InvalidResponseType,
    InvalidCommand,
    InvalidDataLength,
    InvalidChecksum,
    WrongCommandType,
    InvalidHeader,
    DataTooLong,
    BufferTooSmall,
    ReceiveFailed,
    NakReceived,
    ConnectionFailed,
};

pub const CommandType = enum(u8) {
    Power = 0x11,
    LauncherUrl = 0xC7,
};
