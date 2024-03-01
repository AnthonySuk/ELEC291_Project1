#----------------------------------------------------------Program Description------------------------------------------------------------------#
#Project:       ELEC 291 Project 1: Reflow Oven Controller Python GUI
#Authors:       Jiayi Chen, Yifan Chen, Shitong Zou, Huiyu Chen, Hanlin Yu, Jinke Su
#Last Update:   2024-2-13 at 14:32 (PST)
#Description:   This program is designed to control a reflow oven and display critical data and information in real-time.
#@Copyright:    All right reserved by the authors. 版权所有 仿冒必究(:p)
#----------------------------------------------------------Program Description------------------------------------------------------------------#


#------------------------------------------------------------Import Libraries-------------------------------------------------------------------#
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.offsetbox import OffsetImage, AnnotationBbox
import matplotlib.animation as animation
import sys, time, math
import serial
import tkinter as tk
from tkinter import simpledialog
import requests
from bs4 import BeautifulSoup
from random import randint, randrange
import csv
import pygame
import cv2
import threading
#-----------------------------------------------------------------------------------------------------------------------------------------------#


#------------------------------------------------------------Global Variables-------------------------------------------------------------------#
#store time and temperature data
xdata, ydata = [], []
#cumulative temperature, used to calculate the mean temperature
total_temp = 0
#mean culmulative temperature
mean_ydata = []
#url for the weather in UBC
url = "https://www.timeanddate.com/weather/@7910029"
#max range for x-axis
xsize = 600
#create a figure with 2 subplots
fig, axs = plt.subplots(2, 1)
#store oven temp data and average temp data in csv files
test_data_file_name = 'test_data.csv'
#window size for moving average
window_size = 10
#store filtered oven temp data
filtered_oven_temp = []
#store filtered temp data
filtered_ydata = []
# mydata is the data that will be sent to the user's phone
mydata={
'text':'Reflow Oven Controller Password',
'desp':''
}
#-----------------------------------------------------------------------------------------------------------------------------------------------#


#-----------------------------------------------------Get The Current Temperature In UBC--------------------------------------------------------#
#create a GUI window
root = tk.Tk()
root.withdraw()

#send a request to the website
response = requests.get(url)
#use BeautifulSoup to parse the HTML content
soup = BeautifulSoup(response.text, 'html.parser')
#search for the temperature element
temp_element = soup.find('div', {'class': 'h2'})
#strip() removes leading and trailing whitespace

current_UBC_temp = temp_element.text.strip()
current_UBC_temp_float = float(current_UBC_temp[:-2])

#wait for 1 second before sending another request
time.sleep(1)
#-----------------------------------------------------------------------------------------------------------------------------------------------#


#--------------------------------------------------Password For Program To Initiate-------------------------------------------------------------#
#function to generator a fixed-length password
def random_with_N_digits(n):
    range_start = 10**(n-1)
    range_end = (10**n)-1
    return randint(range_start, range_end)

#password for the program to initiate
#correct_password = 123

correct_password = random_with_N_digits(6)
mydata['desp'] = f'Your password is: {correct_password}'
requests.post('https://wx.xtuis.cn/cUJbu1bM627w4ahUwKn8ARl5e.send', data=mydata)
password = simpledialog.askstring('Password', 'Enter the password:', show='*')

# idiot proof the password input
try:
    password = int(password)
except:
    password = -1
    print('Please enter a number!')

#if the password is correct, initiate the program
if password == correct_password:
#-----------------------------------------------------------------------------------------------------------------------------------------------#


#------------------------------------------------------------Main Program-----------------------------------------------------------------------#
    
#---------------------------------------------------------File Storage Section------------------------------------------------------------------#
    def write_to_csv(time, oven_temp, avg_temp, filtered_ydata):
        with open(test_data_file_name, mode='a', newline='') as file:
            writer = csv.writer(file)
            writer.writerow([time[-1], oven_temp[-1], avg_temp[-1], filtered_ydata[-1]])
#-----------------------------------------------------------------------------------------------------------------------------------------------#
        

#----------------------------------------------------------Moving Average Filter----------------------------------------------------------------#
    def moving_average(data, window_size):
        return np.convolve(data, np.ones(window_size) / window_size, 'valid')
#-----------------------------------------------------------------------------------------------------------------------------------------------#


#----------------------------------------------------------Pygame for mp3 playing---------------------------------------------------------------#
    # video_path = 'C:/Users/Jackie_Chen/Videos/Counter-strike  Global Offensive/csgo.mp4'
    # cap = cv2.VideoCapture(video_path)
    # if not cap.isOpened():
    #     print("Error opening video stream or file")
    # while cap.isOpened():
    #     ret , frame = cap.read()
    #     if not ret:
    #         break
    #     cv2.imshow('Frame', frame)
    #     if cv2.waitKey(1) == ord('q'):
    #         break
    # cap.release()
    # cv2.destroyAllWindows()
    def play_music():
        pygame.mixer.init()
        pygame.mixer.music.load("C:\CloudMusic\VipSongsDownload\Rick Astley - Never Gonna Give You Up.mp3")
        pygame.mixer.music.set_volume(1.0)
        pygame.mixer.music.play()
        play_time = 18.7
        time.sleep(play_time) #stop after play time
        pygame.mixer.music.stop()

    music_thread = threading.Thread(target=play_music)
    music_thread.start()
#-----------------------------------------------------------------------------------------------------------------------------------------------#
    

#---------------------------------------------------------Initialize Serial Port----------------------------------------------------------------#
    ser = serial.Serial(
    port='COM9',
    baudrate=115200,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_TWO,
    bytesize=serial.EIGHTBITS
    )

    #make sure serial port is open
    ser.isOpen()
    
    #imply correct password
    ser.write('c'.encode())
#-----------------------------------------------------------------------------------------------------------------------------------------------#
    

#--------------------------------------------------------Read Data From Serial Port-------------------------------------------------------------#
    def data_gen():
        t = data_gen.t
        while True:
            t += 1
            try:
                temperature = float(ser.readline().decode().strip())  #read strings from serial port and change it to float numebrs
            except:
                temperature = 22

            yield t, temperature
#----------------------------------------------------------------------------------------------------------------------------------------------#
            

#---------------------------------------------------------Initialize Trace Points -------------------------------------------------------------#
    mean_trace = None
    filtered_oven_trace = None
#----------------------------------------------------------------------------------------------------------------------------------------------#
    

#---------------------------------------------------------Update the Chart with New Data-------------------------------------------------------#
    def run(data):
        global total_temp, filtered_ydata, oven_trace, mean_trace, filtered_oven_trace
        t, y = data
        total_temp += y #compute the cumulative temperature form time t = 0
        mean_temp = total_temp / (t+0.5) #compute the average temperature

        if t > 0:
            xdata.append(t)
            ydata.append(y)
            mean_ydata.append(mean_temp)

            if t > xsize:  #scroll to left when t>size
                axs[0].set_xlim(t - xsize, t)
                axs[1].set_xlim(t - xsize, t)
            
            if filtered_oven_trace is not None:
                filtered_oven_trace.remove()

            if(len(ydata) >= window_size):
                filtered_ydata = moving_average(ydata, window_size)
                filtered_oven_temp.append(filtered_ydata[-1])
                filtered_oven_temp_line.set_data(xdata[window_size-1:], filtered_ydata)
                filtered_oven_trace = axs[0].text(t,filtered_ydata[-1], f'({t:.1f}s, {filtered_ydata[-1]:.2f}°C)', fontsize=9)

            avg_temp_text.set_text(f'Avg Temp: {mean_temp:.2f}℃')
            oven_temp_text.set_text(f'Oven Temp: {y:.2f}℃')
            filtered_oven_temp_text.set_text(f'Filtered Oven Temp: {filtered_ydata[-1]:.2f}℃')

            oven_temp_line.set_data(xdata, ydata) #updata current temperature line

            if mean_trace is not None:
                mean_trace.remove()
            mean_line.set_data(xdata, mean_ydata) #update average temperature line 
            mean_trace = axs[1].text(t,mean_temp, f'({t:.1f}s, {mean_temp:.2f}°C)', fontsize=9)
            
            #update current UBC temperature line
            current_UBC_temp_line.set_data(xdata, current_UBC_temp_float) 

            #write data to csv file
            write_to_csv(xdata, ydata, mean_ydata, filtered_ydata)

        #return what line need to be updated
        return current_UBC_temp_line,oven_temp_line, mean_line, filtered_oven_temp_line
#-----------------------------------------------------------------------------------------------------------------------------------------------#
    

#-----------------------------------------------------------Close the Program-------------------------------------------------------------------#
    #close the program when the chart is closed
    def on_close_figure(event):
        _ = event #to avoid unused variable warning
        sys.exit(0)
#-----------------------------------------------------------------------------------------------------------------------------------------------#
        

#-----------------------------------------------------------Create the Chart--------------------------------------------------------------------#
    #initialize the chart variables
    data_gen.t = 0  # initialize t in data_gen
    fig.canvas.mpl_connect('close_event', on_close_figure) #connect the close event to on_close_figure
    filtered_ydata = [0]

    #oven_temp line and text configuration
    oven_temp_line, = axs[0].plot([], [], lw=2, color='blue')
    oven_temp_text = axs[0].text(0.02, 0.98, f'oven_temp: {ydata}', transform=axs[0].transAxes, va='top', color='blue') #create a text message show at top left

    #filtered_oven_temp line and text configuration
    filtered_oven_temp_line, = axs[0].plot([], [], lw=2, color='orange')
    filtered_oven_temp_text = axs[0].text(0.02, 0.9, f'filtered_oven_temp: {filtered_ydata}', transform=axs[0].transAxes, va='top', color='orange') #create a text message show at top left

    #avg_temp line and text configuration
    mean_line, = axs[1].plot([], [], lw=2, color='red') #create a red mean temperature line
    avg_temp_text = axs[1].text(0.02, 0.98, '', transform=axs[1].transAxes, va='top', color='red') #create a text message show at top left

    #current_UBC_temp line and text configuration
    current_UBC_temp_line, = axs[1].plot([], [], lw=2, color='green', label='Current UBC Temperature') #create a green current UBC temperature line
    current_UBC_temp_text = axs[1].text(0.02, 0.9, f'Current_UBC_temp: {current_UBC_temp}', transform=axs[1].transAxes, va='top', color='green') #create a text message show at top left

    axs[0].set_ylim(-10, 300) #y-axis range from -20 to 50
    axs[0].set_xlim(0, xsize) #x-axis range from 0-50
    axs[0].grid()
    axs[1].set_ylim(-20, 300) #y-axis range from -20 to 50
    axs[1].set_xlim(0, xsize) #x-axis range from 0-50
    axs[1].grid()

    #create animation
    ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=1000, repeat=False)

    #configure the chart
    plt.xlabel('Time(s)')#x-axis label name
    axs[0].set_ylabel('Temperature(℃)')#y-axis label name
    axs[1].set_ylabel('Temperature(℃)')#y-axis label name
    fig.suptitle('ELEC 291 Project 1: Reflow Oven Controller \n Strip Chart', fontsize=14, color='black')
    plt.grid(True)#show mesh
    
    plt.show()#show the chart
#------------------------------------------------------------------------------------------------------------------------------------------------#
    
#--------------------------------------------------------End of Main Program---------------------------------------------------------------------#


#--------------------------------------------------------Password Incorrect---------------------------------------------------------------------#
#exit the program if the password is incorrect
else:
    print('Incorrect password. Please try again.')#if the password is incorrect, print this message
    sys.exit(0)
#-----------------------------------------------------------------------------------------------------------------------------------------------#