mov ds, ax
mov ax, [0x7]
label: 
    jmp label
    var dw 0x99