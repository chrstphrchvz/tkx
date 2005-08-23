package Tkx;

use strict;
our $VERSION = '1.00';

{
    # predeclare
    package Tkx::widget;
    package Tkx::i;
}

package_require("Tk");

our $TRACE;
our $TRACE_MAX_STRING;
our $TRACE_COUNT;
our $TRACE_TIME;
our $TRACE_CALLER;

$TRACE = $ENV{PERL_TKX_TRACE} unless defined $TRACE;
$TRACE_MAX_STRING = 64 unless defined $TRACE_MAX_STRING;
$TRACE_COUNT = 1 unless defined $TRACE_COUNT;
$TRACE_TIME = 1 unless defined $TRACE_TIME;
$TRACE_CALLER = 1 unless defined $TRACE_CALLER;


sub import {
    my($class, @subs) = @_;
    my $pkg = caller;
    for (@subs) {
	s/^&//;
	if (/^[a-zA-Z]\w*/ && $_ ne "import") {
	    no strict 'refs';
	    *{"$pkg\::$_"} = \&$_;
	}
	else {
	    die qq("$_" is not exported by the $class module);
	}
    }
}

sub AUTOLOAD {
    our $AUTOLOAD;
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::')+2);
    return scalar(Tkx::i::call(Tkx::i::expand_name($method), @_));
}

sub MainLoop () {
    while (eval { local $TRACE; Tkx::i::call("winfo", "exists", ".") }) {
	Tkx::i::DoOneEvent(0);
    }
}

sub SplitList ($) {
    my $list = shift;
    unless (wantarray) {
	require Carp;
	Carp::croak("Tkx::SplitList needs list context");
    }
    return @$list if ref($list) eq "ARRAY" || ref($list) eq "Tcl::List";
    return Tkx::i::call("concat", $list);
}

*Ev = \&Tcl::Ev;

package Tkx::widget;

use overload '""' => sub { ${$_[0]} },
             fallback => 1;

my %data;
my %class;
my %mega;

sub new {
    my $class = shift;
    my $name = shift;
    return bless \$name, $class{$name} || $class;
}

sub _data {
    my $self = shift;
    return $data{$$self} ||= {};
}

sub _kid {
    my($self, $name) = @_;
    substr($name, 0, 0) = $$self eq "." ? "." : "$$self.";
    return $self->_nclass->new($name);
}

sub _parent {
    my $self = shift;
    my $name = $$self;
    return undef if $name eq ".";
    substr($name, rindex($name, ".")) = "";
    $name = "." unless length($name);
    return $self->_nclass->new($name);
}

sub _class {
    my $self = shift;
    my $old = ref($self);
    if (@_) {
	my $class = shift;
	$class{$$self} = $class;
	bless $self, $class;
    }
    $old;
}

sub _Mega {
    my $class = shift;
    my $widget = shift;
    my $impclass = shift || caller;
    $mega{$widget} = $impclass;
}

sub _nclass {
    __PACKAGE__;
}

sub _mpath {
    my $self = shift;
    $$self;
}

sub AUTOLOAD {
    my $self = shift;

    our $AUTOLOAD;
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::')+2);
    my $prefix = substr($method, 0, 2);

    if ($prefix eq "c_") {
	my $widget = Tkx::i::expand_name(substr($method, 2));
	my $name;
	for (my $i = 0; $i < @_; $i += 2) {
	    if ($_[$i] eq "-name") {
		(undef, $name) = splice(@_, $i, 2);
		substr($name, 0, 0) = ($$self eq "." ? "." : "$$self.")
		    if index($name, ".") == -1;
		last;
	    }
	}
	$name ||= Tkx::i::wname($widget, $$self);
	if (my $mega = $mega{$widget}) {
	    return $mega->_Populate($widget, $name, @_);
	}
	return $self->_nclass->new(scalar(Tkx::i::call($widget, $name, @_)));
    }

    if ($prefix eq "g_") {
        return scalar(Tkx::i::call(Tkx::i::expand_name(substr($method, 2)), $$self, @_));
    }

    if ($prefix eq "m_") {
	my @i = Tkx::i::expand_name(substr($method, 2));
	return scalar(Tkx::i::call($self->_mpath($i[0]), @i, @_));
    }
    elsif (index($prefix, "_") != -1) {
	require Carp;
	Carp::croak("method '$method' reserved by Tkx");
    }

    $method = "m_$method";
    return $self->$method(@_);
}

sub DESTROY {}  # avoid AUTOLOADing it


package Tkx::widget::_destroy;

sub new {
    my($class, @paths) = @_;
    bless \@paths, $class;
}

sub DESTROY {
    my $self = shift;
    for my $path (@$self) {
	if ($path eq ".") {
	    %data = ();
	    return;
	}

	my $path_re = qr/^\Q$path\E(?:\.|\z)/;
        for my $hash (\%data, \%class) {
	    for my $key (keys %$hash) {
		next unless $key =~ $path_re;
		delete $hash->{$key};
	    }
	}
    }
}

package Tkx::i;

use Tcl;
$Tcl::STACK_TRACE = 0;

my $interp;
my $trace_count = 0;
my $trace_start_time = 0;

BEGIN {
    $interp = Tcl->new;
    $interp->Init;
}

sub expand_name {
    my(@f) = (shift);
    @f = split(/(?<!_)_(?!_)/, $f[0]) if wantarray;
    for (@f) {
	s/(?<!_)__(?!_)/::/g;
	s/(?<!_)___(?!_)/_/g;
    }
    wantarray ? @f : $f[0];
}

sub wname {
    my($class, $parent) = @_;
    my $name = lc($class);
    $name =~ s/.*:://;
    substr($name, 1) = "";
    my @kids = call("winfo", "children", $parent);
    substr($name, 0, 0) = ($parent eq "." ? "." : "$parent.");
    if (grep $_ eq $name, @kids) {
	my %kids = map { $_ => 1 } @kids;
	my $count = 2;
	$count++ while $kids{"$name$count"};
	$name .= $count;
    }
    $name;
}

sub call {
    if ($Tkx::TRACE) {
	my @prefix = "Tkx";
	if ($Tkx::TRACE_COUNT) {
	    push(@prefix, ++$trace_count);
	}
	if ($Tkx::TRACE_TIME) {
	    my $ts;
	    unless ($trace_start_time) {
		if (eval { require Time::HiRes }) {
		    $trace_start_time = Time::HiRes::time();
		}
		else {
		    $trace_start_time = time;
		}
	    }
	    if (defined &Time::HiRes::time) {
		$ts = sprintf "%.1fs", Time::HiRes::time() - $trace_start_time;
	    }
	    else {
		$ts = time - $trace_start_time;
		$ts .= "s";
	    }
	    push(@prefix, $ts);
	}
	if ($Tkx::TRACE_CALLER) {
	    my $i = 0;
	    while (my($pkg, $file, $line) = caller($i)) {
		unless ($pkg eq "Tkx" || $pkg =~ /^Tkx::/) {
		    $file =~ s,.*[/\\],,;
		    push(@prefix, $file, $line);
		    last;
		}
		$i++;
	    }
	}

	my($cmd, @args) = @_;
	for (@args) {
	    if (ref eq "CODE" || ref eq "ARRAY" && ref($_->[0]) eq "CODE") {
		$_ = "perl::callback";
	    }
	    elsif (ref eq "ARRAY" || ref eq "Tcl::List") {
		$_ = $interp->call("format", "[list %s]", $_);
	    }
	    else {
		if ($TRACE_MAX_STRING && length > $TRACE_MAX_STRING) {
		    substr($_, 2*$TRACE_MAX_STRING/3, -$TRACE_MAX_STRING/3) = " ... ";
		}
		s/([\\{}\"\[\]\$])/\\$1/g;
		s/\r/\\r/g;
		s/\n/\\n/g;
		s/\t/\\t/g;
		s/([^\x00-\xFF])/sprintf "\\u%04x", ord($1)/ge;
		s/([^\x20-\x7e])/sprintf "\\x%02x", ord($1)/ge;
		$_ = "{$_}" if / /;
	    }
	}
	print STDERR join(" ", (join("-", @prefix) . ":"), $cmd, @args) . "\n";
    }
    my @cleanup;
    if ($_[0] eq "destroy") {
	my @paths = @_;
	shift(@paths);
	push(@cleanup, Tkx::widget::_destroy->new(@paths));
    }
    return $interp->call(@_);
}

sub DoOneEvent {
    $interp->DoOneEvent(@_);
}

1;

__END__

=head1 NAME

Tkx - Yet another Tk interface

=head1 SYNOPSIS

  use Tkx;
  my $mw = Tkx::widget->new(".");
  $mw->c_button(
       -text => "Hello, world",
       -command => sub { $mw->g_destroy; },
  )->g_pack;
  Tkx::MainLoop();

=head1 DESCRIPTION

The C<Tkx> module provides yet another Tk interface for Perl.  Tk is a
GUI toolkit tied to the Tcl language, and C<Tkx> provides a bridge to
Tcl that allows Tk based applications to be written in Perl.

The main idea behind Tkx is that it is a very thin wrapper on top of
Tcl, i.e. that what you get is exactly the behaviour you read about in
the Tcl/Tk documentation with no surprises added by the Perl layer.

The following functions are provided:

=over

=item Tkx::MainLoop( )

This will enter the Tk mainloop and start processing events.  The
function returns when the main window has been destroyed.  There is no
return value.

=item Tkx::Ev( $field, ... )

This creates an object that if passed as the first argument to a
callback will expand the corresponding Tcl template substitutions in
the context of that callback.  The description of Tkx::I<foo> below
explain how callback arguments are provided, and the available
substitutions are described in the Tcl documentation for the C<bind>
command.

=item Tkx::SplitList( $list )

This will split up a Tcl list into Perl list.  The individual elements
of the list are returned as separate elements:

    @a = Tkx::SplitList(Tkx::set("a"));

This function will croak if the argument is not a well formed list or if
called in scalar context.

=item Tkx::I<foo>( @args )

Any other function will invoke the I<foo> Tcl function with the given
arguments.  The name I<foo> first undergo the following substitutions
of embedded underlines:

    foo_bar  -->  "foo", "bar"   # break into words
    foo__bar -->  "foo::bar"     # access namespaces
    foo___bar --> "foo_bar"      # when you actually need a '_'

This allow us conveniently to map most of the Tcl namespace to Perl.
If this mapping does not suit you, use C<< Tkx::i::call($func, @args)
>>.  This will invoke the function named by $func with no name
substitutions or magic.

Examples:

    Tkx::expr("3 + 3");
    Tkx::package_require("BWidget");
    Tkx::DynamicHelp__add(".", -text => "Hi there");

The arguments passed can be plain scalars, array references, code
references, or scalar references.

Array references are converted to Tcl lists.  The arrays can contain
other array references or plain scalars to form nested lists.

For Tcl APIs that require callbacks you can pass a reference to a Perl
function.  Alternatively an array reference with a code reference as
the first element, will allow the callback to receive the rest of the
elements as arguments when invoked.  The Tkx::Ev() function can be
used to fill in Tcl provided info as arguments.  Eg:

    Tkx::after(3000, sub { print "Hi" });
    Tkx::bind(".", "<Key>", [sub { print "$_[0]\n"; }, Tkx::Ev("%A")]);

For Tcl APIs that require variables to be passed, you might pass a
reference to a Perl scalar.  The scalar will be watched and updated in
the same way as the Tcl variable would.

The Tcl string result is returned in both scalar and array context.
Tcl errors are propagated as Perl exceptions.

If the boolean variable $Tkx::TRACE is set to a true value, then a
trace of all commands passed to Tcl will be printed on STDERR.  This
variable is initialized from the C<PERL_TKX_TRACE> environment
variable.  The trace is useful for debugging and if you need to report
errors to the Tcl maintainers in terms of Tcl statements.  The trace
lines are prefixed with:

    Tkx-$seq-$ts-$file-$line:

where $seq is a sequence number, $ts is a timestamp in seconds since
the first command was issued, and $file and $line indicate on which
source line this call was triggered.

=back

All these functions can be exported by Tkx if you grow tired of typing
the C<Tkx::> prefix.  Example:

    use strict;
    use Tkx qw(MainLoop button pack destroy);

    pack(button(".b", -text => "Press me!", -command => [\&destroy, "."]));
    MainLoop;

=head2 Widget handles

The class C<Tkx::widget> is used to wrap Tk widget paths or names.
These objects stringify as the path they wrap.

The following methods are provided:

=over

=item $w = Tkx::widget->new( $path )

This constructs a new widget handle for a given path.  It is not a
problem to have multiple handle objects to the same path.

=item Tkx::widget->_Mega( $widget, $class )

This register $class as the one implementing $widget widgets.  See
L</Meta widgets>.

=item $w->_data

Returns a hash that can be used to keep instance specific data.  This
is useful for holding instance data for mega widgets.  The data is
attached to the underlying widget, so if you create another handle to
the same widget it will return the same hash via its _data() method.

The data hash is automatically destroyed when the corresponding widget
is destroyed.

=item $w->_parent

Returns a handle for the parent widget.  Returns C<undef> if there is
no parent, i.e. $w is the main window (root).

=item $w->_kid( $name )

Returns a handle for a kid widget with the given name.  The $name can
contain dots to access grandkids.  There is no check that a kid with
the given name actually exists, so this method can't fail.  This is a
feature.  It can for instance be used to construct names of widgets to
be created later.

=item $w->_class( $class )

Sets the widget handle class for the current path.  This will both
change the class of the current handle and make sure later handles
created for the path belong to the given class.  The class should
normally be a subclass of C<Tkx::widget>.  Overriding the class for a
path is useful for implementing mega widgets.  Kids of $w are not
affected by this, unless the class overrides the _nclass() method.

=item $w->_nclass

This returns the default widget handle class that will be used for
kids and parent.  Subclasses might want to override this method.
The default implementation always returns C<Tkx::widget>.

=item $w->_mpath( $method )

This returns a Tcl widget path that will be used to forward any
m_I<foo> method calls.  Mega widget classes might want to override
this method.  The default implementation returns C<$w>.

=item $new_w = $w->c_I<foo>( @args )

This creates a new I<foo> widget as a child of the current widget.  It
will call the I<foo> Tcl command and pass it a new unique subpath of
the current path.  The handle to the new widget is returned.  Any
double underscores in the name I<foo> is expanded as described for
Tkx::foo() above.

Example:

    $w->c_label(-text => "Hello", -relief => "sunken");

The name selected for the child will be the first letter in the
widget.  If that name is not unique a number is appended to ensure
uniqueness among the children.  If a C<-name> argument is passed it is
used to form the name and then removed from the arglist passed to Tcl.
Example:

    $w->c_iwidgets_calendar(-name => "cal");

If a mega widget implementation class has be registered for I<foo>,
then its _Populate() method is called instead of passing widget
creation to Tcl.

=item $w->m_I<foo>( @args )

This will invoke the I<foo> subcommand for the current widget.  This
is the same as:

    $func = "Tkx::$w";
    &$func(expand("foo"), @args);

where the expand() function expands underscores as described for
Tkx::foo() above.  Note that methods that do not start with a prefix
of the form /^_/ or /^[a-zA-Z]_/ are also treated as the C<m_> methods.

Example:

    $w->m_configure(-background => "red");

Subclasses might override the _mpath() method to have m_I<foo> forward
the subcommand somewhere else than the current widget.

=item $w->g_I<foo>( @args )

This will invoke the I<foo> Tcl command with the current widget as
first argument.  This is the same as:

    $func = "Tkx::foo";
    &$func($w, @args);

Any underscores in the name I<foo> are expanded as described for
Tkx::foo() above.

Example:

    $w->e_pack_forget;

=item $w->I<foo>( @args )

If the method does not have a prefix of the form /^_/ or /^[a-zA-Z]_/,
then it is treated as if it had the "m_" prefix, i.e. the I<foo>
subcommand for the current widget is invoked.

The method names with prefix /^_/ and /^[a-zA-Z]_/ are reserved for
future extensions to this API.

=back

=head2 Mega widgets

Mega widgets can be implemented in Perl and used by Tkx.  To declare a
mega widget make a Perl class like this one:

    package Foo;
    use base 'Tkx::widget';
    Foo->_Mega("foo");

    sub _Populate {
        my($class, $widget, $path, %opt) = @_;
        ...
    }

The mega widget class should inherit from C<Tkx::widget> and will
register itself by calling the _Mega() class method.  In the example
above we tell Tkx that any "foo" widgets should be handled by the Perl
class "Foo" instead of Tcl.  When a new "foo" widget is instantiated
with:

    $w->n_foo(-text => "Hi", -foo => 1);

then the _Populate() class method of C<Foo> is called.  It will be
passed the widget type to create, the full path to use as widget
name and any options passed in.  The widget name is passed in so that a
single Perl class can implement multiple widget types.

The _Populate() class should create a root object with the given $path
as name and populate it with the internal widgets.  Normally the root
object will be forced to belong to the implementation class so that it
can trap various method calls on it.  By using the _class() method to
set class _Populate() can ensure that new handles to this mega widget
also use this class.

The implementation class can define an _ipath() method to delegate any
i_I<foo> method calls to one of its subwidgets and it might want to
override the i_configure() and i_cget() methods if it implements
additional options or want more control over delegation.  The class
C<Tkx::MegaConfig> provide implementations of i_configure() and
i_cget() that can be useful for controlling delegation of
configuration options.

See L<Tkx::LabEntry> for a trivial example mega widget.

=head1 ENVIRONMENT

The C<PERL_TKX_TRACE> environment variable initialize the $Tkx::TRACE setting.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

Copyright 2005 ActiveState.  All rights reserved.

=head1 SEE ALSO

L<Tkx::MegaConfig>, L<Tcl>

Alternative Tk bindings for Perl are described in L<Tcl::Tk> and L<Tk>.

More information about Tcl/Tk can be found at L<http://www.tcl.tk/>.
