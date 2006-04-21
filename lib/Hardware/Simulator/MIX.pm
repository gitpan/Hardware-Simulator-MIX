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
	set_word
	get_overflow 
	get_word
	get_pc
	get_cmp_flag );

our $VERSION   = 0.02;

my $max_byte = 64;

sub new 
{
	my $invocant = shift;
	my $class = ref($invocant) || $invocant;
	my $self = {
		@_ 
	};
	bless $self, $class;
	$self->reset();
	return $self; 
}

sub reset 
{
	my $self = shift;

	$self->{rA} = ['+', 0, 0, 0, 0, 0];
	$self->{rX} = ['+', 0, 0, 0, 0, 0];
	$self->{rJ} = ['+', 0, 0, 0, 0, 0];
	$self->{rZ} = ['+', 0, 0, 0, 0, 0];

	@{$self->{rI1}} = ('+', 0, 0, 0, 0, 0);
	@{$self->{rI2}} = ('+', 0, 0, 0, 0, 0);
	@{$self->{rI3}} = ('+', 0, 0, 0, 0, 0);
	@{$self->{rI4}} = ('+', 0, 0, 0, 0, 0);
	@{$self->{rI5}} = ('+', 0, 0, 0, 0, 0);
	@{$self->{rI6}} = ('+', 0, 0, 0, 0, 0);

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

sub step
{
	my $self = shift;

	return if $self->{status} != 0;

	# Fetch instruction
	my $loc = $self->{pc} = $self->{pc_next};
	my @word = $self->get_word($loc);
	return if $self->{status} != 0;

	my $c = $word[5];
	my $f = $word[4];
	my $r = $f%8;
	my $l = int($f/8);
	my $i = $word[3];
	my $a = $word[1] * $max_byte + $word[2];
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
		my @tmp = $self->get_word($m, $l, $r);
		$self->set_reg('rA', \@tmp);
	} elsif ($c == 15) { ## LDX
		my @tmp = $self->get_word($m, $l, $r);
		$self->set_reg('rX', \@tmp);
	} elsif ($c >= 9 && $c <= 14) { ## LDi
		my @tmp = $self->get_word($m, $l, $r);
		$self->set_reg('rI' . ($c-8), \@tmp);
	} elsif ($c == 16) { ## LDAN
		my @tmp = $self->get_word($m, $l, $r);
		@tmp = neg_word(\@tmp);
		$self->set_reg('rA', \@tmp);
	} elsif ($c == 23) { ## LDXN
		my @tmp = $self->get_word($m, $l, $r);
		@tmp = neg_word(\@tmp);
		$self->set_reg('rX', \@tmp);
	} elsif ($c >= 17 && $c <= 22) { ## LDiN
		my @tmp = $self->get_word($m, $l, $r);
		@tmp = neg_word(\@tmp);
		$self->set_reg('rI' . ($c-16), \@tmp);
	} 
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
	my @retval = ();

	push @retval, @{$self->{$reg}}[0];
	my $l = ($reg =~ m/r(I|J)/)?4:1;
	while ($l <= 5) {
		push @retval, @{$self->{$reg}}[$l];
		++$l;
	}
	my $value = get_value(@retval);
	return wantarray? @retval:$value;
}

sub set_reg
{
	my ($self, $reg, $wref) = @_;

	my @word = @{$wref};
	if (!exists $self->{$reg})
	{
		$self->{status} = 2;
		$self->{message} = "accessing non-existed reg: $reg";
		return;
	}

	my $sign = '+';
	if (@{$wref}[0] eq '+' || @{$wref}[0] eq '-') 
	{
		$sign = shift @{$wref};
	}
	@{$self->{$reg}}[0] = $sign;

	my $l = ($reg =~ m/r(I|J)/)?4:1;
	my $r = 5;
	while ($r >= $l && @word != 0)
	{
		@{$self->{$reg}}[$r] = pop @word;
		--$r;
	}
}

sub is_halted {
	my $self = shift;
	return 0 if $self->{status} == 0;
	return 1;
}

sub get_word
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
	my $value = get_value(@retval);
	debug(" ($l:$r) is ", word_to_string(@retval), ", value is $value");
	return wantarray? @retval : $value;
}

sub set_word
{
	my ($self,$loc,$wref, $l, $r) = @_;

	if ($loc < 0 || $loc > 3999) {
		$self->{status} = 2;
		$self->{message} = "access invalid memory location: $loc";
		return;
	}

	my @word = @{$wref};
	debug("set word ", word_to_string(@word) );

	if (!defined $l) {
		$l = 0;
		$r = 5;
	} elsif (!defined $r) {
		$r = $l;
	}
	my $dest = @{$self->{mem}}[$loc];
	debug("   to loc#$loc ", word_to_string(@{$dest}), "($l:$r)");
	for (my $i = $r; $i >= $l;  $i--) {
		@{$dest}[$i] = pop @word;
	}
	debug("  => ", word_to_string(@{$dest}));
}

########################################################################
# Utilities
########################################################################

sub word_to_string
{
	my $retstr;
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


sub get_value
{
	my $retval = 0;
	my $pos = -1;
	foreach (@_) {
		if ($_ eq '-') {
			$pos = 0;
		} elsif ($_ eq '+') {
			$pos = 1;
		} else {
			$retval += $retval * $max_byte + $_;
		}
	}
	return $pos!=0 ? $retval : 0 - $retval;
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

# Return a MIX char by its code
sub mix_char 
{
	return substr($mix_charset, $_[0], 1);
}

# Return code for a MIX char
sub mix_char_code 
{ 
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

Is under development.


=head1 AUTHOR

Chaoji Li<lichaoji@ict.ac.cn>

=head1 BUGS


=head1 SEE ALSO
 

=head1 COPYRIGHT

=cut
