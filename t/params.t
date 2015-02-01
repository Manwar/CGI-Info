#!perl -wT

use strict;
use warnings;
use Test::Most tests => 132;
use Test::NoWarnings;
use File::Spec;

BEGIN {
	use_ok('CGI::Info');
}

PARAMS: {
	$ENV{'GATEWAY_INTERFACE'} = 'CGI/1.1';
	$ENV{'REQUEST_METHOD'} = 'GET';
	$ENV{'QUERY_STRING'} = 'foo=bar';

	my $i = new_ok('CGI::Info');
	my %p = %{$i->params()};
	ok($p{foo} eq 'bar');
	ok(!defined($p{fred}));
	ok($i->as_string() eq 'foo=bar');

	$ENV{'QUERY_STRING'} = '=bar';

	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok(!defined($p{fred}));
	ok($i->as_string() eq '');

	$ENV{'QUERY_STRING'} = 'foo=bar&fred=wilma';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{foo} eq 'bar');
	ok($p{fred} eq 'wilma');
	ok($i->as_string() eq 'foo=bar;fred=wilma');

	$ENV{'QUERY_STRING'} = 'name=nigel+horne';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{name} eq 'nigel horne');

	$ENV{'QUERY_STRING'} = 'name=nigel%2Bhorne';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{name} eq 'nigel horne');

	$ENV{'QUERY_STRING'} = 'foo=bar&fred=wilma&foo=%3Dbaz';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{foo} eq 'bar,=baz');
	ok($p{fred} eq 'wilma');
	ok($i->as_string() eq 'foo=bar,\\=baz;fred=wilma');

	# Reading twice should yield the same result
	%p = %{$i->params()};
	ok($p{foo} eq 'bar,=baz');

	$ENV{'QUERY_STRING'} = 'foo=&fred=wilma';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok(!defined($p{foo}));
	ok($p{fred} eq 'wilma');
	ok($i->as_string() eq 'fred=wilma');

	$ENV{'QUERY_STRING'} = 'foo=&fred=wilma&foo=bar';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{foo} eq 'bar');
	ok($p{fred} eq 'wilma');
	ok($i->as_string() eq 'foo=bar;fred=wilma');

	# Catch XSS attempts
	$ENV{'QUERY_STRING'} = 'foo=bar&fred=<script>alert(123)</script>';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{fred} eq '&lt;script&gt;alert(123)&lt;/script&gt;');

	$ENV{'QUERY_STRING'} = '<script>alert(123)</script>=wilma';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{'&lt;script&gt;alert(123)&lt;/script&gt;'} eq 'wilma');

	$ENV{'QUERY_STRING'} = 'username=admin&password=foo';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{'username'} eq 'admin');
	ok($p{'password'} eq 'foo');

	$ENV{'QUERY_STRING'} = 'foo%41=%20bar';
	$i = new_ok('CGI::Info');
	my $p = $i->params();
	ok($p->{'fooA'} eq 'bar');
	ok($i->as_string() eq 'fooA=bar');

	delete $ENV{'QUERY_STRING'};
	$i = new_ok('CGI::Info');
	ok(!$i->params());

	$ENV{'REQUEST_METHOD'} = 'HEAD';
	$ENV{'QUERY_STRING'} = 'foo=b+ar&fred=wilma';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{fred} eq 'wilma');
	ok($p{foo} eq 'b ar');

	$ENV{'REQUEST_METHOD'} = 'FOO';
	$i = new_ok('CGI::Info');

	local $SIG{__WARN__} = sub { die $_[0] };
	eval { $i->params() };
	ok($@ =~ /Use POST, GET or HEAD/);

	delete $ENV{'QUERY_STRING'};
	$ENV{'REQUEST_METHOD'} = 'GET';
	$i = new_ok('CGI::Info');
	ok(!defined($i->params()));
	ok($i->as_string() eq '');

	$ENV{'REQUEST_METHOD'} = 'POST';
	delete $ENV{'CONTENT_LENGTH'};
	$i = new_ok('CGI::Info');
	ok(!defined($i->params()));
	ok($i->as_string() eq '');

	my $input = 'foo=bar';
	$ENV{'CONTENT_LENGTH'} = length($input);

	open (my $fin, '<', \$input);
	local *STDIN = $fin;

	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{foo} eq 'bar');	# Fails on Perl 5.6.2
	ok(!defined($p{fred}));
	ok($i->as_string() eq 'foo=bar');
	close $fin;

	# Creating a second object should give the same parameters, without
	# reading
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{foo} eq 'bar');
	ok(!defined($p{fred}));
	ok($i->as_string() eq 'foo=bar');

	# TODO: find and use a free filename, otherwise /tmp/hello.txt
	# will be overwritten if it exists
	$ENV{'CONTENT_TYPE'} = 'Multipart/form-data; boundary=-----xyz';
	$input = <<'EOF';
-------xyz
Content-Disposition: form-data; name="country"

44
-------xyz
Content-Disposition: form-data; name="datafile"; filename="hello.txt"
Content-Type: text/plain

Hello, World

-------xyz--
EOF
	$ENV{'CONTENT_LENGTH'} = length($input);

	open ($fin, '<', \$input);
	local *STDIN = $fin;

	CGI::Info->reset();	# Force stdin re-read
	$i = new_ok('CGI::Info' => [
		upload_dir => File::Spec->tmpdir()
	]);
	%p = %{$i->params()};
	ok(defined($p{country}));
	ok($p{country} eq '44');
	ok($p{datafile} =~ /^hello.txt_.+/);
	my $filename = File::Spec->catfile(File::Spec->tmpdir(), $p{datafile});
	ok(-e $filename);
	ok(-r $filename);
	unlink($filename);
	close $fin;

	open ($fin, '<', \$input);
	local *STDIN = $fin;

	CGI::Info->reset();	# Force stdin re-read
	$i = new_ok('CGI::Info');
	%p = %{$i->params(upload_dir => File::Spec->tmpdir())};
	ok(defined($p{country}));
	ok($p{country} eq '44');
	ok($p{datafile} =~ /^hello.txt_.+/);
	$filename = File::Spec->catfile(File::Spec->tmpdir(), $p{datafile});
	ok(-e $filename);
	ok(-r $filename);
	unlink($filename);
	close $fin;

	$input = <<'EOF';
-------xyz
Content-Disposition: form-data; name="country"

44
-------xyz
Content-Disposition: form-data; name=".hidden"; filename="/.trojanhorse.js"
Content-Type: text/plain

I would do nasty things, but my upload will be disallowed

-------xyz--
EOF
	$ENV{'CONTENT_LENGTH'} = length($input);

	open ($fin, '<', \$input);
	local *STDIN = $fin;

	CGI::Info->reset();	# Force stdin re-read
	$i = new_ok('CGI::Info' => [
		upload_dir => File::Spec->tmpdir()
	]);
	eval { %p = $i->params() };
	ok($@ =~ /Disallowing invalid filename/);
	ok(defined($p{country}));
	ok($p{country} eq '44');
	ok($p{datafile} =~ /^hello.txt_.+/);
	$filename = File::Spec->catfile(File::Spec->tmpdir(), $p{datafile});
	ok(!-e $filename);
	ok(!-r $filename);
	close $fin;

	$input = <<'EOF';
-------xyz
Content-Disposition: form-data; name="country"

44
-------xyz
Content-Disposition: form-data; name="datafile"; filename="hello.txt"
Content-Type: text/plain

Hello, World

-------xyz--
EOF
	$ENV{'CONTENT_LENGTH'} = length($input);

	open ($fin, '<', \$input);
	local *STDIN = $fin;

	CGI::Info->reset();	# Force stdin re-read
	$i = new_ok('CGI::Info' => [
		upload_dir => '/does_not_exist11',
	]);
	eval { %p = $i->params() };
	ok($@ =~ /_upload_dir isn't a directory/);
	ok(defined($p{country}));
	ok($p{country} eq '44');
	ok($p{datafile} =~ /^hello.txt_.+/);
	$filename = File::Spec->catfile(File::Spec->tmpdir(), $p{datafile});
	ok(!-e $filename);
	ok(!-r $filename);
	close $fin;

	open ($fin, '<', \$input);
	local *STDIN = $fin;

	CGI::Info->reset();	# Force stdin re-read
	$i = new_ok('CGI::Info' => [
		upload_dir => undef,
	]);
	eval { %p = $i->params() };
	ok($@ =~ /Attempt to upload a file when upload_dir has not been set/);
	ok(defined($p{country}));
	ok($p{country} eq '44');
	ok($p{datafile} =~ /^hello.txt_.+/);
	$filename = File::Spec->catfile(File::Spec->tmpdir(), $p{datafile});
	ok(!-e $filename);
	ok(!-r $filename);
	close $fin;

	SKIP: {
		# e.g. running as root, or on Windows
		skip 'Root directory is writable', 7 if(-w '/');
		open ($fin, '<', \$input);
		local *STDIN = $fin;

		CGI::Info->reset();	# Force stdin re-read
		$i = new_ok('CGI::Info' => [
			upload_dir => '/',
		]);
		eval { %p = $i->params() };
		ok($@ =~ /_upload_dir isn't writeable/);
		ok(defined($p{country}));
		ok($p{country} eq '44');
		ok($p{datafile} =~ /^hello.txt_.+/);
		$filename = File::Spec->catfile(File::Spec->tmpdir(), $p{datafile});
		ok(!-e $filename);
		ok(!-r $filename);
		close $fin;
	}

	open ($fin, '<', \$input);
	local *STDIN = $fin;

	my $script_path = $i->script_path();
	CGI::Info->reset();	# Force stdin re-read
	$i = new_ok('CGI::Info' => [
		upload_dir => $script_path,
	]);
	eval { %p = $i->params() };
	ok($@ =~ /_upload_dir isn't a directory/);
	ok(defined($p{country}));
	ok($p{country} eq '44');
	ok($p{datafile} =~ /^hello.txt_.+/);
	$filename = File::Spec->catfile(File::Spec->tmpdir(), $p{datafile});
	ok(!-e $filename);
	ok(!-r $filename);
	close $fin;

	open ($fin, '<', \$input);
	local *STDIN = $fin;
	$script_path = $i->script_path();
	CGI::Info->reset();	# Force stdin re-read
	$i = new_ok('CGI::Info' => [
		upload_dir => '.',
	]);
	eval { %p = $i->params() };
	ok($@ =~ /_upload_dir must be a full pathname/);
	ok(defined($p{country}));
	ok($p{country} eq '44');
	ok($p{datafile} =~ /^hello.txt_.+/);
	$filename = File::Spec->catfile(File::Spec->tmpdir(), $p{datafile});
	ok(!-e $filename);
	ok(!-r $filename);
	close $fin;

	$ENV{'CONTENT_TYPE'} = 'xyzzy';
	open ($fin, '<', \$input);
	local *STDIN = $fin;

	CGI::Info->reset();	# Force stdin re-read
	$i = new_ok('CGI::Info' => [
		upload_dir => File::Spec->tmpdir()
	]);
	eval { %p = $i->params() };
	ok($@ =~ /POST: Invalid or unsupported content type: xyzzy/);
	ok(defined($p{country}));
	ok($p{country} eq '44');
	ok($p{datafile} =~ /^hello.txt_.+/);
	$filename = File::Spec->catfile(File::Spec->tmpdir(), $p{datafile});
	ok(!-e $filename);
	ok(!-r $filename);
	close $fin;

	$ENV{'CONTENT_TYPE'} = 'Multipart/form-data; boundary=-----xyz';
	$input = <<'EOF';
-------xyz
Content-Disposition: form-data; name="country"

44
-------xyz
Content-Disposition: form-data; name="datafile"; filename="../../../passwd"
Content-Type: text/plain

Hello, World

-------xyz--
EOF
	open ($fin, '<', \$input);
	local *STDIN = $fin;
	$script_path = $i->script_path();
	CGI::Info->reset();	# Force stdin re-read
	$i = new_ok('CGI::Info' => [
		upload_dir => File::Spec->tmpdir()
	]);
	eval { %p = $i->params() };
	diag($@);
	ok($@ =~ /Disallowing invalid filename/);
	ok(defined($p{country}));
	ok($p{country} eq '44');
	ok($p{datafile} =~ /^hello.txt_.+/);
	$filename = File::Spec->catfile(File::Spec->tmpdir(), $p{datafile});
	ok(!-e $filename);
	ok(!-r $filename);
	close $fin;

	# Check params are read from command line arguments for testing scripts
	delete $ENV{'GATEWAY_INTERFACE'};
	delete $ENV{'REQUEST_METHOD'};
	delete $ENV{'QUERY_STRING'};
	push(@ARGV, 'foo=bar');
	push(@ARGV, 'fred=wilma');
	$i = new_ok('CGI::Info');
	%p = %{$i->params(logger => MyLogger->new())};
	ok($p{fred} eq 'wilma');
	ok($i->as_string() eq 'foo=bar;fred=wilma');

	$ENV{'QUERY_STRING'} = 'foo=bar&fred=wilma';
}

# On some platforms it's failing - find out why
package MyLogger;

sub new {
	my ($proto, %args) = @_;

	my $class = ref($proto) || $proto;

	return bless { }, $class;
}

sub debug {
	my $self = shift;
	my $message = shift;

	# Enable this for debugging
	# ::diag($message);
}
