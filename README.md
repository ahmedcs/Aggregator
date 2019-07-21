# Implementing a P4 Calculator

## Introduction

The objective of this tutorial is to implement a basic aggregator and calculator functionality
using a custom protocol header written in P4. The header will contain
an operation to perform and one operands for aggregator and two operands for calculator. 
When a switch receives an aggregator or calculator packet header, it will execute the operation on the
operands, and return the result to the sender.

## Step 1: Run the (incomplete) starter code

The directory with this README also contains a skeleton P4 program,
`aggregator.p4` for aggregator and calculator `calc.py` for calculator only, which can do aggregations using (R=RESET and A=Aggegate) operators
as well as Calculator functions (+, -, |, &)

3. The driver program will provide a new prompt, at which you can type
basic expressions. The test harness will parse your expression, and
prepare a packet with the corresponding operator and operands. It will
then send a packet to the switch for evaluation. When the switch
returns the result of the computation, the test program will print the
result.

```
> 1+1
2
>
0 R
0
>10 A
10
> 5 A
15
```

## Calculator/Aggregator headers format

In the calculator, we define a custom
calculator header, and implement the switch logic to parse header,
perform the requested operation, write the result in the header, and
return the packet to the sender.

We will use the following header format:

             0                1                  2              3
      +----------------+----------------+----------------+---------------+
      |      P         |       4        |     Version    |     Op        |
      +----------------+----------------+----------------+---------------+
      |                              Operand A                           |
      +----------------+----------------+----------------+---------------+
      |                              Operand B                           |
      +----------------+----------------+----------------+---------------+
      |                              Result                              |
      +----------------+----------------+----------------+---------------+
 

-  P is an ASCII Letter 'P' (0x50)
-  4 is an ASCII Letter '4' (0x34)
-  Version is currently 0.1 (0x01)
-  Op is an operation to Perform:
 -   '+' (0x2b) Result = OperandA + OperandB
 -   '-' (0x2d) Result = OperandA - OperandB
 -   '&' (0x26) Result = OperandA & OperandB
 -   '|' (0x7c) Result = OperandA | OperandB
 -   '^' (0x5e) Result = OperandA ^ OperandB
 -   'R' (0x52) Result = OperandA R (Reset register to OperandA)
 -   'A' (0x41) Result = OperandA A (Adds to register to OperandA)
 

We will assume that the calculator header is carried over Ethernet,
and we will use the Ethernet type 0x1234 to indicate the presence of
the header.


