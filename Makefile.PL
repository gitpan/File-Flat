require 5.000;
use ExtUtils::MakeMaker;
WriteMakefile(
	'NAME'         => 'File::Flat',
	'VERSION_FROM' => 'lib/File/Flat.pm',
	'PREREQ_PM'    => {
		'File::Spec'       => 0.85,    # Faster and more featureful
		'File::Copy'       => 0,       # In Perl core, we don't care about versions
		'File::NCopy'      => 0.34,    # Required for File::Spec support
		'File::Slurp'      => 9999.04, # Read/Write files quickly
		'File::Remove'     => 0.21,    # Required for File::Spec support
		'File::Temp'       => 0.14,    # Some bugs below 0.12 could matter
		'IO::File'         => 0,       # Making file handles

		# Testing only
		'Test::More'       => 0,       # In Perl core, we don't care about versions
		'Class::Inspector' => 1.06,    # Useless under Win32 until this
		'File::Find'       => 0,       # Avoid use of system chmod -R in test script
	},
	($] >= 5.005) ? (
		'AUTHOR'     => 'Adam Kennedy (cpan@ali.as)',
		'ABSTRACT'   => 'Unified interface to the filesystem with directories abstracted away',
	) : (),
);
