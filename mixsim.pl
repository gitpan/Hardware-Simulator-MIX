use lib "./lib";
use Hardware::Simulator::MIX;
use Data::Dumper;
use Getopt::Long;

my $opt_byte_size = 64;
my $opt_batch_mode = 0;
my $opt_interactive_mode = 0;
my $opt_myloader = 0;
my $opt_verbose;
my $opt_help = 0;

my $opt_card_reader = "";
my $opt_card_punch = "";
my $opt_printer = "";
my $opt_tape0 = "";
my $opt_tape1 = "";
my $opt_tape2 = "";
my $opt_tape3 = "";
my $opt_tape4 = "";
my $opt_tape5 = "";
my $opt_tape6 = "";
my $opt_tape7 = "";
my $opt_disk0 = "";
my $opt_disk1 = "";
my $opt_disk2 = "";
my $opt_disk3 = "";
my $opt_disk4 = "";
my $opt_disk5 = "";
my $opt_disk6 = "";
my $opt_disk7 = "";


GetOptions ("bytesize=i"   => \$opt_byte_size,
            "cardreader=s" => \$opt_card_reader,
            "cardpunch=s"  => \$opt_card_punch,
            "printer=s"    => \$opt_printer,
            "tape0=s"      => \$opt_tape0,
            "tape1=s"      => \$opt_tape1,
            "tape2=s"      => \$opt_tape2,
            "tape3=s"      => \$opt_tape3,
            "tape4=s"      => \$opt_tape4,
            "tape5=s"      => \$opt_tape5,
            "tape6=s"      => \$opt_tape6,
            "tape7=s"      => \$opt_tape7,
            "disk0=s"      => \$opt_disk0,
            "disk1=s"      => \$opt_disk1,
            "disk2=s"      => \$opt_disk2,
            "disk3=s"      => \$opt_disk3,
            "disk4=s"      => \$opt_disk4,
            "disk5=s"      => \$opt_disk5,
            "disk6=s"      => \$opt_disk6,
            "disk7=s"      => \$opt_disk7,
            "batch"        => \$opt_batch_mode,
            "interactive"  => \$opt_interactive_mode,
            "help"         => \$opt_help,
            "myloader"     => \$opt_myloader,
            "verbose"      => \$opt_verbose);

usage() if $opt_help;

my @default_loader = (
		      " O O6 Y O6    I   B= D O4 Z IQ Z I3 Z EN    E   EU 0BB= H IU   EJ  CA. ACB=   EU",
		      " 1A-H V A=  CEU 0AEH 1AEN    E  CLU  ABG H IH A A= J B. A  9                    ");

my $mix = Hardware::Simulator::MIX->new(max_byte => $opt_byte_size);
install_devices();

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
    flush_devices();
    my $time = $mix->get_current_time();
    my $realtime = $time*$mix->{timeunit}/1000000;
    print "MIX TIME: ", $time, ", ~ ", $realtime, " seconds\n";
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
print "MIX TIME: ", $mix->get_current_time(), "\n";
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

######################################################################
# show_page(optional $page_num)
#     print the newest page if $page_num is not specified.
#
sub show_page
{
    my $page_num = shift;
    my $pages = $mix->get_device_buffer(18);
    my $n = @{$pages};
    return if $n == 0;
    $page_num = $n if !defined $page_num || $page_num > $n;
    
    my $page = @{$pages}[$page_num-1];
    print "Page $page_num of $n\n";
    print $page;   
}


sub step
{
    $mix->step();
    if ($mix->{status} != 0) {
        print $mix->{message}, "\n";
    }
    $mix->print_all_regs();
    print "    Next inst: ", join(" ", @{@{$mix->{mem}}[$mix->{next_pc}]}), "\n";
    print " Current time: ", $mix->get_current_time(), "\n";
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
    print " Current time: ", $mix->get_current_time(), "\n";
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
    print STDERR "LOAD CARD: ERROR MEMORY LOCATION $loc\n" if !defined $loc || $loc < 0 || $loc > 3999;
    $mix->load_card($loc);
}

sub usage {
    print STDERR "perl mixsim.pl [options]\n";
    print STDERR "   --bytesize=<number>\n";
    print STDERR "   --cardreader=<file>\n";
    print STDERR "   --cardpunch=<file>\n";
    print STDERR "   --printer=<file>\n";
    print STDERR "   --tape[0-7]=<file>\n";
    print STDERR "   --disk[0-7]=<file>\n";
    print STDERR "   --batch\n";
    print STDERR "   --help\n";
    print STDERR "   --myloader=<cardfile>\n";
    print STDERR "   --verbose\n";
    exit(1);
}

sub install_devices {
    my @cards = @default_loader;
    my @opt_tape = ($opt_tape0, $opt_tape1, $opt_tape2, $opt_tape3, 
		    $opt_tape4, $opt_tape5, $opt_tape6, $opt_tape7);
    my @opt_disk = ($opt_disk0, $opt_disk1, $opt_disk2, $opt_disk3,
		    $opt_disk4, $opt_disk5, $opt_disk6, $opt_disk7);
    if (open CRDFILE, "<$opt_card_reader") {
	while (<CRDFILE>) {
	    chop;
	    push @cards, $_ if length($_) > 0;
	}
	close CRDFILE;
    }

    $mix->add_device(16,\@cards);
    $mix->add_device(18);
    $mix->add_device(17);

    my $u = 0;

    foreach( @opt_tape ) {
	my @words = ();
	if ($_ ne "" && open TAPEFILE, "<$_") {
	    while(<TAPEFILE>) {
		chop;
		next if m/^\s*$/;
		my @tmp = split;
		push @words, \@tmp;
	    }      
	    close TAPEFILE;
	}
	$mix->add_device($u++, \@words);
    }

    foreach ( @opt_disk) {
	my @words = ();
	if ($_ ne "" && open DISKFILE, "<$_") {
	    while(<DISKFILE>) {
		chop;
		next if m/^\s*$/;
		my @tmp = split;
		push @words, \@tmp;
	    }
	    close DISKFILE;
	}
	$mix->add_device($u++, \@words);
    }
}

sub flush_devices {
    my @opt_tape = ($opt_tape0, $opt_tape1, $opt_tape2, $opt_tape3, 
		    $opt_tape4, $opt_tape5, $opt_tape6, $opt_tape7);
    my @opt_disk = ($opt_disk0, $opt_disk1, $opt_disk2, $opt_disk3,
		    $opt_disk4, $opt_disk5, $opt_disk6, $opt_disk7);
    my $u = 0;
    foreach (@opt_tape) {
	if ($_ ne "") {
	    if (open DISKFILE, ">$_") {
		my $buf = $mix->get_device_buffer($u);
		foreach (@{$buf}) {
		    my @w = @{$_};
		    printf DISKFILE "%s %2d %2d %2d %2d %2d\n", 
		    $w[0], $w[1], $w[2],$w[3],$w[4],$w[5];
		}
		close DISKFILE;
	    } else {
		print STDERR "MIX: can not flush unit %u to file $_\n";
	    }	
	}
	$u++;
    }
    foreach (@opt_disk) {
	if ($_ ne "") {
	    if (open DISKFILE, ">$_") {
		my $buf = $mix->get_device_buffer($u);
		foreach (@{$buf}) {
		    my @w = @{$_};
		    printf DISKFILE "%s %2d %2d %2d %2d %2d\n", 
		    $w[0], $w[1], $w[2],$w[3],$w[4],$w[5];
		}
		close DISKFILE;
	    } else {
		print STDERR "MIX: can not flush unit %u to file $_\n";
	    }
	}
	$u++;
    }

    my $buf = $mix->get_device_buffer(17);
    if ($opt_card_punch ne "" && open CRDFILE, ">$opt_card_punch") {
	foreach (@{$buf}) {
	    print CRDFILE $_, "\n";
	}
	close CRDFILE;
    } elsif (@{$buf} > 0) {	
	print "[CARD PUNCH]\n";
	foreach (@{$buf}) {
	    print $_, "\n";
	}
    }

    $buf = $mix->get_device_buffer(18);
    if (@{$buf} > 0) {
	my $tot = @{$buf};
	my $pg = 1;
	if ($opt_printer ne "" && open PRTFILE, ">$opt_printer") {	
	    foreach (@{$buf}) {
		print PRTFILE "[PAGE $pg/$tot]\n";
		print PRTFILE $_;
		$pg++;
	    }
	    close PRTFILE;
	} else {
	    foreach (@{$buf}) {
		print "[PRINTER $pg/$tot]\n";
		print $_;
		$pg++;
	    }	    
	}
    }
}
