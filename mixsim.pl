use lib "./lib";
use Hardware::Simulator::MIX;
use Data::Dumper;


my $mix      = new Hardware::Simulator::MIX;
my $cmdtable = init_cmdtable();
my $memloc   = 0;


########################################################################
# MAIN ROUTINE
########################################################################

$mix->reset();

print "\n    M I X   S i m u l a t o r\n\n";
print "Type 'h' for help messages.\n";

while (1) 
{
	print "MIX> ";
	my $cmdline = <STDIN>;
	chop($cmdline);
	$cmdline =~ s/^\s+//;
	my @args = split /\s+/, $cmdline;
	next if @args == 0;
	my $cmd = shift @args;
	my $cb = $cmdtable->{$cmd}->{cb};
	next if !defined $cb;
	&$cb(@args);
}
exit(0);

########################################################################

sub init_cmdtable
{
$cmdtable = {
	l => {  help => "Load file into memory",
		cb => sub {load_file(@_)} },
	e => {  help => "Edit memory",
		cb => sub {edit_memory(@_)} },
	d => {  help => "Display memory",
		cb => sub { display_memory(@_) } },
	h => {  help => "Display help messages",
		cb => sub { help() } },
	q => {  help => "Quit",
	        cb => sub { exit(0) } },
	r => {  help => "Display registers",
		cb => sub { $mix->print_all_regs() } }
	};
}

sub help
{
	for (sort keys %{$cmdtable}) {
		print $_, "\t", $cmdtable->{$_}->{help}, "\n";
	}
}

sub display_memory
{
	my ($loc) = @_;
	$memloc = $loc if defined $loc;
	for ( $memloc .. $memloc+9 ) {
		next if $_ < 0;
		last if $_ > 3999;
		my @w = $mix->read_mem($_);
		printf "%04d: %s  %2d %2d %2d %2d %2d    ",
			$_, $w[0], $w[1], $w[2], $w[3], $w[4], $w[5];
		for (1 .. 5) {
			my $ch = mix_char($w[$_]);
			print $ch if defined $ch;
			print '^' if!defined $ch;
		}
		print "\n";
	}
	$memloc += 10 if $memloc+10 < 4000;
}

sub edit_memory
{
	my ($loc) = @_;
	return if !defined $loc || $loc < 0;
	while ($loc < 4000) {
		printf "%04d: ", $loc;
		my $w = <STDIN>;
		chop($w);
		last if $w =~ /^\s*$/;
		$w =~ s/^\s+//;
		my @w = split /\s+/, $w;
		$mix->write_mem($loc, \@w);
		$loc++;
	}
}

sub load_file
{
	my ($srcfile) = @_;
	if (@_ == 0) {
		print "l <dumpfile>\n";
		return;
	}
	if (! open FILE, "<$srcfile") {
		print "LOAD FILE FAILED\n";	
		return;
	}
	my $ln = 0;
	while (<FILE>) {
		$ln++;
		chop;
		next if m/^\s*$/;
		s/^\s+//;
		s/:/ /;
		my ($loc, @w) = split /\s+/;
		$mix->write_mem($loc, \@w);
	}
	close FILE;	
	print "LOAD FILE OK\n";
}
