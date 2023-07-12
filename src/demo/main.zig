const std = @import("std");
// const demo = @import("demo.zig");
// const objz = @import("objz");

pub fn main() !void {
    // var myname = objz.NSString.allocStaticStr("Umur Gedik");
    // const inst = demo.MyClass.alloc().initWithNameAndInt(myname, 31);

    // std.log.debug("My name is: {s}", .{
    //     inst.name().cStringUsingEncoding(objz.NSString.Encoding.utf8),
    // });
    // std.log.debug("My age is: {d}", .{inst.age()});

    // inst.setAge(32);

    // std.log.debug("My age next month: {d}", .{inst.age()});

    // const conformant = objz.Id(demo.SomeProtocol).from(inst);
    // _ = conformant.someMethod(objz.Id(objz.NSObject).from(conformant));

    // const another = demo.AnotherClass.alloc().init();
    // another.blit(demo.MTLBlitOption.depthFromDepthStencil | demo.MTLBlitOption.stencilFromDepthStencil);
}
