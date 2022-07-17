const std = @import("std");
const win = std.os.windows;

const IMC_GETOPENSTATUS: win.WPARAM = 0x0005;
const IMC_SETOPENSTATUS: win.WPARAM = 0x0006;

extern "user32" fn GetForegroundWindow() callconv(win.WINAPI) ?win.HWND;
extern "user32" fn SendMessageA(hWnd: ?win.HANDLE, msg: win.UINT, wParam: win.WPARAM, lParam: win.LPARAM) callconv(win.WINAPI) win.LRESULT;
extern "imm32" fn ImmGetDefaultIMEWnd(hWnd: ?win.HWND) callconv(win.WINAPI) ?win.HWND;
extern "shell32" fn CommandLineToArgvW(lpCmdLine: win.LPCWSTR, pNumArgs: *c_int) callconv(win.WINAPI) [*]win.LPWSTR;

fn imControl(hWnd: ?win.HWND, wParam: win.WPARAM, lParam: win.LPARAM) win.LRESULT {
    return SendMessageA(hWnd, win.user32.WM_IME_CONTROL, wParam, lParam);
}

fn imGetStatus(hWnd: ?win.HWND) isize {
    return imControl(hWnd, IMC_GETOPENSTATUS, 0);
}

fn imSetStatus(hWnd: ?win.HWND, status: isize) void {
    _ = imControl(hWnd, IMC_SETOPENSTATUS, status);
}

pub fn main() !void {
    if (GetForegroundWindow()) |hWnd| {
        if (ImmGetDefaultIMEWnd(hWnd)) |hIMEWnd| {
            var argc: c_int = 0;
            const cmdline = win.kernel32.GetCommandLineW();
            const args = CommandLineToArgvW(cmdline, &argc);

            if (argc > 1) {
                const status = args[1][0] + (@intCast(u32, args[1][1]) << 16);
                switch (status) {
                    '0' => imSetStatus(hIMEWnd, 0),
                    '1' => imSetStatus(hIMEWnd, 1),
                    else => {
                        std.os.exit(1);
                    },
                }
            } else {
                const status = imGetStatus(hIMEWnd);
                const stdout = std.io.getStdOut().writer();
                try stdout.print("{}\n", .{status});
            }
        }
    }
}
