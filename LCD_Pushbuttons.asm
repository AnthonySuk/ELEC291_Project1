;2024/2/12 16:42
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



TIMER2_RATE   EQU 1000     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))


;Tj_temp equ #0x25

ORG 0x0000
	ljmp main

; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

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
Reflow_n:  db 'STOP          ',0
Reflow_0:  db 'RAMP SOAK   ',0
Reflow_1:  db 'SOAK        ',0
Reflow_2:  db 'RAMP PEAK   ',0
Reflow_3:  db 'REFLOW      ',0
Reflow_4:  db 'COOLIG      ',0
Blank:     db '                 ',0
Warning:   db ' To IS TOO LOW!  ',0


;---------------------------------;
;        Pin Connections   		  ;
;---------------------------------;
cseg
; These 'equ' must match the hardware wiring
; change all p1.3 to p1.2
; speaker pin15
; LM335(detect temp) pin14
LCD_RS equ P1.2
LCD_E  equ P1.4
LCD_D4 equ P0.0
LCD_D5 equ P0.1
LCD_D6 equ P0.2
LCD_D7 equ P0.3
; Button 
; For some reason, we reverse the pin of increase and decrease
BUTTON_START    equ P1.2
BUTTON_STOP     equ P0.0
BUTTON_SELECT   equ P0.1
BUTTON_INCREASE equ P0.3
BUTTON_DECREASE equ P0.2

;declare the pin for speaker
SOUND_OUT equ P1.0

;declare the pin for PWM
PWM_OUT equ P1.6

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
checking_sound: dbit 1

;---------------------------------;
;          Data Segment			  ;
;---------------------------------;
; These register definitions needed by 'math32.inc'
DSEG at 30H
x:   ds 4
y:   ds 4
bcd: ds 5
VLED_ADC: ds 2
temp: ds 1

DSEG at 0x50
TIME_SOAK: ds 1
TIME_REFLOW: ds 1
TEMP_SOAK: ds 1
TEMP_REFLOW: ds 1
TEMP_TARGET: ds 1
TEMP_SIGMAERROR: ds 2

pwm: ds 1
FSM1_state: ds 1
sec: ds 1
TIME_REALTIME: ds 1
pwm_counter: ds 1

; Counter
COUNTER_BUTTON_SELECT: ds 1
COUNTER_TIME_PWM: ds 2
Tj_temp: ds 1
COUNTER_1MS: ds 2


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
;Timer2 initialization
Timer2_Init:
	mov T2CON, #0 ; Stop timer/counter.  Autoreload mode.
	mov TH2, #high(TIMER2_RELOAD)
	mov TL2, #low(TIMER2_RELOAD)
	; Set the reload value
	orl T2MOD, #0x80 ; Enable timer 2 autoreload
	mov RCMP2H, #high(TIMER2_RELOAD)
	mov RCMP2L, #low(TIMER2_RELOAD)
	; Init One millisecond interrupt counter.  It is a 16-bit variable made with two 8-bit parts
	clr a
	mov COUNTER_1MS+0, a
	mov COUNTER_1MS+1, a
	mov COUNTER_TIME_PWM+0, A
	mov COUNTER_TIME_PWM+1, A
	; Enable the timer and interrupts
	orl EIE, #0x80 ; Enable timer 2 interrupt ET2=1
    setb TR2  ; Enable timer 2
	ret

;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2

	push acc
	push psw

Timer2_ISR_Inc_COUTERPWM:
	inc COUNTER_TIME_PWM+0
	mov a, COUNTER_TIME_PWM+0
	jnz Timer2_PWM_Inc_Done
	inc COUNTER_TIME_PWM+1
	sjmp Timer2_ISR_Inc_COUTER1MS
	
Timer2_PWM_Inc_Done:
	mov a,COUNTER_TIME_PWM+0
	cjne a,#low(10), Timer2_ISR_Inc_COUTER1MS
	mov a,COUNTER_TIME_PWM+1
	cjne a,#high(10), Timer2_ISR_Inc_COUTER1MS

	clr a
	mov COUNTER_TIME_PWM+0, a
	mov COUNTER_TIME_PWM+1, a

	inc pwm_counter
	clr c
	mov a, pwm
	subb a, pwm_counter ; If pwm_counter <= pwm then c=1
	cpl c
	mov PWM_OUT, c
	
	mov a, pwm_counter
	cjne a, #100, Timer2_ISR_Inc_COUTER1MS
	mov pwm_counter, #0	

Timer2_ISR_Inc_COUTER1MS:
    inc COUNTER_1MS+0
	mov a, COUNTER_1MS+0
	jnz Timer2_RealTime_Inc_Done
	inc COUNTER_1MS+1
	sjmp Timer2_RealTime_Inc_Done
	
Timer2_RealTime_Inc_Done:
	mov a,COUNTER_1MS+0
	cjne a,#low(998), Timer2_ISR_Done
	mov a,COUNTER_1MS+1
	cjne a,#high(998), Timer2_ISR_Done

;	mov a,COUNTER_1MS+0
;	cjne a,#low(1000), Timer2_ISR_Done
;	mov a,COUNTER_1MS+1
;	cjne a,#high(1000), Timer2_ISR_Done
	; 1 second is satisfy, clean counter
	clr A
	mov COUNTER_1MS+0,A
	mov COUNTER_1MS+1,A
	;add 1 to TIME_REALTIME
	mov a,TIME_REALTIME
	add a,#1
	mov TIME_REALTIME,a
	inc sec ; It is super easy to keep a seconds count here

Timer2_ISR_Done:
	pop psw
	pop acc
	reti

Init_All:
	; Configure all the pins for biderectional I/O
	mov	P3M1, #0x00
	mov	P3M2, #0x00
	mov	P1M1, #0x00
	mov	P1M2, #0x00
	mov	P0M1, #0x00
	mov	P0M2, #0x00

;Timer0 initialization	
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
;Timer2 initialization
;------------------------------------------;
;Timer 2(for now speaker)
	lcall Timer2_Init 
;------------------------------------------;

; Button Initial
	mov COUNTER_BUTTON_SELECT,#0x00
	mov TEMP_SOAK,#150
	mov TIME_SOAK,#40
	mov TEMP_REFLOW,#240
	mov TIME_REFLOW,#20

; Initialize the pins used by the ADC (P1.1, P1.7) as input.
	orl	P1M1, #0b00100010
	anl	P1M2, #0b11011101
	
	; Initialize and start the ADC:
	anl ADCCON0, #0xF0
	orl ADCCON0, #0x05 ; Select channel 7
	; AINDIDS select if some pins are analog inputs or digital I/O:
	mov AINDIDS, #0x00 ; Disable all analog inputs
	orl AINDIDS, #0b00100001 ; Activate AIN0 and AIN7 analog inputs
	orl ADCCON1, #0x01 ; Enable ADC
	
	ret

;delay configuration
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

;Increase time number when button pushed
CHECK_BUTTON_INCREASE_time:
		jb PB_INCREASE, Inc_num
		ret
	Inc_num:
		add a, #0x01
		ret
	
;Decrease time number when button pushed
CHECK_BUTTON_DECREASE_time:
		jb PB_DECREASE, Dec_num
		ret
	Dec_num:
		clr c
		subb a, #0x01
		ret

SendString:
    clr A
    movc A, @A+DPTR
    jz SendStringDone
    lcall putchar
    inc DPTR
    sjmp SendString
SendStringDone:
    ret
	
;Increase temp number when button pushed
CHECK_BUTTON_INCREASE:
	jb PB_INCREASE, Inc_temp_num
	ret
Inc_temp_num:
	add a, #0x01
	ret
	
;Decrease temp number when button pushed
CHECK_BUTTON_DECREASE:
	jb PB_DECREASE, Dec_temp_num
	ret
Dec_temp_num:
	clr c
	subb a, #0x01
	ret

;check state for choosing which number should be changed
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
		lcall CHECK_BUTTON_INCREASE_time
		lcall CHECK_BUTTON_DECREASE_time
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
		lcall CHECK_BUTTON_INCREASE_time
		lcall CHECK_BUTTON_DECREASE_time
		mov TIME_REFLOW, a
		
		Display_char(#'=')
	CHECK_BUTTON_SELECT_STATE_DONE:
		ret     



;Detect which botton is pushed
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
		mov R2, #10
		lcall Waitms_NOINT
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

;FSM start
CHECK_BUTTON_START:
	push acc
	;setb TR2
	mov a, #0x01
	mov FSM1_state, a
	mov TIME_REALTIME, #0
	pop acc
	ret

;FSM stop
CHECK_BUTTON_STOP:
	push acc
	
	mov a, #0x00
	mov FSM1_state, a
	pop acc
	ret	

;Check whcih variable should be changed
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

;Display information on LCD
Display_PushButtons_LCD:
	Set_Cursor(2, 2)
	mov a, TEMP_SOAK
	lcall SendToLCD
	
	Set_Cursor(2, 6)
	mov a, TIME_SOAK
	lcall SendToLCD_2digit
	
	; Test Only, show COUNTER_BUTTON_SELECT
	;Set_Cursor(2,8)
	;Display_BCD(COUNTER_BUTTON_SELECT)
	
	Set_Cursor(2, 11)
	mov a, TEMP_REFLOW
	lcall SendToLCD
		
	Set_Cursor(2, 15)
	mov a, TIME_REFLOW
	lcall SendToLCD_2digit
	ret	
	
; Display the room temperature in LCD
Display_Tj_ban:
	clr ADCF
	setb ADCS ;  ADC start trigger signal
    jnb ADCF, $ ; for conversion complete
    
    ; Read the ADC result and store in [R1, R0]
    push acc
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
	lcall Display_formated_BCD_Su ;give temperature to LCD
	pop acc
	ret

Display_formated_BCD_Su:
	Display_BCD(bcd+2)
	Display_char(#'.')
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
	ret

Display_Tj:
	Set_Cursor(1, 13)
	Display_char(#'2')
	Display_char(#'2')

Read_ADC:
	clr ADCF
	setb ADCS ;  ADC start trigger signal
    jnb ADCF, $ ; Wait for conversion complete
    
    ; Read the ADC result and store in [R1, R0]
    mov a, ADCRL
    anl a, #0x0f
    mov R0, a
    mov a, ADCRH   
    swap a
    push acc
    anl a, #0x0f
    mov R1, a
    pop acc
    anl a, #0xf0
    orl a, R0
    mov R0, A
	ret

;ADC USING, function for operating ADC
Average_ADC:
	Load_x(0)
	mov R5, #200
Sum_loop0:
	lcall Read_ADC
	mov y+3, #0
	mov y+2, #0
	mov y+1, R1
	mov y+0, R0
	lcall add32
	djnz R5, Sum_loop0
	load_y(200)
	lcall div32
	ret
	
; Eight bit number to display passed in.
; Sends result to LCD
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
	
SendToLCD_2digit:
	mov b, #10
	div ab
	orl a, #0x30 ; Convert tens to ASCII
	lcall ?WriteData; Send to LCD
	mov a, b
	orl a, #0x30 ; Convert units to ASCII
	lcall ?WriteData; Send to LCD
	ret
	
Display_formated_BCD_Ste:
	mov a, temp
	Set_Cursor(1, 4)
	lcall SendToLCD
	ret

SendToSerial:
	mov b, #100
	div ab
	orl a, #0x30 ; Convert hundreds to ASCII
	lcall putchar ; Send to Serial
	mov a, b ; Remainder is in register b
	mov b, #10
	div ab
	orl a, #0x30 ; Convert tens to ASCII
	lcall putchar ; Send to Serial
	mov a, b
	orl a, #0x30 ; Convert units to ASCII
	lcall putchar ; Send to Serial
	ret

return:
    DB  '\r', '\n', 0

Send_to_computer:
	push AR0
	mov a, temp
	lcall SendToSerial
    mov DPTR, #return
    lcall SendString
    pop AR0
    ret

Get_temp_adc:
; Read the 2.08V LED voltage connected to AIN0 on pin 6
	anl ADCCON0, #0xF0
	orl ADCCON0, #0x00 ; Select channel 0
	lcall Read_ADC
	; Save result for later use
	mov VLED_ADC+0, R0
	mov VLED_ADC+1, R1

	; Read the signal connected to AIN7
	anl ADCCON0, #0xF0
	orl ADCCON0, #0x05 ; Select channel 7
	
	lcall Average_ADC
    
    ; Convert to voltage
	mov x+0, R0
	mov x+1, R1
	; Pad other bits with zero
	mov x+2, #0
	mov x+3, #0
	Load_y(41180) ; The MEASURED LED voltage: 2.074V, with 4 decimal places
	lcall mul32
	; Retrive the ADC LED value
	mov y+0, VLED_ADC+0
	mov y+1, VLED_ADC+1
	; Pad other bits with zero
	mov y+2, #0
	mov y+3, #0
	lcall div32
	
	load_y(3)
	lcall div32
	load_y(41)
	lcall div32
	load_y(22)
	lcall add32

	mov temp,x

	; Convert to BCD and display
	lcall hex2bcd
	lcall Display_formated_BCD_Ste
	; Wait 500 ms between conversions
	mov R2, #50
	lcall Waitms_NOINT
	lcall Send_to_computer
	ret

Waitms_NOINT:
	push AR1
	push AR0
L3_1: mov R1, #200
L2_1: mov R0, #104
L1_1: djnz R0, L1_1 ; 4 cycles->4*60.24ns*104=25us
    djnz R1, L2_1 ; 25us*200=5.0ms
    djnz R2, L3_1 ; 5.0ms*100=0.5s (approximately)
    pop AR0
    pop AR1
    ret

UpdatePWM:
	mov x+0, TEMP_TARGET
	mov x+1, #0
	mov x+2, #0
	mov x+3, #0

	mov y+0, temp
	mov y+1, #0
	mov y+2, #0
	mov y+3, #0

	; Check overheat
	lcall x_lteq_y
	jb mf, UpdatePWM_Stop
	; Traget temperature - Current temperature = delta T
	lcall sub32
	mov R0,x+0
	mov R1,x+1
	; Update sigma error = sigma error + delta T
	mov y+0,TEMP_SIGMAERROR+0
	mov y+1,TEMP_SIGMAERROR+1
	mov y+2,#0
	mov y+3,#0
	lcall add32
	mov TEMP_SIGMAERROR+0,x+0
	mov TEMP_SIGMAERROR+1,x+1
	; delta T * pwm period 
	load_y(100)
	lcall mul32
	; delta T * pwm period / Target temperature = %pwm
	mov y+0, TEMP_TARGET
	mov y+1, #0
	mov y+2, #0
	mov y+3, #0
	lcall div32
	; Check, threshhold is set to 50% of the pwm period
	load_y(40)
	lcall x_gteq_y
	jb mf, UpdatePWM_FullPower
	; pwm = pwm% * kp + sigma error * ki
	; kp
	load_y(2)
	lcall mul32
	mov R0,x+0
	mov R1,x+1
	; ki
	load_y(5)
	mov x+0,TEMP_SIGMAERROR+0
	mov x+1,TEMP_SIGMAERROR+1
	mov x+2,#0
	mov x+3,#0
	lcall mul32
	load_y(1000)
	lcall div32
	mov y+0,R0
	mov y+1,R1
	mov y+2,#0
	mov y+3,#0
	lcall add32
	mov pwm,x+0
	sjmp UpdatePWM_Done
UpdatePWM_Stop:
	mov pwm,#0
	sjmp UpdatePWM_Done
UpdatePWM_FullPower:
	; Set pwm to full pwm period
	mov pwm,#100
UpdatePWM_Done:
	ret

;---------------------------------;
;    main function starts here    ;
;---------------------------------;
main:
	mov sp, #0x7f
	lcall Init_All
    lcall LCD_4BIT
    
	setb EA ; Enable Global interrupts    
    ; initial messages in LCD
	Set_Cursor(1, 1)
    Send_Constant_String(#Line1)

	
	lcall Display_Tj
	Set_Cursor(2, 1)
    Send_Constant_String(#Line2)
    
	mov FSM1_state, #0x00

	
	FSM1:
	
	FSM1_state0:
	lcall Get_temp_adc
	lcall Display_Tj
	lcall CHECK_BUTTON_SELECT_STATE
	

	Set_Cursor(1,7)
	mov a,pwm
	lcall SendToLCD
	
	
    mov a, FSM1_state
	cjne a, #0x00, FSM1_state1
	mov pwm,#0
	lcall LCD_PB
	lcall Display_PushButtons_LCD
	
	mov sec, #0

FSM1_state0_done:
    ljmp FSM1
FSM1_state1:
	;lcall Get_temp_adc
	;lcall Display_Tj
	Set_Cursor(2, 13)
    mov a, TIME_REALTIME
    lcall SendToLCD
    Display_char(#'s')
	mov a, FSM1_state
	cjne a, #1, ZHONGZHUAN
	mov TEMP_TARGET,TEMP_SOAK;;;;;;
		lcall UpdatePWM;;;;;;;;;;;;
	Set_Cursor(2, 1)
    Send_Constant_String(#Reflow_0)
	lcall LCD_PB
	;mov pwm, #100
	mov a, TIME_REALTIME
	clr c
	subb a, #60
	jnc check_abort 
Continue_state1:
	mov a, TEMP_SOAK
	clr c
	subb a, temp
	jnc FSM1_state1_done
	mov FSM1_state, #2
	mov sec, #0
FSM1_state1_done:
	ljmp FSM1
	
ZHONGZHUAN:
	ljmp FSM1_state2
	
check_abort:
	clr c
	mov temp, a
	subb a, #50
	jc ABORTION
	ljmp Continue_state1
ABORTION:
	mov FSM1_state,#0
	Set_Cursor(2, 1)
    Send_Constant_String(#Warning)
    mov R2, #200
    lcall Waitms_NOINT
    lcall Waitms_NOINT
	Set_Cursor(2, 1)
    Send_Constant_String(#Line2)
	ljmp FSM1
;;wait soak
FSM1_state2:
	;lcall Get_temp_adc
	;lcall Display_Tj
	mov a, FSM1_state
	cjne a, #2, FSM1_state3
	Set_Cursor(2, 1)
    Send_Constant_String(#Reflow_1)
    	lcall UpdatePWM;;;;;;;;;;;;
	lcall LCD_PB
next_2:

   ; mov pwm, #20
    mov a, TIME_SOAK
    clr c
    subb a, sec
    jnc FSM1_state2_done
    mov FSM1_state, #3
FSM1_state2_done:
    ljmp FSM1
;;wait until temp reflow
FSM1_state3:
	;lcall Get_temp_adc
	;lcall Display_Tj
	mov a, FSM1_state
	cjne a, #3, FSM1_state4
	mov TEMP_TARGET,TEMP_REFLOW;;;;;;;;
		lcall UpdatePWM;;;;;;;;;;;;
	Set_Cursor(2, 1)
    Send_Constant_String(#Reflow_2)
	lcall LCD_PB
next_3:
;	mov pwm, #100
	mov a,TEMP_REFLOW
	clr c
	subb a,temp
	jnc FSM1_state3_done
	mov FSM1_state,#4
	mov sec,#0
	
FSM1_state3_done:
	ljmp FSM1

FSM1_state4:
	;lcall Get_temp_adc
	;lcall Display_Tj
	mov a, FSM1_state
	cjne a, #4, FSM1_state5
		lcall UpdatePWM;;;;;;;;;;;;
	Set_Cursor(2, 1)
    Send_Constant_String(#Reflow_3)
	lcall LCD_PB
next_4:
;	mov pwm,#20
	mov a,TIME_REFLOW
	clr c
	subb a,sec	
	jnc FSM1_state4_done
	mov FSM1_state,#5
	mov sec,#0x00
FSM1_state4_done:
	ljmp FSM1

FSM1_state5:
	lcall Get_temp_adc
	lcall Display_Tj
    Set_Cursor(2, 1)
    Send_Constant_String(#Reflow_4) 
	;cjne a, #5,FSM1_state0
	lcall LCD_PB
	mov pwm,#0
	mov a, #60
	clr c
	subb a, temp
	jc FSM1_state5_done
	mov FSM1_state,#0
	mov sec,#0x00
	Set_Cursor(2, 1)
    Send_Constant_String(#Blank)
    Set_Cursor(2, 1)
    Send_Constant_String(#Line2)

FSM1_state5_done:
	ljmp FSM1


	
END