
     T H E   M I X   S I M U L A T O R   A N D   A S S E M B L E R

                   Chaoji Li<lichaoji@gmail.com>

                         March 22, 2008


                -  Y    =    =    =   =   =    Y  -
              | o \|    | \/ |    |     x      |/ o |
               \ /  \   =    =    =   =   =   /  \ /


There are so many MIX simulators all over the world. The reason for this
one is that it is written in perl as a well defined module, aiming to be
reused. People can also use this one as a reference model when testing 
their own simulators. I suggest everyone who really wants to read the
programs in TAOCP should implement one by himself, so as to understand
the MIX machine and the MIX instructions better. MIX is also similar to
various machines produced in 1960s. To write the simulator yourself would
be a rewarding trip if you are curious about the history of computer 
programming.

This simulator supports almost all instructions, except for float operations.

Card reader/punch and printer are supported.
Disk/tape are partial supported.


===============
 I N S T A L L
===============

(1) Extract the source tar ball:

    tar -xvzf Hardware-Simulator-MIX-<version>.tar.gz

(2) Install "Build" module from CPAN.
(3) Run following commands in the extracted directory:

        perl Build.PL
        perl Build
        perl Build test
        perl Build install

Steps (2) and (3) is not required if you only want to play
within the extracted directory.


===========================
 D O C U M E N T A T I O N
===========================

perldoc mixsim.pl
perldoc mixasm.pl
perldoc Hardware::Simulator::MIX
perldoc doc/mix.pod

=======================
 Q U I C K   S T A R T
=======================

In the package directory, 

>perl mixasm.pl mixal/primes

Two files will be generated in the current directory.

   * primes.lst -- listing files
   * primes.crd -- card deck file which can be loaded by mix simulator

>perl mixsim.pl --batch primes.crd

The outputs are:

== PAGE 1 OF 1 ==
FIRST FIVE HUNDRED PRIMES
     0002 0233 0547 0877 1229 1597 1993 2371 2749 3187
     ...
     0229 0541 0863 1223 1583 1987 2357 2741 3181 3571     

You can also enter the interactive mode. An example session is
shown below.

>perl mixsim.pl primes.crd


    M I X   S i m u l a t o r

Type 'h' for help messages.
MIX> g 3000
 rA: + 00 00 00 00 00 +0
 rX: + 00 33 30 30 30 +8775582     3000
rI1: + 00 00 +0000   rI2: - 00 30 -0030
rI3: + 46 56 +3000   rI4: + 00 00 +0000
rI5: + 00 00 +0000   rI6: + 00 00 +0000
 rJ: + 00 14 +0014   NO EQ  1325u
3000: IOC  0,0(18)
MIX> g 3029
 rA: + 30 30 30 30 30 +511305630  00000
 rX: + 30 30 32 32 39 +511313959  00229
rI1: + 00 00 +0000   rI2: + 55 51 +3571
rI3: + 00 19 +0019   rI4: + 31 51 +2035
rI5: + 00 00 +0000   rI6: + 00 00 +0000
 rJ: + 47 18 +3026   NO EQ  1183474u
3029: HLT  0,0(2)
MIX> prt
Page 1 of 1
FIRST FIVE HUNDRED PRIMES
     0002 0233 0547 0877 1229 1597 1993 2371 2749 3187
     ....
     0229 0541 0863 1223 1583 1987 2357 2741 3181 3571
MIX>


