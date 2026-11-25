#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <xinput.h>
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>

static XINPUT_STATE samples[XUSER_MAX_COUNT];
static bool connected[XUSER_MAX_COUNT];
static ULONGLONG clockMs;
static int cursorCount;
static HCURSOR cursorShape;

static int WINAPI testShowCursor(BOOL show)
{
    return cursorCount += show ? 1 : -1;
}

static BOOL WINAPI testCursorInfo(PCURSORINFO info)
{
    info->flags=cursorCount < 0 ? 0 : CURSOR_SHOWING;
    return TRUE;
}

static BOOL WINAPI testCursorPos(LPPOINT point)
{
    *point=(POINT){10,10};
    return TRUE;
}

static HCURSOR WINAPI testSetCursor(HCURSOR shape)
{
    HCURSOR previous=cursorShape;
    cursorShape=shape;
    return previous;
}

static DWORD WINAPI testGetState(DWORD index, XINPUT_STATE *state)
{
    if (!connected[index]) return ERROR_DEVICE_NOT_CONNECTED;
    *state = samples[index];
    return ERROR_SUCCESS;
}

static ULONGLONG WINAPI testGetTickCount(void)
{
    return clockMs;
}

#define XInputGetState testGetState
#define GetTickCount64 testGetTickCount
#define ShowCursor testShowCursor
#define GetCursorInfo testCursorInfo
#define GetCursorPos testCursorPos
#define SetCursor testSetCursor
#include "../scarlet-lightgun.c"

static void expectEvent(unsigned index, unsigned player, enum GunEvent kind)
{
    assert(index < eventCount);
    assert(events[index].player == player);
    assert(events[index].kind == kind);
}

int main(void)
{
    SetEnvironmentVariableW(L"SCARLET_GUN_MODE", L"Gamepad");
    SetEnvironmentVariableW(L"SCARLET_GUN_RELOAD", L"0");
    readEnvironment();
    assert(gamepadMode && gunMode && !rawMode && reloadEnabled);
    gameWindow = CreateWindowW(L"STATIC", L"", WS_POPUP, 0, 0, 1000, 600, NULL, NULL, NULL, NULL);
    assert(gameWindow);
    assert(SetWindowSubclass(gameWindow, gameProc, 1, 0));

    cursorShape=LoadCursor(NULL,IDC_ARROW);
    updateGamepadCursor(true);
    assert(cursorCount == -1 && cursorHideCalls == 1 && !cursorShape);
    updateGamepadCursor(true);
    assert(cursorCount == -1 && cursorHideCalls == 1);
    updateGamepadCursor(false);
    assert(cursorCount == 0 && cursorHideCalls == 0);

    connected[1] = connected[3] = true;
    updateGamepads(false);
    assert(gamepads[0].index == 1 && gamepads[1].index == 3);
    assert(guns[0].point.x == 500 && guns[0].point.y == 300);
    assert(eventCount == 2);
    expectEvent(0, 0, SCREEN_IN);
    expectEvent(1, 1, SCREEN_IN);

    eventCount = 0;
    RECT viewport = {0, 0, 1000, 600};
    XINPUT_GAMEPAD motion = {.sThumbLX=3000, .sThumbLY=-4000};
    applyGamepad(0, &motion, &viewport, 0.05);
    assert(guns[0].point.x == 500 && guns[0].point.y == 300);
    motion.sThumbRX = 32767;
    motion.sThumbRY = 32767;
    applyGamepad(0, &motion, &viewport, 0.05);
    assert(guns[0].point.x > 500 && guns[0].point.y < 300);
    for (int tick=0; tick<30; ++tick) applyGamepad(0, &motion, &viewport, 0.05);
    assert(guns[0].point.x == 999 && guns[0].point.y == 0);
    assert(guns[1].point.x == 500 && guns[1].point.y == 300);
    assert(eventCount == 0);

    samples[1].Gamepad.bRightTrigger = XINPUT_GAMEPAD_TRIGGER_THRESHOLD;
    updateGamepads(false);
    assert(eventCount == 0);
    samples[1].Gamepad.bRightTrigger++;
    samples[3].Gamepad.wButtons = XINPUT_GAMEPAD_START;
    updateGamepads(false);
    assert(eventCount == 2);
    expectEvent(0, 0, FIRE_DOWN);
    expectEvent(1, 1, START_DOWN);
    eventCount = 0;
    samples[1].Gamepad.bRightTrigger = 0;
    samples[1].Gamepad.wButtons = XINPUT_GAMEPAD_A;
    updateGamepads(false);
    assert(eventCount == 0);

    samples[1].Gamepad.wButtons |= XINPUT_GAMEPAD_X;
    samples[3].Gamepad.wButtons = XINPUT_GAMEPAD_RIGHT_SHOULDER;
    updateGamepads(false);
    assert(eventCount == 4);
    expectEvent(0, 0, FIRE_UP);
    expectEvent(1, 0, SCREEN_OUT);
    expectEvent(2, 1, SELECT_DOWN);
    expectEvent(3, 1, START_UP);
    eventCount = 0;
    updateGamepads(false);
    assert(eventCount == 1);
    expectEvent(0, 0, SCREEN_IN);
    assert(!guns[0].trigger);

    SendMessageW(gameWindow, WM_KILLFOCUS, 0, 0);
    assert(clearButtons && !guns[0].trigger && !guns[1].selecting);
    updateGamepads(false);
    assert(eventCount == 2);
    expectEvent(0, 0, SCREEN_IN);
    expectEvent(1, 1, SCREEN_IN);

    eventCount = 0;
    samples[1].Gamepad.wButtons = 0;
    updateGamepads(false);
    samples[1].Gamepad.bRightTrigger = 255;
    updateGamepads(false);
    connected[1] = false;
    updateGamepads(false);
    assert(eventCount == 2);
    expectEvent(0, 0, FIRE_DOWN);
    expectEvent(1, 0, FIRE_UP);
    assert(gamepads[0].index == XUSER_MAX_COUNT && gamepads[1].index == 3);
    eventCount = 0;
    clockMs += 1000;
    connected[0] = true;
    samples[0].Gamepad.wButtons = XINPUT_GAMEPAD_START;
    updateGamepads(false);
    assert(gamepads[0].index == 0 && gamepads[1].index == 3);
    assert(eventCount == 1);
    expectEvent(0, 0, SCREEN_IN);

    eventCount = 0;
    samples[0].Gamepad.wButtons = XINPUT_GAMEPAD_BACK;
    updateGamepads(false);
    assert(pauseRequested && eventCount == 0);

    DestroyWindow(gameWindow);
    puts("PASS: XInput assignment, independent aim, dead zones, gameplay buttons, focus and disconnect");
    return 0;
}
