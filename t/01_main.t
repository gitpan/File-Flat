#!/usr/local/bin/perl

# Formal testing for Class::Inspector

# Do all the tests on ourself, since we know we will be loaded.

use strict;
use lib '../../../modules'; # Development testing
use lib '../lib';           # Installation testing
use UNIVERSAL 'isa';
use Test::Simple tests => 234;
use Class::Inspector ();

# Set up any needed globals
use vars qw{$loaded $ci $bad};
BEGIN {
	$loaded = 0;
	$| = 1;
}

use vars qw{$content_string @content_array $content_length};
BEGIN { 
	$content_string = "one\ntwo\nthree\n\n"; 
	@content_array = ( 'one', 'two', 'three', '' );
	$content_length = length $content_string;
}



# Check their perl version, and that modules are installed
BEGIN {
	ok( $] >= 5.005, "Your perl is new enough" );
	ok( Class::Inspector->installed( 'IO::File' ), "IO::File is installed" );
	ok( Class::Inspector->installed( 'File::Copy' ), "File::Copy is installed" );
	ok( Class::Inspector->installed( 'File::Temp' ), "File::Temp is installed" );
	ok( Class::Inspector->installed( 'File::Spec' ), "File::Spec is installed" );
	require File::Spec;
	ok( File::Spec->VERSION >= 0.82, "File::Spec is new enough" );
	ok( Class::Inspector->installed( 'File::Flat' ), "File::Flat is installed" );
}
	




# Does the module itself load
END { ok( 0, 'File::Flat loads correctly' ) unless $loaded; }
use File::Flat;
$loaded = 1;
ok( 1, 'File::Flat loads correctly' );





# First, let's check the APIs of both File::Flat and File::Flat::Object
# to make sure they present matching APIs
my $classmethods = Class::Inspector->methods( 'File::Flat' )
	or die "Failed to get methods for File::Flat";
my $objectmethods = Class::Inspector->methods( 'File::Flat::Object' )
	or die "Failed to get methods for File::Flat::Objects";
my %apihash = ();
foreach ( grep { $_ ne 'new' } grep { ! /^_/ } (@$classmethods, @$objectmethods) ) {
	$apihash{$_}++;
}

my @missing = grep { $apihash{$_} == 1 } sort keys %apihash;
if ( @missing ) {
	print map { "Public method '$_' was not present "
		. "in both File::Flat and File::Flat::Object\n" } @missing;
}
ok( scalar @missing == 0, "Static and object APIs match" );





# Create the files for the file test section
if ( system( 'touch ./rwx; chmod 0000 ./rwx' ) ) {
	die "Failed to create file we can do anything to";
}
if ( system( 'touch ./Rwx; chmod 0400 ./Rwx' ) ) {
	die "Failed to create file we can only read";
}
if ( system( 'touch ./rWx; chmod 0200 ./rWx' ) ) {
	die "Failed to create file we can only write";
}
if ( system( 'touch ./rwX; chmod 0100 ./rwX' ) ) {
	die "Failed to create file we can only execute";
}
if ( system( 'touch ./RWx; chmod 0600 ./RWx' ) ) {
	die "Failed to create file we can read and write";
}
if ( system( 'touch ./RwX; chmod 0500 ./RwX' ) ) {
	die "Failed to create file we can read and execute";
}
if ( system( 'touch ./rWX; chmod 0300 ./rWX' ) ) {
	die "Failed to create file we can write and execute";
}
if ( system( 'touch ./RWX; chmod 0700 ./RWX' ) ) {
	die "Failed to create file we can read, write and execute";
}
unless ( chmod 0777, '.' ) {
	die "Failed to set current directory to mode 777";
}
unless ( -e './gooddir' ) {
	unless ( mkdir './gooddir', 0755 ) {
		die "Failed to create mode 0755 directory";
	}
}
unless ( -e './baddir' ) {
	unless ( mkdir './baddir', 0000 ) {
		die "Failed to create mode 0500 directory";
	}
}

# We are also going to use a file called "./null" to represent
# a file that doesn't exist.



### Test Section 1 
# Here we will test all the static methods that are handled directly, and
# not passed on to the object form of the methods.

# Test the error message handling
my $error_message = 'foo';
my $rv = File::Flat->_andError( $error_message );
ok( ! defined $rv, "->_andError returns undef" );
ok( $File::Flat::errstr eq $error_message, "->_andError sets error message" );
ok( File::Flat->errstr eq $error_message, "->errstr retrieves error message" );

# Test the static ->exists method
ok( ! File::Flat->exists( './null' ), "Static ->exists doesn't see missing file" );
ok( File::Flat->exists( './rwx' ), "Static ->exists sees mode 000 file" );
ok( File::Flat->exists( './Rwx' ), "Static ->exists sees mode 400 file" );
ok( File::Flat->exists( './RWX' ), "Static ->exists sees mode 700 file" );
ok( File::Flat->exists( '.' ), "Static ->exists sees . directory" );
ok( File::Flat->exists( './baddir' ), "Static ->exists sees mode 000 directory" );

# Test the static ->isaFile method
ok( ! File::Flat->isaFile( './null' ), "Static ->isaFile returns false for missing file" );
ok( File::Flat->isaFile( './rwx' ), "Static ->isaFile returns true for mode 000 file" );
ok( File::Flat->isaFile( './RWX' ), "Static ->isaFile returns true for mode 700 file" );
ok( ! File::Flat->isaFile( '.' ), "Static ->isaFile returns false for . directory" );
ok( ! File::Flat->isaFile( './gooddir' ), "Static ->isaFile returns false for subdirectory" );

# Test the static ->isaDirectory method
ok( ! File::Flat->isaDirectory( './null' ), "Static ->isaDirectory returns false for missing directory" );
ok( ! File::Flat->isaDirectory( './rwx' ), "Static ->isaDirectory returns false for mode 000 file" );
ok( ! File::Flat->isaDirectory( './RWX' ), "Static ->isaDirectory returns false for mode 700 file" );
ok( File::Flat->isaDirectory( '.' ), "Static ->isaDirectory returns true for . directory" );
ok( File::Flat->isaDirectory( './gooddir' ), "Static ->isaDirectory returns true for readable subdirectory" );
ok( File::Flat->isaDirectory( './baddir' ), "Static ->isaDirectory return true for unreadable subdirectory" );

# Test the static ->canRead method
ok( ! File::Flat->canRead( './null' ), "Static ->canRead returns false for missing file" );
ok( ! File::Flat->canRead( './rwx' ), "Static ->canRead returns false for mode 000 file" );
ok( File::Flat->canRead( './Rwx' ), "Static ->canRead returns true for mode 400 file" );
ok( ! File::Flat->canRead( './rWx' ), "Static ->canRead returns false for mode 200 file" );
ok( ! File::Flat->canRead( './rwX' ), "Static ->canRead returns false for mode 100 file" );
ok( File::Flat->canRead( './RWx' ), "Static ->canRead returns true for mode 500 file" );
ok( File::Flat->canRead( './RwX' ), "Static ->canRead returns true for mode 300 file" );
ok( File::Flat->canRead( './RWX' ), "Static ->canRead returns true for mode 700 file" );
ok( File::Flat->canRead( '.' ), "Static ->canRead returns true for . directory" );
ok( File::Flat->canRead( './gooddir' ), "Static ->canRead returns true for readable subdirectory" );
ok( ! File::Flat->canRead( './baddir' ), "Static ->canRead returns false for unreadable subdirectory" );

# Test the static ->canWrite method
ok( File::Flat->canWrite( './null' ), "Static ->canWrite returns true for missing, creatable, file" );
ok( ! File::Flat->canWrite( './rwx' ), "Static ->canWrite returns false for mode 000 file" );
ok( ! File::Flat->canWrite( './Rwx' ), "Static ->canWrite returns false for mode 400 file" );
ok( File::Flat->canWrite( './rWx' ), "Static ->canWrite returns true for mode 200 file" );
ok( ! File::Flat->canWrite( './rwX' ), "Static ->canWrite returns false for mode 100 file" );
ok( File::Flat->canWrite( './RWx' ), "Static ->canWrite returns true for mode 500 file" );
ok( ! File::Flat->canWrite( './RwX' ), "Static ->canWrite returns false for mode 300 file" );
ok( File::Flat->canWrite( './RWX' ), "Static ->canWrite returns true for mode 700 file" );
ok( File::Flat->canWrite( '.' ), "Static ->canWrite returns true for . directory" );
ok( File::Flat->canWrite( './gooddir' ), "Static ->canWrite returns true for writable subdirectory" );
ok( ! File::Flat->canWrite( './baddir' ), "Static ->canWrite returns false for unwritable subdirectory" );
ok( ! File::Flat->canWrite( './baddir/file' ), "Static ->canWrite returns false for missing, non-creatable file" );

# Test the static ->canReadWrite method
ok( ! File::Flat->canReadWrite( './null' ), "Static ->canReadWrite returns false for missing file" );
ok( ! File::Flat->canReadWrite( './rwx' ), "Static ->canReadWrite returns false for mode 000 file" );
ok( ! File::Flat->canReadWrite( './Rwx' ), "Static ->canReadWrite returns false for mode 400 file" );
ok( ! File::Flat->canReadWrite( './rWx' ), "Static ->canReadWrite returns false for mode 200 file" );
ok( ! File::Flat->canReadWrite( './rwX' ), "Static ->canReadWrite returns false for mode 100 file" );
ok( File::Flat->canReadWrite( './RWx' ), "Static ->canReadWrite returns true for mode 500 file" );
ok( ! File::Flat->canReadWrite( './RwX' ), "Static ->canReadWrite returns false for mode 300 file" );
ok( File::Flat->canReadWrite( './RWX' ), "Static ->canReadWrite returns true for mode 700 file" );
ok( File::Flat->canReadWrite( '.' ), "Static ->canReadWrite returns true for . directory" );
ok( File::Flat->canReadWrite( './gooddir' ), "Static ->canReadWrite returns true for readwritable subdirectory" );
ok( ! File::Flat->canReadWrite( './baddir' ), "Static ->canReadWrite returns false for unreadwritable subdirectory" );

# Test the static ->canExecute method
ok( ! File::Flat->canExecute( './null' ), "Static ->canExecute returns false for missing file" );
ok( ! File::Flat->canExecute( './rwx' ), "Static ->canExecute returns false for mode 000 file" );
ok( ! File::Flat->canExecute( './Rwx' ), "Static ->canExecute returns false for mode 400 file" );
ok( ! File::Flat->canExecute( './rWx' ), "Static ->canExecute returns false for mode 200 file" );
ok( File::Flat->canExecute( './rwX' ), "Static ->canExecute returns true for mode 100 file" );
ok( ! File::Flat->canExecute( './RWx' ), "Static ->canExecute returns false for mode 500 file" );
ok( File::Flat->canExecute( './RwX' ), "Static ->canExecute returns true for mode 300 file" );
ok( File::Flat->canExecute( './RWX' ), "Static ->canExecute returns true for mode 700 file" );
ok( File::Flat->canExecute( '.' ), "Static ->canExecute returns true for . directory" );
ok( File::Flat->canExecute( './gooddir' ), "Static ->canExecute returns true for executable subdirectory" );
ok( ! File::Flat->canExecute( './baddir' ), "Static ->canExecute returns false for unexecutable subdirectory" );

# Test the static ->canOpen method
ok( ! File::Flat->canOpen( './null' ), "Static ->canOpen returns false for missing file" );
ok( ! File::Flat->canOpen( './rwx' ), "Static ->canOpen returns false for mode 000 file" );
ok( File::Flat->canOpen( './Rwx' ), "Static ->canOpen returns true for mode 400 file" );
ok( ! File::Flat->canOpen( './rWx' ), "Static ->canOpen returns false for mode 200 file" );
ok( ! File::Flat->canOpen( './rwX' ), "Static ->canOpen returns false for mode 100 file" );
ok( File::Flat->canOpen( './RWx' ), "Static ->canOpen returns true for mode 500 file" );
ok( File::Flat->canOpen( './RwX' ), "Static ->canOpen returns true for mode 300 file" );
ok( File::Flat->canOpen( './RWX' ), "Static ->canOpen returns true for mode 700 file" );
ok( ! File::Flat->canOpen( '.' ), "Static ->canOpen returns false for . directory" );
ok( ! File::Flat->canOpen( './gooddir' ), "Static ->canOpen returns false for readable subdirectory" );
ok( ! File::Flat->canOpen( './baddir' ), "Static ->canOpen returns false for unreadable subdirectory" );

# Test the existance of normal and/or binary files
ok( ! File::Flat->isText( './null' ), "Static ->isText returns false for missing file" );
ok( ! File::Flat->isText( './ff_binary' ), "Static ->isText returns false for binary file" );
ok( File::Flat->isText( './ff_text' ), "Static ->isText returns true for text file" );
ok( ! File::Flat->isText( './gooddir' ), "Static ->isText returns false for good subdirectory" );
ok( ! File::Flat->isText( './baddir' ), "Static ->isText returns false for bad subdirectory" );
ok( ! File::Flat->isBinary( './null' ), "Static ->isBinary returns false for missing file" );
ok( File::Flat->isBinary( './ff_binary' ), "Static ->isBinary returns true for binary file" );
ok( ! File::Flat->isBinary( './ff_text' ), "Static ->isBinary returns false for text file" );
ok( ! File::Flat->isBinary( './gooddir' ), "Static ->isBinary return false for good subdirectory" );
ok( ! File::Flat->isBinary( './baddir' ), "Static ->isBinary returns false for bad subdirectory" );

my %handle = ();

# Do open handle methods return false for bad values
$handle{generic} = File::Flat->open( './null' );
$handle{readhandle} = File::Flat->open( './null' );
$handle{writehandle} = File::Flat->open( './null' );
$handle{appendhandle} = File::Flat->open( './null' );
$handle{readwritehandle} = File::Flat->open( './null' );
ok( ! defined $handle{generic}, "Static ->open call returns undef on bad file name" );
ok( ! defined $handle{readhandle}, "Static ->getReadHandle returns undef on bad file name" );
ok( ! defined $handle{writehandle}, "Static ->getWriteHandle returns undef on bad file name" );
ok( ! defined $handle{appendhandle}, "Static ->getAppendHandle returns undef on bad file name" );
ok( ! defined $handle{readwritehandle}, "Static ->getReadWriteHandle returns undef on bad file name" );

# Do the open methods at least return a file handle
system( 'cp ff_text ff_handle' ) and die "Failed to copy file in preperation for test";
$handle{generic} = File::Flat->open( './ff_handle' );
$handle{readhandle} = File::Flat->getReadHandle( './ff_handle' );
$handle{writehandle} = File::Flat->getWriteHandle( './ff_handle' );
$handle{appendhandle} = File::Flat->getAppendHandle( './ff_handle' );
$handle{readwritehandle} = File::Flat->getReadWriteHandle( './ff_handle' );
ok( isa( $handle{generic}, 'IO::File' ), "Static ->open call returns IO::File object" );
ok( isa( $handle{readhandle}, 'IO::File' ), "Static ->getReadHandle returns IO::File object" );
ok( isa( $handle{writehandle}, 'IO::File' ), "Static ->getWriteHandle returns IO::File object" );
ok( isa( $handle{appendhandle}, 'IO::File' ), "Static ->getAppendHandle returns IO::File object" );
ok( isa( $handle{readwritehandle}, 'IO::File' ), "Static ->getReadWriteHandle returns IO::File object" );






# Test the static ->copy method
ok( ! defined File::Flat->copy(), '->copy() returns error' );
ok( ! defined File::Flat->copy( './ff_content' ), '->copy( file ) returns error' );
$rv = File::Flat->copy( './ff_content', './ff_content2' );
ok( $rv, "Static ->copy returns true correctly for same directory copy" );
ok( -e './ff_content2', "Static ->copy actually created the file for same directory copy" );
ok( check_content_file( './ff_content2' ), "Static ->copy copies the file without breaking it" );
$rv = File::Flat->copy( './ff_text', './a/ff_text3' );
ok( $rv, "Static ->copy returns true correctly for single sub-directory copy" );
ok( -e './a/ff_text3', "Static ->copy actually created the file for single sub-directory copy" );
$rv = File::Flat->copy( './ff_text', './a/b/c/d/e/ff_text3' );
ok( $rv, "Static ->copy returns true correctly for multiple sub-directory copy" );
ok( -e './a/b/c/d/e/ff_text3', "Static ->copy actually created the file for multiple sub-directory copy" );
$rv = File::Flat->copy( './nonexistant', './something' );
ok( ! $rv, "Static ->copy return undef when file does not exist" );

# Directory copying
$rv = File::Flat->copy( './a/b/c', './a/b/d' );
ok( $rv, '->copy( dir, dir ) returns true' );
ok( -d './a/b/d', '->copy( dir, dir ): New dir exists' );
ok( -f './a/b/d/d/e/ff_text3', '->( dir, dir ): Files within directory were copied' );

# Test the static ->move method
$rv = File::Flat->move( './a/b/c/d/e/ff_text3', './moved_1' );
ok( $rv, "Static ->move for move to existing directory returns true " );
ok( ! -e './a/b/c/d/e/ff_text3', "Static ->move for move to existing directory actually removes the old file" );
ok( -e './moved_1', "Static ->move for move to existing directory actually creates the new file" );
$rv = File::Flat->move( './ff_content2', './b/c/d/e/moved_2' );
ok( $rv, "Static ->move for move to new directory returns true " );
ok( ! -e './ff_content2', "Static ->move for move to new directory actually removes the old file" );
ok( -e './b/c/d/e/moved_2', "Static ->move for move to new directory actually creates the new file" );
ok( check_content_file( './b/c/d/e/moved_2' ), "Static ->move moved the file without breaking it" );






# Test the static ->slurp method
ok( check_content_file( './ff_content' ), "Content tester works" );
my $content = File::Flat->slurp();
ok( ! defined $content, "Static ->slurp returns error on no arguments" );
$content = File::Flat->slurp( './nonexistant' );
ok( ! defined $content, "Static ->slurp returns error on bad file" );
$content = File::Flat->slurp( './ff_content' );
ok( defined $content, "Static ->slurp returns defined" );
ok( defined $content, "Static ->slurp returns something" );
ok( isa( $content, 'SCALAR' ), "Static ->slurp returns a scalar reference" );
ok( length $$content, "Static ->slurp returns content" );
ok( $$content eq $content_string, "Static ->slurp returns the correct file contents" );

# Test the static ->read 
$content = File::Flat->read();
ok( ! defined $content, "Static ->read returns error on no arguments" );
$content = File::Flat->read( './nonexistant' );
ok( ! defined $content, "Static ->read returns error on bad file" );
$content = File::Flat->read( './ff_content' );
ok( defined $content, "Static ->read doesn't error on good file" );
ok( $content, "Static ->read returns true on good file" );
ok( ref $content, "Static ->read returns a reference on good file" );
ok( isa( $content, 'ARRAY' ), "Static ->read returns an array ref on good file" );
ok( scalar @$content == 4, "Static ->read returns the correct length of data" );
my $matches = (
	$content->[0] eq 'one'
	and $content->[1] eq 'two'
	and $content->[2] eq 'three'
	and $content->[3] eq ''
	) ? 1 : 0;
ok( $matches, "Static ->read returns the expected content" );

# And again in an array context
my @content = File::Flat->read();
ok( ! scalar @content, "Static ->read (array context) returns error on no arguments" );
@content = File::Flat->read( './nonexistant' );
ok( ! scalar @content, "Static ->read (array context) returns error on bad file" );
@content = File::Flat->read( './ff_content' );
ok( scalar @content, "Static ->read (array context) doesn't error on good file" );
ok( scalar @content == 4, "Static ->read (array context) returns the correct length of data" );
$matches = (
	$content[0] eq 'one'
	and $content[1] eq 'two'
	and $content[2] eq 'three'
	and $content[3] eq ''
	) ? 1 : 0;
ok( $matches, "Static ->read (array context) returns the expected content" );

	



# Test the many and varies write() options.
ok( ! File::Flat->write(), "->write() fails correctly" );
ok( ! File::Flat->write( './write_1' ), "->write( file ) fails correctly" );
ok( ! -e './write_1', "->write( file ) doesn't actually create a file" );
$rv = File::Flat->write( './write_1', $content_string );
ok( $rv, "->File::Flat->write( file, string ) returns true" );
ok( -e './write_1', "->write( file, string ) actually creates a file" );
ok( check_content_file( './write_1' ), "->write( file, string ) writes the correct content" );
$rv = File::Flat->write( './write_2', $content_string );
ok( $rv, "->File::Flat->write( file, string_ref ) returns true" );
ok( -e './write_2', "->write( file, string_ref ) actually creates a file" );
ok( check_content_file( './write_2' ), "->write( file, string_ref ) writes the correct content" );
$rv = File::Flat->write( './write_3', \@content_array );
ok( $rv, "->write( file, array_ref ) returns true" );
ok( -e './write_3', "->write( file, array_ref ) actually creates a file" );
ok( check_content_file( './write_3' ), "->write( file, array_ref ) writes the correct content" );

# Repeat with a handle first argument
my $handle = File::Flat->getWriteHandle( './write_4' );
ok( ! File::Flat->write( $handle ), "->write( handle ) fails correctly" );
ok( isa( $handle, 'IO::Handle' ), 'Got write handle for test' );
$rv = File::Flat->write( $handle, $content_string );
$handle->close();
ok( $rv, "->write( handle, string ) returns true" );
ok( -e './write_4', "->write( handle, string ) actually creates a file" );
ok( check_content_file( './write_1' ), "->write( handle, string ) writes the correct content" );

$handle = File::Flat->getWriteHandle( './write_5' );
ok( isa( $handle, 'IO::Handle' ), 'Got write handle for test' );
$rv = File::Flat->write( $handle, $content_string );
$handle->close();
ok( $rv, "->File::Flat->write( handle, string_ref ) returns true" );
ok( -e './write_5', "->write( handle, string_ref ) actually creates a file" );
ok( check_content_file( './write_5' ), "->write( handle, string_ref ) writes the correct content" );

$handle = File::Flat->getWriteHandle( './write_6' );
ok( isa( $handle, 'IO::Handle' ), 'Got write handle for test' );
$rv = File::Flat->write( $handle, \@content_array );
$handle->close();
ok( $rv, "->File::Flat->write( handle, array_ref ) returns true" );
ok( -e './write_6', "->write( handle, array_ref ) actually creates a file" );
ok( check_content_file( './write_6' ), "->write( handle, array_ref ) writes the correct content" );






# Check the ->overwrite method
ok( ! File::Flat->overwrite(), "->overwrite() fails correctly" );
ok( ! File::Flat->overwrite( './over_1' ), "->overwrite( file ) fails correctly" );
ok( ! -e './over_1', "->overwrite( file ) doesn't actually create a file" );
$rv = File::Flat->overwrite( './over_1', $content_string );
ok( $rv, "->File::Flat->overwrite( file, string ) returns true" );
ok( -e './over_1', "->overwrite( file, string ) actually creates a file" );
ok( check_content_file( './over_1' ), "->overwrite( file, string ) writes the correct content" );
$rv = File::Flat->overwrite( './over_2', $content_string );
ok( $rv, "->File::Flat->overwrite( file, string_ref ) returns true" );
ok( -e './over_2', "->overwrite( file, string_ref ) actually creates a file" );
ok( check_content_file( './over_2' ), "->overwrite( file, string_ref ) writes the correct content" );
$rv = File::Flat->overwrite( './over_3', \@content_array );
ok( $rv, "->overwrite( file, array_ref ) returns true" );
ok( -e './over_3', "->overwrite( file, array_ref ) actually creates a file" );
ok( check_content_file( './over_3' ), "->overwrite( file, array_ref ) writes the correct content" );

# Check actually overwriting a file
ok ( File::Flat->copy( './ff_text', 'over_4' ), "Preparing for overwrite test" );
$rv = File::Flat->overwrite( './over_4', \$content_string );
ok( $rv, "->overwrite( file, array_ref ) returns true" );
ok( -e './over_4', "->overwrite( file, array_ref ) actually creates a file" );
ok( check_content_file( './over_4' ), "->overwrite( file, array_ref ) writes the correct content" );





# Check the basics of the ->remove method
ok( ! File::Flat->remove(), "->remove() correctly return an error" );
ok( ! File::Flat->remove( './nonexistant' ), "->remove( file ) returns an error for a nonexistant file" );
ok( File::Flat->remove( './over_4' ), "->remove( file ) returns true for existing file" );
ok( ! -e './over_4', "->remove( file ) actually removes the file" );
ok( File::Flat->remove( './a' ), "->remove( directory ) returns true for existing directory" );
ok( ! -e './a', "->remove( directory ) actually removes the directory" );





# Check the append method
ok( ! File::Flat->append(), "->append() correctly returns an error" );
ok( ! File::Flat->append( './append_1' ), "->append( file ) correctly returns an error" );
ok( ! -e './append_1', "->append( file ) doesn't actually create a file" );
$rv = File::Flat->append( './append_1', $content_string );
ok( $rv, "->File::Flat->append( file, string ) returns true" );
ok( -e './append_1', "->append( file, string ) actually creates a file" );
ok( check_content_file( './append_1' ), "->append( file, string ) writes the correct content" );
$rv = File::Flat->append( './append_2', $content_string );
ok( $rv, "->File::Flat->append( file, string_ref ) returns true" );
ok( -e './append_2', "->append( file, string_ref ) actually creates a file" );
ok( check_content_file( './append_2' ), "->append( file, string_ref ) writes the correct content" );
$rv = File::Flat->append( './append_3', \@content_array );
ok( $rv, "->append( file, array_ref ) returns true" );
ok( -e './append_3', "->append( file, array_ref ) actually creates a file" );
ok( check_content_file( './append_3' ), "->append( file, array_ref ) writes the correct content" );

# Now let's try an actual append
ok( File::Flat->append( './append_4', "one\ntwo\n" ), "Preparing for real append" );
my $rv = File::Flat->append( './append_4', "three\n\n" );
ok( $rv, "->append( file, array_ref ) for an actual append returns true" );
ok( -e './append_4', "->append( file, array_ref ): File still exists" );
ok( check_content_file( './append_4' ), "->append( file, array_ref ) results in the correct file contents" );







# Test the ->fileSize method
ok( File::Flat->write( './size_1', 'abcdefg' )
	&& File::Flat->write( './size_2', join '', ( 'd' x 100000 ) )
	&& File::Flat->write( './size_3', '' ),
	"Preparing for file size tests" 
	);
ok( ! defined File::Flat->fileSize(), "->fileSize() correctly returns error" );
ok( ! defined File::Flat->fileSize( './nonexistant' ), '->fileSize( file ) returns error for nonexistant' );
ok( ! defined File::Flat->fileSize( './a' ), '->fileSize( directory ) returns error' );
$rv = File::Flat->fileSize( './size_1' );
ok( defined $rv, "->fileSize( file ) returns true for small file" );
ok( $rv == 7, "->fileSize( file ) returns the correct size for small file" );
$rv = File::Flat->fileSize( './size_2' );
ok( defined $rv, "->fileSize( file ) returns true for big file" );
ok( $rv == 100000, "->fileSize( file ) returns the correct size for big file" );
$rv = File::Flat->fileSize( './size_3' );
ok( defined $rv, "->fileSize( file ) returns true for empty file" );
ok( $rv == 0, "->fileSize( file ) returns the correct size for empty file" );







# Test the ->truncate method. Use the append files
ok( ! defined File::Flat->truncate(), '->truncate() correctly returns error' );
ok( ! defined File::Flat->truncate( './rwx' ), '->truncate( file ) returns error when no permissions' );
ok( ! defined File::Flat->truncate( './b' ), '->truncate( directory ) returns error' );
$rv = File::Flat->truncate( './trunc_1' );
ok( $rv, '->truncate( file ) returns true for non-existant file' );
ok( -e './trunc_1', '->truncate( file ) creates new file' );
ok( File::Flat->fileSize( './trunc_1' ) == 0, '->truncate( file ) creates file of 0 bytes' );
$rv = File::Flat->truncate( './append_1' );
ok( $rv, '->truncate( file ) returns true for existing file' );
ok( -e './append_1', '->truncate( file ): File still exists' );
ok( File::Flat->fileSize( './append_1' ) == 0, '->truncate( file ) truncates to 0 bytes' );
$rv = File::Flat->truncate( './append_2', 0 );
ok( $rv, '->truncate( file, 0 ) returns true for existing file' );
ok( -e './append_2', '->truncate( file, 0 ): File still exists' );
ok( File::Flat->fileSize( './append_2' ) == 0, '->truncate( file, 0 ) truncates to 0 bytes' );
$rv = File::Flat->truncate( './append_3', 5 );
ok( $rv, '->truncate( file, 5 ) returns true for existing file' );
ok( -e './append_3', '->truncate( file, 5 ): File still exists' );
ok( File::Flat->fileSize( './append_3' ) == 5, '->truncate( file, 5 ) truncates to 5 bytes' );





exit();





sub check_content_file {
	my $file = shift;
	return undef unless -e $file;
	return undef unless -r $file;
	
	open( FILE, $file ) or return undef;
	@content = <FILE>;
	chomp @content;
	close FILE;
	
	return undef unless scalar @content == 4;
	return undef unless $content[0] eq 'one';
	return undef unless $content[1] eq 'two';
	return undef unless $content[2] eq 'three';
	return undef unless $content[3] eq '';
	
	return 1;
}

END {
	# When we finish there are going to be some fucked up files.
	# Make them less fucked up
	system( 'chmod -R u+rwx *' );
	foreach ( qw{
		rwx rwX rWx Rwx rWX RwX RWx RWX 
		ff_handle moved_1
		write_1 write_2 write_3 write_4 write_5 write_6
		over_1 over_2 over_3 over_4
		append_1 append_2 append_3 append_4
		size_1 size_2 size_3
		trunc_1
	} ) {
		unlink $_;
	}
	foreach ( qw{a b baddir gooddir} ) {
		system( "rm -rf $_" );
	}
}
