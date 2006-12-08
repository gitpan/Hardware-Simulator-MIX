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

our $VERSION   = 0.04;

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

	$self->{clk_count} = 0;
	$self->{pc}        = 0;
	$self->{pc_next}   = 0;
	$self->{ov_flag}   = 0;
	$self->{cmp_flag}  = 0;
	$self->{status}    = 0;
	$self->{message}   = 'running';
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

	return if $self->{status} != 0;

	# Fetch instruction
	my $loc = $self->{pc} = $self->{pc_next};
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
	
	$self->{pc_next} = $self->{pc} + 1;
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
	} else {
		$self->{status} = 2;
		$self->{message} = "Unknown instruction: loc $loc:" . word_to_string(@word);
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
	print "\nPC = ", $self->{pc}, "  NEXT = ", $self->{pc_next};
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
	my ($self, $reg) = @_;

	if (!exists $self->{$reg}) {
		$self->{status} = 2;
		$self->{message} = "accessing non-existed reg: $reg";
		return;
	}
	my $r = $self->{$reg};
	my $value = word_to_int($r, $self->{max_byte});
	return wantarray? @{$r}:$value;
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
	debug("get word from loc#$loc ", word_to_string(@word));
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
