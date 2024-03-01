# ELEC291_Project1
Reflow oven control
## Subteam mission
### Input output control
-  Get oven temperature
-  Using timer interrupt to periodically get the temperature data
-  PWM control
-  LCD display
    -  Row 1：T0（Oven temperature） Tj（Room temperature）
    -  Row 2：S（Soak temperature，Soak time） R（Reflow temperature，Reflow time）
-  Button
    -  Start Button
    -  Stop Button
    -  Switch select（soak temperature，soak time，reflow temperature，reflow time）
    -  Increase number
    -  Decrease number
-  Relative calculation
    -  Current temperature Tc and target temperature T, ΔT = T - Tc
    -  Relative percentage of current error and target temperature ΔT% = ΔT / T
    -  Oven output time t = ΔT% * PWM period * kp
