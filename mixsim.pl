use lib "./lib";
use Hardware::Simulator::MIX;
use Data::Dumper;
use Getopt::Long;

my $opt_crdfile   = "";
my $opt_byte_size = 64;
my $opt_batch_mode = 0;
my $opt_myloader = 0;
my $opt_verbose;

GetOptions ("bytesize=i"   => \$opt_byte_size,
            "incards=s" => \$opt_crdfile, 
	    "batch"        => \$opt_batch_mode,
	    "myloader"     => \$opt_myloader,
            "verbose"      => \$opt_verbose);

my @cards = ();

my $ld1 = " O O6 Y O6    I   B= D O4 Z IQ Z I3 Z EN    E   EU 0BB= H IU   EJ  CA. ACB=   EU";
my $ld2 = " 1A-H V A=  CEU 0AEH 1AEN    E  CLU  ABG H IH A A= J B. A  9                    ";

if (!$opt_myloader) {
	unshift @cards, $ld2;
	unshift @cards, $ld1;
}

if (open CRDFILE, "<$opt_crdfile") {
	while (<CRDFILE>) {
		chop;
		push @cards, $_ if length($_) > 0;
	}
	close CRDFILE;
}

my $mix = Hardware::Simulator::MIX->new (
		max_byte => $opt_byte_size,
		in_cards => \@cards
	);


########################################################################
# Batch Mode
########################################################################

if ($opt_batch_mode) {
	$mix->reset();
	$mix->go();
	if ($mix->{status} == 2) {
		print "MIX ERROR: " . $mix->{message} . "\n";
		print "PC = " . $mix->{pc} . "\n";
		print join(" ", $mix->read_mem($mix->{pc}));
	} 
	my @outcards = @{$mix->{out_cards}};
	if (@outcards > 0) {
		print "== OUT CARDS ==\n";
		foreach (@outcards) {
			print $_, "\n";
		}
	}
	my @pages = @{$mix->{printer}};
	my $n = @pages;
	for (my $i = 0; $i < $n; $i++) {
		print "== PAGE " . ($i+1) . " OF $n ==\n";
		print $pages[$i];
	}
	exit;
}

########################################################################
# Interactive Mode
########################################################################

my $cmdtable = init_cmdtable();
my $memloc   = 0;
$mix->reset();

print "\n    M I X   S i m u l a t o r\n\n";
print "Type 'h' for help messages.\n";

$mix->load_card(0);
if ($mix->{status}==2) {
    print "\nLoader missing\n";
}

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
        prt => {  help => "prt => Show current page, prt n => show page n",
                cb => sub { show_page(@_) } },
	l => {  help => "Load card",
		cb => sub {load_card(@_)} },
        s => {  help => "Step",
                cb => sub {step()} },
        g => {  help => "Go to location",
                cb => sub { run_until(@_)}},
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

sub show_page
{
    my ($page_num) = @_;
    my $pages = $mix->{printer};
    my $n = @{$pages};
    if ($n>0) {
        if (!defined $page_num) {
            $page_num = $n;
        }
        if ($page_num > $n) {
            print "Error: no such page\n";
        } else {
            print "Page $page_num of $n\n";
            print @{$pages}[$page_num-1]; 
        }
    }
}


sub step
{
    $mix->step();
    if ($mix->{status} != 0) {
        print $mix->{message}, "\n";
    }
    $mix->print_all_regs();
    print "    Next inst: ", join(" ", @{@{$mix->{mem}}[$mix->{next_pc}]}), "\n";
}

sub run_until
{
    my ($loc) = @_;
    if ($mix->{status} != 0) {
        print $mix->{message}, "\n";
        return;
    }
    $mix->step();
    while ($mix->{next_pc} != $loc && $mix->{status} == 0) {
        $mix->step();
    }
    if ($mix->{status} != 0) {
        print $mix->{message}, "\n";
    }
    $mix->print_all_regs();
    print "Previous inst: ", join(" ", @{@{$mix->{mem}}[$mix->{pc}]}), "\n";
    print "    Next inst: ", join(" ", @{@{$mix->{mem}}[$mix->{next_pc}]}), "\n";
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

sub load_card
{
	my ($loc) = @_;
        $mix->load_card($loc);
}
