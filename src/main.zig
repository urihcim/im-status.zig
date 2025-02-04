const std = @import("std");
const win = std.os.windows;

const WM_IME_CONTROL = 0x0283;
const IMC_GETOPENSTATUS = 0x0005;
const IMC_SETOPENSTATUS = 0x0006;

const GUITHREADINFO = extern struct {
    cbSize: win.DWORD,
    flags: win.DWORD,
    hwndActive: ?win.HWND,
    hwndFocus: ?win.HWND,
    hwndCapture: ?win.HWND,
    hwndMenuOwner: ?win.HWND,
    hwndMoveSize: ?win.HWND,
    hwndCaret: ?win.HWND,
    rcCaret: win.RECT,
};

extern "kernel32" fn GetLastError() callconv(win.WINAPI) win.DWORD;
extern "user32" fn GetGUIThreadInfo(idThread: win.DWORD, pgui: *GUITHREADINFO) callconv(win.WINAPI) win.BOOL;
extern "user32" fn SendMessageA(hWnd: ?win.HANDLE, msg: win.UINT, wParam: win.WPARAM, lParam: win.LPARAM) callconv(win.WINAPI) win.LRESULT;
extern "imm32" fn ImmGetDefaultIMEWnd(hWnd: ?win.HWND) callconv(win.WINAPI) ?win.HWND;
extern "shell32" fn CommandLineToArgvW(lpCmdLine: win.LPCWSTR, pNumArgs: *c_int) callconv(win.WINAPI) [*]win.LPWSTR;

fn imGetWindow() !win.HWND {
    var hWnd: ?win.HWND = undefined;
    var gui = std.mem.zeroes(GUITHREADINFO);
    gui.cbSize = @sizeOf(GUITHREADINFO);
    if (GetGUIThreadInfo(0, &gui) == win.TRUE) {
        hWnd = gui.hwndFocus;
    } else {
        std.log.err("GetGUIThreadInfo failed: err={}", .{GetLastError()});
        return error.Failed;
    }
    if (ImmGetDefaultIMEWnd(hWnd)) |hWndIME| {
        return hWndIME;
    } else {
        std.log.err("ImmGetDefaultIMEWnd failed: err={}", .{GetLastError()});
        return error.Failed;
    }
}

fn imControl(hWnd: ?win.HWND, wParam: win.WPARAM, lParam: win.LPARAM) !win.LRESULT {
    const r = SendMessageA(hWnd, WM_IME_CONTROL, wParam, lParam);
    const err = GetLastError();
    if (err != 0) {
        std.log.err("SendMessage failed: r={} err={}", .{ r, err });
        return error.Failed;
    }
    return r;
}

fn imGetStatus(hWnd: ?win.HWND) isize {
    return imControl(hWnd, IMC_GETOPENSTATUS, 0) catch 0;
}

fn imSetStatus(hWnd: ?win.HWND, status: isize) !void {
    _ = try imControl(hWnd, IMC_SETOPENSTATUS, status);
}

pub fn main() void {
    errdefer std.process.exit(1);

    const hWndIME = try imGetWindow();
    var argc: c_int = 0;
    const cmdline = win.kernel32.GetCommandLineW();
    const args = CommandLineToArgvW(cmdline, &argc);
    if (argc > 1) {
        const status = args[1][0];
        switch (status) {
            '0' => try imSetStatus(hWndIME, 0),
            '1' => {
                try imSetStatus(hWndIME, 1);
            },
            else => {
                std.log.err("invalid parameter", .{});
                return error.InvalidParameter;
            },
        }
    } else {
        const status = imGetStatus(hWndIME);
        const stdout = std.io.getStdOut().writer();
        try stdout.print("{}\n", .{status});
    }
}
