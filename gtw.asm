section .text

REENQUEUE: equ 2
APP_RESPONSE: equ 1

NEW_WORK: equ 2
RESPONSE: equ 1
MASK: equ 32767

GT_WGM_RINGS_PTR: equ 0    ; IO
GT_WGM_FUNCTION_PTR: equ 8 ; callback
GT_WGM_WM_ROUND_IDX: equ 16    ; where to pass the next job
GT_WGM_WM_MAX_COUNT: equ 24
GT_WGM_W_MAX_COUNT: equ 32
GT_WGM_EPOLL_FD: equ 40
GT_WGM_IN_TAIL: equ 64
GT_WGM_IN_HEAD: equ 72
GT_WGM_OUT_TAIL: equ 80
GT_WGM_OUT_HEAD: equ 88
GT_WGM_WM_LEN: equ 96 
GT_WGM_IN_QUEUE_PTR: equ 104
GT_WGM_OUT_QUEUE_PTR: equ 112
GT_WGM_RINGS: equ 128
GT_WGM_WM_OFF: equ 256

GT_WM_NEXT_W_NODE: equ 0    ; next work handler
GT_WM_IN_TAIL: equ 8
GT_WM_IN_HEAD: equ 16
GT_WM_OUT_TAIL: equ 24
GT_WM_OUT_HEAD: equ 32
GT_WM_WGM_PTR: equ 40
GT_WM_USER_DATUM: equ 48
; FREE_SPACE: 8 bytes
GT_WM_SAVED_REGISTERS: equ 64
GT_WM_NEXT_INSTRUCTION: equ 96 ; this is inside the saved registers
GT_WM_QUEUE_IN: equ 256
GT_WM_QUEUE_OUT: equ 1050624

GT_W_PARENT_WM: equ 0
GT_W_NEXT_W_NODE: equ 8
GT_W_INSTRUCTION_PTR: equ 16
GT_W_STACK_BASE_PTR: equ 24
GT_W_STACK_PTR: equ 32
; 32 bytes empty
GT_W_IN_TAIL: equ 64
GT_W_IN_HEAD: equ 72
GT_W_OUT_TAIL: equ 80
GT_W_OUT_HEAD: equ 88

extern rings_setup
extern rings_reap
extern rings_submit

global gt_wgm_compute_req_mem
global gt_wgm_init
global gt_wgm_add_manager
global gt_wm_init
global gt_wm_add_worker
global gt_wgm_submit_work
global gt_wgm_work
global gt_wgm_get_datum_back
global gt_wm_work
global gt_wm_set_user_datum
global gt_w_get_wm_datum
global gt_w_return
global gt_w_write
global gt_w_read
global gt_w_close
global gt_w_openat
global gt_w_send_datum_back


gt_wgm_compute_req_mem:
  ; RDI -> max managers
  ; RSI -> max workers
  shl rsi,1
  add rdi,rsi
  lea rax,[rdi*8+256]
  ret


gt_wgm_init:
  ; RDI -> wgm
  ; RSI -> max managers
  ; RDX -> max workers
  ; RCX -> work callback
  pxor xmm0,xmm0
  movdqa [rdi+64],xmm0
  movdqa [rdi+80],xmm0
  movdqa [rdi+96],xmm0
  movdqa [rdi+112],xmm0

  lea r8,[rdi+GT_WGM_RINGS]

  mov [rdi+GT_WGM_RINGS_PTR],r8
  mov [rdi+GT_WGM_FUNCTION_PTR],rcx
  mov qword [rdi+GT_WGM_WM_ROUND_IDX],0
  mov [rdi+GT_WGM_WM_MAX_COUNT],rsi
  mov [rdi+GT_WGM_W_MAX_COUNT],rdx

  ; skip the work managers
  lea rax,[rdi+rsi*8+GT_WGM_WM_OFF]
  mov [rdi+GT_WGM_IN_QUEUE_PTR],rax

  ; skip in queue
  lea r11,[rax+rdx*8]
  mov [rdi+GT_WGM_OUT_QUEUE_PTR],r11

  push rdi

  mov eax,291
  xor edi,edi
  syscall
  cmp rax,0
  jl .ret_error

  pop rdi
  mov [rdi+GT_WGM_EPOLL_FD],rax

  mov rdi,[rdi+GT_WGM_RINGS_PTR]
  mov rsi,32768
  call rings_setup

  ret

.ret_error:
  xor eax,eax
  ret


gt_wgm_add_manager:
  ; RDI -> wgm
  ; RSI -> manager
  mov rax,[rdi+GT_WGM_WM_LEN]
  mov [rdi+GT_WGM_WM_OFF+rax*8],rsi
  inc rax
  mov [rdi+GT_WGM_WM_LEN],rax
  mov [rsi+GT_WM_WGM_PTR],rdi
  ret


gt_wm_init:
  ; RDI -> wm
  pxor xmm0,xmm0
  movdqa [rdi],xmm0
  movdqa [rdi+16],xmm0
  movdqa [rdi+32],xmm0
  movdqa [rdi+48],xmm0
  movdqa [rdi+64],xmm0
  movdqa [rdi+80],xmm0
  movdqa [rdi+96],xmm0
  movdqa [rdi+112],xmm0
  movdqa [rdi+128],xmm0
  movdqa [rdi+144],xmm0
  movdqa [rdi+160],xmm0
  movdqa [rdi+176],xmm0
  movdqa [rdi+192],xmm0
  movdqa [rdi+208],xmm0
  movdqa [rdi+224],xmm0
  movdqa [rdi+240],xmm0
  ret


gt_wm_add_worker:
  ; RDI -> wm
  ; RSI -> worker
  ; RDX -> stack
  pxor xmm0,xmm0
  movdqa [rsi+0],xmm0
  movdqa [rsi+16],xmm0
  movdqa [rsi+32],xmm0
  movdqa [rsi+48],xmm0

  mov [rsi+GT_W_PARENT_WM],rdi

  ; get next linked worker
  mov rcx,[rdi+GT_WM_NEXT_W_NODE]

  ; add to this link
  mov [rsi+GT_W_NEXT_W_NODE],rcx

  ; replace old node by this one
  mov [rdi+GT_WM_NEXT_W_NODE],rsi

  and rdx,0xfffffffffffffff0
  mov [rsi+GT_W_STACK_BASE_PTR],rdx

  ret


gt_wgm_submit_work:
  ; RDI -> wgm
  ; RSI -> datum

  ; get tail and head
  mov rax,[rdi+GT_WGM_IN_TAIL]
  mov rcx,[rdi+GT_WGM_IN_HEAD]

  ; get maximum
  mov r8,[rdi+GT_WGM_W_MAX_COUNT]
  lea r9,[rcx+1]

  ; wrap around if needed
  xor edx,edx
  cmp r9,r8
  cmove r9d,edx

  ; check if the queue is full
  cmp r9,rax
  je .full

  ; ok, can add to the queue
  mov rdx,[rdi+GT_WGM_IN_QUEUE_PTR]

  ; now rdx points to the in queue
  dec r9
  mov [rdx+r9*8],rsi
  inc r9
  mov [rdi+GT_WGM_IN_HEAD],r9

  xor eax,eax
  inc eax
  ret

.full:
  xor eax,eax
  ret


gt_wgm_work:
  ; RDI -> wgm
  push rbp
  push rbx
  push r12
  sub rsp,64

  ; check in queue
  mov rsi,[rdi+GT_WGM_IN_TAIL]
  mov rdx,[rdi+GT_WGM_IN_HEAD]

  ; worker count is the size of the queue
  mov rcx,[rdi+GT_WGM_W_MAX_COUNT]

  ; address of the in queue
  mov rbp,[rdi+GT_WGM_IN_QUEUE_PTR]

  .consume_in_queue:
    ; if tail = head
    ; then it's empty
    cmp rsi,rdx
    je .consume_io

    mov r12,[rbp+rsi*8]

  ; next round work manager idx
  mov rax,[rdi+GT_WGM_WM_ROUND_IDX]
  
  ; work manager count
  mov r9,[rdi+GT_WGM_WM_LEN]

  ; value to wrap around to
  xor r8,r8

  ; move to the next position
  inc rax

  ; check if it's full
  cmp rax,r9

  ; wrap around if needed
  cmovz rax,r8
  mov [rdi+GT_WGM_WM_ROUND_IDX],rax

  ; work manager
  mov rbx,[rdi+rax*8+GT_WGM_WM_OFF]

  mov r8,[rbx+GT_WM_IN_TAIL]
  mov r9,[rbx+GT_WM_IN_HEAD]

  inc r9
  and r9,MASK
  cmp r9,r8
  je .retry_in_enqueue

  ; post work in r12
.can_in_enqueue:
  dec r9
  and r9,MASK
  shl r9,5

  mov qword [rbx+GT_WM_QUEUE_IN+r9],NEW_WORK
  mov [rbx+GT_WM_QUEUE_IN+r9+8],r12

  shr r9,5
  inc r9
  and r9,MASK
  mov [rbx+GT_WM_IN_HEAD],r9

  ; wrap around if needed
  xor eax,eax
  inc rsi
  cmp rsi,rcx
  cmove esi,eax
  mov [rdi+GT_WGM_IN_TAIL],rsi

  jmp .consume_in_queue

.retry_in_enqueue:
  pause
  mov r8,[rbx+GT_WM_IN_TAIL]
  mov r9,[rbx+GT_WM_IN_HEAD]

  inc r9
  and r9,MASK
  cmp r9,r8
  je .retry_in_enqueue

  jmp .can_in_enqueue


.consume_io:
  mov rbp,rdi

  .input_loop:
    ; rbp -> gt_wgm
    push rcx
    push rdx
    push rdi
    push rsi
    push r8
    push r9
    push r11
    sub rsp,8

    mov rdi,[rbp+GT_WGM_RINGS_PTR]
    lea rsi,[rsp+64]
    mov rdx,1
    call rings_reap

    add rsp,8
    pop r11
    pop r9
    pop r8
    pop rsi
    pop rdi
    pop rdx
    pop rcx

    test eax,1
    jz .output_loop_pre

    ; got 1 cqe entry -> 16 bytes
    movdqa xmm0,[rsp]

    ; pass to the correct worker
    ; this is the user data portion
    mov rax,[rsp]

    ; rax is pointing to the gt_w structure
    ; we can get the parent manager
    mov rdi,[rax+GT_W_PARENT_WM]

    ; rdi is the work manager
    ; get their input queue
    ; it's at GT_WM_QUEUE_IN
    ; but, before, get the head
    ; and check the tail
    mov rcx,[rdi+GT_WM_IN_TAIL]
    mov r11,[rdi+GT_WM_IN_HEAD]

    ; head + 1 must not equal tail
    inc r11
    and r11,MASK
    cmp r11,rcx
    je .retry_input_enqueue
  
  .can_input_enqueue:
    dec r11
    and r11,MASK

    ; scale the index
    shl r11,5

    ; now r11 is the correct position
    ; just store the 32 bytes there
    mov qword [rdi+r11+GT_WM_QUEUE_IN],RESPONSE
    ; next 8 bytes are unused
    ; then the actual cqe
    movdqa [rdi+r11+GT_WM_QUEUE_IN+16],xmm0

    ; unscale r11
    shr r11,5

    inc r11
    and r11,MASK

    ; move the head
    mov [rdi+GT_WM_IN_HEAD],r11

    ; move to the next input
    jmp .input_loop

.retry_input_enqueue:
  pause
  mov rcx,[rdi+GT_WM_IN_TAIL]
  mov r11,[rdi+GT_WM_IN_HEAD]

  ; head + 1 must not equal tail
  inc r11
  and r11,MASK
  cmp r11,rcx
  je .retry_input_enqueue
  
  jmp .can_input_enqueue


.output_loop_pre:
  ; prepare output loop
  ; rbp -> wgm
  ; go around all the queues
  xor ecx,ecx

  .output_loop:
    cmp rcx,[rbp+GT_WGM_WM_LEN]
    je .all_done

    ; get worker manager
    mov rax,[rbp+GT_WGM_WM_OFF+rcx*8]

    ; retrieve up to 1 entry from the queue
    ; check head and tail
    mov rdi,[rax+GT_WM_OUT_TAIL]
    mov rsi,[rax+GT_WM_OUT_HEAD]
    cmp rdi,rsi
    je .out_queue_empty

    ; get queue out message
    shl rdi,6
    movdqa xmm0,[rax+GT_WM_QUEUE_OUT+rdi]

    ; all zeros means it's a response to the app
    ptest xmm0,xmm0
    jz .not_io_uring_response

    ; otherwise it's for the io_uring library
    push rax
    push rcx
    push rdx
    push rdi
    push rsi
    push r8
    push r9
    push r11

    lea rsi,[rax+GT_WM_QUEUE_OUT+rdi]
    mov rdi,[rbp+GT_WGM_RINGS_PTR]
    call rings_submit
    test eax,eax
    jz .retry_rings_submit

  .rings_submitted:

    pop r11
    pop r9
    pop r8
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rax


  .move_tail:
    ; move tail forward
    shr rdi,6
    inc rdi
    and rdi,MASK
    mov [rax+GT_WM_OUT_TAIL],rdi
    
    inc rcx ; next work manager
    jmp .output_loop

  .not_io_uring_response:
    ; rbp -> work group manager
    ; rax -> worker manager
    ; rdi -> msg offset
    ; check if it's a reenqueue msg
    cmp qword [rax+GT_WM_QUEUE_OUT+rdi+16],REENQUEUE
    je .do_reenqueue

    push r12
    push rbx
    push rdx
    push rsi

    xor esi,esi

    ; check head and tail
  .check_wgm_queue_out:
    mov r12,[rbp+GT_WGM_OUT_TAIL]
    mov rbx,[rbp+GT_WGM_OUT_HEAD]

    inc rbx
    cmp rbx,[rbp+GT_WGM_W_MAX_COUNT]
    cmove ebx,esi

    cmp rbx,r12
    je .spin_app_response

    ; has space
    mov rbx,[rbp+GT_WGM_OUT_HEAD]

    mov r12,[rax+GT_WM_QUEUE_OUT+rdi+24]

    mov rdx,[rbp+GT_WGM_OUT_QUEUE_PTR]
    mov [rdx+rbx*8],r12

    ; enqueued out
    inc rbx
    cmp rbx,[rbp+GT_WGM_W_MAX_COUNT]
    cmove ebx,esi
    mov [rbp+GT_WGM_OUT_HEAD],rbx

    pop rsi
    pop rdx
    pop rbx
    pop r12
    jmp .move_tail

  .spin_app_response:
    pause
    jmp .check_wgm_queue_out

  .do_reenqueue:
    ; datum
    push rcx
    push rbx
    push rsi
    push r11

    ; get ptrs
    mov rcx,[rax+GT_WM_IN_TAIL]
    mov r11,[rax+GT_WM_IN_HEAD]

    ; remember current position
    mov rbx,r11

    ; check if head + 1 != tail
    inc r11
    and r11,MASK
    cmp rcx,r11
    je .spin_reenqueue

    ; every entry is 32 bytes
    shl rbx,5

    ; get datum from out queue
    mov rsi,[rax+GT_WM_QUEUE_OUT+rdi+24]

    mov qword [rax+GT_WM_QUEUE_IN+rbx],NEW_WORK
    mov [rax+GT_WM_QUEUE_IN+rbx+8],rsi

    mov [rax+GT_WM_IN_HEAD],r11

    pop r11
    pop rsi
    pop rbx
    pop rcx

    jmp .move_tail

  .spin_reenqueue:
    pause
    pop r11
    pop rsi
    pop rbx
    pop rcx
    jmp .do_reenqueue

  .out_queue_empty:
    inc rcx
    jmp .output_loop

.all_done:
  add rsp,64
  pop r12
  pop rbx
  pop rbp
  ret

.retry_rings_submit:
  pause
  mov rax,[rsp+56]
  mov rdi,[rsp+32]
  lea rsi,[rax+GT_WM_QUEUE_OUT+rdi]
  mov rdi,[rbp+GT_WGM_RINGS_PTR]
  call rings_submit
  test eax,eax
  jz .retry_rings_submit
  jmp .rings_submitted


gt_wgm_get_datum_back:
  ; rdi -> wgm
  ; rsi -> *ok

  ; zero to avoid branching
  xor r11,r11

  ; out queue
  mov rdx,[rdi+GT_WGM_OUT_QUEUE_PTR]

  ; tail and head
  mov rcx,[rdi+GT_WGM_OUT_TAIL]
  mov r8,[rdi+GT_WGM_OUT_HEAD]

  lea r9,[rcx+1]
  cmp r9,[rdi+GT_WGM_W_MAX_COUNT]
  cmove r9,r11

  ; move the value anyway
  mov rax,[rdx+rcx*8]

  ; if the queue is empty, we set ok to 0
  cmp rcx,r8
  
  cmove rdx,r11
  mov [rsi],rdx

  ; set the current tail
  mov rdx,rcx

  ; if it's not empty, advance tail
  cmovne rdx,r9

  mov [rdi+GT_WGM_OUT_TAIL],rdx

  ret


_save_regs:
  mov [rdi+GT_WM_SAVED_REGISTERS+0],rax
  mov [rdi+GT_WM_SAVED_REGISTERS+8],rbx
  mov [rdi+GT_WM_SAVED_REGISTERS+16],rcx
  mov [rdi+GT_WM_SAVED_REGISTERS+24],rdx
  ;mov [rdi+GT_WM_SAVED_REGISTERS+32],rdi
  mov [rdi+GT_WM_SAVED_REGISTERS+40],rsi
  mov [rdi+GT_WM_SAVED_REGISTERS+48],rbp
  mov [rdi+GT_WM_SAVED_REGISTERS+56],rsp
  mov [rdi+GT_WM_SAVED_REGISTERS+64],r8
  mov [rdi+GT_WM_SAVED_REGISTERS+72],r9
  mov [rdi+GT_WM_SAVED_REGISTERS+80],r10
  mov [rdi+GT_WM_SAVED_REGISTERS+88],r11
  mov [rdi+GT_WM_SAVED_REGISTERS+96],r12
  mov [rdi+GT_WM_SAVED_REGISTERS+104],r13
  mov [rdi+GT_WM_SAVED_REGISTERS+112],r14
  mov [rdi+GT_WM_SAVED_REGISTERS+120],r15

  jmp [rdi+GT_WM_NEXT_INSTRUCTION]


_restore_regs:
  mov rdi,[rdi+GT_W_PARENT_WM]

  mov rax,[rdi+GT_WM_SAVED_REGISTERS+0]
  mov rbx,[rdi+GT_WM_SAVED_REGISTERS+8]
  mov rcx,[rdi+GT_WM_SAVED_REGISTERS+16]
  mov rdx,[rdi+GT_WM_SAVED_REGISTERS+24]
  ;mov rdi,[rdi+GT_WM_SAVED_REGISTERS+32]
  mov rsi,[rdi+GT_WM_SAVED_REGISTERS+40]
  mov rbp,[rdi+GT_WM_SAVED_REGISTERS+48]
  mov rsp,[rdi+GT_WM_SAVED_REGISTERS+56]
  mov r8,[rdi+GT_WM_SAVED_REGISTERS+64]
  mov r9,[rdi+GT_WM_SAVED_REGISTERS+72]
  mov r10,[rdi+GT_WM_SAVED_REGISTERS+80]
  mov r11,[rdi+GT_WM_SAVED_REGISTERS+88]
  mov r12,[rdi+GT_WM_SAVED_REGISTERS+96]
  mov r13,[rdi+GT_WM_SAVED_REGISTERS+104]
  mov r14,[rdi+GT_WM_SAVED_REGISTERS+112]
  mov r15,[rdi+GT_WM_SAVED_REGISTERS+120]

  jmp [rdi+GT_WM_NEXT_INSTRUCTION]


gt_wm_set_user_datum:
  ; rdi -> wm
  ; rsi -> datum
  mov [rdi+GT_WM_USER_DATUM],rsi
  ret


gt_wm_work:
  ; rdi -> wm 

  ; get wgm
  mov rsi,[rdi+GT_WM_WGM_PTR]

  ; get work group procedure
  mov rdx,[rsi+GT_WGM_FUNCTION_PTR]

  ; dispatch every input to the correct worker
  mov rcx,[rdi+GT_WM_IN_TAIL]
  .deplete_queue:
    cmp rcx,[rdi+GT_WM_IN_HEAD]
    je .done

    ; each entry is 32 bytes long
    shl rcx,5

    ; load the first 8 bytes
    mov r11,[rdi+GT_WM_QUEUE_IN+rcx]
    test r11,NEW_WORK
    jnz .process_new_work

    ; handle response
    ; first 16 bytes are not used
    ; get the last 16 
    ; this is the worker
    mov r10,[rdi+GT_WM_QUEUE_IN+rcx+16]
    movsxd rax,[rdi+GT_WM_QUEUE_IN+rcx+24]

    ; rax is the return code
    ; we have to return control to the worker
    mov qword [rdi+GT_WM_NEXT_INSTRUCTION],.back_to_worker
    jmp _save_regs

  .back_to_worker:
    mov qword [rdi+GT_WM_NEXT_INSTRUCTION],.continue_depleting
    mov rsp,[r10+GT_W_STACK_PTR]
    ; rax has the return code
    mov rdi,[r10+GT_W_INSTRUCTION_PTR]
    jmp rdi

  .continue_depleting:
    shr rcx,5
    inc rcx
    and rcx,MASK
    mov [rdi+GT_WM_IN_TAIL],rcx
    jmp .deplete_queue

.process_new_work:
  ; spawn new worker
  mov rax,[rdi+GT_WM_NEXT_W_NODE]
  cmp rax,0
  je .handle_new_work_bottleneck

  ; next worker in the list
  mov rsi,[rax+GT_W_NEXT_W_NODE]

  ; link it
  mov [rdi+GT_WM_NEXT_W_NODE],rsi

  ; save registers
  mov qword [rdi+GT_WM_NEXT_INSTRUCTION],.first_to_worker
  jmp _save_regs

.first_to_worker:
  ; remember where to return
  mov qword [rdi+GT_WM_NEXT_INSTRUCTION],.continue_depleting

  ; the datum sent by the app
  mov rsi,[rdi+GT_WM_QUEUE_IN+rcx+8]

  ; rax has the worker
  mov rdi,rax

  ; switch to worker stack
  mov rsp,[rax+GT_W_STACK_BASE_PTR]

  ; rdx has the procedure
  call rdx
  
.done:
  jmp gt_wm_work

.handle_new_work_bottleneck:
  ; send to output to be reenqueued
  ; RDI -> wm
  mov r10,[rdi+GT_WM_OUT_TAIL]
  mov rsi,[rdi+GT_WM_OUT_HEAD]

  ; rax -> head
  mov rax,rsi

  inc rsi
  and rsi,MASK
  cmp rsi,r10
  je .handle_new_work_bottleneck
  
  ; has space
  lea r10,[rdi+GT_WM_QUEUE_OUT]
  shl rax,6
  add r10,rax
  
  ; datum to reenqueue
  ; moving from in to out
  mov r11,[rdi+GT_WM_QUEUE_IN+rcx+8]

  ; code to reenqueue
  pxor xmm0,xmm0
  movdqa [r10],xmm0

  mov qword [r10+16],REENQUEUE
  mov [r10+24],r11

  mov [rdi+GT_WM_OUT_HEAD],rsi

  jmp .continue_depleting


gt_w_get_wm_datum:
  ; rdi -> worker
  mov rsi,[rdi+GT_W_PARENT_WM]
  mov rax,[rsi+GT_WM_USER_DATUM]
  ret


gt_w_return:
  ; RDI -> worker

  ; get the manager
  mov rsi,[rdi+GT_W_PARENT_WM]

  ; add to linked list of free workers
  mov rdx,[rsi+GT_WM_NEXT_W_NODE]
  mov [rdi+GT_W_NEXT_W_NODE],rdx
  mov [rsi+GT_WM_NEXT_W_NODE],rdi

  ; return to the manager
  jmp _restore_regs


_in_out:
 ; RDI -> worker 
  push rbx
  push rcx
  push rdx
  push rdi
  push rsi
  push rbp
  push r8
  push r9
  push r10
  push r11
  push r12
  push r13
  push r14
  push r15
  sub rsp,8

  ; get parent wm
  mov rax,[rdi+GT_W_PARENT_WM]

  ; get queue out positions
  mov r11,[rax+GT_WM_OUT_TAIL]
  mov r12,[rax+GT_WM_OUT_HEAD]

  ; next position
  lea r13,[r12+1]
  and r13,MASK
  cmp r13,r11
  je .return_error

  ; there's space
  ; load the destination address
  shl r12,6
  lea r11,[rax+GT_WM_QUEUE_OUT+r12]

  ; zero
  pxor xmm0,xmm0
  movdqa [r11],xmm0
  movdqa [r11+16],xmm0
  movdqa [r11+32],xmm0
  movdqa [r11+48],xmm0

  ; r15 is the wgm
  mov r15,[rax+GT_WM_WGM_PTR]
  mov r14,rax

  ; eax has the fd
  mov eax,[r15+GT_WGM_EPOLL_FD]
  
  ; epoll
  shl rax,32
  or rax,0x1d
  mov [r11],rax

  ; epoll struct
  sub rsp,16

  ; offset
  mov [r11+8],rsp

  ; address
  mov [r11+16],rsi

  ; length
  mov qword [r11+24],1

  ; worker ctx
  mov [r11+32],rdi

  ; 
  mov [rsp],r10
  mov [rsp+8],rdi

  ; advance head
  mov [r14+GT_WM_OUT_HEAD],r13

  ; go to another process
  mov qword [rdi+GT_W_INSTRUCTION_PTR],.ret_handler
  mov [rdi+GT_W_STACK_PTR],rsp
  jmp _restore_regs

.ret_handler:
  add rsp,24
  pop r15
  pop r14
  pop r13
  pop r12
  pop r11
  pop r10
  pop r9
  pop r8
  pop rbp
  pop rsi
  pop rdi
  pop rdx
  pop rcx
  pop rbx
  ret

.return_error:
  mov rax,-128000
  sub rsp,16
  jmp .ret_handler


_io_rw:
  ; RDI -> worker
  ; ESI -> fd
  ; RDX -> offset
  ; RCX -> buffer
  ; R8  -> length
 
  push rbx
  push rcx
  push rdx
  push rdi
  push rsi
  push rbp
  push r8
  push r9
  push r10
  push r11
  push r12
  push r13
  push r14
  push r15
  sub rsp,8

  call _in_out

  add rsp,8

  cmp rax,-128000
  je .return_error

  ; get parent wm
  mov rax,[rdi+GT_W_PARENT_WM]

  ; get queue out positions
  mov r11,[rax+GT_WM_OUT_TAIL]
  mov r12,[rax+GT_WM_OUT_HEAD]

  ; next position
  lea r13,[r12+1]
  and r13,MASK
  cmp r13,r11
  je .return_error

  ; there's space
  ; load the destination address
  shl r12,6
  lea r11,[rax+GT_WM_QUEUE_OUT+r12]

  pxor xmm0,xmm0
  movdqa [r11+32],xmm0
  movdqa [r11+48],xmm0

  ; opcode + fd
  shl rsi,32
  or rsi,r9
  mov [r11],rsi

  ; offset
  mov [r11+8],rdx

  ; address
  mov [r11+16],rcx

  ; length
  mov [r11+24],r8

  ; user data
  mov [r11+32],rdi

  ; go to another process
  mov qword [rdi+GT_W_INSTRUCTION_PTR],.ret_handler
  mov [rdi+GT_W_STACK_PTR],rsp

  ; advance head
  mov [rax+GT_WM_OUT_HEAD],r13

  jmp _restore_regs

.ret_handler:
  pop r15
  pop r14
  pop r13
  pop r12
  pop r11
  pop r10
  pop r9
  pop r8
  pop rbp
  pop rsi
  pop rdi
  pop rdx
  pop rcx
  pop rbx
  ret

.return_error:
  mov rax,-128000
  jmp .ret_handler


gt_w_write:
  mov r10,4
  mov r9,23
  jmp _io_rw


gt_w_read:
  mov r10,1
  mov r9,22
  jmp _io_rw


_make_call:
  ; receive data in:
  ; xmm0, xmm1, xmm2, xmm3
  push rbp
  push rbx
  push r12
  push r13
  push r14
  push r15

  ; get worker manager
  mov rax,[rdi+GT_W_PARENT_WM]

  ; get queue out positions
  mov r11,[rax+GT_WM_OUT_TAIL]
  mov r12,[rax+GT_WM_OUT_HEAD]

  ; next position
  lea r13,[r12+1]
  and r13,MASK
  cmp r13,r11
  je .return_error

  ; there's space
  ; load the destination address
  shl r12,6
  lea r11,[rax+GT_WM_QUEUE_OUT+r12]

  movdqa [r11],xmm0
  movdqa [r11+16],xmm1
  movdqa [r11+32],xmm2
  movdqa [r11+48],xmm3

  ; go to another process
  mov qword [rdi+GT_W_INSTRUCTION_PTR],.done
  mov [rdi+GT_W_STACK_PTR],rsp

  ; advance head
  mov [rax+GT_WM_OUT_HEAD],r13

  jmp _restore_regs

.done:
  pop r15
  pop r14
  pop r13
  pop r12
  pop rbx
  pop rbp
  ret

.return_error:
  mov rax,-128000
  jmp .done


gt_w_send_datum_back:
  ; RDI -> worker
  ; RSI -> datum

  ; get worker manager
  mov rdx,[rdi+GT_W_PARENT_WM]

  ; check out queue
  mov rcx,[rdx+GT_WM_OUT_TAIL]
  mov r8,[rdx+GT_WM_OUT_HEAD]
  lea r9,[r8+1]
  and r9,MASK
  cmp r9,rcx
  je .queue_full

  ; qeueue is not full

  ; 64 bytes per entry
  shl r8,6

  ; first 16 bytes = 0 means it's not io_uring
  pxor xmm0,xmm0
  movdqa [rdx+GT_WM_QUEUE_OUT+r8],xmm0

  ; mark as a response
  mov qword [rdx+GT_WM_QUEUE_OUT+r8+16],APP_RESPONSE

  ; the actual response
  mov [rdx+GT_WM_QUEUE_OUT+r8+24],rsi

  ; advance the queue head
  mov [rdx+GT_WM_OUT_HEAD],r9

  xor eax,eax
  inc eax

  ret

.queue_full:
  mov rax,-128000
  ret


gt_w_close:
  ; align to 16
  sub rsp,8

  xor eax,eax
  push rax

  shl rsi,32
  or rsi,19 ; close
  push rsi

  movdqa xmm0,[rsp]

  pxor xmm1,xmm1

  push rax
  push rdi
  movdqa xmm2,[rsp]

  pxor xmm3,xmm3

  add rsp,40

  jmp _make_call
  

gt_w_openat:
  ; rdi -> worker
  ; esi -> dirfd
  ; rdx -> pathname
  ; ecx -> flags
  ; r8  -> mode
  sub rsp,8

  xor eax,eax
  push rax

  ; opcode + fd + offset
  shl rsi,32
  or rsi,18 ; openat
  push rsi
  movdqa xmm0,[rsp]

  ; addr + len + flags
  sub rsp,8

  mov [rsp],r8d

  mov [rsp+4],ecx

  push rdx
  movdqa xmm1,[rsp]

  push rax
  push rdi
  movdqa xmm2,[rsp]

  pxor xmm3,xmm3

  add rsp,56

  jmp _make_call

