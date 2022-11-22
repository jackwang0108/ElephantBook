%include "boot.inc"

section loader  vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP equ LOADER_BASE_ADDR
jmp loader_start

; 构建gdt及其内部描述符
GDT_BASE:
    dd  0x0000_0000
    dd  0x0000_0000
CODE_DESC:
    dd  0x0000_FFFF
    dd  DESC_CODE_HIGH4
DATA_STACK_DESC:
    dd  0x0000_FFFF
    dd  DESC_DATA_HIGH4
VIDEO_DESC:
    dd  0x8000_0007
    dd DESC_VIDEO_HIGH4
GDT_SIZE    equ     $ - GDT_BASE            ; GDT_SIZE和GDT_LIMIT都是为后续加载GDT做准备
GDT_LIMIT   equ     GDT_SIZE - 1
times 60 dq 0                               ; 为GDT预留60个描述符的位置

; 构建段选择子
SELECTOR_CODE   equ     (0x0001 << 3) + TI_GDT + RPL0
SELECTOR_DATA   equ     (0x0002 << 3) + TI_GDT + RPL0
SELECTOR_VIDEO  equ     (0x0003 << 3) + TI_GDT + RPL0

; GDT指针
gdt_ptr dw      GDT_LIMIT
    dd      GDT_BASE

; data
loader_msg db '2 loader in real.'

loader_start:

    ; 输出字符串 利用0x13功能
    ; -----------------------------------------------------------
    ; INT 0x10   功能号:0x13	   功能描述:输出字符串
    ; ------------------------------------------------------
    ; 输入:
    ;   AH 功能号= 0x13
    ;   AL = 写字符方式, AL=0x01表示光标跟随字符移动(每写一个字符，光标后移一个字符)
    ;       - 0: 字符串中只含显示字符, 其显示属性在BL, 显示后，光标位置不变
    ;       - 1: 字符串中只含显示字符, 其显示属性在BL, 显示后，光标位置改变
    ;       - 2: 字符事中含显示字符和显示属性。显示后, 光标位置不变
    ;       - 3: 字符串中含显示字符和显示属性。显示后, 光标位置改变
    ;   BH = 要显示的页号
    ;   BL = 字符属性, BL=0x02表示黑底绿字
    ;   CX = 字符串的长度，不包括结尾的'\0'
    ;   ES:BP = 字符串首地址
    ; 无返回值:
    mov sp, LOADER_STACK_TOP
    mov bp, loader_msg
    mov cx, 17
    mov ax, 0x13_01
    mov bx, 0x00_1F         ; 1F: 蓝底粉红字
    mov dx, 0x18_00
    int 10h

    ; -------------------- 准备进入保护模式 --------------------
    ; 第一步：打开A20
    ; 第二步：加载GDT
    ; 第三步：cr0的pe位设置为1

    ; 第一步: 打开A20
    in al, 0x92
    or al, 0000_0010B
    out 0x92, al

    ; 第二步: 记载GDT
    lgdt [gdt_ptr]

    ; 第三步: cr0第0位置1
    mov eax, cr0
    or eax, 0x0000_0001
    mov cr0, eax

    ; 第四步: 刷新流水线
    jmp dword SELECTOR_CODE:p_mode_start

[bits 32]
p_mode_start:
    mov ax, SELECTOR_DATA
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, LOADER_STACK_TOP
    mov ax, SELECTOR_VIDEO
    mov gs, ax

    mov byte [gs:160], 'P'

    jmp $
