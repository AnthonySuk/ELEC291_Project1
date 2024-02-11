$NOLIST
$MODN76E003
$LIST

;  N76E003 pinout:
;                               -------
;       PWM2/IC6/T0/AIN4/P0.5 -|1    20|- P0.4/AIN5/STADC/PWM3/IC3
;               TXD/AIN3/P0.6 -|2    19|- P0.3/PWM5/IC5/AIN6
;               RXD/AIN2/P0.7 -|3    18|- P0.2/ICPCK/OCDCK/RXD_1/[SCL]
;                    RST/P2.0 -|4    17|- P0.1/PWM4/IC4/MISO
;        INT0/OSCIN/AIN1/P3.0 -|5    16|- P0.0/PWM3/IC3/MOSI/T1
;              INT1/AIN0/P1.7 -|6    15|- P1.0/PWM2/IC2/SPCLK
;                         GND -|7    14|- P1.1/PWM1/IC1/AIN7/CLO
;[SDA]/TXD_1/ICPDA/OCDDA/P1.6 -|8    13|- P1.2/PWM0/IC0
;                         VDD -|9    12|- P1.3/SCL/[STADC]
;            PWM5/IC7/SS/P1.5 -|10   11|- P1.4/SDA/FB/PWM1
;                               -------
;

CLK               EQU 16600000 ; Microcontroller system frequency in Hz
BAUD              EQU 115200 ; Baud rate of UART in bps
TIMER1_RELOAD     EQU (0x100-(CLK/(16*BAUD)))
TIMER0_RELOAD_1MS EQU (0x10000-(CLK/1000))

To_temp equ 0x25
Tj_temp equ 0x25

ORG 0x0000
	ljmp main

;---------------------------------;
;      String Declarations		  ;
;---------------------------------;
;              1234567890123456    <- This helps determine the location of the counter
;Line1:     db 'LCD PUSH BUTTONS', 0
Line1:     db 'To= xxC  Tj=xxC'  ,0
Line2:     db 'Sxxx,xx  Rxxx,xx' ,0
Blank_3:   db '   '				 ,0
Blank_2:   db '  '				 ,0

;---------------------------------;
;        Pin Connections   		  ;
;---------------------------------;
cseg
; These 'equ' must match the hardware wiring
; change all p1.3 to p1.2
; speaker 14
LCD_RS equ P1.2
LCD_E  equ P1.4
LCD_D4 equ P0.0
LCD_D5 equ P0.1
LCD_D6 equ P0.2
LCD_D7 equ P0.3

BUTTON_START    equ P1.3
BUTTON_STOP     equ P0.0
BUTTON_SELECT   equ P0.1
BUTTON_INCREASE equ P0.2
BUTTON_DECREASE equ P0.3

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

;---------------------------------;
;            Bit Segment		  ;
;---------------------------------;
BSEG
; These five bit variables store the value of the pushbuttons after calling 'LCD_PB' below
PB0: dbit 1		;Start button
PB1: dbit 1		;Stop button
PB2: dbit 1		;Select button 
PB3: dbit 1		;Increase
PB4: dbit 1		;Decrease

;---------------------------------;
;          Data Segment			  ;
;---------------------------------;
DSEG at 0x30

TIME_SOAK: ds 1
TIME_REFLOW: ds 1
TEMP_SOAK: ds 1
TEMP_REFLOW: ds 1
TEMP_OVEN: ds 1
TEMP_REF: ds 1

; FSM
pwm: ds 1  
state: ds 1

; Counter
COUNTER_BUTTON_SELECT: ds 1


FSM1:
	mov a, FSM1_state
FSM1_state0:
	cjne a, #0, FSM1_state1
		
	mov pwm, #0
	jb PB6, FSM1_state0_done
	jnb PB6, $ ; Wait for key release
	mov FSM1_state, #1
	mov sec,#0

FSM1_state0_done:
    ljmp FSM1
FSM1_state1:
	cjne a, #1, FSM1_state2

	jnb PB1,next_1
	Wait_Milli_Seconds(#50)
	jnb PB1,next_1
	jb PB1,$
	mov FSM1_state,#0
	ljmp FSM1
next_1:

	mov pwm, #100
	;mov sec, #0
	cjne sec, #60, check_abort
Continue_state1:
	mov a, #150
	clr c
	subb a, temp
	jnc FSM1_state1_done
	mov FSM1_state, #2
	mov sec, #0
FSM1_state1_done:
	ljmp FSM1
	
check_abort:
	clr c
	subb temp, #50
	jc ABORTION
	ljmp Continue_state1
ABORTION:
	mov FSM1_state,#0
	ljmp FSM1

FSM1_state2:
	cjne a, #2, FSM1_state3

	jnb PB1,next_2
	Wait_Milli_Seconds(#50)
	jnb PB1,next_2
	jb PB1,$
	mov FSM1_state,#0
	ljmp FSM1
next_2:

    mov pwm, #20
    mov a, #60
    clr c
    subb a, sec
    jnc FSM1_state2_done
    mov FSM1_state, #3
FSM1_state2_done:
    ljmp FSM1

FSM1_state3:
	cjne a, #3, FSM1_state4

	jnb PB1,next_3
	Wait_Milli_Seconds(#50)
	jnb PB1,next_3
	jb PB1,$
	mov FSM1_state,#0
	ljmp FSM1
next_3:
	mov pwm, #100
	mov a,#220
	clr c
	subb a,temp
	jnc FSM1_state3_done
	mov FSM1_state,#4
	mov sec,#0
	
FSM1_state3_done:
	ljmp FSM1

FSM1_state4:
	cjne a, #4,FSM1_state5

	jnb PB1,next_4
	Wait_Milli_Seconds(#50)
	jnb PB1,next_4
	jb PB1,$
	mov FSM1_state,#0
	ljmp FSM1
next_4:
	mov pwm,#20
	mov a,#45
	clr c
	subb a,sec	
	jnc FSM1_state4_done
	mov FSM1_state,#5
	mov sec,#0
FSM1_state4_done:
	ljmp FSM1

FSM1_state5:
	cjne a, #5,FSM1_state0

	mov pwm,#0
	mov a,#60
	clr c
	subb a,temp
	jc FSM1_state5_done
	mov FSM1_state,#0
FSM1_state5_done:
	ljmp FSM1