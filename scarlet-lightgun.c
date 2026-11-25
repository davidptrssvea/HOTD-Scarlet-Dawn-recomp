#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#include <xinput.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <wchar.h>
#include "scarlet-reticle.h"

/* Offsets are for the SHA-256 checked Scarlet Dawn export build only. */
typedef void (*GameCall)(void *);
typedef void *(*MakeName)(uint64_t *, const char *, int);
enum GunEvent { SCREEN_IN, SCREEN_OUT, FIRE_DOWN, FIRE_UP, SELECT_DOWN, SELECT_UP, START_DOWN, START_UP };
static const uint32_t methods[2][8] = {
    {0x1de110,0x1de130,0x1de250,0x1de2b0,0x1de150,0x1de1b0,0x1de2d0,0x1de330},
    {0x1de350,0x1de370,0x1de4b0,0x1de520,0x1de390,0x1de400,0x1de540,0x1de5b0}
};
static const unsigned queueSize = 64;
static struct Gun {
    wchar_t path[1024];
    HANDLE device;
    POINT point;
    bool inside, trigger, selecting, starting, offscreenButton;
} guns[2];
static struct Event {
    POINT point;
    unsigned player;
    enum GunEvent kind;
} events[64];
static unsigned eventCount;
static bool clearButtons, initialized, gunMode, rawMode, gamepadMode, reloadEnabled, switchWeaponOnReload;
static unsigned borderWidth;
static HWND gameWindow, borderWindow;
static RECT borderBounds;
static int whiteEdge, blackEdge;
static uintptr_t imageBase;
static void *previousController;
static bool secondPlayerWasActive, secondPlayerIsActive;
static unsigned deliveredButtons[2];
static struct Gamepad {
    DWORD index;
    double x, y;
    unsigned buttons;
    bool synced;
} gamepads[2] = {{.index=XUSER_MAX_COUNT}, {.index=XUSER_MAX_COUNT}};
static LONGLONG gamepadTick, gamepadFrequency;
static ULONGLONG nextGamepadScan;
static unsigned cursorHideCalls, gamepadSensitivity = 100;
static bool pauseRequested;
static HWND pauseWindow;

static void releaseGamepadCursor(void)
{
    while (cursorHideCalls) {
        ShowCursor(TRUE);
        --cursorHideCalls;
    }
}

static void updateGamepadCursor(bool foreground)
{
    if (!gamepadMode) return;
    POINT point;
    RECT client;
    if (!foreground || pauseWindow || IsIconic(gameWindow) ||
        !GetCursorPos(&point) || !ScreenToClient(gameWindow,&point) ||
        !GetClientRect(gameWindow,&client) || !PtInRect(&client,point)) {
        releaseGamepadCursor();
        return;
    }
    CURSORINFO cursor={.cbSize=sizeof cursor};
    if (GetCursorInfo(&cursor) && (cursor.flags & CURSOR_SHOWING)) {
        for (unsigned tries=0; tries<16; ++tries) {
            ++cursorHideCalls;
            if (ShowCursor(FALSE) < 0) break;
        }
    }
    SetCursor(NULL);
}

static void emit(unsigned player, enum GunEvent kind)
{
    if (eventCount == queueSize) {
        eventCount = 0;
        clearButtons = true;
    }
    events[eventCount++] = (struct Event){guns[player].point,player,kind};
}

static void screen(unsigned player, bool inside)
{
    struct Gun *gun = &guns[player];
    if (gun->inside == inside) return;
    gun->inside = inside;
    if (inside) {
        emit(player, SCREEN_IN);
        return;
    }
    if (gun->trigger) {
        gun->trigger = false;
        emit(player, FIRE_UP);
    }
    if (reloadEnabled) emit(player, SCREEN_OUT);
}

static void press(unsigned player, enum GunEvent down, bool pressed)
{
    struct Gun *gun = &guns[player];
    bool *held = down == FIRE_DOWN ? &gun->trigger : down == SELECT_DOWN ? &gun->selecting : &gun->starting;
    if (down == FIRE_DOWN && pressed && !gun->inside) return;
    if (*held == pressed) return;
    *held = pressed;
    emit(player, pressed ? down : down + 1);
}

static void driverReload(unsigned player, bool down)
{
    struct Gun *gun = &guns[player];
    if (gun->offscreenButton == down) return;
    gun->offscreenButton = down;
    if (down) screen(player, false);
}

static void aim(unsigned player, POINT point)
{
    RECT client;
    if (!GetClientRect(gameWindow, &client)) return;
    struct Gun *gun = &guns[player];
    gun->point = point;
    screen(player, !gun->offscreenButton && PtInRect(&client, point));
}

static void resetGun(struct Gun *gun)
{
    gun->inside = gun->trigger = gun->selecting = gun->starting = gun->offscreenButton = false;
    gun->point = (POINT){-1,-1};
}

enum GamepadButton { PAD_FIRE=1, PAD_RELOAD=2, PAD_SELECT=4, PAD_START=8, PAD_PAUSE=16 };

static void applyGamepad(unsigned player, const XINPUT_GAMEPAD *input, const RECT *client, double elapsed)
{
    struct Gamepad *pad = &gamepads[player];
    double x = input->sThumbLX, y = input->sThumbLY;
    const double rx = input->sThumbRX, ry = input->sThumbRY;
    if (rx*rx + ry*ry > x*x + y*y) {
        x = rx;
        y = ry;
    }
    const double length = sqrt(x*x + y*y);
    const double deadzone = XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE;
    if (length > deadzone) {
        const double strength = (fmin(length,32767.0) - deadzone) / (32767.0 - deadzone);
        const double distance = 0.016 * gamepadSensitivity * client->bottom * elapsed * strength * strength;
        pad->x += x / length * distance;
        pad->y -= y / length * distance;
    }
    pad->x = fmax(0, fmin(pad->x, client->right - 1));
    pad->y = fmax(0, fmin(pad->y, client->bottom - 1));
    aim(player, (POINT){(LONG)(pad->x + 0.5), (LONG)(pad->y + 0.5)});

    unsigned buttons = 0;
    if ((input->wButtons & XINPUT_GAMEPAD_A) || input->bRightTrigger > XINPUT_GAMEPAD_TRIGGER_THRESHOLD)
        buttons |= PAD_FIRE;
    if (input->wButtons & (XINPUT_GAMEPAD_X | XINPUT_GAMEPAD_LEFT_SHOULDER)) buttons |= PAD_RELOAD;
    if (input->wButtons & (XINPUT_GAMEPAD_Y | XINPUT_GAMEPAD_RIGHT_SHOULDER)) buttons |= PAD_SELECT;
    if (input->wButtons & XINPUT_GAMEPAD_START) buttons |= PAD_START;
    if (input->wButtons & XINPUT_GAMEPAD_BACK) buttons |= PAD_PAUSE;
    const unsigned changed = pad->synced ? pad->buttons ^ buttons : 0;
    pad->buttons = buttons;
    pad->synced = true;

    if (changed & buttons & PAD_PAUSE) pauseRequested = true;
    if (changed & buttons & PAD_RELOAD) screen(player, false);
    if (changed & PAD_FIRE) press(player, FIRE_DOWN, (buttons & PAD_FIRE) != 0);
    if (changed & PAD_SELECT) press(player, SELECT_DOWN, (buttons & PAD_SELECT) != 0);
    if (changed & PAD_START) press(player, START_DOWN, (buttons & PAD_START) != 0);
}

static void updateGamepads(bool controllerChanged)
{
    RECT client;
    if (!GetClientRect(gameWindow,&client) || client.right <= 0 || client.bottom <= 0) return;
    LARGE_INTEGER clock;
    QueryPerformanceCounter(&clock);
    const double elapsed = gamepadTick && gamepadFrequency ?
        fmin((double)(clock.QuadPart - gamepadTick) / (double)gamepadFrequency, 0.05) : 0;
    gamepadTick = clock.QuadPart;

    unsigned assigned = 0;
    for (unsigned p=0; p<2; ++p) {
        struct Gamepad *pad = &gamepads[p];
        if (pad->index == XUSER_MAX_COUNT) continue;
        if (controllerChanged) {
            pad->synced = false;
            guns[p].trigger = guns[p].selecting = guns[p].starting = false;
        }
        XINPUT_STATE state;
        if (XInputGetState(pad->index,&state) == ERROR_SUCCESS) {
            assigned |= 1u << pad->index;
            applyGamepad(p,&state.Gamepad,&client,elapsed);
        } else {
            press(p,FIRE_DOWN,false);
            press(p,SELECT_DOWN,false);
            press(p,START_DOWN,false);
            resetGun(&guns[p]);
            pad->index = XUSER_MAX_COUNT;
        }
    }

    const ULONGLONG now = GetTickCount64();
    if (now < nextGamepadScan) return;
    nextGamepadScan = now + 1000;
    for (DWORD index=0; index<XUSER_MAX_COUNT; ++index) {
        const unsigned vacant = gamepads[0].index == XUSER_MAX_COUNT ? 0 : 1;
        if (gamepads[vacant].index != XUSER_MAX_COUNT) break;
        if (assigned & (1u << index)) continue;
        XINPUT_STATE state;
        if (XInputGetState(index,&state) != ERROR_SUCCESS) continue;
        gamepads[vacant] = (struct Gamepad){.index=index, .x=client.right/2.0, .y=client.bottom/2.0};
        applyGamepad(vacant,&state.Gamepad,&client,0);
    }
}

static int rawPlayer(HANDLE device, bool absolute)
{
    if (!device) return -1;
    for (int p = 0; p < 2; ++p)
        if (guns[p].device == device) return p;
    wchar_t path[1024];
    UINT length = ARRAYSIZE(path);
    if (GetRawInputDeviceInfoW(device, RIDI_DEVICENAME, path, &length) == (UINT)-1) return -1;
    for (int p = 0; p < 2; ++p) {
        if (!_wcsicmp(guns[p].path, path)) {
            guns[p].device = device;
            return p;
        }
    }
    if (!absolute) return -1;
    for (int p = 0; p < 2; ++p) {
        if (!guns[p].device && !_wcsicmp(guns[p].path, L"auto")) {
            guns[p].device = device;
            return p;
        }
    }
    return -1;
}

static void rawPacket(HRAWINPUT handle)
{
    RAWINPUT input;
    UINT bytes = sizeof(input);
    if (GetRawInputData(handle, RID_INPUT, &input, &bytes, sizeof(RAWINPUTHEADER)) == (UINT)-1 ||
        input.header.dwType != RIM_TYPEMOUSE) return;
    const RAWMOUSE *mouse = &input.data.mouse;
    bool absolute = (mouse->usFlags & MOUSE_MOVE_ABSOLUTE) != 0;
    int p = rawPlayer(input.header.hDevice, absolute);
    if (p < 0) return;
    RECT client;
    if (!GetClientRect(gameWindow, &client) || client.right <= 0 || client.bottom <= 0) return;
    const USHORT buttons = mouse->usButtonFlags;
    if (buttons & RI_MOUSE_RIGHT_BUTTON_DOWN) driverReload(p, true);
    if (buttons & RI_MOUSE_RIGHT_BUTTON_UP) driverReload(p, false);
    if (absolute) {
        bool desktop = (mouse->usFlags & MOUSE_VIRTUAL_DESKTOP) != 0;
        int width = GetSystemMetrics(desktop ? SM_CXVIRTUALSCREEN : SM_CXSCREEN);
        int height = GetSystemMetrics(desktop ? SM_CYVIRTUALSCREEN : SM_CYSCREEN);
        POINT pos = {
            (desktop ? GetSystemMetrics(SM_XVIRTUALSCREEN) : 0) + (LONG)((int64_t)mouse->lLastX * (width-1) / 65535),
            (desktop ? GetSystemMetrics(SM_YVIRTUALSCREEN) : 0) + (LONG)((int64_t)mouse->lLastY * (height-1) / 65535)
        };
        if (ScreenToClient(gameWindow, &pos)) aim(p, pos);
    } else if (mouse->lLastX || mouse->lLastY) {
        POINT pos = guns[p].point;
        if (!PtInRect(&client, pos)) pos = (POINT){client.right/2,client.bottom/2};
        pos.x += mouse->lLastX;
        pos.y += mouse->lLastY;
        aim(p, pos);
    }
    if (buttons & RI_MOUSE_LEFT_BUTTON_DOWN) press(p, FIRE_DOWN, true);
    if (buttons & RI_MOUSE_LEFT_BUTTON_UP) press(p, FIRE_DOWN, false);
    if (buttons & (RI_MOUSE_MIDDLE_BUTTON_DOWN|RI_MOUSE_BUTTON_4_DOWN)) press(p, SELECT_DOWN, true);
    if (buttons & (RI_MOUSE_MIDDLE_BUTTON_UP|RI_MOUSE_BUTTON_4_UP)) press(p, SELECT_DOWN, false);
    if (buttons & RI_MOUSE_BUTTON_5_DOWN) press(p, START_DOWN, true);
    if (buttons & RI_MOUSE_BUTTON_5_UP) press(p, START_DOWN, false);
}

static bool pointerMessage(UINT message)
{
    return message >= WM_LBUTTONDOWN && message <= WM_XBUTTONDBLCLK && message != WM_MOUSEWHEEL;
}

static LRESULT CALLBACK gameProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR id, DWORD_PTR data)
{
    (void)data;
    if (msg == WM_NCDESTROY) {
        if (pauseWindow) DestroyWindow(pauseWindow);
        releaseGamepadCursor();
        RemoveWindowSubclass(hwnd, gameProc, id);
        gameWindow = NULL;
        borderWindow = NULL;
        clearReticles();
        for (unsigned p=0;p<2;++p) reticleSprites[p].window=NULL;
        eventCount = 0;
        for (unsigned p = 0; p < 2; ++p) {
            resetGun(&guns[p]);
            gamepads[p].synced = false;
        }
    }
    if (msg == WM_SETCURSOR && LOWORD(lp)==HTCLIENT &&
        (hideNativeCursor || (gamepadMode && !pauseWindow && GetForegroundWindow()==hwnd))) {
        SetCursor(NULL);
        return TRUE;
    }
    if (msg == WM_KILLFOCUS) {
        releaseGamepadCursor();
        clearReticles();
        if (borderWindow) ShowWindow(borderWindow,SW_HIDE);
        clearButtons = true;
        eventCount = 0;
        for (unsigned p = 0; p < 2; ++p) {
            resetGun(&guns[p]);
            gamepads[p].synced = false;
        }
    }
    if (wp == VK_ESCAPE && (msg == WM_KEYDOWN || msg == WM_KEYUP)) {
        if (msg == WM_KEYDOWN && !(lp & (1L << 30)) && GetForegroundWindow()==hwnd)
            pauseRequested = true;
        return 0;
    }
    if (!gunMode) return DefSubclassProc(hwnd,msg,wp,lp);
    if (gamepadMode && (msg == WM_MOUSEMOVE || msg == WM_MOUSEWHEEL || pointerMessage(msg)))
        return pointerMessage(msg) && msg >= WM_XBUTTONDOWN ? TRUE : 0;
    if (rawMode && msg == WM_INPUT) {
        if (GetForegroundWindow() == hwnd) rawPacket((HRAWINPUT)lp);
        return DefWindowProcW(hwnd,msg,wp,lp);
    }
    if (rawMode && msg == WM_INPUT_DEVICE_CHANGE && wp == GIDC_REMOVAL) {
        for (unsigned p = 0; p < 2; ++p) if (guns[p].device == (HANDLE)lp) {
            press(p, FIRE_DOWN, false);
            press(p, SELECT_DOWN, false);
            press(p, START_DOWN, false);
            resetGun(&guns[p]);
            guns[p].device = NULL;
        }
    }
    if (rawMode && _wcsicmp(guns[1].path,L"disabled") && wp == '2' &&
        (msg == WM_KEYDOWN || msg == WM_KEYUP)) {
        press(1, START_DOWN, msg == WM_KEYDOWN);
        return 0;
    }
    if (!rawMode && (msg == WM_MOUSEMOVE || pointerMessage(msg)) &&
        GetForegroundWindow() == hwnd) {
        if (msg == WM_RBUTTONDOWN || msg == WM_RBUTTONDBLCLK) driverReload(0, true);
        if (msg == WM_RBUTTONUP) driverReload(0, false);
        POINT point = {GET_X_LPARAM(lp),GET_Y_LPARAM(lp)};
        aim(0, point);
        switch (msg) {
        case WM_LBUTTONDOWN: case WM_LBUTTONDBLCLK: press(0, FIRE_DOWN, true); break;
        case WM_LBUTTONUP: press(0, FIRE_DOWN, false); break;
        case WM_MBUTTONDOWN: case WM_MBUTTONDBLCLK: press(0, SELECT_DOWN, true); break;
        case WM_MBUTTONUP: press(0, SELECT_DOWN, false); break;
        case WM_XBUTTONDOWN: case WM_XBUTTONDBLCLK: case WM_XBUTTONUP:
            press(0, GET_XBUTTON_WPARAM(wp)==XBUTTON1 ? SELECT_DOWN : START_DOWN, msg!=WM_XBUTTONUP);
            break;
        }
    }
    if (pointerMessage(msg)) return msg >= WM_XBUTTONDOWN ? TRUE : 0;
    return DefSubclassProc(hwnd,msg,wp,lp);
}

static LRESULT CALLBACK borderProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    if (msg == WM_NCHITTEST) return HTTRANSPARENT;
    if (msg == WM_ERASEBKGND) return 1;
    if (msg == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
    if (msg == WM_PAINT) {
        PAINTSTRUCT paint;
        HDC dc = BeginPaint(hwnd,&paint);
        RECT area;
        GetClientRect(hwnd,&area);
        FillRect(dc,&area,(HBRUSH)GetStockObject(WHITE_BRUSH));
        InflateRect(&area,-whiteEdge,-whiteEdge);
        FillRect(dc,&area,(HBRUSH)GetStockObject(BLACK_BRUSH));
        EndPaint(hwnd,&paint);
        return 0;
    }
    return DefWindowProcW(hwnd,msg,wp,lp);
}

static void updateBorder(void)
{
    if (!borderWidth) return;
    RECT bounds;
    if (GetForegroundWindow()!=gameWindow || IsIconic(gameWindow) || !GetClientRect(gameWindow,&bounds)) {
        if (borderWindow && IsWindowVisible(borderWindow)) ShowWindow(borderWindow,SW_HIDE);
        return;
    }
    MapWindowPoints(gameWindow,NULL,(POINT *)&bounds,2);
    int w=bounds.right-bounds.left, h=bounds.bottom-bounds.top;
    if (w<64 || h<64) return;
    if (!borderWindow) {
        HINSTANCE instance = GetModuleHandleW(NULL);
        WNDCLASSW cls = {.lpfnWndProc=borderProc,.hInstance=instance,.lpszClassName=L"ScarletSindenBorder"};
        RegisterClassW(&cls);
        borderWindow = CreateWindowExW(WS_EX_LAYERED|WS_EX_TRANSPARENT|WS_EX_NOACTIVATE|WS_EX_TOOLWINDOW,
            cls.lpszClassName,L"",WS_POPUP|WS_DISABLED,0,0,0,0,gameWindow,NULL,instance,NULL);
        if (!borderWindow) return;
        SetLayeredWindowAttributes(borderWindow,0,255,LWA_ALPHA);
        SetRectEmpty(&borderBounds);
    }
    if (!EqualRect(&bounds,&borderBounds)) {
        whiteEdge=(h*3*borderWidth+9999)/10000;
        blackEdge=(h*borderWidth+19999)/20000;
        int edge=whiteEdge+blackEdge;
        HRGN frame=CreateRectRgn(0,0,w,h), hole=CreateRectRgn(edge,edge,w-edge,h-edge);
        if (frame && hole && CombineRgn(frame,frame,hole,RGN_DIFF)!=ERROR) {
            if (!SetWindowRgn(borderWindow,frame,FALSE)) DeleteObject(frame);
        } else if (frame) DeleteObject(frame);
        if (hole) DeleteObject(hole);
        SetWindowPos(borderWindow,HWND_TOPMOST,bounds.left,bounds.top,w,h,SWP_NOACTIVATE|SWP_SHOWWINDOW);
        InvalidateRect(borderWindow,NULL,FALSE);
        borderBounds=bounds;
    } else if (!IsWindowVisible(borderWindow)) {
        SetWindowPos(borderWindow,HWND_TOPMOST,bounds.left,bounds.top,w,h,SWP_NOACTIVATE|SWP_SHOWWINDOW);
    }
}

/* Unreal can release its raw registration when the mouse capture mode changes. */
static void ensureRawRegistration(void)
{
    RAWINPUTDEVICE registrations[16];
    UINT count=ARRAYSIZE(registrations);
    UINT got=GetRegisteredRawInputDevices(registrations,&count,sizeof registrations[0]);
    if (got!=(UINT)-1) {
        for (UINT i=0; i<got; ++i) {
            const RAWINPUTDEVICE *entry=&registrations[i];
            if (entry->usUsagePage==1 && entry->usUsage==2 && entry->hwndTarget==gameWindow &&
                (entry->dwFlags & RIDEV_DEVNOTIFY)) return;
        }
    }
    RAWINPUTDEVICE mouse={1,2,RIDEV_DEVNOTIFY,gameWindow};
    RegisterRawInputDevices(&mouse,1,sizeof mouse);
}

static BOOL CALLBACK findWindow(HWND hwnd, LPARAM unused)
{
    (void)unused;
    wchar_t cls[32];
    if (!GetClassNameW(hwnd,cls,ARRAYSIZE(cls)) || wcscmp(cls,L"UnrealWindow")) return TRUE;
    if (!SetWindowSubclass(hwnd,gameProc,1,0)) return TRUE;
    gameWindow=hwnd;
    if (rawMode) ensureRawRegistration();
    return FALSE;
}

static void readEnvironment(void)
{
    wchar_t value[16] = L"";
    GetEnvironmentVariableW(L"SCARLET_GUN_MODE",value,ARRAYSIZE(value));
    rawMode = !wcscmp(value,L"RawInput");
    gamepadMode = !wcscmp(value,L"Gamepad");
    const bool sinden = !wcscmp(value,L"Sinden");
    gunMode = rawMode || sinden || gamepadMode;
    configureReticle();
    if (gamepadMode) {
        LARGE_INTEGER frequency;
        if (QueryPerformanceFrequency(&frequency)) gamepadFrequency = frequency.QuadPart;
        if (reticleStyle == RETICLE_ORIGINAL) reticleStyle = RETICLE_RING_DOT;
        if (GetEnvironmentVariableW(L"SCARLET_GAMEPAD_SENSITIVITY",value,ARRAYSIZE(value))) {
            const unsigned parsed = wcstoul(value,NULL,10);
            if (parsed >= 50 && parsed <= 175) gamepadSensitivity = parsed;
        }
    }
    GetEnvironmentVariableW(L"SCARLET_GUN_RELOAD",value,ARRAYSIZE(value));
    reloadEnabled = gamepadMode || wcscmp(value,L"0") != 0;
    switchWeaponOnReload = sinden &&
        GetEnvironmentVariableW(L"SCARLET_SINDEN_SWITCH_WEAPON_ON_RELOAD",value,ARRAYSIZE(value))==1 &&
        value[0]==L'1';
    if (GetEnvironmentVariableW(L"SCARLET_GUN_BORDER",value,ARRAYSIZE(value))) borderWidth = wcstoul(value,NULL,10);
    if (gamepadMode || borderWidth>100) borderWidth=0;
    for (unsigned p=0; p<2; ++p) {
        if (!GetEnvironmentVariableW(p?L"SCARLET_GUN_P2":L"SCARLET_GUN_P1",guns[p].path,ARRAYSIZE(guns[p].path)))
            wcscpy(guns[p].path,p?L"disabled":L"auto");
        resetGun(&guns[p]);
    }
}

static void gamePoint(void *controller, unsigned player, POINT point)
{
    uint8_t *positions = (uint8_t *)controller+(player?0xbe0:0xbd0);
    *(POINT *)positions=point;
    *(POINT *)(positions+8)=point;
}

static bool secondPlayerActive(void *controller)
{
    if (gamepadMode ? gamepads[1].index == XUSER_MAX_COUNT :
        (!rawMode || !_wcsicmp(guns[1].path,L"disabled"))) return false;
    typedef void *(*GetWorld)(void *);
    GetWorld getWorld = *(GetWorld *)(*(uint8_t **)controller+0x138);
    uint8_t *world = getWorld(controller);
    if (!world) return false;
    void *instance = *(void **)(world+0x140);
    if (!instance) return false;

    /* Query the same Blueprint predicate that controls the equipment menus. */
    static uint64_t name;
    if (!name) ((MakeName)(imageBase+0x300890))(&name,"IsPlayerActive",0);
    if (!name) return false;
    typedef void *(*FindFunction)(void *, uint64_t);
    void *function = ((FindFunction)(imageBase+0x4a30d0))(instance,name);
    if (!function) return false;
    typedef void (*ProcessEvent)(void *, void *, void *);
    ProcessEvent processEvent = *(ProcessEvent *)(*(uint8_t **)instance+0x1f8);
    struct { int32_t player; uint8_t active; uint8_t padding[3]; } params = {1,0,{0}};
    processEvent(instance,function,&params);
    return params.active!=0;
}

static bool hasExtraWeaponAmmo(const void *controller)
{
    const uint8_t *actor = controller;
    const uint8_t *actorClass = *(const uint8_t *const *)(actor+0x10);
    static uint64_t shootingController;
    if (!shootingController)
        ((MakeName)(imageBase+0x300890))(&shootingController,"MouseShoot_C",0);
    if (!shootingController || !actorClass || *(const uint64_t *)(actorClass+0x18)!=shootingController)
        return false;

    /* MouseShoot_C::GunTrigger1P and its equipment and remaining rounds per slot. */
    const uint8_t *trigger = *(const uint8_t *const *)(actor+0xe10);
    if (!trigger) return false;
    struct IntArray {
        const int32_t *items;
        int32_t count, capacity;
    };
    const struct IntArray *equipment = (const struct IntArray *)(trigger+0x148);
    const struct IntArray *remaining = (const struct IntArray *)(trigger+0x160);
    const int32_t normalSlots = *(const int32_t *)(trigger+0x19c);
    if (!equipment->items || !remaining->items || normalSlots<2 || normalSlots>3 ||
        normalSlots>equipment->count || normalSlots>remaining->count)
        return false;

    /* Slot zero is the standard Machine Gun. Slots one and two are the selected extras. */
    for (int32_t slot=1; slot<normalSlots; ++slot)
        if (equipment->items[slot]>0 && remaining->items[slot]>0) return true;
    return false;
}

static void callGame(void *controller, unsigned player, enum GunEvent kind)
{
    if (player && kind < START_DOWN && !secondPlayerIsActive) return;
    if (!player && kind==SCREEN_OUT && switchWeaponOnReload && hasExtraWeaponAmmo(controller)) {
        /* Keep P1 off-screen state without broadcasting the separate reload event. */
        uint8_t *state = controller;
        state[0xb65] = 0;
        state[0xb67] = 1;
        /* Use the game's weapon selector while an extra weapon can still fire. */
        const unsigned selectBit = 1u << ((SELECT_DOWN-FIRE_DOWN)/2);
        if (!(deliveredButtons[0] & selectBit)) {
            ((GameCall)(imageBase+methods[0][SELECT_DOWN]))(controller);
            ((GameCall)(imageBase+methods[0][SELECT_UP]))(controller);
        }
        return;
    }
    if (kind >= FIRE_DOWN) {
        unsigned bit = 1u << ((kind-FIRE_DOWN)/2);
        bool down = (kind-FIRE_DOWN)%2 == 0;
        if (down) deliveredButtons[player] |= bit;
        else {
            if (!(deliveredButtons[player] & bit)) return;
            deliveredButtons[player] &= ~bit;
        }
    }
    ((GameCall)(imageBase+methods[player][kind]))(controller);
}

static void *pauseContext;
static HANDLE pauseSettings;
static wchar_t pauseResult[2048];
static unsigned pauseKeys, pauseSelection;
static HWND pauseButtons[2];
enum { PAUSE_RESUME=101, PAUSE_SETTINGS=102, PAUSE_TIMER=1 };
enum { MENU_BACK=1, MENU_UP=2, MENU_DOWN=4, MENU_SELECT=8 };

static bool setPaused(void *context, bool paused)
{
    /* UGameplayStatics::SetGamePaused and IsGamePaused in the verified export. */
    typedef bool (*SetPaused)(void *, bool);
    typedef bool (*IsPaused)(void *);
    IsPaused isPaused = (IsPaused)(imageBase+0x11d4300);
    if (isPaused(context) == paused) return true;
    ((SetPaused)(imageBase+0x11dd760))(context,paused);
    return isPaused(context) == paused;
}

static unsigned pauseInput(void)
{
    unsigned keys = 0;
    if (GetAsyncKeyState(VK_ESCAPE) < 0) keys |= MENU_BACK;
    if (GetAsyncKeyState(VK_UP) < 0) keys |= MENU_UP;
    if (GetAsyncKeyState(VK_DOWN) < 0) keys |= MENU_DOWN;
    if (GetAsyncKeyState(VK_RETURN) < 0) keys |= MENU_SELECT;
    if (gamepadMode) for (unsigned p=0; p<2; ++p) {
        XINPUT_STATE state;
        if (gamepads[p].index == XUSER_MAX_COUNT ||
            XInputGetState(gamepads[p].index,&state) != ERROR_SUCCESS) continue;
        const unsigned buttons = state.Gamepad.wButtons;
        if (buttons & (XINPUT_GAMEPAD_BACK | XINPUT_GAMEPAD_B)) keys |= MENU_BACK;
        if ((buttons & XINPUT_GAMEPAD_DPAD_UP) || state.Gamepad.sThumbLY > 18000) keys |= MENU_UP;
        if ((buttons & XINPUT_GAMEPAD_DPAD_DOWN) || state.Gamepad.sThumbLY < -18000) keys |= MENU_DOWN;
        if (buttons & XINPUT_GAMEPAD_A) keys |= MENU_SELECT;
    }
    return keys;
}

static void openPauseSettings(HWND window)
{
    wchar_t root[2048], powerShell[512], command[3072];
    const DWORD rootLength = GetEnvironmentVariableW(L"SCARLET_SETTINGS_ROOT",root,ARRAYSIZE(root));
    const UINT systemLength = GetSystemDirectoryW(powerShell,ARRAYSIZE(powerShell)-64);
    if (!rootLength || rootLength >= ARRAYSIZE(root) ||
        !systemLength || systemLength >= ARRAYSIZE(powerShell)-64) return;
    wcscat(powerShell,L"\\WindowsPowerShell\\v1.0\\powershell.exe");
    const unsigned long session = (unsigned long)GetCurrentProcessId();
    if (swprintf(pauseResult,ARRAYSIZE(pauseResult),L"%ls\\Local\\.pause-controls-%lu.ini",root,session) < 0 ||
        swprintf(command,ARRAYSIZE(command),L"\"%ls\" -NoProfile -ExecutionPolicy Bypass -STA -File \"%ls\\scarlet-menu.ps1\" -StartMode PauseSettings -PauseSession %lu",
                 powerShell,root,session) < 0) return;
    DeleteFileW(pauseResult);
    STARTUPINFOW start={.cb=sizeof start};
    PROCESS_INFORMATION process;
    if (!CreateProcessW(powerShell,command,NULL,NULL,FALSE,CREATE_NO_WINDOW,NULL,root,&start,&process)) {
        MessageBoxW(window,L"Could not open the Scarlet Dawn settings.",L"Scarlet Dawn",MB_OK | MB_ICONERROR);
        return;
    }
    CloseHandle(process.hThread);
    pauseSettings = process.hProcess;
    EnableWindow(window,FALSE);
}

static void applyPauseSettings(void)
{
    const wchar_t *section=L"Controls";
    const unsigned style=GetPrivateProfileIntW(section,L"Style",reticleStyle,pauseResult);
    const unsigned size=GetPrivateProfileIntW(section,L"Size",reticleSize,pauseResult);
    const unsigned color=GetPrivateProfileIntW(section,L"Color",99,pauseResult);
    const unsigned speed=GetPrivateProfileIntW(section,L"Sensitivity",gamepadSensitivity,pauseResult);
    if (style <= RETICLE_OPEN_CROSS) reticleStyle = (enum ReticleStyle)style;
    if (gamepadMode && reticleStyle == RETICLE_ORIGINAL) reticleStyle = RETICLE_RING_DOT;
    if (size >= 1 && size <= 3) reticleSize = (int)size;
    setReticleColor(color);
    if (speed >= 50 && speed <= 175) gamepadSensitivity = speed;
    for (unsigned p=0; p<2; ++p)
        if (reticleSprites[p].window) InvalidateRect(reticleSprites[p].window,NULL,FALSE);
    DeleteFileW(pauseResult);
}

static void resumeGame(HWND menu)
{
    if (pauseSettings || !setPaused(pauseContext,false)) return;
    DestroyWindow(menu);
    SetForegroundWindow(gameWindow);
    SetFocus(gameWindow);
}

static LRESULT CALLBACK pauseProc(HWND window, UINT message, WPARAM wp, LPARAM lp)
{
    if (message == WM_COMMAND && !pauseSettings && HIWORD(wp)==BN_CLICKED) {
        if (LOWORD(wp)==PAUSE_RESUME) resumeGame(window);
        if (LOWORD(wp)==PAUSE_SETTINGS) openPauseSettings(window);
        return 0;
    }
    if (message == WM_CLOSE) {
        resumeGame(window);
        return 0;
    }
    if (message == WM_TIMER && wp==PAUSE_TIMER) {
        if (pauseSettings) {
            if (WaitForSingleObject(pauseSettings,0)==WAIT_OBJECT_0) {
                CloseHandle(pauseSettings);
                pauseSettings=NULL;
                applyPauseSettings();
                EnableWindow(window,TRUE);
                SetForegroundWindow(window);
                SetFocus(pauseButtons[pauseSelection]);
                pauseKeys=pauseInput();
            }
            return 0;
        }
        const unsigned keys=pauseInput();
        const unsigned pressed=keys & ~pauseKeys;
        pauseKeys=keys;
        if (GetForegroundWindow()!=window) return 0;
        if (pressed & MENU_BACK) resumeGame(window);
        else if (pressed & (MENU_UP | MENU_DOWN)) {
            pauseSelection ^= 1;
            SetFocus(pauseButtons[pauseSelection]);
        } else if (pressed & MENU_SELECT) {
            SendMessageW(pauseButtons[pauseSelection],BM_CLICK,0,0);
        }
        return 0;
    }
    if (message == WM_DESTROY) {
        KillTimer(window,PAUSE_TIMER);
        if (pauseSettings) CloseHandle(pauseSettings);
        pauseSettings=NULL;
        pauseWindow=NULL;
        pauseContext=NULL;
        gamepadTick=0;
    }
    return DefWindowProcW(window,message,wp,lp);
}

static bool beginPause(void *controller)
{
    if (!pauseRequested) return false;
    pauseRequested=false;
    if (GetForegroundWindow()!=gameWindow) return false;
    typedef bool (*IsPaused)(void *);
    if (((IsPaused)(imageBase+0x11d4300))(controller) || !setPaused(controller,true)) return false;
    pauseContext=controller;
    HINSTANCE instance=GetModuleHandleW(NULL);
    WNDCLASSW cls={.lpfnWndProc=pauseProc,.hInstance=instance,.lpszClassName=L"ScarletPause",
                   .hCursor=LoadCursor(NULL,IDC_ARROW),.hbrBackground=(HBRUSH)(COLOR_WINDOW+1)};
    RegisterClassW(&cls);
    RECT area;
    GetWindowRect(gameWindow,&area);
    pauseWindow=CreateWindowExW(WS_EX_TOOLWINDOW,L"ScarletPause",L"Scarlet Dawn paused",
        WS_POPUP|WS_CAPTION|WS_SYSMENU,(area.left+area.right-320)/2,(area.top+area.bottom-172)/2,
        320,172,gameWindow,NULL,instance,NULL);
    if (pauseWindow) {
        for (unsigned index=0; index<2; ++index) {
            pauseButtons[index]=CreateWindowW(L"BUTTON",index?L"Settings":L"Resume",
                WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_PUSHBUTTON,18,18+47*(int)index,268,36,pauseWindow,
                (HMENU)(UINT_PTR)(PAUSE_RESUME+index),instance,NULL);
            if (pauseButtons[index]) SendMessageW(pauseButtons[index],WM_SETFONT,(WPARAM)GetStockObject(DEFAULT_GUI_FONT),TRUE);
        }
    }
    if (!pauseWindow || !pauseButtons[0] || !pauseButtons[1] || !SetTimer(pauseWindow,PAUSE_TIMER,25,NULL)) {
        if (pauseWindow) DestroyWindow(pauseWindow);
        setPaused(controller,false);
        pauseContext=NULL;
        return false;
    }
    for (unsigned p=0; p<2; ++p) {
        callGame(controller,p,FIRE_UP);
        callGame(controller,p,SELECT_UP);
        callGame(controller,p,START_UP);
    }
    eventCount=0;
    clearReticles();
    releaseGamepadCursor();
    pauseKeys=pauseInput();
    pauseSelection=0;
    ShowWindow(pauseWindow,SW_SHOW);
    SetForegroundWindow(pauseWindow);
    SetFocus(pauseButtons[0]);
    return true;
}

static void updateReticles(void *controller)
{
    if (reticleStyle==RETICLE_ORIGINAL) return;
    RECT client;
    const uint8_t *appData=*(const uint8_t **)(imageBase+0x3087750);
    if (!appData || GetForegroundWindow()!=gameWindow || IsIconic(gameWindow) ||
        !GetClientRect(gameWindow,&client)) {
        clearReticles();
        return;
    }
    POINT cursor={0,0};
    bool cursorInClient=GetCursorPos(&cursor) && ScreenToClient(gameWindow,&cursor) && PtInRect(&client,cursor);
    bool wasHidden=hideNativeCursor;
    hideNativeCursor=cursorInClient && (gamepadMode || appData[0x231]!=0 || (rawMode && appData[0x232]!=0));
    if (hideNativeCursor) {
        CURSORINFO info={.cbSize=sizeof info};
        if (GetCursorInfo(&info) && (info.flags & CURSOR_SHOWING)) SetCursor(NULL);
    } else if (wasHidden && cursorInClient) {
        SetCursor(LoadCursor(NULL,IDC_ARROW));
    }
    POINT origin={0,0};
    if (!ClientToScreen(gameWindow,&origin)) return;
    for (unsigned p=0;p<2;++p) {
        POINT point=*(const POINT *)((const uint8_t *)controller+(p?0xbe0:0xbd0));
        const bool showPlayer = gamepadMode ?
            gamepads[p].index != XUSER_MAX_COUNT && (!p || secondPlayerIsActive) :
            (!p || rawMode) && appData[0x231+p];
        if (reticleStyle==RETICLE_OFF || !showPlayer ||
            !PtInRect(&client,point) ||
            (!gunMode && (!cursorInClient || ((point.x==0 && point.y==0) && (cursor.x!=0 || cursor.y!=0))))) {
            hideReticle(p);
            continue;
        }
        point.x+=origin.x;
        point.y+=origin.y;
        moveReticle(gameWindow,p,point,client.bottom);
    }
}

__declspec(dllexport) void ScarletLightgunTick(void *controller)
{
    if (!initialized) {
        imageBase = (uintptr_t)GetModuleHandleW(NULL);
        readEnvironment();
        initialized=true;
    }
    ((GameCall)(imageBase+0x1de6d0))(controller);
    if (!gameWindow) EnumThreadWindows(GetCurrentThreadId(),findWindow,0);
    if (!gameWindow) return;
    if (pauseWindow || beginPause(controller)) return;
    if (!gunMode) {
        updateReticles(controller);
        return;
    }

    const bool foreground = GetForegroundWindow() == gameWindow;
    updateGamepadCursor(foreground);
    if (!rawMode && !gamepadMode && foreground) {
        POINT point;
        if (GetCursorPos(&point) && ScreenToClient(gameWindow,&point)) aim(0,point);
    }
    if (rawMode && foreground) {
        static ULONGLONG nextRegistrationCheck;
        ULONGLONG now=GetTickCount64();
        if (now>=nextRegistrationCheck) {
            ensureRawRegistration();
            nextRegistrationCheck=now+1000;
        }
    }
    updateBorder();

    secondPlayerIsActive = secondPlayerActive(controller);
    const bool controllerChanged = previousController != controller;
    if (controllerChanged) {
        deliveredButtons[0]=deliveredButtons[1]=0;
        if (guns[0].inside) callGame(controller,0,SCREEN_IN);
        secondPlayerWasActive=false;
        previousController=controller;
    }
    if (secondPlayerIsActive && !secondPlayerWasActive && guns[1].inside)
        callGame(controller,1,SCREEN_IN);
    secondPlayerWasActive=secondPlayerIsActive;
    if (clearButtons) {
        for (unsigned p=0; p<2; ++p) {
            callGame(controller,p,FIRE_UP);
            callGame(controller,p,SELECT_UP);
            callGame(controller,p,START_UP);
        }
        clearButtons=false;
    }
    if (gamepadMode) {
        if (foreground) updateGamepads(controllerChanged);
        else gamepadTick = 0;
    }
    for (unsigned i=0; i<eventCount; ++i) {
        const struct Event *e=&events[i];
        gamePoint(controller,e->player,e->point);
        callGame(controller,e->player,e->kind);
    }
    eventCount=0;
    for (unsigned p=0; p<2; ++p)
        gamePoint(controller,p,guns[p].inside?guns[p].point:(POINT){-1,-1});
    updateReticles(controller);
}
