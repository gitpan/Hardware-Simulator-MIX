package Hardware::Simulator::MIX;

use strict;
use warnings;
use Data::Dumper;
require Exporter;

our @ISA       = qw(Exporter);
our @EXPORT    = qw( 
		     new 
		     reset 
		     step 
		     mix_char 
		     mix_char_code 
		     get_overflow 
		     read_mem
		     write_mem
		     set_max_byte
		     get_pc
                     get_reg
                     get_current_time
                     get_exec_count
                     get_exec_time
                     get_last_error
		     get_cmp_flag );

our $VERSION   = 0.2;

sub new 
{
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
    my $self = {
	@_ 
	};
    bless $self, $class;

    $self->{max_byte} = 64 if !exists $self->{max_byte};

    # According to knuth, in 1960s, one time unit on a high-priced machine is 1 us. 
    # and a low cost is 10 us.  One time unit is same to the memory access time
    # we want to set it to 5 us.
    $self->{timeunit} = 5  if !exists $self->{timeunit};
    $self->{ms} = 1000/$self->{timeunit};

    $self->{dev} = {};
    $self->reset();
    return $self; 
}

sub get_max_byte
{
    my $self = shift;
    return $self->{max_byte};
}

sub set_max_byte
{
    my $self = shift;
    $self->{max_byte} = shift;
}

sub get_last_error
{
    my $self = shift;
    return ""     if ($self->{status} == 0);
    return "HALT" if ($self->{status} == 1);
    return "ERROR: " . uc("$self->{message}") if $self->{status} >= 2;
}

sub reset 
{
    my $self = shift;

    $self->{rA} = ['+', 0, 0, 0, 0, 0];
    $self->{rX} = ['+', 0, 0, 0, 0, 0];
    $self->{rJ} = ['+', 0, 0, 0, 0, 0];
    $self->{rZ} = ['+', 0, 0, 0, 0, 0];

    $self->{rI1} = ['+', 0, 0, 0, 0, 0];
    $self->{rI2} = ['+', 0, 0, 0, 0, 0];
    $self->{rI3} = ['+', 0, 0, 0, 0, 0];
    $self->{rI4} = ['+', 0, 0, 0, 0, 0];
    $self->{rI5} = ['+', 0, 0, 0, 0, 0];
    $self->{rI6} = ['+', 0, 0, 0, 0, 0];

    $self->{mem} = [];
    $self->{execnt} = [];
    $self->{exetime} = [];

    for (0 .. 3999) {
	push @{$self->{mem}}, ['+', 0, 0, 0, 0, 0];
	push @{$self->{execnt}}, 0;
	push @{$self->{exetime}}, 0;
    }

    $self->{devstat} = [];
    for (0 .. 19) {
        push @{$self->{devstat}}, {
            laststarted => 0,
            delay => 0
        };
    }

    # MIX running time from last reset, recorded in time units
    $self->{time}      = 0;
        
    $self->{pc}        = 0;
    $self->{next_pc}   = 0;
    $self->{ov_flag}   = 0;
    $self->{cmp_flag}  = 0;
    $self->{status}    = 0;
    $self->{message}   = 'running';
}

# For tape and disk units, each item in buffer is a word, like
#   ['+', 0, 0, 0, 1, 2]
# For card reader and punch, each item of buffer is a line.        
# For printer, each item of buffer is a page.
# e.g.   $mix->add_device(16, \@cards);
sub add_device 
{
    my ($self, $u, $buf) = @_; 
    return 0 if $u > 19 || $u < 0;
    $self->{dev}->{$u} = {};
    if (defined $buf) {
	$self->{dev}->{$u}->{buf} = $buf;
    } else {
	$self->{dev}->{$u}->{buf} = [];
    }
    $self->{dev}->{$u}->{pos} = 0;
    return 1;
}

sub go 
{
    my ($self) = @_;

    $self->load_card(0);
    while ($self->{status} == 0) {
	$self->step();
    }
}

sub get_overflow
{
    my $self = shift;
    return $self->{ov_flag};
}

sub get_cmp_flag
{
    my $self = shift;
    return $self->{cmp_flag};
}

sub get_pc
{
    my $self = shift;
    return $self->{pc};
}

sub get_next_pc
{
    my $self = shift;
    return $self->{next_pc};
}

sub get_current_time
{
    my $self = shift;
    return $self->{time};
}

sub get_exec_count
{
    my ($self, $loc) = @_;
    return @{$self->{execnt}}[$loc];
}

sub get_exec_time
{
    my ($self, $loc) = @_;
    return @{$self->{exetime}}[$loc];
}

# Usage: $self->wait_until_device_ready($devnum)
#
# Used only before IN/OUT operations. 
# 
# If the device is busy, that is, the current time - last started < delay,
# increase the current time, so that the device would be ready

sub wait_until_device_ready
{
    my ($self, $devnum) = @_;
    my $devstat = @{$self->{devstat}}[$devnum];
    my $laststarted = $devstat->{laststarted};

    # See whether the device is still busy
    if ($self->{time} - $laststarted < $devstat->{delay})
    {
        # advance the current system time to the point
        # that the device would be ready
        $self->{time} = $laststarted + $devstat->{delay};
    }
}

# Execute an instruction, update the machine state
sub step
{
    my $self = shift;

    my @regname = qw(rA rI1 rI2 rI3 rI4 rI5 rI6 rX);

    return if $self->{status} != 0;

    my $start_time = $self->{time};

    # Fetch instruction
    my $loc = $self->{pc};
    my @word = $self->read_mem_timed($loc);
    return if $self->{status} != 0;

    my $c = $word[5];
    my $f = $word[4];
    my $r = $f%8;
    my $l = int($f/8);
    my $i = $word[3];
    my $a = $word[1] * $self->{max_byte} + $word[2];
    $a = ($word[0] eq '+')? $a : (0 - $a);
    my $m = $a;
    if ($i >= 1 && $i <= 6) {
	$m += $self->get_reg('rI' . $i);
    }
    
    $self->{next_pc} = $self->{pc} + 1;

    if ( $c == 5 && $f == 2) { ## HLT: the machine stops
	$self->{status} = 1;
	$self->{message} = 'halts normally';
    } elsif ($c == 0) { ## NOP: no operation
    } elsif ($c == 8) { ## LDA: load A
	my @tmp = $self->read_mem_timed($m, $l, $r);
	$self->set_reg('rA', \@tmp);
    } elsif ($c == 15) { ## LDX
	my @tmp = $self->read_mem_timed($m, $l, $r);
	$self->set_reg('rX', \@tmp);
    } elsif ($c >= 9 && $c <= 14) { ## LDi
	my @tmp = $self->read_mem_timed($m, $l, $r);
	$self->set_reg('rI' . ($c-8), \@tmp);
    } elsif ($c == 16) { ## LDAN
	my @tmp = $self->read_mem_timed($m, $l, $r);
	@tmp = neg_word(\@tmp);
	$self->set_reg('rA', \@tmp);
    } elsif ($c == 23) { ## LDXN
	my @tmp = $self->read_mem_timed($m, $l, $r);
	@tmp = neg_word(\@tmp);
	$self->set_reg('rX', \@tmp);
    } elsif ($c >= 17 && $c <= 22) { ## LDiN
	my @tmp = $self->read_mem_timed($m, $l, $r);
	@tmp = neg_word(\@tmp);
	$self->set_reg('rI' . ($c-16), \@tmp);
    } elsif ($c == 24) { ## STA
	$self->write_mem_timed($m, $self->{rA}, $l, $r);
    } elsif (25 <= $c && $c <= 30) { ## STi
	my $ri = 'rI' . ($c-24);
	$self->write_mem_timed($m, $self->{$ri}, $l, $r);
    } elsif ($c == 31) { ## STX
	$self->write_mem_timed($m, $self->{rX}, $l, $r);
    } elsif ($c == 32) { ## STJ
	$self->write_mem_timed($m, $self->{rJ}, $l, $r);
    } elsif ($c == 33) { ## STZ
	$self->write_mem_timed($m, $self->{rZ}, $l, $r);
    } elsif ($c == 1) { ## ADD
	my @tmp = $self->read_mem_timed($m, $l, $r);
	$self->add(\@tmp);
    } elsif ($c == 2) { ## SUB
	my @tmp = $self->read_mem_timed($m, $l, $r);
	$self->minus(\@tmp);
    } elsif ($c == 3 && $f != 6) { ## MUL
	my @tmp = $self->read_mem_timed($m, $l, $r);
	$self->mul(\@tmp);

        # MUL requires 8 additional time units
        $self->{time} += 8;
    } elsif ($c == 4 && $f != 6) { ## DIV
	my @tmp = $self->read_mem_timed($m, $l, $r);
	$self->div(\@tmp);

        # DIV requires 10 additional time units
        $self->{time} += 10;
    } elsif (48 <= $c && $c <= 55) { 
	my $reg = $self->{$regname[$c-48]};
	if ($f == 0) { ## INC
	    my $v = word_to_int($reg, $self->{max_byte});
	    if (int_to_word($v+$m, $reg, $self->{max_byte})) {
		$self->{ov_flag} = 0;
	    } else {
		$self->{ov_flag} = 1;
	    }
	} elsif ($f == 1) { ## DEC
	    my $v = word_to_int($reg, $self->{max_byte});
	    if (int_to_word($v-$m, $reg, $self->{max_byte})) {
		$self->{ov_flag} = 0;
	    } else {
		$self->{ov_flag} = 1;
	    }
	} elsif ($f == 2) { ##ENT
	    int_to_word($m, $reg, $self->{max_byte});
	} elsif ($f == 3) { ##ENN
	    int_to_word(-$m, $reg, $self->{max_byte});
	} else {
	    goto  ERROR_INST;
	}
    } elsif (56 <= $c && $c <= 63) { ## CMP
	my $tmp1 = $self->get_reg($regname[$c-56], $l, $r);
	my $tmp2 = $self->read_mem_timed($m, $l, $r);
	$self->{cmp_flag} = $tmp1 - $tmp2;
    } elsif ($c == 39) { ## JMP ON CONDITION
	goto ERROR_INST if $f > 9;
	my $ok   = 1;
	my $savj = 0;
	my $cf   = $self->{cmp_flag};
	my @cond = ($cf<0,$cf==0,$cf>0,$cf>=0,$cf!=0,$cf<=0);

	if ($f == 0) {
	    $ok = 1;
	}elsif ($f == 1) {
	    $savj = 1;
	} elsif ($f == 2) {
	    $ok = $self->{ov_flag};
	} elsif ($f == 3) {
	    $ok = !$self->{ov_flag};
	} else {
	    $ok = $cond[$f-4];
	}

	if ($ok) {
	    if (!$savj) {
		int_to_word($self->{next_pc}, $self->{rJ}, $self->{max_byte});
	    }
	    $self->{next_pc} = $m;
	}
    } elsif (40 <= $c && $c <= 47) {
	goto ERROR_INST if $f > 5;
	my $val = $self->get_reg($regname[$c-40]);
	my @cond = ($val<0,$val==0,$val>0,$val>=0,$val!=0,$val<=0);
	if ($cond[$f]) {
	    int_to_word($self->{next_pc}, $self->{rJ}, $self->{max_byte});
	    $self->{next_pc} = $m;
	}
    } elsif ($c == 7) {
	my $dest = $self->get_reg('rI1');
	for (my $i = 0; $i < $f; $i++, $m++, $dest++) {
	    my @w = $self->read_mem_timed($m);
	    $self->write_mem_timed($dest, \@w);
	}
	my @tmp = ('+', 0,0,0,0,0);
	int_to_word($dest, \@tmp, $self->{max_byte});
	$self->set_reg('rI1', \@tmp);
    } elsif ($c == 6) { ## Shift Operators
	goto ERROR_INST if $m < 0;

	my @a = @{$self->{rA}};
	my @x = @{$self->{rX}};
	my $sa = shift @a;
	my $sx = shift @x;
	if ($f == 0) { ## SLA
	    $m = $m%5;
	    while (--$m >= 0) {
		shift @a;
		push @a, 0;
	    }
	} elsif ($f == 1) { ## SRA
	    $m = $m%5;
	    while (--$m >= 0) {
		pop @a;
		unshift @a, 0;
	    }
	} elsif ($f == 2) { ## SLAX
	    $m = $m%10;
	    while (--$m >= 0) {
		shift @a;
		push @a, shift @x;
		push @x, 0;
	    }
	} elsif ($f == 3) { ## SRAX
	    $m = $m%10;
	    while (--$m >= 0) {
		pop @x;
		unshift @x, pop @a;
		unshift @a, 0;
	    }
	} elsif ($f == 4) { ## SLC
	    $m = $m%10;
	    while (--$m >= 0) {
		push @a, shift @x;
		push @x, shift @a;
	    }
	} elsif ($f == 5) { ## SRC
	    $m = $m%10;
	    while (--$m >= 0) {
		unshift @a, pop @x;
		unshift @x, pop @a;
	    }
	} else {
	    goto ERROR_INST;
	}
	unshift @a, $sa;
	unshift @x, $sx;
	$self->set_reg('rA', \@a);
	$self->set_reg('rX', \@x);

        # shift operations takes additional 1 time unit
        $self->{time} = $self->{time} + 1;

    } elsif ($c == 5 && $f == 0) { ## NUM
	my @a = @{$self->{rA}};
	my @x = @{$self->{rX}};
	my $m = $self->{max_byte};
	my $M = $m*$m*$m*$m*$m;
	my $sa = shift @a;
	shift @x;
	push @a, @x;
	my $val = 0;
	while (@a) {
	    my $d = shift @a;
	    $val = $val*10+($d % 10);
	}
	if ($val >= $M) {
	    $val = $val % $M;
	    $self->{ov_flag} = 1;
	} else {
	    $self->{ov_flag} = 0;
	}
	int_to_word($val, $self->{rA}, $m);
	@{$self->{rA}}[0] = $sa;
    } elsif ($c == 5 && $f == 1) { ## CHAR
	my $val = word_to_uint($self->{rA}, $self->{max_byte});
	my $i;
	for ($i = 5; $i >= 1; $i--) {
	    @{$self->{rX}}[$i] = 30 + $val%10;
	    $val = int($val/10);
	}
	for ($i = 5; $i >= 1; $i--) {
	    @{$self->{rA}}[$i] = 30 + $val%10;
	    $val = int($val/10);
	}
    } elsif ($c == 36) { ## IN
	if ($f == 16) { ## CARD READER
            $self->wait_until_device_ready($f);
	    $self->load_card($m);
	} elsif ($f >= 0 && $f <= 7) {
            $self->wait_until_device_ready($f);
	    $self->read_tape($f, $m);
	} elsif ($f >= 8 && $f <= 15) {
            $self->wait_until_device_ready($f);
	    $self->read_disk($f, $m);
	} else {
	    $self->{status} = 2;
	    $self->{message} = "input device(#$f) not supported at $loc";
	}
    } elsif ($c == 37) {
	if ($f == 17) { ## CARD Punch
	    $self->wait_until_device_ready($f);
            $self->punch_card($m);
	} elsif ($f == 18)  { ## Printer
	    $self->wait_until_device_ready($f);
	    $self->print_line($m);
	} elsif (0 <= $f && $f <= 7) {
	    $self->wait_until_device_ready($f);
	    $self->write_tape($f, $m);
	} elsif (8 <= $f && $f <= 15) {
	    $self->wait_until_device_ready($f);
	    $self->write_disk($f, $m);
	} else {
	    $self->{status} = 2;
	    $self->{message} = "output device(#$f) not supported at $loc";
	}
    } elsif ($c == 35) {
	if ($f == 18) { ## Printer: set up new page
	    $self->wait_until_device_ready($f);
	    $self->new_page($m);
	} elsif (0 <= $f && $f <= 7) {
	    $self->set_tape_pos($f, $m);
	} elsif (8 <= $f && $f <= 15) {
	    $self->set_disk_pos($f);
	} else {
	    $self->{status} = 2;
	    $self->{message} = "ioctrl for device(#$f) not supported at $loc";
	}
    } elsif ($c == 34) { ## JBUS: Always no busy
    } elsif ($c == 38) { ## JRED: Jump immediately		
	int_to_word($self->{next_pc}, $self->{rJ}, $self->{max_byte});
	$self->{next_pc} = $m;
    } else {
ERROR_INST:
	$self->{status} = 2;
	$self->{message} = "invalid instruction at $loc";
    }

    @{$self->{execnt}}[$loc]++;
    @{$self->{exetime}}[$loc] += $self->{time} - $start_time;
    $self->{pc} = $self->{next_pc};
}

sub get_device_buffer {
    my $self = shift;
    my $u = shift;
    if (exists $self->{dev}->{$u}) {
	return $self->{dev}->{$u}->{buf};
    } else {
	return undef;
    }    
}

sub write_tape {
    my ($self, $u, $m) = @_;
    my $tape = $self->{dev}->{$u};
    my $n = @{$tape->{buf}};    
    for (my $i = 0; $i < 100; $i++) {	
	my @w = $self->read_mem($m+$i);
	if ($tape->{pos} < $n) {
	    @{$tape->{buf}}[ $tape->{pos} ] = \@w;
	} else {
	    push @{$tape->{buf}}, \@w;
	}
	$tape->{pos}++;
    }    

}
sub read_tape {
    my ($self, $u, $m) = @_;
    my $tape = $self->{dev}->{$u};
    my $n = @{$tape->{buf}};    

    for (my $i = 0; $i < 100 && $tape->{pos} < $n; $i++) {	
	my $w = @{$tape->{buf}}[ $tape->{pos} ];
	$self->write_mem($m+$i, $w);
	$tape->{pos}++;
    }        
}


# TODO: tape and disk io

# device ability is aligned with IBM1130.org
# tape io: 10ms
# disk io: 10ms
# seek : 10ms

sub set_tape_pos {

}
sub set_disk_pos {
}
sub write_disk {
}
sub read_disk {
}

# Load cards into memory started at $loc
sub load_card 
{
    my ($self,$loc) = @_;

    # Check if card reader installed
    if (!exists $self->{dev}->{16}) {
	$self->{status} = 2;
	$self->{message} = "missing card reader";
	return 0;
    }

    my $reader = $self->{dev}->{16};
    my $buf = $reader->{buf};
    my $pos = $reader->{pos};

    # Check if there are cards unread
    if ($pos >= @{$buf}) {
	$self->{status} = 2;
	$self->{message} = "no card in card reader";
	return 0;
    }
    
    my $crd = @{$buf}[$pos];
    $reader->{pos}++;

    # Pad spaces to make the card have 80 characters
    if (length($crd)!=80) {
	$crd .= " " x (80-length($crd));
    }
    my @w = ('+');
    for (my $i = 0; $i < 80; $i++) {
	my $c = mix_char_code( substr($crd,$i,1) );
	if ($c == -1) {
	    $self->{status} = 2;
	    $self->{message} = "invalid card: '$crd'";
	    return 0;
	} else {
	    push @w, $c;
	    if (@w == 6) {
		$self->write_mem($loc++, \@w);
		@w = ('+');
	    }
	}
    }

    my $devstat = @{$self->{devstat}}[17];
    $devstat->{laststarted} = $self->{time};
    $devstat->{delay} = 100 * $self->{ms}; # Read 10 cards per second
    
    return 1;
}


sub punch_card 
{
    my ($self, $loc) = @_;

    if (!exists $self->{dev}->{17}) {
	$self->{status} = 2;
	$self->{message} = "missing card punch";
	return;
    }    

    my $crd;
    for (my $i = 0; $i < 16; $i++) {
	my @w = $self->read_mem($loc++);
	shift @w;
	while (@w) {
	    my $ch = mix_char(shift @w);
	    if (defined $ch) {
		$crd .= $ch; 
	    } else {
		$crd .= "^";
	    }
	}
    }

    my $dev = $self->{dev}->{17};
    push @{$dev->{buf}}, $crd;

    my $devstat = @{$self->{devstat}}[17];
    $devstat->{laststarted} = $self->{time};
    $devstat->{delay} = 500 * $self->{ms}; # Punch 2 cards per second
}

sub print_line 
{
    my ($self, $loc) = @_;
    my $printer = $self->{dev}->{18};
    if (!defined $printer) {
	$self->{status} = 2;
	$self->{message} = "missing printer";
	return;
    }

    my $page = pop @{$printer->{buf}};
    $page = "" if !defined $page;

    my $line;
    for (my $i = 0; $i < 24; $i++) {
	my @w = $self->read_mem($loc++);
	shift @w;
	while (@w) {
	    my $ch = mix_char(shift @w);
	    if (defined $ch) {
		$line .= $ch; 
	    } else {
		$line .= "^";
	    }
	}
    }
    $line =~ s/\s+$//;
    $page .= $line . "\n";
    push @{$printer->{buf}}, $page;

    my $devstat = @{$self->{devstat}}[18];
    $devstat->{laststarted} = $self->{time};
    $devstat->{delay} = 100 * $self->{ms}; # Print 10 lines per second
}

sub new_page 
{
    my ($self, $m) = @_;
    my $printer = $self->{dev}->{18};

    if (!defined $printer) {
	$self->{status} = 2;
	$self->{message} = "missing printer";
	return;
    }

    if ($m == 0) {
	push @{$printer->{buf}}, "";
    } else {
	$self->{status} = 2;
	$self->{message} = "printer ioctrl error: M should be zero";
    }

    my $devstat = @{$self->{devstat}}[18];
    $devstat->{laststarted} = $self->{time};
    $devstat->{delay} = 10 * $self->{ms};
}

sub clear_status 
{
    my ($self) = @_;
    $self->{status} = 0;
}

sub get_reg
{
    my ($self, $reg, $l, $r) = @_;

    if (!exists $self->{$reg}) {
	$self->{status} = 2;
	$self->{message} = "accessing non-existed reg: $reg";
	return undef;
    }

    if (defined $l) {
	$r = $l if !defined $r;
    } else {
	$l = 0;
	$r = 5;
    }

    my @word = @{$self->{$reg}};
    my @retval = ();

    for ($l .. $r) {
	push @retval, $word[$_]
    }
    @retval = fix_word(@retval);
    my $value = word_to_int(\@retval, $self->{max_byte});
    return wantarray? @retval : $value;
}

sub set_reg
{
    my ($self, $reg, $wref) = @_;

    if (!exists $self->{$reg}) {
	$self->{status} = 2;
	$self->{message} = "accessing non-existed reg: $reg";
	return;
    }
    my @word = @{$wref};

    my $sign = '+';
    if (@{$wref}[0] eq '+' || @{$wref}[0] eq '-') {
	$sign = shift @{$wref};
    }
    @{$self->{$reg}}[0] = $sign;

    my $l = ($reg =~ m/r(I|J)/)?4:1;
    my $r = 5;
    while ($r >= $l && @word != 0) {
	@{$self->{$reg}}[$r] = pop @word;
	--$r;
    }
}

sub is_halted 
{
    my $self = shift;
    return 0 if $self->{status} == 0;
    return 1;
}

sub read_mem_timed
{
    my $self = shift;
    $self->{time} = $self->{time} + 1;
    return $self->read_mem(@_);
}

sub write_mem_timed
{
    my $self = shift;
    $self->{time} = $self->{time} + 1;
    return $self->write_mem(@_);
}


sub read_mem
{
    my ($self,$loc,$l, $r) = @_;

    if ($loc < 0 || $loc > 3999) {
	$self->{status} = 2;
	$self->{message} = "access invalid memory location: $loc";
	return;
    }

    my @word = @{@{$self->{mem}}[$loc]};
    if (defined $l) 
    {
	$r = $l if !defined $r;
    }
    else {
	$l = 0;
	$r = 5;
    }

    my @retval = ();
    for ($l .. $r) {
	push @retval, $word[$_]
	}
    @retval = fix_word(@retval);
    my $value = word_to_int(\@retval, $self->{max_byte});
    return wantarray? @retval : $value;
}




#####################################################################
## memfunc write_mem
#
# Calling: $xxx->write_mem($loc, $wref, $l, $r)
#
# $loc: location, must be in [0..3999]
# $wref: reference to a mix word
# $l,$r: field specification of destinated word, 0<=$l<=$r<=5
#
#####################################################################

sub write_mem
{
    my ($self,$loc,$wref, $l, $r) = @_;

    if ($loc < 0 || $loc > 3999) {
	$self->{status} = 2;
	$self->{message} = "access invalid memory location: $loc";
	return;
    }

    my @word = @{$wref};
    debug("write mem ", word_to_string(@word) );

    if (!defined $l) {
	$l = 0;
	$r = 5;
    } elsif (!defined $r) {
	$r = $l;
    }
    my $dest = @{$self->{mem}}[$loc];
    debug("   to loc#$loc ", word_to_string(@{$dest}), "($l:$r)");
    for (my $i = $r; $i >= $l;  $i--) {
	@{$dest}[$i] = pop @word if $i > 0;
	if ($i == 0) {
	    if (@word > 0 && ($word[0] eq '+' || $word[0] eq '-')) {
		@{$dest}[0]  = $word[0];
	    } else {
		@{$dest}[0]  = '+';
	    }
	}
    }
    debug("  => ", word_to_string(@{$dest}));
}

#######################################################################
# Private member functions
#######################################################################

sub add
{
    my ($self, $w) = @_;
    my $m = $self->{max_byte};
    my $a = $self->{rA};

    if (!int_to_word(word_to_int($w,$m)+word_to_int($a,$m), $a, $m)) {
	$self->{ov_flag} = 1;
    } else {
	$self->{ov_flag} = 0;
    }
}

sub minus
{
    my ($self, $w) = @_;
    my @t = @{$w};
    if ($t[0] eq '+') {
	$t[0] = '-';
    } else {
	$t[0] = '+';
    }
    $self->add(\@t);
}

sub mul
{
    my ($self, $w) = @_;
    my $a = $self->{rA};
    my $x = $self->{rX};
    my $m = $self->{max_byte};
    my $M = $m*$m*$m*$m*$m;

    my $v = word_to_int($a,$m)*word_to_int($w,$m);

    my $sign = ($v>=0?'+':'-');
    $v = -$v if $v < 0;

    int_to_word($v%$M, $x, $m);
    int_to_word(int($v/$M), $a, $m);

    @{$x}[0] = @{$a}[0] = $sign;
    $self->{ov_flag} = 0;
}

sub div
{
    my ($self, $w) = @_;
    my $a = $self->{rA};
    my $x = $self->{rX};
    my $m = $self->{max_byte};
    my $M = $m*$m*$m*$m*$m;

    my $v  = word_to_uint($w,$m);

    if ($v==0) {
	$self->{ov_flag} = 1;
	return;
    }

    my $va = word_to_uint($a,$m);
    my $vx = word_to_uint($x,$m);
    my $V  = $va*$M+$vx;

    my $sign;
    my $sa = @{$a}[0];
    if ($sa eq @{$w}[0]) {
	$sign = '+';
    } else {
	$sign = '-';
    }
    
    int_to_word($V%$v, $x, $m);
    @{$x}[0] = $sa;
    if (int_to_word(int($V/$v), $a, $m)) {
	$self->{ov_flag} = 0;
    } else {
	$self->{ov_flag} = 1;
    }
    @{$a}[0] = $sign;
}

########################################################################
# Utilities
########################################################################

sub get_dev_name 
{
    my ($unit) = @_;
    if ($unit >= 0 && $unit <= 7) {
	return "Tape $unit";
    } elsif ($unit >= 8 && $unit <= 15) {
	return "Disk/Drum $unit";
    } elsif ($unit == 16) {
	return "Card reader";
    } elsif ($unit == 17) {
	return "Card punch";
    } elsif ($unit == 18) {
	return "Printer";
    } elsif ($unit == 19) {
	return "Typewriter and paper tape";
    } else {
	return "Null Device";
    }
}

sub fix_word
{
    my @tmp = @_;
    my $sign = shift @tmp;
    if ($sign eq '+' || $sign eq '-') {
	
    } else {
	unshift @tmp, $sign;
	$sign = '+';
    }
    while (@tmp != 5) {
	unshift @tmp, 0;
    }
    unshift @tmp, $sign;
    return @tmp;
}

sub neg_word
{
    my @tmp = @{$_[0]};
    if ($tmp[0] eq '-') {
	$tmp[0] = '+';
    } elsif ($tmp[0] eq '+') {
	$tmp[0] = '-';
    } else {
	unshift @tmp, '-';
    }
    return @tmp;
}

sub word_to_int
{
    my ($wref, $m) = @_;
    my $val = 0;
    
    $m = 64 if (!defined $m); 
    
    for my $i (1 .. 5) {
	$val = $val * $m + @{$wref}[$i];
    }
    if (@{$wref}[0] eq '+') {
	return $val;
    } else {
	return -$val;
    }
}

sub word_to_uint
{
    my ($wref, $m) = @_;
    my $val = 0;
    
    $m = 64 if (!defined $m); 
    
    for my $i (1 .. 5) {
	$val = $val * $m + @{$wref}[$i];
    }
    return $val;
}

# If overflow return 0;
# If ok, return 1;
sub int_to_word
{
    my ($val, $wref, $m) = @_;
    my $i = 5;

    $m = 64 if (!defined $m); 

    if ($val < 0) {
	@{$wref}[0] = '-';
	$val = -$val;
    } else {
	@{$wref}[0] = '+';
    }

    for (; $i > 0; $i--) {
	@{$wref}[$i] = $val % $m;
	$val = int($val/$m);
    }
    return $val==0;
}

sub word_to_string
{
    my $retstr = '';
    my $prefix = '';
    foreach (@_) {
	if ($_ eq '-') {
	    $prefix = '-';
	} elsif ($_ eq '+') {
	    $prefix = '+';
	} else {
	    $retstr .= ($_ < 10? ' 0' : ' ') . $_;
	}
    }
    return $prefix . $retstr;
}


my $debug_mode = 0;
sub debug 
{
    return if !$debug_mode;
    print "DEBUG: ";
    print $_ foreach @_;
    print "\n";
}

my $mix_charset = " ABCDEFGHI^JKLMNOPQR^^STUVWXYZ0123456789.,()+-*/=\$<>@;:'";

# Return a MIX char by its code.
# valid input: 0 .. 55
# If the input is not in the range above, an `undef' is returned.
sub mix_char 
{
    return undef if $_[0] < 0 || $_[0] >= length($mix_charset);
    return substr($mix_charset, $_[0], 1);
}

# Return code for a MIX char
# If not found, return -1.
# Note, char '^' is not a valid char in MIX charset.
sub mix_char_code 
{ 
    return -1 if $_[0] eq "^";
    return index($mix_charset, $_[0]); 
}

1;

__END__

    =head1 NAME

Hardware::Simulator::MIX - Knuth's famous virtual machine

=head1 SYNOPSIS
  
    use Hardware::Simulator::MIX;

    my $mix = new Hardware::Simulator::MIX;
    while (!$mix->is_halted()) {
        $mix->step();
    }

=head1 DESCRIPTION

This implementation includes the GO button and the default loader is the answer to
Exercise 1.3 #26.

For detailed architecture information, search MIX in wikipedia.

=head1 CONSTRUCTOR

    $mix = Hardware::Simulator::MIX->new(%options);

This method constructs a new C<Hardware::Simulator::MIX> object and returns it.
Key/value pair arguments may be provided to set up the initial state.
The following options correspond to attribute methods described below:

    KEY                     DEFAULT
    -----------             --------------------
    max_byte                64
    timeunit                5   (microseconds)

=head1 MACHINE STATE

=over 4

=item Registers

Accessing registers:

    $mix->{reg_name}

It is a reference to a MIX word.
Available registers are listed below:

    REGNAME                FORMAT
    -----------            -----------------------
    rA                     [?, ?, ?, ?, ?, ?]
    rX                     [?, ?, ?, ?, ?, ?]
    rI1                    [?, 0, 0, 0, ?, ?]
    rI1                    [?, 0, 0, 0, ?, ?]
    rI2                    [?, 0, 0, 0, ?, ?]
    rI3                    [?, 0, 0, 0, ?, ?]
    rI4                    [?, 0, 0, 0, ?, ?]
    rI5                    [?, 0, 0, 0, ?, ?]
    rI6                    [?, 0, 0, 0, ?, ?]
    rI6                    [?, 0, 0, 0, ?, ?]
    rJ                     [?, 0, 0, 0, ?, ?]
    pc                     Integer in 0..3999

Note: the names are case sensitive.

=item Memory

=item Flags

$mix->get_cmp_flag() returns an integer. If the returned value is negative, 
the flag is "L"; if the return value is positive, the flag is "G";
if the return value is 0, the flag is "E".

$mix->get_overflow() return 0 if there is no overflow. return 1 if overflow happen.

Flags may be updated after execute new instruction.

=item Status


$mix->get_current_time() returns the current mix running time in time units since the last reset.

=back

=head1 METHODS

=over 4

=item $mix->get_reg($reg_name)

=item $mix->is_halted()

=item $mix->reset()

=item $mix->read_mem($loc)

=item $mix->read_mem($loc, $l)

=item $mix->read_mem($loc, $l, $r)

Return a MIX word from memory. C<$loc> must be among 0 to 3999. 
If field spec C<$l> and C<$r> are missing, they are 0 and 5;
If C<$r> is missing, it is same as C<$l>.

=item $mix->step()

=item $mix->set_reg($reg_name, $wref)

=item $mix->write_mem($loc, $wref, $l, $r)

=back

=head1 AUTHOR

Chaoji Li<lichaoji@gmail.com>

Please feel free to send a email to me if you have any question.

=head1 SEE ALSO
 
The package also includes a mixasm.pl which assembles MIXAL programs. Usage:

    perl mixasm.pl <yourprogram>

This command will generate a .crd file which is a card deck to feed into the mixsim.pl.
Typical usage:

    perl mixsim.pl --cardreader=<yourprogram.crd>

Then type 'h' at the command line so you can see a list of commands. You can load a MIX program
into the machine and see it run.

=cut
