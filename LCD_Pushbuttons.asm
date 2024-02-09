; N76E003 LCD_Pushbuttons.asm: Reads muxed push buttons using one input

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

To_temp equ #0x25
Tj_temp equ #0x25

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


;---------------------------------;
;          Data Segment			  ;
;---------------------------------;
DSEG at 0x30

TIME_SOAK: ds 2
TIME_REFLOW: ds 2
TEMP_SOAK: ds 2
TEMP_REFLOW: ds 2
TEMP_OVEN: ds 2
TEMP_REF: ds 2
pwm: ds 1
state: ds 1
; Counter
COUNTER_BUTTON_SELECT: ds 1
; 
x:   ds 4
y:   ds 4
bcd: ds 5
VLED_ADC: ds 2
count: ds 1

;---------------------------------;
;          Code Segment			  ;
;---------------------------------;
CSEG
Init_All:
	; Configure all the pins for biderectional I/O
	mov	P3M1, #0x00
	mov	P3M2, #0x00
	mov	P1M1, #0x00
	mov	P1M2, #0x00
	mov	P0M1, #0x00
	mov	P0M2, #0x00
	
;Timer 0 using for delay functions
	; Using timer 0 for delay functions.  Initialize here:
	clr	TR0 ; Stop timer 0
	orl	CKCON,#0x08 ; CLK is the input for timer 0
	anl	TMOD,#0xF0 ; Clear the configuration bits for timer 0
	orl	TMOD,#0x01 ; Timer 0 in Mode 1: 16-bit timer

;Timer 1 using for generate baud rate
	orl	CKCON, #0x10 ; CLK is the input for timer 1
	orl	PCON, #0x80 ; Bit SMOD=1, double baud rate
	mov	SCON, #0x52
	anl	T3CON, #0b11011111
	anl	TMOD, #0x0F ; Clear the configuration bits for timer 1
	orl	TMOD, #0x20 ; Timer 1 Mode 2
	mov	TH1, #TIMER1_RELOAD ; TH1=TIMER1_RELOAD;
	setb TR1

;Timer 2

; Button Initial
	mov COUNTER_BUTTON_SELECT,#0
	mov TEMP_SOAK,#0x25
	mov TIME_SOAK,#0x45
	mov TEMP_REFLOW,#0x23
	mov TIME_REFLOW,#0x55

	ret

wait_1ms:
	clr	TR0 ; Stop timer 0
	clr	TF0 ; Clear overflow flag
	mov	TH0, #high(TIMER0_RELOAD_1MS)
	mov	TL0,#low(TIMER0_RELOAD_1MS)
	setb TR0
	jnb	TF0, $ ; Wait for overflow
	ret

; Wait the number of miliseconds in R2
waitms:
	lcall wait_1ms
	djnz R2, waitms
	ret

;Increase number when button pushed
CHECK_BUTTON_INCREASE:
	jb BUTTON_INCREASE, Inc_num
	Wait_Milli_Seconds(#50)
	jnb BUTTON_INCREASE, $
Inc_num:
	add a, #0x01
	ret
	
;Decrease number when button pushed
CHECK_BUTTON_DECREASE:
	jb BUTTON_DECREASE, Dec_num
	Wait_Milli_Seconds(#50)
	jnb BUTTON_DECREASE, $
Dec_num:
	subb a, #0x01
	ret

CHECK_BUTTON_SELECT:
	jb BUTTON_SELECT, CHECK_BUTTON_SELECT_DONE
	Wait_Milli_Seconds(#50)	
	jb BUTTON_SELECT, CHECK_BUTTON_SELECT_DONE 
	jnb BUTTON_SELECT, $	

; Counter++
	mov a, COUNTER_BUTTON_SELECT
	add a,#1
	mov COUNTER_BUTTON_SELECT,a

; #0 default #1 S_temp #2 S_time #3 R_temp #4 R_time
CHECK_BUTTON_SELECT_1:
	cjne a,#1,CHECK_BUTTON_SELECT_2
	mov a,TEMP_SOAK
	
	sjmp CHECK_BUTTON_SELECT_DONE
	
CHECK_BUTTON_SELECT_2:
	cjne a,#2,CHECK_BUTTON_SELECT_3
	mov a,TIME_SOAK
	
	sjmp CHECK_BUTTON_SELECT_DONE

CHECK_BUTTON_SELECT_3:
	cjne a,#3,CHECK_BUTTON_SELECT_4
	mov a,TEMP_REFLOW
	
	sjmp CHECK_BUTTON_SELECT_DONE

CHECK_BUTTON_SELECT_4:
	cjne a,#4,CHECK_BUTTON_SELECT_0
	mov a,TIME_REFLOW
	
	sjmp CHECK_BUTTON_SELECT_DONE

CHECK_BUTTON_SELECT_0:
	mov COUNTER_BUTTON_SELECT,#0
	ret
	
CHECK_BUTTON_SELECT_DONE:
	ret     

CHECK_BUTTON_START:
	ret

CHECK_BUTTON_STOP:
	ret

LCD_PB:
	lcall CHECK_BUTTON_SELECT
	lcall CHECK_BUTTON_START
	lcall CHECK_BUTTON_STOP
LCD_PB_Done:		
	ret

Display_PushButtons_LCD:
	Set_Cursor(2, 2)
	mov a, TEMP_SOAK
	;da a
    Display_BCD(TEMP_SOAK)	

	Set_Cursor(2, 6)
	mov a, TIME_SOAK
	;da a
    Display_BCD(TIME_SOAK)	

	Set_Cursor(2, 11)
	mov a, TEMP_REFLOW
	;da a
    Display_BCD(TEMP_REFLOW)	

	Set_Cursor(2, 15)
    Display_BCD(TIME_REFLOW)		

	;mov a,COUNTER_BUTTON_SELECT
	;cjne a,#0,Display_PushButtons_LCD_Done

Display_PushButtons_LCD_Done:
	ret
;---------------------------------;
;    main function starts here    ;
;---------------------------------;
main:
	mov sp, #0x7f
	lcall Init_All
    lcall LCD_4BIT
    
    ; initial messages in LCD
	Set_Cursor(1, 1)
    Send_Constant_String(#Line1)

	Set_Cursor(1,5)
	Display_BCD(To_temp)
	Set_Cursor(1,13)
	Display_BCD(Tj_temp)

	Set_Cursor(2, 1)
    Send_Constant_String(#Line2)

	
Forever:
	;jnb
	;lcall LCD_PB
	lcall Display_PushButtons_LCD
	
	; Wait 50 ms between readings
	;mov R2, #50
	;lcall waitms
	
	sjmp Forever
	
END
	