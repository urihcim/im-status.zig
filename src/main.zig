const std = @import("std");
const win = std.os.windows;

const WM_IME_CONTROL = 0x0283;
const IMC_GETOPENSTATUS = 0x0005;
const IMC_SETOPENSTATUS = 0x0006;

const VK_IME_ON = 0x16;
const VK_IME_OFF = 0x1A;
const VK_ESCAPE = 0x1B;
const VK_LWIN = 0x5B;
const VK_RWIN = 0x5C;
const VK_F10 = 0x79;
const VK_LSHIFT = 0xA0;
const VK_RSHIFT = 0xA1;
const VK_LCONTROL = 0xA2;
const VK_RCONTROL = 0xA3;
const VK_LMENU = 0xA4;
const VK_RMENU = 0xA5;

const KEYEVENTF_EXTENDEDKEY = 0x0001;
const KEYEVENTF_KEYUP = 0x0002;
const KEYEVENTF_UNICODE = 0x0004;
const KEYEVENTF_SCANCODE = 0x0008;

const INPUT_MOUSE = 0;
const INPUT_KEYBOARD = 1;
const INPUT_HARDWARE = 2;

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

const MOUSEINPUT: type = extern struct {
    dx: win.LONG,
    dy: win.LONG,
    mouseData: win.DWORD,
    dwFlags: win.DWORD,
    time: win.DWORD,
    dwExtraInfo: win.ULONG_PTR,
};

const KEYBDINPUT = extern struct {
    wVk: win.WORD,
    wScan: win.WORD,
    dwFlags: win.DWORD,
    time: win.DWORD,
    dwExtraInfo: win.ULONG_PTR,
};

const HARDWAREINPUT: type = extern struct {
    uMsg: win.DWORD,
    wParamL: win.WORD,
    wParamH: win.WORD,
};

const INPUT = extern struct {
    type: win.DWORD,
    u: extern union {
        mi: MOUSEINPUT,
        ki: KEYBDINPUT,
        hi: HARDWAREINPUT,
    },
};

extern "kernel32" fn GetLastError() callconv(win.WINAPI) win.DWORD;
extern "user32" fn GetGUIThreadInfo(idThread: win.DWORD, pgui: *GUITHREADINFO) callconv(win.WINAPI) win.BOOL;
extern "user32" fn SendMessageA(hWnd: ?win.HANDLE, msg: win.UINT, wParam: win.WPARAM, lParam: win.LPARAM) callconv(win.WINAPI) win.LRESULT;
extern "user32" fn SendInput(cInputs: win.UINT, pInputs: [*]const INPUT, cbSize: c_int) callconv(win.WINAPI) win.UINT;
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

fn imGetStatus() isize {
    const hWnd = imGetWindow() catch return 0;
    return imControl(hWnd, IMC_GETOPENSTATUS, 0) catch 0;
}

fn imSetStatus(status: isize) !void {
    const hWnd = try imGetWindow();
    _ = try imControl(hWnd, IMC_SETOPENSTATUS, status);
}

fn imSendInput(inputs: []const INPUT) !void {
    //const r = SendInput(@intCast(inputs.len), @ptrCast(&inputs[0]), @sizeOf(INPUT));
    const r = SendInput(@intCast(inputs.len), inputs.ptr, @sizeOf(INPUT));
    if (r == 0) {
        std.log.err("SendInput failed: err={}", .{GetLastError()});
        return error.Failed;
    }
}

fn imKey(wVk: win.WORD, dwFlags: win.DWORD) INPUT {
    return .{ .type = INPUT_KEYBOARD, .u = .{ .ki = .{
        .wVk = wVk,
        .wScan = 0,
        .dwFlags = dwFlags,
        .time = 0,
        .dwExtraInfo = 0,
    } } };
}

fn imKeyModUp() []const INPUT {
    return &[_]INPUT{
        //imKey(VK_LWIN, KEYEVENTF_KEYUP),
        //imKey(VK_RWIN, KEYEVENTF_KEYUP),
        imKey(VK_LSHIFT, KEYEVENTF_KEYUP),
        imKey(VK_RSHIFT, KEYEVENTF_KEYUP),
        imKey(VK_LCONTROL, KEYEVENTF_KEYUP),
        imKey(VK_RCONTROL, KEYEVENTF_KEYUP),
        //imKey(VK_LMENU, KEYEVENTF_KEYUP),
        //imKey(VK_RMENU, KEYEVENTF_KEYUP),
    };
}

fn imOff() !void {
    const inputs = comptime imKeyModUp() ++ [_]INPUT{
        imKey(VK_IME_OFF, 0),
        imKey(VK_IME_OFF, KEYEVENTF_KEYUP),
    };
    try imSendInput(inputs);
}

fn imOn() !void {
    const inputs = comptime imKeyModUp() ++ [_]INPUT{
        imKey(VK_IME_ON, 0),
        imKey(VK_IME_ON, KEYEVENTF_KEYUP),
        imKey(VK_LSHIFT, 0),
        imKey(VK_F10, 0),
        imKey(VK_F10, KEYEVENTF_KEYUP),
        imKey(VK_LSHIFT, KEYEVENTF_KEYUP),
        imKey(VK_ESCAPE, 0),
        imKey(VK_ESCAPE, KEYEVENTF_KEYUP),
    };
    try imSendInput(inputs);
}

pub fn main() void {
    errdefer std.process.exit(1);

    var argc: c_int = 0;
    const cmdline = win.kernel32.GetCommandLineW();
    const args = CommandLineToArgvW(cmdline, &argc);
    if (argc > 1) {
        const status = args[1][0];
        switch (status) {
            '0' => try imOff(),
            '1' => try imOn(),
            else => {
                std.log.err("invalid parameter", .{});
                return error.InvalidParameter;
            },
        }
    } else {
        const status = imGetStatus();
        const stdout = std.io.getStdOut().writer();
        try stdout.print("{}\n", .{status});
    }
}
