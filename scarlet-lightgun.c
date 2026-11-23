#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <wchar.h>
#include "scarlet-reticle.h"

/* Offsets are for the SHA-256 checked Scarlet Dawn export build only. */
typedef void (*GameCall)(void *);
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
static bool clearButtons, initialized, gunMode, rawMode, reloadEnabled;
static unsigned borderWidth;
static HWND gameWindow, borderWindow;
static RECT borderBounds;
static int whiteEdge, blackEdge;
static uintptr_t imageBase;
static void *previousController;
static bool secondPlayerWasActive, secondPlayerIsActive;
static unsigned deliveredButtons[2];

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
        RemoveWindowSubclass(hwnd, gameProc, id);
        gameWindow = NULL;
        borderWindow = NULL;
        clearReticles();
        for (unsigned p=0;p<2;++p) reticleSprites[p].window=NULL;
        eventCount = 0;
        for (unsigned p = 0; p < 2; ++p) resetGun(&guns[p]);
    }
    if (msg == WM_SETCURSOR && LOWORD(lp)==HTCLIENT && hideNativeCursor) {
        SetCursor(NULL);
        return TRUE;
    }
    if (msg == WM_KILLFOCUS) {
        clearReticles();
        if (borderWindow) ShowWindow(borderWindow,SW_HIDE);
        clearButtons = true;
        eventCount = 0;
        for (unsigned p = 0; p < 2; ++p) resetGun(&guns[p]);
    }
    if (!gunMode) return DefSubclassProc(hwnd,msg,wp,lp);
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
    gunMode = rawMode || !wcscmp(value,L"Sinden");
    configureReticle();
    GetEnvironmentVariableW(L"SCARLET_GUN_RELOAD",value,ARRAYSIZE(value));
    reloadEnabled = wcscmp(value,L"0") != 0;
    if (GetEnvironmentVariableW(L"SCARLET_GUN_BORDER",value,ARRAYSIZE(value))) borderWidth = wcstoul(value,NULL,10);
    if (borderWidth>100) borderWidth=0;
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
    if (!rawMode || !_wcsicmp(guns[1].path,L"disabled")) return false;
    typedef void *(*GetWorld)(void *);
    GetWorld getWorld = *(GetWorld *)(*(uint8_t **)controller+0x138);
    uint8_t *world = getWorld(controller);
    if (!world) return false;
    void *instance = *(void **)(world+0x140);
    if (!instance) return false;

    /* Query the same Blueprint predicate that controls the equipment menus. */
    static uint64_t name;
    typedef void *(*MakeName)(uint64_t *, const char *, int);
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

static void callGame(void *controller, unsigned player, enum GunEvent kind)
{
    if (player && kind < START_DOWN && !secondPlayerIsActive) return;
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
    hideNativeCursor=cursorInClient && (appData[0x231]!=0 || (rawMode && appData[0x232]!=0));
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
        if (reticleStyle==RETICLE_OFF || (p==1 && !rawMode) || !appData[0x231+p] ||
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
    if (!gunMode) {
        updateReticles(controller);
        return;
    }

    if (!rawMode && GetForegroundWindow()==gameWindow) {
        POINT point;
        if (GetCursorPos(&point) && ScreenToClient(gameWindow,&point)) aim(0,point);
    }
    if (rawMode && GetForegroundWindow()==gameWindow) {
        static ULONGLONG nextRegistrationCheck;
        ULONGLONG now=GetTickCount64();
        if (now>=nextRegistrationCheck) {
            ensureRawRegistration();
            nextRegistrationCheck=now+1000;
        }
    }
    updateBorder();

    secondPlayerIsActive = secondPlayerActive(controller);
    if (previousController!=controller) {
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
