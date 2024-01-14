const std = @import("std");
const win = std.os.windows;

const IMC_GETOPENSTATUS: win.WPARAM = 0x0005;
const IMC_SETOPENSTATUS: win.WPARAM = 0x0006;

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

extern "user32" fn GetForegroundWindow() callconv(win.WINAPI) ?win.HWND;
extern "user32" fn GetGUIThreadInfo(idThread: win.DWORD, pgui: *GUITHREADINFO) callconv(win.WINAPI) win.BOOL;
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
    var hWnd = GetForegroundWindow();
    var gui = std.mem.zeroes(GUITHREADINFO);
    gui.cbSize = @sizeOf(GUITHREADINFO);
    if (GetGUIThreadInfo(0, &gui) != 0) {
        hWnd = gui.hwndFocus;
    }
    if (ImmGetDefaultIMEWnd(hWnd)) |hIMEWnd| {
        var argc: c_int = 0;
        const cmdline = win.kernel32.GetCommandLineW();
        const args = CommandLineToArgvW(cmdline, &argc);
        if (argc > 1) {
            const status = args[1][0];
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
