package Class::Inspector;

# Bundled version for testing

use strict qw{vars subs};

use Class::ISA;
use File::Spec ();
use List::Util 'first';

# Declare globals
use vars qw{$VERSION};
BEGIN {
	$VERSION = 1.1;
}

# Provide the any list logic function for convenience
sub any(&@) { my $code = shift; foreach ( @_ ) { return 1 if &{$code}() } return '' }





#####################################################################
# Basic Methods

# Is the class installed on the machine, or rather, is it available
# to Perl. This is basically just a wrapper around C<resolved_filename>.
sub installed {
	my $class = shift;
	
	# Can we find a resolved filename
	my $rv = $class->resolved_filename( shift );
	return $rv ? 1 : $rv;
}

# Is the class loaded.
# We do this by seeing if the namespace is "occupied", which basically
# means any symbols other than child symbol table branches.
sub loaded {
	my $class = shift;
	my $name = $class->_class( shift ) or return undef;

	# Are there any symbol table entries other than other namespaces
	return any { ! (substr($_, -2, 2) eq '::') } keys %{"$name\::"};
}

# Convert to a filename, in the style of
# First::Second -> First/Second.pm
sub filename {
	my $class = shift;
	my $name = $class->_class( shift ) or return undef;
	return File::Spec->catfile( split /(?:'|::)/, $name ) . '.pm';
}

# Resolve the full filename for the class.
sub resolved_filename {
	my $class = shift;
	my $name = $class->_class( shift ) or return undef;
	my @try_first = @_;
	
	# Get the base filename
	my $filename = $class->filename( $name );
	
	# Look through the @INC path to find the file
	foreach ( @try_first, @INC ) {
		my $full = File::Spec->catfile( $_, $filename );
		return $full if -e $full;
	}
	
	# File not found
	return '';
}

# Get the loaded filename for the class.
sub loaded_filename {
	my $class = shift;
	my $name = $class->_class( shift ) or return undef;
	
	# Look the base filename up in %INC
	return $INC{ $class->filename($name) };
}

	



#####################################################################
# Sub Related Methods

# Get a reference to a list of function names for a class.
# Note: functions NOT methods.
sub functions {
	my $class = shift;
	my $name = $class->_class( shift ) or return undef;

	# Only works if the class is loaded
	return undef unless $class->loaded( $name );

	# Get all the CODE symbol table entries
	return [ 
		grep { defined &{"$name\::$_"} } 
		sort keys %{"$name\::"} 
		];
}

# As above, but returns a ref to an array of the actual 
# CODE refs of the functionsb
sub function_refs {
	my $class = shift;
	my $name = $class->_class( shift ) or return undef;

	# Only works if the class is loaded
	return undef unless $class->loaded( $name );

	# Get all the CODE symbol table entries,
	# but this time return them as CODE refs
	return [ 
		map { \&{"$name\::$_"} }
		grep { defined &{"$name\::$_"} }
		sort keys %{"$name\::"} 
		];
}

# Does a particular function exist
sub function_exists {
	my $class = shift;
	my $name = $class->_class( shift ) or return undef;
	my $function = shift or return undef;

	# Only works if the class is loaded
	return undef unless $class->loaded( $name );

	# Does the GLOB exist and it's CODE part exist
	return defined &{"$name\::$function"};
}

# Get all the available methods for the class
sub methods {
	my $class = shift;
	my $name = $class->_class( shift ) or return undef;
	my @arguments = map { lc $_ } @_;
	
	# Define the options hash
	my %options = ();
	
	# Process the arguments to define the options
	foreach ( @arguments ) {
		if ( $_ eq 'public' ) {
			# Only get public methods
			return undef if $options{private};
			$options{public} = 1;
				
		} elsif ( $_ eq 'private' ) {
			# Only get private methods
			return undef if $options{public};
			$options{private} = 1;
			
		} elsif ( $_ eq 'full' ) {
			# Return the full method name
			return undef if $options{expanded};
			$options{full} = 1;
			
		} elsif ( $_ eq 'expanded' ) {
			# Returns class, method and function ref
			return undef if $options{full};
			$options{expanded} = 1;
			
		} else {
			# Unknown or unsupported options
			return undef;
		}
	}

	# Only works if the class is loaded
	return undef unless $class->loaded( $name );

	# Get the super path ( not including UNIVERSAL )
	my @path = Class::ISA::self_and_super_path( $name );
	
	# Build a merge the method names across the entire super path.
	# Sort alphabetically and return.	
	my %methods = ();
	foreach my $namespace ( @path ) {
		foreach ( grep { defined &{"$namespace\::$_"} } keys %{"$namespace\::"} ) {
			next if $methods{$_};
			$methods{$_} = $namespace;
		}
	}

	# Filter to public or private methods if needed
	my @methodlist = sort keys %methods;
	@methodlist = grep { ! /^\_/ } @methodlist if $options{public};
	@methodlist = grep { /^\_/ } @methodlist if $options{private};

	# Return in the correct format
	@methodlist = map { "$methods{$_}\::$_" } @methodlist if $options{full};
	@methodlist = map { 
		[ "$methods{$_}\::$_", $methods{$_}, $_, \&{"$methods{$_}\::$_"} ] 
		} @methodlist if $options{expanded};

	return \@methodlist;
}





#####################################################################
# Children Related Methods
# These can go undocumented for now, until I decide if it's best to
# just search the children in namespace only, or if I should do it via
# the file system.

# Find all the loaded classes below us
sub children {
	my $class = shift;
	my $name = $class->_class(shift) or return ();

	# Find all the Foo:: elements in our symbol table
	no strict 'refs';
	return map { "$name\::$_" } sort grep { s/::$// } keys %{"$name\::"};
}

# As above, but recursively
sub recursive_children {
	my $class = shift;
	my $name = $class->_class(shift) or return ();
	my @children = ( $name );
	
	# Do the search using a nicer, more memory efficient
	# variant of actual recursion.
	{ no strict 'refs';
		my $i = 0;
		while ( my $class = $children[$i++] ) {
			push @children, map { "$name\::$_" } grep { s/::$// } keys %{"$class\::"};
		}
	}

	return sort @children;
}





#####################################################################
# Private Methods

sub _class {
	my $class = shift;
	my $name = shift or return '';

	# Handle main shorthand
	return 'main' if $name eq '::';
	$name =~ s/^::/main::/;

	return $name =~ /^[a-z]\w*((?:'|::)\w+)*$/io ? $name : '';
}

1;

__END__

=pod

=head1 NAME

Class::Inspector - Provides information about Classes

=head1 SYNOPSIS

  use Class::Inspector;
  
  # Is a class installed and/or loaded
  Class::Inspector->installed( 'Foo::Class' );
  Class::Inspector->loaded( 'Foo::Class' );
  
  # Filename related information
  Class::Inspector->filename( 'Foo::Class' );
  Class::Inspector->resolved_filename( 'Foo::Class' );
  
  # Get subroutine related information
  Class::Inspector->functions( 'Foo::Class' );
  Class::Inspector->function_refs( 'Foo::Class' );
  Class::Inspector->function_exists( 'Foo::Class', 'bar' );
  Class::Inspector->methods( 'Foo::Class', 'full', 'public' );

=head1 DESCRIPTION

Class::Inspector allows you to get information about a loaded class. Most or
all of this information can be found in other ways, but they arn't always
very friendly, and usually involve a relatively high level of Perl wizardry,
or strange or unusual looking code. Class::Inspector attempts to provide 
an easier, more friendly interface to this information.

=head1 METHODS

=head2 installed( $class )

Tries to determine is a class is installed on the machine, or at least 
available to Perl. It does this by essentially wrapping around 
C<resolved_filename>. Returns true if installed/available, returns 0 if
the class is not installed. Returns undef if the class name is invalid.

=head2 loaded( $class )

Tries to determine if a class is loaded by looking for symbol table entries. 
This method will work even if the class does not have it's own file, but is 
contained inside a single module with multiple package/classes. Even in the 
case of some sort of run-time loading class being used, these typically 
leave some trace in the symbol table, so an C<Class::Autouse> or C<Autoload> 
based class should correctly appear loaded.

=head2 filename( $class )

For a given class, returns the base filename for the class. This will NOT be
a fully resolved filename, just the part of the filename BELOW the @INC entry.

For example: Class->filename( 'Foo::Bar' ) returns 'Foo/Bar.pm'

This filename will be returned for the current platform. It should work on all
platforms. Returns the filename on success. Returns undef on error, which could
only really be caused by an invalid class name.

=head2 resolved_filename( $class, @try_first )

For a given class, returns the fully resolved filename for a class. That is, the
file that the class would be loaded from. This is not nescesarily the file that
the class WAS loaded from, as the value returned is determined each time it runs,
and the @INC include path may change. To get the actual file for a loaded class,
see the C<loaded_filename> method. Returns the filename for the class on success. 
Returns undef on error.

=head2 loaded_filename( $class )

For a given, loaded, class, returns the name of the file that it was originally
loaded from. Returns false if the class is not loaded, or did not have it's own
file.

=head2 functions( $class )

Returns a list of the names of all the functions in the classes immediate
namespace. Note that this is not the METHODS of the class, just the functions.
Returns a reference to an array of the function names on success. Returns undef
on error or if the class is not loaded.

=head2 function_refs( $class )

Returns a list of references to all the functions in the classes immediate
namespace. Returns a reference to an array of CODE refs of the functions on
success. Returns undef on error or if the class is not loaded.

=head2 function_exists( $class, $function )

Given a class and function the C<function_exists> method will check to see
if the function exists in the class. Note that this is as a function, not
as a method. To see if a method exists for a class, use the C<can> method
in UNIVERSAL, and hence to every other class. Returns 1 if the function
exists. Returns 0 if the function does not exist. Returns undef on error,
or if the class is not loaded.

=head2 methods( $class, @options )

For a given class name, the C<methods> method will returns ALL the methods
available to that class. This includes all methods available from every
class up the class' C<@ISA> tree. Returns a reference to an array of the
names of all the available methods on success. Returns undef if the class
is not loaded.

A number of options are available to the C<methods> method. These should
be listed after the class name, in any order.

=over 4

=item public

The C<public> option will return only 'public' methods, as defined by the Perl
convention of prepending an underscore to any 'private' methods. The C<public> 
option will effectively remove any methods that start with an underscore.

=item private

The C<private> options will return only 'private' methods, as defined by the
Perl convention of prepending an underscore to an private methods. The
C<private> option will effectively remove an method that do not start with an
underscore.

B<Note: The C<public> and C<private> options are mutually exclusive>

=item full

C<methods> normally returns just the method name. Supplying the C<full> option
will cause the methods to be returned as the full names. That is, instead of
returning C<[ 'method1', 'method2', 'method3' ]>, you would instead get
C<[ 'Class::method1', 'AnotherClass::method2', 'Class::method3' ]>.

=item expanded

The C<expanded> option will cause a lot more information about method to be 
returned. Instead of just the method name, you will instead get an array
reference containing the method name as a single combined name, ala C<full>,
the seperate class and method, and a CODE ref to the actual function ( if
available ). Please note that the function reference is not guarenteed to 
be available. c<Class::Inspector> is intended at some later time, work 
with modules that have some some of common run-time loader in place ( e.g
C<Autoloader> or C<Class::Autouse> for example.

The response from C<methods( 'Class', 'expanded' )> would look something like
the following.

  [
    [ 'Class::method1', 'Class', 'method1', \&Class::method1 ],
    [ 'Another::method2', 'Another', 'method2', \&Another::method2 ],
    [ 'Foo::bar', 'Foo', 'bar', \&Foo::bar ],
  ]

=back

=head1 BUGS

No known bugs, but I'm taking suggestions for additional functionality.

=head1 SUPPORT

Contact the author

=head1 AUTHOR

        Adam Kennedy
        cpan@ali.as
        http://ali.as/

=head1 SEE ALSO

Class::Handle, which wraps this one

=head1 COPYRIGHT

Copyright (c) 2002 Adam Kennedy. All rights reserved.
This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
