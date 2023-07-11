const objz = @import("objz");
const objc = @import("objc");

pub fn Id(comptime Protocol_: type) type {
    return struct {
        pub const Protocol = Protocol_;
        const Self = @This();
        const is_id = true;

        __object: objc.Object,

        pub usingnamespace Protocol_.InstanceMethods(Self);

        pub fn __call(self: Self, comptime ReturnType: type, selector: objc.Sel, args: anytype) ReturnType {
            if (ReturnType == Self) {
                const instance = self.__object.msgSend(objc.Object, selector, args);
                return Self{ .__object = instance };
            } else {
                return self.__object.msgSend(ReturnType, selector, args);
            }
        }

        pub fn from(instance: anytype) Self {
            const Instance = @TypeOf(instance);
            if (@hasDecl(Instance, "Protocol") and @hasDecl(Instance, "is_id")) {
                inline for (Instance.Protocol.conforms_to) |proto| {
                    if (proto == Protocol_) return .{ .__object = instance.__object };
                }
            }

            comptime {
                var found = false;
                inline for (Instance.conforms_to) |proto| {
                    if (proto == Protocol_) {
                        found = true;
                        break;
                    }
                }

                if (!found) @compileLog(Instance, "does not conform to", Protocol_, "protocol");
            }

            return .{ .__object = instance.__object };
        }
    };
}
