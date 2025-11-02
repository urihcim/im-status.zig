const std = @import("std");
const win = std.os.windows;

const WM_IME_CONTROL = 0x0283;
const IMC_GETOPENSTATUS = 0x0005;
const IMC_SETOPENSTATUS = 0x0006;

const PROCESS_VM_READ = 0x0010;
const PROCESS_QUERY_INFORMATION = 0x0400;

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
    cbSize: win.DWORD = @sizeOf(GUITHREADINFO),
    flags: win.DWORD = 0,
    hwndActive: ?win.HWND = null,
    hwndFocus: ?win.HWND = null,
    hwndCapture: ?win.HWND = null,
    hwndMenuOwner: ?win.HWND = null,
    hwndMoveSize: ?win.HWND = null,
    hwndCaret: ?win.HWND = null,
    rcCaret: win.RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
};

const MOUSEINPUT: type = extern struct {
    dx: win.LONG,
    dy: win.LONG,
    mouseData: win.DWORD = 0,
    dwFlags: win.DWORD = 0,
    time: win.DWORD = 0,
    dwExtraInfo: win.ULONG_PTR = 0,
};

const KEYBDINPUT = extern struct {
    wVk: win.WORD,
    wScan: win.WORD,
    dwFlags: win.DWORD = 0,
    time: win.DWORD = 0,
    dwExtraInfo: win.ULONG_PTR = 0,
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

    fn VK(wVK: win.WORD, dwFlags: win.DWORD) INPUT {
        return .{ .type = INPUT_KEYBOARD, .u = .{ .ki = .{
            .wVk = wVK,
            .wScan = 0,
            .dwFlags = dwFlags,
        } } };
    }
};

extern "kernel32" fn GetLastError() callconv(.winapi) win.DWORD;
extern "kernel32" fn GetCommandLineW() callconv(.winapi) win.LPWSTR;
extern "kernel32" fn OpenProcess(dwDesiredAccess: win.DWORD, bInheritHandle: win.BOOL, dwProcessId: win.DWORD) callconv(.winapi) ?win.HANDLE;
extern "psapi" fn GetModuleFileNameExA(hProcess: win.HANDLE, hModule: ?win.HMODULE, lpFilename: win.LPSTR, nSize: win.DWORD) callconv(.winapi) win.DWORD;
extern "user32" fn GetWindowThreadProcessId(hWnd: win.HWND, lpdwProcessId: ?*win.DWORD) callconv(.winapi) win.DWORD;
extern "user32" fn GetGUIThreadInfo(idThread: win.DWORD, pgui: *GUITHREADINFO) callconv(.winapi) win.BOOL;
extern "user32" fn SendMessageA(hWnd: win.HANDLE, msg: win.UINT, wParam: win.WPARAM, lParam: win.LPARAM) callconv(.winapi) win.LRESULT;
extern "user32" fn SendInput(cInputs: win.UINT, pInputs: [*]const INPUT, cbSize: c_int) callconv(.winapi) win.UINT;
extern "imm32" fn ImmGetDefaultIMEWnd(hWnd: win.HWND) callconv(.winapi) ?win.HWND;
extern "shell32" fn CommandLineToArgvW(lpCmdLine: win.LPCWSTR, pNumArgs: *c_int) callconv(.winapi) [*]win.LPWSTR;

fn imGetFocus() !win.HWND {
    var gui = GUITHREADINFO{};
    if (GetGUIThreadInfo(0, &gui) == win.FALSE) {
        std.log.err("GetGUIThreadInfo failed: err={}", .{GetLastError()});
        return error.Failed;
    }
    if (gui.hwndFocus) |hWnd| {
        return hWnd;
    } else {
        std.log.err("hwndFocus is null", .{});
        return error.Failed;
    }
}

fn imGetExeName() ![]const u8 {
    const hWnd = try imGetFocus();

    var pid: win.DWORD = undefined;
    if (GetWindowThreadProcessId(hWnd, &pid) == 0) {
        std.log.err("GetWindowThreadProcessId failed: err={}", .{GetLastError()});
        return error.Failed;
    }

    var hProcess: win.HANDLE = undefined;
    if (OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, win.FALSE, pid)) |handle| {
        hProcess = handle;
    } else {
        std.log.err("OpenProcess failed: err={}", .{GetLastError()});
        return error.Failed;
    }
    defer _ = win.CloseHandle(hProcess);

    var buf: [255:0]u8 = undefined;
    const r = GetModuleFileNameExA(hProcess, null, &buf, buf.len);
    if (r == 0) {
        std.log.err("GetModuleFileNameEx failed: err={}", .{GetLastError()});
        return error.Failed;
    }
    return buf[0..@intCast(r)];
}

fn imGetWindow() !win.HWND {
    const hWnd = try imGetFocus();
    if (ImmGetDefaultIMEWnd(hWnd)) |hWndIME| {
        return hWndIME;
    } else {
        std.log.err("ImmGetDefaultIMEWnd failed", .{});
        return error.Failed;
    }
}

fn imControl(hWnd: win.HWND, wParam: win.WPARAM, lParam: win.LPARAM) !win.LRESULT {
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
    const r = SendInput(@intCast(inputs.len), inputs.ptr, @sizeOf(INPUT));
    if (r == 0) {
        std.log.err("SendInput failed: err={}", .{GetLastError()});
        return error.Failed;
    }
}

fn imReleaseModKey() !void {
    const inputs = &[_]INPUT{
        INPUT.VK(VK_LSHIFT, KEYEVENTF_KEYUP),
        INPUT.VK(VK_RSHIFT, KEYEVENTF_KEYUP),
        INPUT.VK(VK_LCONTROL, KEYEVENTF_KEYUP),
        INPUT.VK(VK_RCONTROL, KEYEVENTF_KEYUP),
        //INPUT.VK(VK_LMENU, KEYEVENTF_KEYUP),
        //INPUT.VK(VK_RMENU, KEYEVENTF_KEYUP),
        //INPUT.VK(VK_LWIN, KEYEVENTF_KEYUP),
        //INPUT.VK(VK_RWIN, KEYEVENTF_KEYUP),
    };
    try imSendInput(inputs);
}

fn imFixUp() !void {
    const name = try imGetExeName();
    if (!std.mem.endsWith(u8, name, "\\Code.exe")) {
        return;
    }
    const inputs = &[_]INPUT{
        INPUT.VK(VK_LSHIFT, 0),
        INPUT.VK(VK_F10, 0),
        INPUT.VK(VK_F10, KEYEVENTF_KEYUP),
        INPUT.VK(VK_LSHIFT, KEYEVENTF_KEYUP),
        INPUT.VK(VK_ESCAPE, 0),
        INPUT.VK(VK_ESCAPE, KEYEVENTF_KEYUP),
    };
    try imSendInput(inputs);
}

fn imKeyOff() !void {
    try imReleaseModKey();
    const inputs = &[_]INPUT{
        INPUT.VK(VK_IME_OFF, 0),
        INPUT.VK(VK_IME_OFF, KEYEVENTF_KEYUP),
    };
    try imSendInput(inputs);
}

fn imKeyOn() !void {
    try imReleaseModKey();
    const inputs = &[_]INPUT{
        INPUT.VK(VK_IME_ON, 0),
        INPUT.VK(VK_IME_ON, KEYEVENTF_KEYUP),
    };
    try imSendInput(inputs);
    try imFixUp();
}

fn imOff() !void {
    try imSetStatus(0);
}

fn imOn() !void {
    try imKeyOn();
}

pub fn main() void {
    errdefer std.process.exit(1);

    var argc: c_int = 0;
    const cmdline = GetCommandLineW();
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
        var buf: [16]u8 = undefined;
        var stdout = std.fs.File.stdout().writer(&buf).interface;
        try stdout.print("{}\n", .{status});
        try stdout.flush();
    }
}
