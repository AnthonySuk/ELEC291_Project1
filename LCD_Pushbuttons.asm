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
;Line1:    db 'LCD PUSH BUTTONS' , 0
Line1:     db 'To= xxC  Tj=xxC ' ,0
Line2:     db 'Sxxx,xx  Rxxx,xx' ,0
Blank_3:   db '   '				 ,0
Blank_2:   db '  '				 ,0
S: 		   db 'S'				 ,0
R:		   db 'R'				 ,0
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
; Button 
; For some reason, we reverse the pin of increase and decrease
BUTTON_START    equ P1.3
BUTTON_STOP     equ P0.0
BUTTON_SELECT   equ P0.1
BUTTON_INCREASE equ P0.3
BUTTON_DECREASE equ P0.2

;---------------------------------;
;            Bit Segment		  ;
;---------------------------------;
BSEG

PB_START   : dbit 1
PB_STOP    : dbit 1
PB_SELECT  : dbit 1
PB_INCREASE: dbit 1
PB_DECREASE: dbit 1
mf: dbit 1

;---------------------------------;
;          Data Segment			  ;
;---------------------------------;
; These register definitions needed by 'math32.inc'
DSEG at 30H
x:   ds 4
y:   ds 4
bcd: ds 5

DSEG at 0x50
TIME_SOAK: ds 1
TIME_REFLOW: ds 1
TEMP_SOAK: ds 1
TEMP_REFLOW: ds 1
TEMP_OVEN: ds 1
TEMP_REF: ds 1
pwm: ds 1
state: ds 1
; Counter
COUNTER_BUTTON_SELECT: ds 1

;---------------------------------;
;          Include Segment		  ;
;---------------------------------;
$NOLIST
$include(math32.inc)
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

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
	mov COUNTER_BUTTON_SELECT,#0x00
	mov TEMP_SOAK,#215
	mov TIME_SOAK,#0x45
	mov TEMP_REFLOW,#189
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
		jb PB_INCREASE, Increase_press
		ret
	Increase_press:
		jb BUTTON_INCREASE, Inc_num
		Wait_Milli_Seconds(#50)
		jb BUTTON_INCREASE, $
	Inc_num:
		add a, #1
		ret
	
;Decrease number when button pushed
CHECK_BUTTON_DECREASE:
		jb PB_DECREASE, Decrease_press
		ret
	Decrease_press:
		jb BUTTON_DECREASE, Dec_num
		Wait_Milli_Seconds(#50)
		jb BUTTON_DECREASE, $
	Dec_num:
		subb a, #1
		ret

; #0 default #1 S_temp #2 S_time #3 R_temp #4 R_time
CHECK_BUTTON_SELECT_STATE:
		mov a, COUNTER_BUTTON_SELECT
	CHEKC_BUTTON_SELECT_STATE0:
		cjne a, #0, CHECK_BUTTON_SELECT_STATE1

		Set_Cursor(2,14)
		Display_char(#',')

		ljmp CHECK_BUTTON_SELECT_STATE_DONE
	CHECK_BUTTON_SELECT_STATE1:
		Set_Cursor(2,1)

		cjne a, #1, CHECK_BUTTON_SELECT_STATE2
		mov a,TEMP_SOAK
		lcall CHECK_BUTTON_INCREASE
		lcall CHECK_BUTTON_DECREASE
		mov TEMP_SOAK, a

		Display_char(#'=')

		ljmp CHECK_BUTTON_SELECT_STATE_DONE
	CHECK_BUTTON_SELECT_STATE2:
		Display_char(#'R')
		Set_Cursor(2,5)

		cjne a,#2,CHECK_BUTTON_SELECT_STATE3
		mov a,TIME_SOAK
		lcall CHECK_BUTTON_INCREASE
		lcall CHECK_BUTTON_DECREASE
		;da a
		mov TIME_SOAK, a

		Display_char(#'=')

		ljmp CHECK_BUTTON_SELECT_STATE_DONE
	CHECK_BUTTON_SELECT_STATE3:
		Display_char(#',')
		Set_Cursor(2,10)

		cjne a,#3,CHECK_BUTTON_SELECT_STATE4
		mov a,TEMP_REFLOW
		lcall CHECK_BUTTON_INCREASE
		lcall CHECK_BUTTON_DECREASE
		mov TEMP_REFLOW, a
		
		Display_char(#'=')

		sjmp CHECK_BUTTON_SELECT_STATE_DONE
	CHECK_BUTTON_SELECT_STATE4:
		Display_char(#'S')
		Set_Cursor(2,14)

		cjne a,#4,CHECK_BUTTON_SELECT_STATE_DONE
		mov a,TIME_REFLOW
		lcall CHECK_BUTTON_INCREASE
		lcall CHECK_BUTTON_DECREASE
		;da a
		mov TIME_REFLOW, a
		
		Display_char(#'=')
	CHECK_BUTTON_SELECT_STATE_DONE:
		ret     

CHECK_BUTTON_START:
	ret

CHECK_BUTTON_STOP:
	ret	

LCD_PB:
		; Set variables to 1: 'no push button pressed'
		setb PB_START
		setb PB_STOP
		setb PB_SELECT
		setb PB_INCREASE
		setb PB_DECREASE
		; The input pin used to check set to '1'
		setb P1.5
		; Check if any push button is pressed
		; When all button not press, positive will connect with P1.5 and pull P1.5 up, P1.5 will not be zero
		clr BUTTON_START
		clr BUTTON_STOP
		clr BUTTON_SELECT
		clr BUTTON_INCREASE
		clr BUTTON_DECREASE
		jb P1.5, LCD_PB_Done
		; Debounce
		mov R2, #50
		lcall waitms
		jb P1.5, LCD_PB_Done
		; Set the LCD data pins to logic 1
		setb BUTTON_START
		setb BUTTON_STOP
		setb BUTTON_SELECT
		setb BUTTON_INCREASE
		setb BUTTON_DECREASE
		; Check the push buttons one by one
		clr BUTTON_START
		mov c, P1.5
		mov PB_START, c
		setb BUTTON_START
	
		clr BUTTON_STOP
		mov c, P1.5
		mov PB_STOP, c
		setb BUTTON_STOP

		clr BUTTON_SELECT
		mov c, P1.5
		mov PB_SELECT, c
		setb BUTTON_SELECT

		clr BUTTON_INCREASE
		mov c, P1.5
		mov PB_INCREASE, c
		setb BUTTON_INCREASE

		clr BUTTON_DECREASE
		mov c, P1.5
		mov PB_DECREASE, c
		setb BUTTON_DECREASE
		; Call function
		jnb PB_START, CHECK_BUTTON_START
		jnb PB_STOP , CHECK_BUTTON_STOP
		jnb PB_SELECT, CHECK_BUTTON_SELECT
	LCD_PB_Done:		
		ret

CHECK_BUTTON_SELECT:
		mov a,COUNTER_BUTTON_SELECT
		add a, #1
		da a
		cjne a,#5,Not_reset
		mov COUNTER_BUTTON_SELECT,#0
		sjmp CHECK_BUTTON_SELECT_DONE
	Not_reset:
		mov COUNTER_BUTTON_SELECT,a
		clr a
		ret
	CHECK_BUTTON_SELECT_DONE:
		ret
	

SendToLCD:
	mov b, #100
	div ab
	orl a, #0x30 ; Convert hundreds to ASCII
	lcall ?WriteData ; Send to LCD
	mov a, b ; Remainder is in register b
	mov b, #10
	div ab
	orl a, #0x30 ; Convert tens to ASCII
	lcall ?WriteData; Send to LCD
	mov a, b
	orl a, #0x30 ; Convert units to ASCII
	lcall ?WriteData; Send to LCD
	ret

Display_PushButtons_LCD:
	Set_Cursor(2, 2)
	mov a, TEMP_SOAK
	lcall SendToLCD
	
	Set_Cursor(2, 6)
	Display_BCD(TIME_SOAK)
	
	; Test Only, show COUNTER_BUTTON_SELECT
	;Set_Cursor(2,8)
	;Display_BCD(COUNTER_BUTTON_SELECT)
	
	Set_Cursor(2, 11)
	mov a, TEMP_REFLOW
	lcall SendToLCD
		
	Set_Cursor(2, 15)
	Display_BCD(TIME_REFLOW)
	ret	

Display_formated_BCD:
	Display_BCD(bcd+2)
	Display_char(#'.')
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
	Set_Cursor(2, 10)
	;Display_char(#'=')
	ret
	
	
Display_Tj:
	clr ADCF
	setb ADCS ;  ADC start trigger signal
    jnb ADCF, $ ; Wait for conversion complete
    
    ; Read the ADC result and store in [R1, R0]
    mov a, ADCRH   
    swap a
    push acc
    anl a, #0x0f
    mov R1, a
    pop acc
    anl a, #0xf0
    orl a, ADCRL
    mov R0, A
    
    ; Convert to voltage
	mov x+0, R0
	mov x+1, R1
	mov x+2, #0
	mov x+3, #0
	Load_y(49500) ; VCC voltage measured
	lcall mul32
	Load_y(4095) ; 2^12-1
	lcall div32

	;(vout-2.73)*100=vout*100-273
	Load_y(27300)
	lcall sub32
	load_y(100)
	lcall mul32
	
	; Convert to BCD and display
	lcall hex2bcd
	Set_Cursor(1, 13)
	lcall Display_formated_BCD ;give temperature to LCD

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
	
	lcall LCD_PB
	lcall CHECK_BUTTON_SELECT_STATE
	lcall Display_PushButtons_LCD
	;lcall Display_Tj
	
	;Wait 50 ms between readings
	mov R2, #50
	lcall waitms
	
	sjmp Forever
	
END
	