package Hardware::Simulator::MIX;

use strict;
use warnings;
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
	get_cmp_flag );

our $VERSION   = 0.05;

sub new 
{
	my $invocant = shift;
	my $class = ref($invocant) || $invocant;
	my $self = {
		@_ 
	};
	bless $self, $class;
	$self->{max_byte} = 64 if !exists $self->{max_byte};

	$self->reset();
	return $self; 
}

sub set_max_byte
{
	my $self = shift;
	$self->{max_byte} = shift;
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
	for (0 .. 3999) {
		push @{$self->{mem}}, ['+', 0, 0, 0, 0, 0];
	}
	
	$self->{in_cards}  = [] if !exists $self->{in_cards};



	$self->{out_cards} = [];
	$self->{printer}   = [];

	$self->{clk_count} = 0;
	$self->{pc}        = 0;
	$self->{next_pc}   = 0;
	$self->{ov_flag}   = 0;
	$self->{cmp_flag}  = 0;
	$self->{status}    = 0;
	$self->{message}   = 'running';
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

##
# memfunc: step
# description: Execute an instruction, update the machine state
##
sub step
{
	my $self = shift;

	my @regname = qw(rA rI1 rI2 rI3 rI4 rI5 rI6 rX);

	return if $self->{status} != 0;

	# Fetch instruction
	my $loc = $self->{pc} = $self->{next_pc};

	my @word = $self->read_mem($loc);
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
		my @tmp = $self->read_mem($m, $l, $r);
		$self->set_reg('rA', \@tmp);
	} elsif ($c == 15) { ## LDX
		my @tmp = $self->read_mem($m, $l, $r);
		$self->set_reg('rX', \@tmp);
	} elsif ($c >= 9 && $c <= 14) { ## LDi
		my @tmp = $self->read_mem($m, $l, $r);
		$self->set_reg('rI' . ($c-8), \@tmp);
	} elsif ($c == 16) { ## LDAN
		my @tmp = $self->read_mem($m, $l, $r);
		@tmp = neg_word(\@tmp);
		$self->set_reg('rA', \@tmp);
	} elsif ($c == 23) { ## LDXN
		my @tmp = $self->read_mem($m, $l, $r);
		@tmp = neg_word(\@tmp);
		$self->set_reg('rX', \@tmp);
	} elsif ($c >= 17 && $c <= 22) { ## LDiN
		my @tmp = $self->read_mem($m, $l, $r);
		@tmp = neg_word(\@tmp);
		$self->set_reg('rI' . ($c-16), \@tmp);
	} elsif ($c == 24) { ## STA
		$self->write_mem($m, $self->{rA}, $l, $r);
	} elsif (25 <= $c && $c <= 30) { ## STi
		my $ri = 'rI' . ($c-24);
		$self->write_mem($m, $self->{$ri}, $l, $r);
	} elsif ($c == 31) { ## STX
		$self->write_mem($m, $self->{rX}, $l, $r);
	} elsif ($c == 32) { ## STJ
		$self->write_mem($m, $self->{rJ}, $l, $r);
	} elsif ($c == 33) { ## STZ
		$self->write_mem($m, $self->{rZ}, $l, $r);
	} elsif ($c == 1) { ## ADD
		my @tmp = $self->read_mem($m, $l, $r);
		$self->add(\@tmp);
	} elsif ($c == 2) { ## SUB
		my @tmp = $self->read_mem($m, $l, $r);
		$self->minus(\@tmp);
	} elsif ($c == 3 && $f != 6) { ## MUL
		my @tmp = $self->read_mem($m, $l, $r);
		$self->mul(\@tmp);
	} elsif ($c == 4 && $f != 6) { ## DIV
		my @tmp = $self->read_mem($m, $l, $r);
		$self->div(\@tmp);
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
		my $tmp2 = $self->read_mem($m, $l, $r);
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
			my @w = $self->read_mem($m);
			$self->write_mem($dest, \@w);
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
	} elsif ($c == 36) {
		if ($f == 16) { ## CARD READER
		    $self->load_card($m);
		} else {
		    $self->{status} = 2;
		    $self->{message} = "input device(#$f) not supported at $loc";
		}
	} elsif ($c == 37) {
		if ($f == 17) { ## CARD Punch
		    $self->punch_card($m);
		} elsif ($f == 18)  { ## Printer
		    $self->print_line($m);
		} else {
		    $self->{status} = 2;
		    $self->{message} = "output device(#$f) not supported at $loc";
		}
	} elsif ($c == 35) {
		if ($f == 18) { ## Printer: set up new page
			$self->new_page($m);
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
}

sub load_card {
	my ($self, $loc) = @_;
	my $crds = $self->{in_cards};
	if (@{$crds}==0) {
		$self->{status} = 2;
		$self->{message} = "missing cards";
	} else {
		my $crd = shift @{$crds};
		if (length($crd)!=80) {
			$crd .= " " x (80-length($crd));
		}
		my @w = ('+');
		for (my $i = 0; $i < 80; $i++) {
			my $c = mix_char_code( substr($crd,$i,1) );
			if ($c == -1) {
			    $self->{status} = 2;
			    $self->{message} = "invalid card: '$crd'";
			} else {
			    push @w, $c;
			    if (@w == 6) {
			    	$self->write_mem($loc++, \@w);
				@w = ('+');
			    }
                        }
		}
	}
}

sub punch_card {
	my ($self, $loc) = @_;
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

	push @{$self->{out_cards}}, $crd;
}

sub print_line {
	my ($self, $loc) = @_;

	my $page = pop @{$self->{printer}};
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
	push @{$self->{printer}}, $page;
}

sub new_page {
	my ($self, $m) = @_;
	if ($m == 0) {
		push @{$self->{printer}}, "";
	} else {
		$self->{status} = 2;
		$self->{message} = "printer ioctrl error: M should be zero";
	}
}

sub print_all_regs {
	my ($self) = @_;

	print " rA: ";
	$self->print_reg('rA');
	print "  rX: ";
	$self->print_reg('rX');
	print "\nrI1: ";
	$self->print_reg('rI1');
	print "  rI2: ";
	$self->print_reg('rI2');
	print "\nrI3: ";
	$self->print_reg('rI3');
	print "  rI4: ";
	$self->print_reg('rI4');
	print "\nrI5: ";
	$self->print_reg('rI5');
	print "  rI6: ";
	$self->print_reg('rI6');
	print "\n rJ: ";
	$self->print_reg('rJ');
	print "\nPC = ", $self->{pc}, "  NEXT = ", $self->{next_pc};
	print "  ", $self->{ov_flag}?'OV':'NO';
	if ($self->{cmp_flag} > 0) {
		print " GT",
	} elsif ($self->{cmp_flag} < 0) {
		print " LT";
	} else {
		print " EQ";
	}
	if ($self->{status} == 0) {
		print " OK";
	} elsif ($self->{status} == 1) {
		print " HALT";
	} else {
		print " ERROR";
	}
	print "\n";
}

sub print_reg {
	my ($self, $reg) = @_;
	my @word = $self->get_reg($reg);
	print word_to_string(@word);
}

sub clear_status {
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

sub is_halted {
	my $self = shift;
	return 0 if $self->{status} == 0;
	return 1;
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

sub get_dev_name {
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

Number system.
Memory word.
Field specification.
Architecture.
char set.

=head1 CONSTRUCTOR

    $mix = Hardware::Simulator::MIX->new(%options);

This method constructs a new C<Hardware::Simulator::MIX> object and returns it.
Key/value pair arguments may be provided to set up the initial state.
The following options correspond to attribute methods described below:

    KEY                     DEFAULT
    -----------             --------------------
    max_byte                64

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

=item Status

=back

=head1 METHODS

=over 4

=item $mix->is_halted()

=item $mix->reset()

=item $mix->step()


=item $mix->read_mem($loc)

=item $mix->read_mem($loc, $l)

=item $mix->read_mem($loc, $l, $r)

Return a MIX word from memory. C<$loc> must be among 0 to 3999. 
If field spec C<$l> and C<$r> are missing, they are 0 and 5;
If C<$r> is missing, it is same as C<$l>.

=item $mix->write_mem($loc, $wref, $l, $r)

=item $mix->set_reg($reg_name, $wref)

=item $mix->get_reg($reg_name)

=back

=head1 AUTHOR

Chaoji Li<lichaoji@ict.ac.cn>

Please feel free to send a email to me if you have any question.

=head1 BUGS


=head1 SEE ALSO
 
The package also includes a mixasm.pl which assembles MIXAL programs. Usage:

    perl mixasm.pl <srcfile.mixal>

Again, there is a mixsim.pl which is a command line interface to control MIX machine. Usage:

    perl mixsim.pl

Then type 'h' at the command line so you can see a list of commands. You can load a MIX program
into the machine and see it run.

=head1 COPYRIGHT

=cut
