.intel_syntax noprefix

.section .data

    sockaddr_in:
        .word 2         # AF_INET
        .word 0x5000    # port 80 (in network byte order)
        .long 0         # address

    http_200:
        .asciz "HTTP/1.0 200 OK\r\n\r\n"

.global _start

.section .text

_start:

    # 41 - sys_socket - int family - int type - int protocol
    mov rdi, 2
    mov rsi, 1
    mov rdx, 0
    mov rax, 41
    syscall
    # rax = 3

    # 49 - sys_bind - int fd - struct sockaddr *umyaddr - int addrlen
    mov rdi, rax
    lea rsi, [sockaddr_in]
    mov rdx, 16
    mov rax, 49
    syscall

    # 50 - sys_listen - int fd - int backlog
    mov rdi, 3
    mov rsi, 0
    mov rax, 50
    syscall

accept:
    # 43 - sys_accept - int fd - struct sockaddr *upeer_sockaddr - int *upeer_addrlen
    mov rdi, 3
    mov rsi, 0
    mov rdx, 0
    mov rax, 43
    syscall
    # rax = 4

    # 57 - sys_fork
    mov rax, 57
    syscall
    test rax, rax
    jnz PARENT

CHILD:

    # close fd 3 (listening socket)
    mov rdi, 3
    mov rax, 3
    syscall

    # read request
    # 0 - sys_read - unsigned int fd - char *buf - size_t count
    mov rdi, 4
    sub rsp, 512
    mov rsi, rsp
    mov rdx, 512 # read 512 bytes
    mov rax, 0
    syscall
    # rax = num of read bytes
    mov r8, rax # store read bytes in r8

    # file operations

    # extracting path from the start of the request: "GET /file/path HTTP/1.0 ..."

    mov rbx, 0
    lea rcx, [rsp+3]    # set start of file path
    mov al, [rsp]       # read firt character
    cmp al, 'G'         # GET resquest
    je WHILE
    
    inc rcx             # if POST offset start by 1
    mov r9, 1           # set a flag for later (POST)

    WHILE:
        mov al, [rcx+rbx+1] # start after "GET/POST ", +1 for whitespace
        inc rbx             # counter
        cmp al, ' '         # go until next whitespace (end of file path)
        jne WHILE

        mov al, 0
        mov [rcx+rbx], al   # terminate string at whitespace

    # 2 - sys_open - const char *filename - int flags - int mode
    lea rdi, [rcx+1]    # start of file path
    mov rsi, 0
    mov rdx, 0
    mov rax, 2

    test r9, r9         # if GET, do open syscall with read only flags
    jz READ

    mov rsi, 65         # if POST, do open syscall with write and create flags
    mov rdx, 0777
    syscall
    jmp WRITE

    READ:
    syscall
    mov rdi, rax # rdi = 3
    sub rsp, 256 # make room for 264 bytes on the stack
    mov rsi, rsp
    mov rdx, 256 # read 256 bytes to [sp]
    mov rax, 0
    syscall
    # rax = number or read bytes
    push rax     # store to later use for writing the http data
    jmp close_file

    WRITE:
    # 1 - sys_write - unsigned int fd - const char *buf - size_t count
    # r8 = number of read bytes
    # keep looping through request body using rbx as index until \r
    # then check for \r\n\r\n byte sequence that separates header from body
    # keep track of where the body starts and write it to the file

    WHILE2:
        mov al, [rsp+rbx]
        inc rbx
        cmp rbx, 1024   # failsafe in case there is no \r\n\r\n
        jg exit
        cmp al, '\r'    # go until next \r
        jne WHILE2
    ENTER_HIT:
        # is \r\n\r\n?
        mov eax, [rsp+rbx-1]
        cmp eax, 0x0a0d0a0d
        jne WHILE2      # regular \r\n ... keep going
    
    # \r\n\r\n [rsp+rbx-1]
    # 0 terminate data at end of body (r8 == number of bytes read from request)

    mov al, 0
    mov [rsp+r8], al

    # write to file
    mov rdi, 3
    add rbx, 4      # to skip \r\n\r\n
    lea rsi, [rsp+rbx-1]
    sub r8, rbx
    inc r8          # since rbx was 1 too big
    lea rdx, [r8]   # how many bytes the body is
    mov rax, 1      # sys_write
    syscall

close_file:
    mov rdi, 3
    mov rax, 3
    syscall

    # write_200_ok
    # 1 - sys_write - unsigned int fd - const char *buf - size_t count
    mov rdi, 4
    lea rsi, [http_200]
    mov rdx, 19 # length of "HTTP/1.0 200 OK\r\n\r\n"
    mov rax, 1
    syscall

    # if POST, don't write any file content
    test r9, r9
    jnz exit

    # write_file content
    mov rdi, 4
    pop rdx         # number of file bytes, previously pushed to stack
    lea rsi, [rsp]  # file data
    mov rax, 1
    syscall

jmp exit

PARENT:

    # close accepted fd, this only gets used in the child
    # 3 - sys_close - unsigned int fd
    mov rdi, 4
    mov rax, 3
    syscall

    # parent goes back to accepting
    jmp accept

exit:
    # 60 - sys_exit - int error_code
    mov rdi, 0
    mov rax, 60
    syscall
