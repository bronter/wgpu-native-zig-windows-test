const std = @import("std");
const win32 = @import("win32");
const Renderer = @import("renderer.zig");

// Needs to be here or the compiler throws a fit.
pub const UNICODE = true;

// String literals in Zig are UTF-8 encoded by default, but the Windows API needs them to be UTF-16 encoded.
// This function converts a UTF-8 string literal to a zero-terminated UTF-16LE string literal.
const L = win32.zig.L;

const windows_and_messaging = win32.ui.windows_and_messaging;

const WINAPI = std.os.windows.WINAPI;
const FALSE: c_int = 0;

pub export fn wWinMain(
    hInstance: win32.foundation.HINSTANCE,
    _: ?win32.foundation.HINSTANCE,
    _: [*:0]u16,
    _: u32
) callconv(WINAPI) c_int {
    const class_name = L("wgpu-native-zig windows example");
    const class = windows_and_messaging.WNDCLASS {
        .style = .{}, // use style defaults for now
        .lpfnWndProc = WindowProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = hInstance,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = class_name,
    };

    if (windows_and_messaging.RegisterClass(&class) == 0) {
        return FALSE;
    }

    const hwnd = windows_and_messaging.CreateWindowEx(
        .{}, // Style again, use defaults (WINDOW_EX_STYLE).
        class_name, // ClassName
        L("wgpu-native-zig windows example"), // window name,
        windows_and_messaging.WS_OVERLAPPEDWINDOW, // More style flags (WINDOW_STYLE)
        windows_and_messaging.CW_USEDEFAULT, // Initial window top-left position X (i32)
        windows_and_messaging.CW_USEDEFAULT, // Initial window top-left position Y (i32)
        640, // Initial window width (i32)
        480, // Initial window height (i32)
        null, // Parent window handle (HWND)
        null, // Menu handle (HMENU)
        hInstance,

        // Additional data (*anyopaque, also known as LPVOID)
        // When we recieve a WM_CREATE message, the lParam will point to a CREATESTRUCT;
        // the data we pass in here will show up in the lpCreateParam member of the CREATESTRUCT.
        null,
    ) orelse return FALSE;

    var _renderer = Renderer.create(640, 480, hInstance, hwnd) catch return FALSE;
    const renderer = &_renderer;

    // According to Microsoft's docs, for the first call to ShowWindow we should really be using the value of nCmdShow from wWinMain's parameters.
    // In practice, it doesn't seem to matter and the window doesn't show at all if I try to do it properly.
    _ = windows_and_messaging.ShowWindow(hwnd, windows_and_messaging.SW_SHOWDEFAULT);

    var msg: windows_and_messaging.MSG = undefined;
    while (true) {
        // Pass null as hwnd parameter to PeeekMessage in order to receive all messages;
        // otherwise we don't receive WM_QUIT since it is posted to the thread's message queue rather than the window's message queue.
        if (windows_and_messaging.PeekMessage(&msg, null, 0, 0, windows_and_messaging.PM_REMOVE) != 0) {
            if (msg.message == windows_and_messaging.WM_QUIT) {
                break;
            }
            _ = windows_and_messaging.TranslateMessage(&msg);
            _ = windows_and_messaging.DispatchMessage(&msg);
        } else {
            renderer.render() catch {
                break;
            };
        }
    }

    renderer.release();
    _ = windows_and_messaging.DestroyWindow(hwnd);
    _ = windows_and_messaging.UnregisterClass(class_name, hInstance);

    return FALSE;
}

fn WindowProc(
    hwnd: win32.foundation.HWND,
    uMsg: u32,
    wParam: win32.foundation.WPARAM,
    lParam: win32.foundation.LPARAM
) callconv(WINAPI) win32.foundation.LRESULT {
    switch (uMsg) {
        windows_and_messaging.WM_DESTROY => {
            windows_and_messaging.PostQuitMessage(0);
            return 0;
        },
        else => {},
    }
    return windows_and_messaging.DefWindowProc(hwnd, uMsg, wParam, lParam);
}