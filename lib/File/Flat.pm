package File::Flat;

# The File::Flat is a static class that provides an interface to
# a flat filesystem. In effect, it makes the directory seperator
# a part of the file name. On disk, directories will be created on
# demand as required.
#
# For now, this is only expected to work on Unix style filesystems

use strict;
use UNIVERSAL 'isa';

# Load required modules.
use File::Spec ();
use Class::Autouse qw{IO::File};

use vars qw{$VERSION %modes $errstr};
BEGIN {
	# Set the version
	$VERSION = 0.3;

	# Create a map of all file open modes we support,
	# and which ones will create a new file if needed.
	%modes = ( 
		'<'  => 0, 'r'  => 0, # Read
		'+<' => 1, 'r+' => 1, # ReadWrite
		'>'  => 1, 'w'  => 1, # Write
		'+>' => 1, 'w+' => 1, # ReadWrite
		'>>' => 1, 'a'  => 1  # Append
		);

	# Error messages
	$errstr = '';
}





#####################################################################
# Examining the file system

# Does a filesystem entity exist.
sub exists { -e $_[1] }

# Is a filesystem object a file.
sub isaFile { -f $_[1] }

# Is a filesystem object a directory.
sub isaDirectory { -d $_[1] }

# Do we have permission to read a filesystem object.
sub canRead { -e $_[1] and -r $_[1] }

# Do we have permission to write to a filesystem object.
# If it doesn't exist, can we create it.
sub canWrite {
	# If it already exists, check normally
	return -w $_[1] if -e $_[1];
	
	# Can we create it
	my $Object = File::Flat::Object->new( $_[1] ) or return undef;
	return $Object->_canCreate();
}

# Can we both read and write to a filesystem object.
sub canReadWrite { -e $_[1] and -r $_[1] and -w $_[1] }

# Do we have permission to execute a filesystem object
sub canExecute { -e $_[1] and -x $_[1] }

# Could we open this as a file
sub canOpen { -e $_[1] and -f $_[1] and -r $_[1] }

# Could a file or directory be removed, were we to try
sub canRemove {
	# Pass through to the object class
	my $Object = File::Flat::Object->new( $_[1] ) or return undef;
	return $Object->canRemove;
}

# Is the file a text file
sub isText { -e $_[1] and -f $_[1] and -T $_[1] }

# Is a file a binary file.
sub isBinary { -e $_[1] and -f $_[1] and -B $_[1] }

# Stat based methods. 
# I've included only the most usefull one I can think of.
sub fileSize {
	my $class = shift;
	my $file = shift or return undef;
	
	# Check the file
	return $class->_andError( 'File does not exist' ) unless -e $file;
	return $class->_andError( 'Cannot get the file size for a directory' ) unless -f $file;
		
	# A file's size is contained in the 7th element
	return (stat $file)[7];
}

	



#####################################################################
# Opening Files.

# Note: Files are closed conventionally using the IO::Handle's methods.

# Open a file.
# Takes as arguments either a ">filepath" style file name, or the two argument
# form of "mode", "filename". Supports perl '<' type modes, and fopen 'rw' 
# type modes. Pipes and more advanced things are not supported.
# Both the 1 and 2 argument modes are supported.
# Returns an IO::File for the filesystem object.
sub open {
	my $class = shift;
	
	# One or two argument form
	my ($file, $mode) = ();
	if ( scalar @_ == 1 ) {
		$file = shift;
		if ( $file =~ s/^([<>+]{1,2})\s*// ) {
			$mode = $1;
		} else {
			# Read by default
			$mode = '<'; 
		}

	} elsif ( scalar @_ == 2 ) {
		$mode = shift;
		$file = shift;

	} else {
		return $class->_andError( "Invalid argument count to ->open" );
	}

	# Check the mode
	unless ( exists $modes{$mode} ) {
		return $class->_andError( "Unknown or unsupported mode '$mode'" );
	}

	# Ensure the directory exists for those that need it
	my $remove_on_fail = '';
	if ( $modes{$mode} and ! -e $file ) {
		$remove_on_fail = $class->_ensureDirectory( $file );
		return undef unless defined $remove_on_fail;		
	}

	# Try to get the IO::File
	my $handle = IO::File->new( $file, $mode );
	return $handle || $class->_andRemove( $remove_on_fail );
}

# Provide creation mode specific methods
sub getReadHandle { $_[0]->open( '<', $_[1] ) }
sub getWriteHandle { $_[0]->open( '>', $_[1] ) }
sub getAppendHandle { $_[0]->open( '>>', $_[1] ) }
sub getReadWriteHandle { $_[0]->open( '+<', $_[1] ) }





#####################################################################
# Quick File Methods

# Slurp quickly reads in an entire file in a memory efficient manner.
# Reads and file and returns a reference to a scalar containing the file.
# Returns 0 if the file does not exist.
# Returns undef on error.
sub slurp {
	my $class = shift;
	my $file = shift;
	
	# Check the file
	unless ( $class->canOpen( $file ) ) {
		return $class->_andError( "Unable to open file '$file'" );
	}

	# Open the file
	CORE::open( SLURP, $file ) or return $class->_andError( "Error opening file '$file'", $! );
	
	# Create the file buffer, and read in the file
	my $buffer;
	{
		# Don't try to think about "lines" of the file
		local $/ = undef;
		
		# Read in the entire file ( since "lines" don't exist )
		$buffer = <SLURP>;
	}
	
	# Return a reference to file contents
	close SLURP;
	return \$buffer;
}

# read reads in an entire file, returning it as an array or a reference to it.
# depending on the calling context. Returns undef or () on error, depending on 
# the calling context.
sub read {
	my $class = shift;
	my $file = shift or return wantarray ? () : undef;;
	
	# Check the file
	unless ( $class->canOpen( $file ) ) {
		$class->_andError( "Unable to open file '$file'" );
		return wantarray ? () : undef;
	}

	# Read the file
	unless ( CORE::open( READ, $file ) ) {
		$class->_andError( "Error opening file '$file'", $! );
		return wantarray ? () : undef;
	}

	my @content = <READ>;

	close READ or return wantarray ? () : undef;

	# Return in the format they want
	chomp( @content );
	return wantarray ? @content : \@content;
}

# writeFile writes a file to the filesystem, replacing the existing file
# if needed. Existing files will be clobbered before starting to write to
# the file, as per a typical write file handle.
sub write {
	my $class = shift;
	my $file = shift or return undef;
	unless ( defined $_[0] ) {
		return $class->_andError( "Did not pass anything to write to file" );
	}
	
	# Get a ref to the contents.
	# This looks messy, but it avoids copying potentially large amounts
	# of data in memory, bloating the RAM usage.
	# This also makes sure the stuff we are going to write is ok.
	my $contents;
	if ( ref $_[0] ) {
		if ( isa( $_[0], 'SCALAR' ) or isa( $_[0], 'ARRAY' ) ) {
			$contents = $_[0];
		} else {
			return $class->_andError( "Unknown or invalid argument to ->write" );
		}
	} else {
		$contents = \$_[0];
	}
	
	# Get an opened write file handle if we weren't passed a handle already.
	# When this falls out of context, it will close itself.
	# Since there are many things that act like file handles, don't check
	# specifically for IO::Handle or anything, just for a reference.
	my $dontclose = 0;
	if ( ref $file ) { 
		# Don't close is someone passes us a handle.
		# They might want to write other things.
		$dontclose = 1;
	} else {	
		$file = $class->getWriteHandle( $file ) or return undef;
	}
	
	# Write the contents to the handle
	if ( isa( $contents, 'SCALAR' ) ) {
		$file->print( $$contents ) or return undef;
	} else {
		foreach ( @$contents ) {
			# When printing the lines to the file, 
			# fix any possible newline problems.
			chomp $_;
			$file->print( $_ . "\n" ) or return undef;
		}
	}
	
	# Close the file if needed
	$file->close() unless $dontclose;
	
	return 1;	
}

# overwrite() writes a file to the filesystem, replacing the existing file
# if needed. Existing files will be clobbered at the end of writing the file,
# essentially allowing you to write the file to disk atomically.
sub overwrite {
	my $class = shift;
	my $file = shift or return undef;
	return undef unless defined $_[0];
	
	# Make sure we will be able to write over the file
	unless ( $class->canWrite($file) ) {
		return $class->_andError( "Will not be able to create the file '$file'" );
	}

	# Load in the two libraries we need.
	# It's a fair chunk of overhead, so we do it here instead of up
	# the top so it only loads in if we need to do overwriting.
	# Not as good as Class::Autouse, but these arn't OO modules.
	require File::Temp;
	require File::Copy;

	# Get a temp file
	my ($handle, $tempfile) = File::Temp::tempfile( SUFFIX => '.tmp', UNLINK => 0 );
	
	# Write the content to it.
	# Pass the argument by reference if it isn't already,
	# to avoid copying large scalars.
	unless ( $class->write( $handle, ref $_[0] ? $_[0] : \$_[0] ) ) {
		# Clean up and return an error
		$handle->close();
		unlink $tempfile;
		return $class->_andError( "Error while writing file" );
	}

	# We are finished with the handle	
	$handle->close();
	
	# Now move the finished file to the final location
	unless ( File::Copy::move( $tempfile, $file ) ) {
		# Clean up the tempfile and return an error
		unlink $tempfile;
		return $class->_andError( "Failed to copy file into final location" );		
	}		
	
	return 1;	
}

# appendFile writes content to the end of an existing file, or creating the
# file if needed.
sub append {
	my $class = shift;
	my $file = shift or return undef;
	return undef unless defined $_[0];

	# Get the appending handle, and write to it
	my $handle = $class->getAppendHandle( $file ) or return undef;
	unless ( $class->write( $handle, ref $_[0] ? $_[0] : \$_[0] ) ) {
		# Clean up and return an error
		$handle->close();
		return $class->_andError( "Error while writing file" );
	}
	$handle->close();
	
	return 1;
}
		
# Copy a file or directory from one place to another.
# We apply our own copy semantics.
sub copy {
	my $class = shift;
	my $source = File::Spec->canonpath( shift ) or return undef;
	my $target = File::Spec->canonpath( shift ) or return undef;
	
	# Check the source and target
	return $class->_andError( "No such file or directory '$source'" ) unless -e $source;
	if ( -e $target ) {
		unless ( -f $source and -f $target ) {
			return $class->_andError( "Won't overwrite " 
				. (-f $target ? 'file' : 'directory')
				. " '$target' with "
				. (-f $source ? 'file' : 'directory')
				. " '$source'" );
		}
	}		
	unless ( $class->canWrite( $target ) ) {
		return $class->_andError( "Insufficient permissions to create '$target'" );
	}
	
	# Make sure the directory for the target exists
	my $remove_on_fail = $class->_ensureDirectory( $target );
	return undef unless defined $remove_on_fail;

	if ( -f $source ) {
		# Copy a file to the new location
		require File::Copy;
		return File::Copy::copy( $source, $target )
			? 1 : $class->_andRemove( $remove_on_fail );

	} else {
		my $tocopy = File::Spec->catfile( $source, '*' ) or return undef;
		
		# Create the target directory
		unless ( mkdir $target, 0755 ) {
			return $class->_andRemove( $remove_on_fail, 
				"Failed to create directory '$target'" );
		}
		
		# Hand off to File::NCopy
		require File::NCopy;
		my $rv = File::NCopy::copy( \1, $tocopy, $target );
		return defined $rv ? $rv : $class->_andRemove( $remove_on_fail );
	}
}

# Move a file from one place to another.
sub move {
	my $class = shift;
	my $source = shift or return undef;
	my $target = shift or return undef;

	# Check the source and target
	return $class->_andError( "Copy source '$source' does not exist" ) unless -e $source;
	if ( -d $source and -f $target ) {
		return $class->_andError( "Cannot overwrite non-directory '$source' with directory '$target'" );
	}
	
	# Check permissions
	unless ( $class->canWrite( $target ) ) {
		return $class->_andError( "Insufficient permissions to write to '$target'" );
	}
	
	# Make sure the directory for the target exists
	my $remove_on_fail = $class->_ensureDirectory( $target );
	return undef unless defined $remove_on_fail;
	
	# Do the file move
	require File::Copy;
	my $rv = File::Copy::move( $source, $target );
	unless ( $rv ) {
		# Clean up after ourselves
		File::Flat->remove( $remove_on_fail ) if $remove_on_fail;
		return $class->_andError( "Error moveing '$source' to '$target'" );
	}
	
	return 1;
}

# Remove a file or directory ( safely )
sub remove {
	my $class = shift;
	my $file = shift or return undef;
	
	# Does the file exist
	unless ( -e $file ) {
		return $class->_andError( "File or directory does not exist" );
	}

	# Like the others, load in File::Remove	
	require File::Remove;
	
	# Use File::Remove to remove it
	my $rv = File::Remove::remove( \1, $file );
	return $rv ? 1 : undef;
}

# Truncate a file. That is, leave the file in place, 
# but reduce it's size to a certain size, default 0.
sub truncate {
	my $class = shift;
	my $file = shift or return undef;
	my $bytes = defined $_[0] ? shift : 0; # Beginning unless otherwise specified
	
	# Check the file
	if ( -d $file ) {
		return $class->_andError( "Cannot truncate a directory" );
	}
	unless ( $class->canWrite( $file ) ) {
		return $class->_andError( "Insufficient permissions to truncate file" );
	}
	
	# Get a handle to the file and truncate it
	my $handle = $class->open( '>', $file )
		or return $class->_andError( 'Failed to open write file handle' );
	$handle->truncate( $bytes )
		or return $class->_andError( "Failed to truncate file handle: $!" );
	$handle->close();
	
	return 1;
}





#####################################################################
# Directory Methods

# Pass these through to the object version. It should be
# better at this sort of thing.

# Create a directory. 
# Returns true on success, undef on error.
sub makeDirectory {
	my $Object = File::Flat::Object->new( $_[1] ) or return undef;
	return $Object->makeDirectory();
}

# Create the directory below ours
sub _ensureDirectory {
	my $Object = File::Flat::Object->new( $_[1] ) or return undef;
	return $Object->_ensureDirectory();
}




#####################################################################
# Error handling

sub errstr   { $errstr }
sub _andError { $errstr = $_[1]; undef }
sub _andRemove {
	my $self = shift;
	my $to_remove = shift;
	if ( length $to_remove ) {
		require File::Remove;
		File::Remove::remove( $to_remove );
	}
	return @_ 
		? $self->_andError( @_ )
		: undef;
}

1;








package File::Flat::Object;

# Instantiatable version of File::Flat.
# 
# The methods are the same as for File::Flat, where applicable.

use strict;
use UNIVERSAL 'isa';
use File::Spec ();

sub new {
	my $class = shift;
	my $filename = shift or return undef;
	
	return bless {
		type => undef,
		original => $filename,
		absolute => undef,
		volume => undef,
		directories => undef,
		file => undef,
		}, $class;
}

sub _init {
	my $self = shift;

	# Populate the other properties
	$self->{absolute} = File::Spec->rel2abs( $self->{original} );
	my ($v, $d, $f) = File::Spec->splitpath( $self->{absolute} );
	my @dirs = File::Spec->splitdir( $d );
	$self->{volume} = $v;
	$self->{directories} = \@dirs;
	$self->{file} = $f;
	$self->{type} = $self->{file} eq '' ? 'directory' : 'file';

	return 1;
}
	
# Define the basics
sub exists       { -e $_[0]->{original} }
sub isaFile      { -f $_[0]->{original} }
sub isaDirectory { -d $_[0]->{original} }
sub canRead      { -e $_[0]->{original} and -r $_[0]->{original} }
sub canWrite     { -e $_[0]->{original} and -w $_[0]->{original} }
sub canReadWrite { -e $_[0]->{original} and -r $_[0]->{original} and -w $_[0]->{original} }
sub canExecute   { -e $_[0]->{original} and -x $_[0]->{original} }
sub canOpen      { -f $_[0]->{original} and -r $_[0]->{original} }
sub fileSize     { File::Flat->fileSize( $_[0]->{original} ) }

# Can we create this file/directory, if it doesn't exist.
# Returns 2 if yes, but we need to create directories
# Returns 1 if yes, and we won't need to create any directories.
# Returns 0 if no.
sub _canCreate {
	my $self = shift;
	$self->_init() unless defined $self->{type};
	
	# It it already exists, check for writable instead
	if ( -e $self->{original} ) {
		return $self->canWrite;
	}
	
	# Go up the directories and find the last one that exists
	my $dir_known = '';
	my $dir_unknown = '';
	my @dirs = @{$self->{directories}};
	pop @dirs if $self->{file} eq '';
	while ( defined( my $dir = shift @dirs ) ) {
		$dir_unknown = File::Spec->catdir( $dir_known, $dir );
		
		# Does the filesystem object exist
		my $fullpath = File::Spec->catpath( $self->{volume}, $dir_unknown );
		last unless -e $fullpath;

		# This should be a directory
		if ( -d $fullpath ) {
			$dir_known = $dir_unknown;
			next;
		}

		# A file is where we think a directory should be
		return 0;
	}
	
	# $dir_known now contains the last directory that exists.
	# Can we create filesystem objects under this?
	return 0 unless -w $dir_known;
	
	# If @dirs is empty, we don't need to create 
	# any directories when we create the file
	return scalar @dirs ? 2 : 1;
}	 	

### FIXME - Implement this.
# Should check the we can delete the file.
# If it's a directory, should check that we can
# recursively delete everything in it.
sub canRemove { die "The ->canRemove method has not been implemented yet" }

# Is the file a text file.
sub isText { -e $_[0]->{original} and -f $_[0]->{original} and -T $_[0]->{original} }

# Is a file a binary file.
sub isBinary { -e $_[0]->{original} and -f $_[0]->{original} and -B $_[0]->{original} }





#####################################################################
# Opening File

# Pass these down to the static methods

sub open { 
	my $self = shift;
	return defined $_[0]
		? File::Flat->open( $self->{original}, $_[0] ) 
		: File::Flat->open( $self->{original} )
}

sub getReadHandle { File::Flat->open( '<', $_[0]->{original} ) }
sub getWriteHandle { File::Flat->open( '>', $_[0]->{original} ) }
sub getAppendHandle { File::Flat->open( '>>', $_[0]->{original} ) }
sub getReadWriteHandle { File::Flat->open( '+<', $_[0]->{original} ) }





#####################################################################
# Quick File Methods

sub slurp { File::Flat->slurp( $_[0]->{original} ) }
sub read { File::Flat->read( $_[0]->{original} ) }
sub write { File::Flat->write( $_[0]->{original} ) }
sub overwrite { File::Flat->overwrite( $_[0]->{original} ) }
sub append { File::Flat->append( $_[0]->{original} ) }
sub copy { File::Flat->copy( $_[0]->{original}, $_[1] ) }
sub move { 
	my $self = shift;
	my $moveTo = shift;
	File::Flat->move( $self->{original}, $moveTo ) or return undef;
	
	# Since the file is moving, once we actually
	# move the file, update the object information so
	# it refers to the new location.
	$self->{original} = $moveTo;
	
	# Re-initialise if we have already
	$self->init() if $self->{type};
	
	return 1;
}
sub remove { File::Flat->remove( $_[0]->{original} ) }
sub truncate { File::Flat->truncate( $_[0]->{original} ) }






#####################################################################
# Directory methods

# Create a directory. 
# Returns true on success, undef on error.
sub makeDirectory {
	my $self = shift;
	my $mode = shift || 0755;
	if ( -e $self->{original} ) {
		return 1 if -d $self->{original};
	} else {
		return $self->_andError( "'$self->{original}' already exists, and is a file" );
	}
	$self->_init() unless defined $self->{type};
	
	# Ensure the directory below ours exists
	my $remove_on_fail = $self->_ensureDirectory( $mode );
	return undef unless defined $remove_on_fail;
	
	# Create the directory
	unless ( mkdir $self->{original}, $mode ) {
		return $self->_andRemove( $remove_on_fail, 
			"Failed to create directory '$self->{original}': $!" );
	}
	
	return 1;
}

# Make sure the directory that this file/directory is in exists.
# Returns the root of the creation dirs if created.
# Returns '' if nothing required.
# Returns undef on error.
sub _ensureDirectory {
	my $self = shift;
	my $mode = shift || 0755;
	return '' if -e $self->{original};
	$self->_init() unless defined $self->{type};
	
	# Go up the directories and find the last one that exists
	my $dir_known = '';
	my $dir_unknown = '';
	my $creation_root = '';
	my @dirs = @{$self->{directories}};
	pop @dirs if $self->{file} eq '';
	while ( defined( my $dir = shift @dirs ) ) {
		$dir_unknown = File::Spec->catdir( $dir_known, $dir );
		
		# Does the filesystem object exist
		my $fullpath = File::Spec->catpath( $self->{volume}, $dir_unknown );		
		if ( -e $fullpath ) {
			# This should be a directory
			return undef unless -d $fullpath;
		} else {
			# Try to create the directory
			unless ( mkdir $dir_unknown, $mode ) {
				return $self->_andError( $! );
			}
			
			# Set the base of our creations to return
			$creation_root = $dir_unknown unless $creation_root;
		}

		$dir_known = $dir_unknown;
	}
	
	return $creation_root;	
}






#####################################################################
# Error handling

sub errstr   { $File::Flat::errstr }
sub _andError { $File::Flat::errstr = $_[1]; undef }
sub _andRemove { shift; return File::Flat->_andRemove( @_ ) }

1;

__END__

=pod

=head1 NAME

File::Flat - Implements a flat filesystem

=head1 SYNOPSIS

=head1 DESCRIPTION

File::Flat implements a flat filesystem. A flat filesystem is a filesystem in
which directories do not exist. It provides an abstraction over any normal
filesystem which makes it appear as if directories do not exist. In effect,
it will automatically create directories as needed. This is create for things
like install scripts and such, as you never need to worry about the existance
of directories, just write to a file, no matter where it is.

=head2 Comprehensive Implementation

The implementation of File::Flat is extremely comprehensive in scope. It has
methods for all stardard file interaction taks, the -X series of tests, and
some other things, such as slurp.

All methods are statically called, for example, to write some stuff to a file.

use File::Flat;
File::Flat->write( 'filename', 'file contents' );

=head2 Use of other modules

File::Flat tries to use more task orientated modules wherever possible. This
includes the use of File::Copy, File::NCopy, File::Remove and others. These
are mostly loaded on-demand.

=head2 Non-Unix platforms

File::Flat itself should be completely capable of handling any platform
through it's exclusive use of File::Spec.

However, some of the modules it relies upon, particularly File::Remove, and
possible File::NCopy are not File::Spec happy yet. Results may wary on non
Unix platforms. Users of non-Unix platforms are invited to patch
File::Remove ( and possibly File::NCopy ) and File::Flat should work.

=head1 METHODS

=head2 exists( filename )

Tests for the existance of the file.
This is an exact duplicate of the -e function.

=head2 isaFile( filename )

Tests whether C<filename> is a file.
This is an exact duplicate of the -f function.

=head2 isaDirectory( filename )

Test whether C<filename> is a directory.
This is an exact duplicate of the -d function.

=head2 canRead( filename )

Does the file or directory exist, and can we read from it.

=head2 canWrite( filename )

Does the file or directory exist, and can we write to it 
B<OR> can we create the file or directory.

=head2 canReadWrite( filename )

Does a file or directory exist, and can we both read and write it.

=head2 canExecute( filename )

Does a file or directory exist, and can we execute it.

=head2 canOpen( filename )

Is this something we can open a filehandle to. Returns true if filename
exists, is a file, and we can read from it.

=head2 canRemove( filename )

Can we remove the file or directory.

=head2 isaText( filename )

Does the file C<filename> exist, and is it a text file.

=head2 isaBinary( filename )

Does the file C<filename> exist, and is it a binary file.

=head2 fileSize( filename )

If the file exists, returns it's size in bytes.
Returns undef if the file does not exist.

=head2 open( filename ) OR open( mode, filename )

Rough analogue of the open function, but creates directories on demand
as needed. Supports most of the normal options to the normal open function.

In the single argument form, it takes modes in the form [mode]filename. For
example, all the following are valid.

  File::Flat->open( 'filename' );
  File::Flat->open( '<filename' );
  File::Flat->open( '>filename' );
  File::Flat->open( '>>filename' );
  File::Flat->open( '+<filename' );

In the two argument form, it takes the following

  File::Flat->open( '<', 'filename' );
  File::Flat->open( '>', 'filename' );
  File::Flat->open( '>>', 'filename' );
  File::Flat->open( '+<', 'filename' );

It does not support the more esoteric forms of open, such us opening to a pipe
or other such things.

On successfully opening the file, it returns it as an IO::File object.
Returns undef on error.

=head2 getReadHandle( filename )

The same as File::Flat->open( '<', 'filename' )

=head2 getWriteHandle( filename )

The same as File::Flat->open( '>', 'filename' )

=head2 getAppendHandle( filename )

The same as File::Flat->open( '>>', 'filename' )

=head2 getReadWriteHandle( filename )

The same as File::Flat->open( '+<', 'filename' )

=head2 read( filename )

Opens and reads in an entire file, chomping as needed.

In array context, it returns an array containing each line of the file.
In scalar context, it returns a reference to an array containing each line of
the file. It returns undef on error.

=head2 slurp( filename )

Slurp 'slurp's a file in. This attempt to read the entire file into a variable
in as quick and memory efficient method as possible.

On success, returns a reference to a scalar, containing the entire file.
Returns undef on error.

=head2 write( filename, scalar | scalar_ref | array_ref )

The C<write> method is the main method for writing content to a file.
It takes two arguments, the location to write to, and the content to write, 
in several forms.

If the file already exists, it will be clobered before writing starts.
If the file doesn't exists, the file and any directories will be created as
needed.

Content can be provided in three forms. The contents of a scalar argument will
be written directly to the file. You can optionally pass a reference to the 
scalar. This is recommended when the file size is bigger than a few thousand
characters, is it does not duplicate the file contents in memory.
Alternatively, you can pass the content as a reference to an array containing
the contents. To ensure uniformity, C<write> will add a newline to each line,
replacing any existing newline as needed.

Returns true on success, and undef on error.

=head2 append( filename, scalar | scalar_ref | array_ref )

This method is the same as C<write>, except that it appends to the end of 
an existing file ( or creates the file as needed ).

This is the method you should be using to write to log files, etc.

=head2 overwrite( filename, scalar | scalar_ref | array_ref )

Performs an atomic write over a file. It does this by writing to a temporary
file, and moving the completed file over the top of the existing file ( or
creating a new file as needed ). When writing to a file that is on the same
partition as /tmp, this should always be atomic. 

This method otherwise acts the same as C<write>.

=head2 copy( source, target )

The C<copy> method attempts to copy a file or directory from the source to
the target. New directories to contain the target will be created as needed.

For example C<File::Flat->( './this', './a/b/c/d/that' );> will create the 
directory structure required as needed. 

In the file copy case, if the target already exists, and is a writable file,
we replace the existing file, retaining file mode and owners. If the target
is a directory, we do NOT copy into that directory, unlike with the 'cp'
unix command. And error is instead returned.

C<copy> will also do limited recursive copying or directories. If source 
is a directory, and target does not exists, a recursive copy of source will 
be made to target. If target already exists ( file or directory ), C<copy>
will returns with an error.

=head2 move( source, target )

The C<move> method follows the conventions of the 'mv' command, with the 
exception that the directories containing target will of course be created
on demand.

=head2 remove( filename )

The C<remove> method will remove a file, or recursively remove a directory.

=head2 truncate( filename [, size ] )

The C<truncate> method will truncate an existing file to partular size.
A size of 0 ( zero ) is used if no size is provided. If the file does not
exists, it will be created, and set to 0. Attempting to truncate a 
directory will fail.

Returns true on success, or undef on error.

=head2 makeDirectory( directory [, mode ] )

In the case where you do actually have to create a directory only, the
C<makeDirectory> method can be used to create a directory or any depth.

An optional file mode ( default 0755 ) can be provided.

Returns true on success, returns undef on error.

=head1 SUPPORT

Contact the author

=head1 TO DO

  - Needs to be made more efficient.
  - File::Spec::Object needs to be written, and File::Flat ported to use it
  - Function interface to be written, to provide importable functions.

=head1 AUTHORS

        Adam Kennedy ( maintainer )
        cpan@ali.as
        http://ali.as/

=head1 SEE ALSO

File::Spec

=head1 COPYRIGHT

Copyright (c) 2002 Adam Kennedy. All rights reserved.
This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
