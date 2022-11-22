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
    mov byte [gs:162], 'r'
    mov byte [gs:164], 'o'
    mov byte [gs:166], 't'
    mov byte [gs:168], 'e'
    mov byte [gs:170], 'c'
    mov byte [gs:172], 't'
    mov byte [gs:174], 'i'
    mov byte [gs:176], 'o'
    mov byte [gs:178], 'n'
    mov byte [gs:180], ' '
    mov byte [gs:182], 'm'
    mov byte [gs:184], 'o'
    mov byte [gs:186], 'd'
    mov byte [gs:188], 'e'


    ; -------------------- 准备开启内存分页 --------------------
    ; 第一步：准备页目录表、页表
    ; 第二步：段描述符表中线性地址转虚拟地址
    ; 第三步：页目录地址赋给cr3
    ; 第四步：cr0的pg位设置为1
    ; 第五步：分页机制下重新加载段描述符表

    ; 第一步：准备页目录表、页表
    call setup_page

    ; 第二步：线性地址转虚拟地址, 因为等会开启分页后，线性地址就成虚拟地址了，所以为了开启分页之后还是能够访问, 这里先把前面的线性地址转为虚拟地址
    sgdt [gdt_ptr]                              ; 段描述符表地址和大小先保存，等会要重新加载
    mov ebx, [gdt_ptr + 2]                      ; 首先转换视频段
    or dword [ebx + 0x18 + 4], 0xC000_0000      ; 第三个段描述符指向视频段，每个段描述符8字节，所以 + 0x18, 高4字节是段基地址的31~24位
    add dword [gdt_ptr + 2], 0xC000_0000        ; gdt也要转换
    add esp, 0xC000_0000                        ; 栈也要转换

    ; 第三步：页目录地址赋给cr3
    mov eax, PAGE_DIR_TABLE_POS
    mov cr3, eax

    ; 第四步：cr0的pg位设置为1
    mov eax, cr0
    or eax, 0x8000_0000
    mov cr0, eax

    ; 第五步：分页机制下重新加载段地址
    lgdt [gdt_ptr]

    mov byte [gs:320], 'V'
    mov byte [gs:322], 'i'
    mov byte [gs:324], 'r'
    mov byte [gs:326], 't'
    mov byte [gs:328], 'u'
    mov byte [gs:330], 'a'
    mov byte [gs:332], 'l'
    mov byte [gs:334], ' '
    mov byte [gs:336], 'm'
    mov byte [gs:338], 'o'
    mov byte [gs:340], 'd'
    mov byte [gs:342], 'e'

    jmp $


; 函数 
; -----------------------------------------------------------
; setup_page   初始化页目录和第一个页表
; -----------------------------------------------------------
; 无输入:
; 无返回值:
setup_page:
    ; 清除页目录的内存
    mov ecx, 4096
    mov esi, 0
    .clear_page_dir:                    ; 逐字节清除
        mov byte [PAGE_DIR_TABLE_POS + esi], 0
        inc esi
        loop .clear_page_dir
    
    ; 创建页目录项
    .create_pde:
        mov eax, PAGE_DIR_TABLE_POS     ; PAGE_DIR_TABLE_POS = 0x10_0000
        add eax, 0x1000                 ; 0x1000 = 4096, 页目录占用一个页，后面的就是下一个页
        mov ebx, eax                    ; 第一个页的地址（不计页目录的也）eax = 0x10_1000
        
        or eax, PG_US_U | PG_RW_W | PG_P        ; 构建页目录项
        mov [PAGE_DIR_TABLE_POS + 0x0], eax     ; 第一个页目录项，指向的页表在0x10_1000，这个页表是第一个页，也是操作系统所在的页
        mov [PAGE_DIR_TABLE_POS + 0xc00], eax   ; 0xc00就是第768个页表, 让第768个页表也指向操作系统的页表,0~767一共768个页表，表示3G空间; 768~1022一个254个页表，表示3G-4M空间

        sub  eax, 0x1000                        ; eax = 0x10_0000, 指向页目录地址本身
        mov [PAGE_DIR_TABLE_POS + 4092], eax    ; 页目录表最后一个页目录项指向页目录自己（页目录占用一个页）
    
    ; 创建第一个页表(0x10_1000)的内容，这个页表指向操作系统
    mov ecx, 256                            ; 一个页表4M, 操作系统在0~1M, 一个页4K, 所以表示操作系统需要256个页
    mov esi, 0
    xor edx, edx
    mov edx, PG_US_U | PG_RW_W | PG_P       ; edx = 0x0000_0000, 指向操作系统
    .create_pte:
        mov [ebx + esi * 4], edx            ; ebx = 0x10_1000，第一个页的地址
        add edx, 4096                       ; edx + 4096, 下一个页
        inc esi
        loop .create_pte
    
    ; 创建内核其他页表的PDE
    mov eax, PAGE_DIR_TABLE_POS             ; PAGE_DIR_TABLE_POS = 0x10_0000
    add eax, 0x2000                         ; 第二个页的地址（不计页目录的页）eax = 0x10_2000
    or eax, PG_US_U | PG_RW_W | PG_P        ; 构建页目录项
    mov ebx, PAGE_DIR_TABLE_POS
    mov ecx, 254
    mov esi, 769
    .create_kernel_pde:
        mov [ebx + esi * 4], eax            ; ebx是Page_dir的地址
        inc esi
        add eax, 0x1000                     ; 0x1000 = 4096，下一个页
        loop .create_kernel_pde

    ret
