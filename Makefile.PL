require 5.000;
use ExtUtils::MakeMaker;
WriteMakefile(
	'NAME'         => 'File::Flat',
	'VERSION_FROM' => 'lib/File/Flat.pm',
	'PREREQ_PM'    => {
		'Class::Autouse'   => 0.7,
		'File::Spec'       => 0.82,
		'File::Copy'       => 0,
		'File::NCopy'      => 0.32,
		'File::Remove'     => 0.20, # Required for recursive
		'File::Temp'       => 0.12, # Some bugs here could matter
		'IO::File'         => 0,

		'Class::Inspector' => 0, # For the test script
	},
	($] >= 5.005) ? (
		'AUTHOR'     => 'Adam Kennedy (cpan@ali.as)',
		'ABSTRACT'   => 'Provides an interface to a directory-less flat filesystem',
	) : (),
);
