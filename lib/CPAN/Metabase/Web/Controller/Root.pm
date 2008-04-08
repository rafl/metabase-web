use strict;
use warnings;
package CPAN::Metabase::Web::Controller::Root;
use base 'Catalyst::Controller::REST';

use lib "$ENV{HOME}/code/projects/CPAN-Metabase/lib";

our $VERSION = '0.001';
$VERSION = eval $VERSION; # convert '1.23_45' to 1.2345

use CPAN::Metabase::Gateway;
use CPAN::Metabase::Archive::Filesystem;
use Data::GUID;

my $gateway;
BEGIN {
   $gateway ||= CPAN::Metabase::Gateway->new({
    fact_classes => [ 'CPAN::Metabase::Fact::TestFact' ],
    archive      => CPAN::Metabase::Archive::Filesystem->new({
      root_dir => './mb',
    }),
  });
}

sub _gateway { $gateway }

# /submit/dist/RJBS/Acme-ProgressBar-1.124.tar.gz/Test-Report
#  submit dist 0    1                             2
sub submit : Chained('/') CaptureArgs(0) {
}

sub dist : Chained('submit') Args(3) ActionClass('REST') {
  my ($self, $c, $dist_author, $dist_file, $type) = @_;

  { # XXX: 
    return $self->status_bad_request($c, message => 'invalid dist author')
      unless $dist_author =~ /\A[A-Z]+\z/;

    return $self->status_bad_request($c, message => 'invalid distribution')
      unless $dist_file =~ /\.tar\.gz\z/;
  }

  $c->stash(
    user_id     => 'rjbs', # this needs to come from auth and a shared source
    dist_author => $dist_author,
    dist_file   => $dist_file,
    type        => $type,
  );
}

sub dist_PUT {
  my ($self, $c) = @_;

  $c->stash->{content} = $c->req->data->{content};

  # XXX: In the future, this might be a queue id.  That might be a guid.  Time
  # will tell! -- rjbs, 2008-04-08
  my $guid = eval { $self->_gateway->handle($c->stash); };

  unless ($guid) {
    my $error = $@ || '(unknown error)';
    warn $error; # XXX: we should catch and report Permission exceptions, etc
                 # -- rjbs, 2008-04-07

    return $self->status_bad_request($c, message => "gateway failure: $error");
  }

  return $self->status_created(
    $c,
    location => '/guid/' . $guid->as_string, # XXX: uri_for or something?
    entity   => { guid => $guid->as_string },
  );
}

BEGIN{ *dist_POST = \&dist_PUT; }

# /guid/CC3F4AF4-0571-11DD-AA50-85A198B5225E
#  guid 0
sub guid : Chained('/') Args(1) ActionClass('REST') {
  my ($self, $c, $guid) = @_;

  if (my $guid = eval { Data::GUID->from_string($guid) }) {
    $c->stash->{guid} = $guid;
  }
}

sub guid_GET {
  my ($self, $c) = @_;

  return $self->status_bad_request($c, message => "invalid guid")
    unless my $guid = $c->stash->{guid};

  return $self->status_not_found($c, message => 'no such resource')
    unless my $fact = $self->_gateway->archive->extract($guid);
  
  return $self->status_ok(
    $c,
    entity => {
      dist_author    => $fact->dist_author,
      dist_file      => $fact->dist_file,
      type           => $fact->type,
      schema_version => $fact->schema_version,
      content        => $fact->content_as_string,
      user_id        => 'unknown',
    },
  );
}

1;
