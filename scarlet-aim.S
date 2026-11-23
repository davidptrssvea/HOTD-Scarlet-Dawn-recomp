.intel_syntax noprefix
.text
.global scarlet_aim
.global scarlet_aim_end

# Runs at the end of the Windows x64 prologue of UObject::ProcessInternal.
# RBX is the Blueprint frame, RDI is its context. Use the existing shadow space.
scarlet_aim:
    mov r11, [rbx+0x10]                # FFrame::Node (UFunction)
    test r11, r11
    jz original
    mov r10, [rip+name_table]
    test r10, r10
    jz original

    # The same FName can occur on unrelated classes. Match the class and function.
    mov eax, [r11+0x18]
    mov edx, eax
    shr edx, 14
    cmp edx, [r10+0x404]
    jae original
    and eax, 0x3fff
    mov rdx, [r10+rdx*8]
    test rdx, rdx
    jz original
    mov rdx, [rdx+rax*8]
    test rdx, rdx
    jz original
    test byte ptr [rdx], 1
    jnz original
    movabs rax, 0x657265766f486e4f     # OnHovere
    cmp [rdx+0x10], rax
    jne original
    cmp word ptr [rdx+0x18], 0x0064     # d and terminator
    jne original

    mov r11, [r11+0x20]                # UFunction::Outer
    test r11, r11
    jz original
    mov eax, [r11+0x18]
    mov edx, eax
    shr edx, 14
    cmp edx, [r10+0x404]
    jae original
    and eax, 0x3fff
    mov rdx, [r10+rdx*8]
    test rdx, rdx
    jz original
    mov rdx, [rdx+rax*8]
    test rdx, rdx
    jz original
    test byte ptr [rdx], 1
    jnz original
    movabs rax, 0x435f49555f465042     # BPF_UI_C
    cmp [rdx+0x10], rax
    jne original
    cmp byte ptr [rdx+0x18], 0
    jne original

    test r8, r8                         # OnHovered local parameters
    jz original
    mov rcx, [r8]                       # Widget supplied as world context
    test rcx, rcx
    jz original
    call viewport_dpi_scale
    movd eax, xmm0
    cmp eax, 0x3d000000                # Avoid invalid or implausible scales.
    jb original
    cmp eax, 0x42000000
    ja original
    mov r8, [rbx+0x28]
    movq xmm1, [r8+8]                  # Convert the two cursor coordinates.
    shufps xmm0, xmm0, 0
    divps xmm1, xmm0
    movq [r8+8], xmm1

original:
    mov rax, [rdi]
    mov rcx, rdi
    mov r8, [rbx+0x28]
    xor r9d, r9d
    mov rsi, [rbx+0x10]
    mov rdx, rsi
    jmp original_dispatch

scarlet_aim_end:
