require 5.000;
use ExtUtils::MakeMaker;
WriteMakefile(
	'NAME'         => 'File::Flat',
	'VERSION_FROM' => 'lib/File/Flat.pm',
	'PREREQ_PM'    => {
		'Class::Autouse'   => 1.0,
		'File::Spec'       => 0.82,
		'File::Copy'       => 0,
		'File::NCopy'      => 0.32,
		'File::Remove'     => 0.20, # Required for recursive remove
		'File::Temp'       => 0.12, # Some bugs below 0.12 could matter
		'IO::File'         => 0,

		# Testing only
		'Class::Inspector' => 0,
		'File::Find'       => 0, # Avoid use of system chmod -R in test script
	},
	($] >= 5.005) ? (
		'AUTHOR'     => 'Adam Kennedy (cpan@ali.as)',
		'ABSTRACT'   => 'Unified interface to the filesystem with directories abstracted away',
	) : (),
);
