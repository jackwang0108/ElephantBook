%include "boot.inc"

section loader  vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP equ LOADER_BASE_ADDR

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

; total_mem bytes 用于保存内存容量，以字节为单位，此位置比较好记
; 当前偏移 loader.bin 文件头 Ox200 字节 (64个段描述符 * 8字节 + 0个jmp指令 * 3字节 = 515字节, 203H)
; loader. bin 的加载地址是 Ox900
; 故 total mem_bytes 内存中的地址是 OxbOO 将来在内核中咱们会引用此地址
total_mem_bytes dd 0

; 构建段选择子
SELECTOR_CODE   equ     (0x0001 << 3) + TI_GDT + RPL0
SELECTOR_DATA   equ     (0x0002 << 3) + TI_GDT + RPL0
SELECTOR_VIDEO  equ     (0x0003 << 3) + TI_GDT + RPL0

; GDT指针
gdt_ptr dw      GDT_LIMIT
    dd      GDT_BASE

; ards结构体数组, total_memory_byes(4 字节) + gdt_ptr(6 字节) + ards_buf(244 字节) + ards_nr (2 字节) = 256字节
ards_buf times 244 db 0
ards_nr dw 0

; data
loader_msg db '2 loader in real.'

loader_start:

    ; 输出字符串 利用0x13功能
    ; -----------------------------------------------------------
    ; INT 0x10   功能号:0x13	   功能描述:输出字符串
    ; -----------------------------------------------------------
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

    ; 获取内存大小 利用0x15中断的E820功能号
    ; -----------------------------------------------------------
    ; INT 0x15   功能号: 0xE820	   功能描述: 以ARDS结构体形式返回内存大小
    ; -----------------------------------------------------------
    ; 输入:
    ;   EAX 功能号= 0xE820
    ;   EDX = SMAP签名，固定为0x534D4150，当成magic number处理
    ;   ECX = ARDS结构的字节大小，目前是20字节
    ;   EBX = 后续值，由BIOS填写，初次用要设置为0
    ;   ES:DI = ARDS缓冲区的地址
    ; 返回值:
    ;   CF位: 0表示调用为出错，1表示出错
    ;   EAX: SMAP签名
    ;   ECX: 写入的字节大小
    ;   EBX: 后续值
    ;   ES:DI = 和输入值一样，但是已经填充了信息
    xor ebx, ebx
    mov edx, 0x534D4150
    mov di, ards_buf
    .e820_mem_get_loop:
        mov eax, 0x0000_E820
        mov ecx, 20
        int 0x15
        jc .e820_failed_so_try_e801     ; CF=1，有错误发生，则尝试使用e801获取内存
        add di, cx                      ; 移动指针
        inc word [ards_nr]              ; ards数量加1
        cmp ebx, 0                      ; 最后一个结构，返回值为0
        jnz .e820_mem_get_loop

    ; 获取ards数组中BaseAddrLow + LengthLow最大值，就是寻址空间内存的大小
    mov cx, [ards_nr]
    mov ebx, ards_buf                   ; ebx是指向ards的指针
    xor edx, edx
    .find_max_mem_area:
        mov eax, [ebx]
        add eax, [ebx + 8]
        add ebx, 20                     ; 指向下一个ards指针
        cmp edx, eax
        jge .next_ards                  ; edx <= eax
        mov edx, eax
        .next_ards:
            loop .find_max_mem_area
            jmp .mem_get_ok


    ; 通过BIOS 15H中断的E820功能号失败，则尝试E801功能号获取内存大小
    .e820_failed_so_try_e801:

    ; 获取内存大小 利用0x15中断的E801功能号
    ; -----------------------------------------------------------
    ; INT 0x15   功能号: 0xE801	   功能描述: 底端在AX/CX，高端在BX/DX
    ; -----------------------------------------------------------
    ; 输入:
    ;   EAX 功能号= 0xE801
    ; 返回值:
    ;   CF位: 0表示调用为出错，1表示出错
    ;   AX: 低端15MB的寻址空间大小，以1KB为单位
    ;   CX: 和AX相同
    ;   BX: 高端16MB~4GB的寻址空间大小，以64KB为单位
    ;   DX: 和BX相同
    mov eax, 0xE801
    int 0x15
    jc .e801_failed_so_try88            ; CF=1，有错误发生，尝试使用0x88功能号

    ; 首先计算底端16MB内存大小
    mov cx, 0x400                       ; 1KB = 2^10B
    mul cx                              ; ax * cx, 16位计算结果32位在DX:AX
    shl edx, 16
    and eax, 0x0000_FFFF
    or edx, eax
    add edx, 0x10_0000                  ; 高端1MB保留给ISA了
    mov esi, edx

    ; 然后计算16MB以上的内存
    xor eax, eax
    mov ax, bx
    mov ecx, 0x1_0000
    mul ecx                             ; eax * ecx, 32位计算结果64位EDX:EAX
    add esi, eax
    mov edx, esi

    jmp .mem_get_ok


    ; 通过BIOS 15H中断的E801功能号失败，则尝试88功能号获取内存大小
    .e801_failed_so_try88:

    ; 获取内存大小 利用0x15中断的88功能号
    ; -----------------------------------------------------------
    ; INT 0x15   功能号: 0x88	   功能描述: 底端在AX/CX，高端在BX/DX
    ; -----------------------------------------------------------
    ; 输入:
    ;   AH 功能号= 0x88
    ; 返回值:
    ;   CF位: 0表示调用为出错，1表示出错
    ;   AX: 以1KB作为单位大小的1MB以上的连续单位数量
    mov ah, 0x88
    int 0x15
    jc .err_hlt                         ; CF=1，有错误发生，此时三种方式都无法获得寻址空间大小，停机报错
    and eax, 0x0000_FFFF

    mov cx, 0x400
    mul cx                              ; ax * cx, 16位计算结果32位在DX:AX
    shl edx, 16
    or edx, eax
    add edx, 0x10_0000

    ; 将寻址空间大小存入total_mem_bytes处
    .mem_get_ok:
        mov [total_mem_bytes], edx
    
    .err_hlt:

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
p_mode_start:                           ; 保护模式开启，此后所有代码都是运行在保护模式下
    mov ax, SELECTOR_DATA
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, LOADER_STACK_TOP
    mov ax, SELECTOR_VIDEO
    mov gs, ax

    mov byte [gs:160], 'P'

    jmp $