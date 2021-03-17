use warnings;
use strict;
use ExtUtils::MakeMaker;
use Getopt::Long qw(GetOptions);

my $interp;
my $tk_patchLevel;

sub _die ($) {
    # CPAN smokers report FAIL if Makefile.PL dies, it should exit with status 0
    my $err = shift;
    warn $err;
    # Cleanly exit Tcl/Tk if it was loaded
    $interp->Eval('destroy .') if $tk_patchLevel;
    exit 0;
}

# Allow bypassing with --no-test-for-tk
my $test_for_tk = 1;

GetOptions(
    'help!',   \ my $help,
    'test-for-tk!', \$test_for_tk,
) or usage();
usage() if $help;
sub usage {
    _die <<'EOT';
Usage: perl Makefile.PL [--no-test-for-tk] [<makemaker opts>...]
EOT
}

# Unless --no-test-for-tk was specified, check the Tcl/Tk installation
# using Tcl.pm (which is how Tkx will use Tcl/Tk; better than
# looking/asking for a tclsh command not necessarily from the same
# Tcl/Tk installation used by Tcl.pm)
if ($test_for_tk) {
    # Load Tcl via Tcl.pm
    eval {
        require Tcl;
        1;
    } or do {
        my $error = $@ || 'Unknown error';
        _die <<"EOS"
Error: could not load Tcl.pm for Tcl/Tk check (use --no-test-for-tk to skip), reason: $error
EOS
    };
    $interp = new Tcl;
    $interp->Init;
    print STDERR "Tcl.pm $Tcl::VERSION\n";
    printf STDERR "Tcl %s\n", $interp->GetVar('tcl_patchLevel');

    # Check for Tcl/Tk
    eval {
        $tk_patchLevel = $interp->Eval('package require Tk');
        1;
    } or do {
        my $error = $@ || 'Unknown error';
        _die <<"EOS";
Error: could not load Tcl/Tk (use --no-test-for-tk to skip), reason: $error
EOS
    };
    unless ($interp->Eval('package vsatisfies $tk_version 8.4')) {
        _die <<"EOS";
Error: Tcl/Tk $tk_patchLevel detected; Tcl/Tk 8.4 or later is required
EOS
    }
    printf STDERR "Tcl/Tk %s\n", $interp->GetVar('tk_patchLevel');

    # Cleanly exit Tcl/Tk if it was loaded
    $interp->Eval('destroy .') if $tk_patchLevel;
}

WriteMakefile(
    NAME => "Tkx",
    VERSION_FROM => 'lib/Tkx.pm',
    ABSTRACT_FROM => 'lib/Tkx.pm',
    PREREQ_PM => {
        Tcl => '1.00',
    },
    AUTHOR => 'Gisle Aas <gisle@activestate.com>',
    EXE_FILES => [qw(tkx-ed tkx-prove)],
    LICENSE => 'perl_5',
    MIN_PERL_VERSION => '5.008',
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            repository => {
                type => 'git',
                web => 'https://github.com/chrstphrchvz/tkx',
                url => 'https://github.com/chrstphrchvz/tkx.git',
            },
            bugtracker => {
                web => 'https://github.com/chrstphrchvz/tkx/issues',
            },
            MailingList => 'mailto:tcltk@perl.org',
        },
    },
);

BEGIN {
    # compatibility with older versions of MakeMaker
    my $developer = -f ".gitignore";
    my %mm_req = (
        LICENCE => 6.31,
        META_MERGE => 6.45,
        META_ADD => 6.45,
        MIN_PERL_VERSION => 6.48,
    );
    undef(*WriteMakefile);
    *WriteMakefile = sub {
        my %arg = @_;
        for (keys %mm_req) {
            unless (eval { ExtUtils::MakeMaker->VERSION($mm_req{$_}) }) {
                warn "$_ $@" if $developer;
                delete $arg{$_};
            }
        }
        ExtUtils::MakeMaker::WriteMakefile(%arg);
    };
}
