# take a mixal file as input, and run!
use File::Basename;

#die "Invalid argument" if ($#ARGV != 1);
my $srcfile = shift @ARGV;
my ($base, $path, $type) = fileparse($srcfile, qr{\..*});

my @dev = qw(tape0 tape1 tape2 tape3 tape4 tape5 tape6 tape7
	     disk0 disk1 disk2 disk3 disk4 disk5 disk6 disk7);

my $devstr = "";
foreach (@dev)
  {
    $devstr .= "--$_=$_ " if -f;
  }

if (system("perl mixasm.pl $srcfile") == 0)
  {
    
    system("perl mixsim.pl $devstr --batch $base.crd");
  }
