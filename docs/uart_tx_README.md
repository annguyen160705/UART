# what is DATA_WIDTH ? Why is it at 8 ?
DATA_WIDTH is how many bits we want the transmitter to send. It can be changed into whatever you like, 16 32
# What does BAUD_RATE mean in UART? Why is it at 115200 ?
BAUD_RATE tells us how fast the UART communication happens; for example, BAUD_RATE = 115200 means the signal changes at about 115,200 symbols per second, and in normal UART where one symbol represents one bit, this is about 115,200 bits per second.

# what is CLK_FREQ ? Why is it at 100_000_000 ?
CLK_FREQ is the frequency of the system clock that drives your UART RTL. It is not the UART communication speed; instead, it is used together with BAUD_RATE to determine how many system-clock cycles correspond to one UART bit.

Why do we need LB_DATA_WIDTH? What for?
Why do we need PULSE_WIDTH? What for?
Why do we need LB_PULSE_WIDTH? What for?
Why do we need HALF_PULSE_WIDTH? What for?

What is uart_if.tx txif doing here?

What is data_r? What for?
What is sig_r? What for?
What is ready_r? What for?
What is data_cnt? What for?
What is clk_cnt? What for?
