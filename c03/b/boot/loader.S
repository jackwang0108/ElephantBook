%include "boot.inc"

section loader vstart=LOADER_START_SECTOR
    mov byte [gs:0x00], '2'
    mov byte [gs:0x01], 0xA4            ; A表示绿色背景闪烁，4表示前景色位红色

    mov byte [gs:0x02], ' '
    mov byte [gs:0x03], 0xA4            ; A表示绿色背景闪烁，4表示前景色位红色

    mov byte [gs:0x04], 'L'
    mov byte [gs:0x05], 0xA4            ; A表示绿色背景闪烁，4表示前景色位红色

    mov byte [gs:0x06], 'O'
    mov byte [gs:0x07], 0xA4            ; A表示绿色背景闪烁，4表示前景色位红色

    mov byte [gs:0x08], 'A'
    mov byte [gs:0x09], 0xA4            ; A表示绿色背景闪烁，4表示前景色位红色

    mov byte [gs:0x0A], 'D'
    mov byte [gs:0x0B], 0xA4            ; A表示绿色背景闪烁，4表示前景色位红色

    mov byte [gs:0x0C], 'E'
    mov byte [gs:0x0D], 0xA4            ; A表示绿色背景闪烁，4表示前景色位红色

    mov byte [gs:0x0E], 'R'
    mov byte [gs:0x0F], 0xA4            ; A表示绿色背景闪烁，4表示前景色位红色

    jmp $