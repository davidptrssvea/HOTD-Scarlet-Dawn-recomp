#ifndef SCARLET_RETICLE_H
#define SCARLET_RETICLE_H

enum ReticleStyle { RETICLE_ORIGINAL, RETICLE_OFF, RETICLE_DOT, RETICLE_CROSS,
                    RETICLE_RING, RETICLE_RING_DOT, RETICLE_OPEN_CROSS };
static enum ReticleStyle reticleStyle;
static int reticleSize = 2;
static bool hideNativeCursor;
static const COLORREF reticleKey = RGB(255,0,255);
static struct ReticleSprite {
    HWND window;
    POINT center;
    int radius;
    COLORREF color;
} reticleSprites[2];

static void setReticleColor(unsigned color)
{
    const COLORREF palette[] = {RGB(255,255,255),RGB(255,80,80),RGB(116,255,121),RGB(93,234,255),RGB(255,214,91)};
    if (color >= ARRAYSIZE(palette)) return;
    reticleSprites[0].color=palette[color];
    reticleSprites[1].color=palette[color==3?4:3];
}

static void configureReticle(void)
{
    const wchar_t *styles[] = {L"Original",L"Off",L"Dot",L"Cross",L"Ring",L"RingDot",L"OpenCross"};
    const wchar_t *colors[] = {L"White",L"Red",L"Green",L"Cyan",L"Amber"};
    wchar_t text[24];
    if (GetEnvironmentVariableW(L"SCARLET_RETICLE_STYLE",text,ARRAYSIZE(text))) {
        for (unsigned i=0; i<ARRAYSIZE(styles); ++i)
            if (!_wcsicmp(text,styles[i])) reticleStyle=(enum ReticleStyle)i;
    }
    if (GetEnvironmentVariableW(L"SCARLET_RETICLE_SIZE",text,ARRAYSIZE(text))) {
        int size=(int)wcstoul(text,NULL,10);
        if (size>=1 && size<=3) reticleSize=size;
    }
    unsigned chosen=0;
    if (GetEnvironmentVariableW(L"SCARLET_RETICLE_COLOR",text,ARRAYSIZE(text))) {
        for (unsigned i=0; i<ARRAYSIZE(colors); ++i)
            if (!_wcsicmp(text,colors[i])) chosen=i;
    }
    setReticleColor(chosen);
}

static void reticleLine(HDC dc, int x1, int y1, int x2, int y2)
{
    MoveToEx(dc,x1,y1,NULL);
    LineTo(dc,x2,y2);
}

static void drawReticleShape(HDC dc, const struct ReticleSprite *sprite, bool outline)
{
    int r=sprite->radius;
    int c=r+4;
    int thickness=r>=12?2:1;
    COLORREF color=outline?RGB(15,15,18):sprite->color;
    HPEN pen=CreatePen(PS_SOLID,thickness+(outline?2:0),color);
    HBRUSH brush=CreateSolidBrush(color);
    if (!pen || !brush) {
        if (pen) DeleteObject(pen);
        if (brush) DeleteObject(brush);
        return;
    }
    HGDIOBJ savedPen=SelectObject(dc,pen);
    HGDIOBJ savedBrush=SelectObject(dc,GetStockObject(NULL_BRUSH));
    if (reticleStyle==RETICLE_CROSS) {
        reticleLine(dc,c-r,c,c+r+1,c);
        reticleLine(dc,c,c-r,c,c+r+1);
    } else if (reticleStyle==RETICLE_OPEN_CROSS) {
        int gap=(r+2)/3;
        reticleLine(dc,c-r,c,c-gap,c);
        reticleLine(dc,c+gap,c,c+r+1,c);
        reticleLine(dc,c,c-r,c,c-gap);
        reticleLine(dc,c,c+gap,c,c+r+1);
    }
    if (reticleStyle==RETICLE_RING || reticleStyle==RETICLE_RING_DOT)
        Ellipse(dc,c-r,c-r,c+r+1,c+r+1);
    if (reticleStyle==RETICLE_DOT || reticleStyle==RETICLE_RING_DOT) {
        int dot=(r+4)/5;
        SelectObject(dc,brush);
        Ellipse(dc,c-dot,c-dot,c+dot+1,c+dot+1);
    }
    SelectObject(dc,savedBrush);
    SelectObject(dc,savedPen);
    DeleteObject(brush);
    DeleteObject(pen);
}

static LRESULT CALLBACK reticleProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    if (msg==WM_NCCREATE) {
        const CREATESTRUCTW *create=(const CREATESTRUCTW *)lp;
        SetWindowLongPtrW(hwnd,GWLP_USERDATA,(LONG_PTR)create->lpCreateParams);
    }
    if (msg==WM_NCHITTEST) return HTTRANSPARENT;
    if (msg==WM_MOUSEACTIVATE) return MA_NOACTIVATE;
    if (msg==WM_ERASEBKGND) return 1;
    if (msg==WM_PAINT) {
        struct ReticleSprite *sprite=(struct ReticleSprite *)GetWindowLongPtrW(hwnd,GWLP_USERDATA);
        PAINTSTRUCT paint;
        HDC dc=BeginPaint(hwnd,&paint);
        RECT area;
        GetClientRect(hwnd,&area);
        HBRUSH key=CreateSolidBrush(reticleKey);
        if (key) {
            FillRect(dc,&area,key);
            DeleteObject(key);
        }
        if (sprite) {
            drawReticleShape(dc,sprite,true);
            drawReticleShape(dc,sprite,false);
        }
        EndPaint(hwnd,&paint);
        return 0;
    }
    return DefWindowProcW(hwnd,msg,wp,lp);
}

static void hideReticle(unsigned player)
{
    HWND hwnd=reticleSprites[player].window;
    if (hwnd && IsWindowVisible(hwnd)) ShowWindow(hwnd,SW_HIDE);
}

static void moveReticle(HWND owner, unsigned player, POINT screen, int height)
{
    struct ReticleSprite *sprite=&reticleSprites[player];
    const int sizes[]={6,10,15};
    int r=(sizes[reticleSize-1]*height+540)/1080;
    if (r<4) r=4;
    if (r>48) r=48;
    bool redraw=r!=sprite->radius;
    sprite->radius=r;
    if (!sprite->window) {
        HINSTANCE instance=GetModuleHandleW(NULL);
        WNDCLASSW cls={.lpfnWndProc=reticleProc,.hInstance=instance,.lpszClassName=L"ScarletReticle"};
        RegisterClassW(&cls);
        sprite->window=CreateWindowExW(WS_EX_LAYERED|WS_EX_TRANSPARENT|WS_EX_NOACTIVATE|WS_EX_TOOLWINDOW,
            cls.lpszClassName,L"",WS_POPUP|WS_DISABLED,0,0,0,0,owner,NULL,instance,sprite);
        if (!sprite->window) return;
        if (!SetLayeredWindowAttributes(sprite->window,reticleKey,255,LWA_COLORKEY)) {
            DestroyWindow(sprite->window);
            sprite->window=NULL;
            return;
        }
        redraw=true;
    }
    if (redraw || screen.x!=sprite->center.x || screen.y!=sprite->center.y || !IsWindowVisible(sprite->window)) {
        int offset=r+4;
        int span=2*offset+1;
        if (SetWindowPos(sprite->window,HWND_TOPMOST,screen.x-offset,screen.y-offset,span,span,
                         SWP_NOACTIVATE|SWP_NOOWNERZORDER|SWP_SHOWWINDOW)) sprite->center=screen;
        if (redraw) InvalidateRect(sprite->window,NULL,FALSE);
    }
}

static void clearReticles(void)
{
    for (unsigned p=0;p<2;++p) hideReticle(p);
    hideNativeCursor=false;
}

#endif
